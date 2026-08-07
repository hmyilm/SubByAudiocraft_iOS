import Foundation
import AudioCommon
import MLX
import MLXNN
import SourceSeparation

enum VocalIsolationMode: String, CaseIterable, Identifiable {
    case off
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .automatic: return "Akıllı Yerel"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Şarkı doğrudan analiz edilir. Yoğun altyapıda bazı heceler müzikle karışabilir."
        case .automatic:
            return "Müzik yalnız analiz kopyasında bastırılır; vokal daha net çözümlenir. Final video daima orijinal parçayı kullanır."
        }
    }

    var usesVocalIsolation: Bool {
        self == .automatic
    }

    static func resolved(_ rawValue: String?) -> VocalIsolationMode {
        guard let rawValue else { return .automatic }
        return VocalIsolationMode(rawValue: rawValue) ?? .automatic
    }
}

struct VocalIsolationChunk: Equatable {
    let inputRange: Range<Int>
    let outputRange: Range<Int>

    var localOutputRange: Range<Int> {
        let lowerBound = outputRange.lowerBound - inputRange.lowerBound
        return lowerBound..<(lowerBound + outputRange.count)
    }
}

struct PreparedRecognitionAudio {
    let primaryURL: URL
    let fallbackURL: URL?
    let generatedURLs: [URL]
    let usedVocalIsolation: Bool
    let notice: String?
}

/// Analiz için müziği vokalden ayırır. Üretilen dosyalar yalnız konuşma tanımaya
/// verilir; video dışa aktarımı bu servisin çıktısını hiçbir zaman kullanmaz.
final class VocalIsolationService: @unchecked Sendable {
    static let shared = VocalIsolationService()

    static let modelID = "aufklarer/OpenUnmix-HQ-MLX"
    static let modelSampleRate = 44_100
    static let recognitionSampleRate = 16_000
    static let approximateDownloadMegabytes = 34

    // Tüm parçanın spektrogramını tek seferde tutmak iPhone 14'te gereksiz bellek
    // sıçraması yaratır. 24 sn çekirdek + iki yanda 1.5 sn bağlam, BiLSTM'e yeterli
    // müzik bağlamı verirken tepe belleğini parçanın süresinden bağımsız tutar.
    private static let coreChunkSamples = 24 * modelSampleRate
    private static let contextSamples = modelSampleRate * 3 / 2

    enum IsolationError: Error, LocalizedError {
        case missingVocals
        case invalidAudio

        var errorDescription: String? {
            switch self {
            case .missingVocals:
                return "Vokal modeli geçerli bir ses çıkışı üretmedi."
            case .invalidAudio:
                return "Analiz için geçerli bir ses parçası hazırlanamadı."
            }
        }
    }

    private init() {}

    func prepare(
        sourceURL: URL,
        statusUpdate: @escaping (String) -> Void,
        progressUpdate: @escaping (Double) -> Void
    ) async throws -> PreparedRecognitionAudio {
        try Task.checkCancellation()
        statusUpdate("Orijinal parçanın analiz kopyası hazırlanıyor. Final sesine dokunulmayacak.")

        let stereo = try AudioFileLoader.loadStereo(
            url: sourceURL,
            targetSampleRate: Self.modelSampleRate,
            quality: .mastering
        )
        guard stereo.count == 2,
              !stereo[0].isEmpty,
              stereo[0].count == stereo[1].count else {
            throw IsolationError.invalidAudio
        }

        let originalMixURL = temporaryWAVURL(prefix: "subby_mix")
        let originalMono = Self.downmixToMono(left: stereo[0], right: stereo[1])
        let originalForRecognition = AudioFileLoader.resample(
            originalMono,
            from: Self.modelSampleRate,
            to: Self.recognitionSampleRate,
            quality: .standard
        )
        try WAVWriter.write(
            samples: originalForRecognition,
            sampleRate: Self.recognitionSampleRate,
            to: originalMixURL
        )
        progressUpdate(0.08)
        try Task.checkCancellation()

        do {
            let separator = try await loadVocalsOnlySeparator { fraction, message in
                statusUpdate(message)
                progressUpdate(0.08 + (min(max(fraction, 0), 1) * 0.42))
            }
            try Task.checkCancellation()

            statusUpdate("Vokal müzikten ayrılıyor. Belleği korumak için parça küçük bölümler halinde işleniyor.")
            let vocals44k = try isolateChunked(
                stereo: stereo,
                separator: separator
            ) { fraction in
                progressUpdate(0.50 + (min(max(fraction, 0), 1) * 0.43))
            }
            try Task.checkCancellation()

            statusUpdate("Vokal analiz motoru için hazırlanıyor…")
            let vocals16k = AudioFileLoader.resample(
                vocals44k,
                from: Self.modelSampleRate,
                to: Self.recognitionSampleRate,
                quality: .standard
            )
            let vocalsURL = temporaryWAVURL(prefix: "subby_vocals")
            try WAVWriter.write(
                samples: vocals16k,
                sampleRate: Self.recognitionSampleRate,
                to: vocalsURL
            )
            progressUpdate(1)
            Memory.clearCache()

            return PreparedRecognitionAudio(
                primaryURL: vocalsURL,
                fallbackURL: originalMixURL,
                generatedURLs: [vocalsURL, originalMixURL],
                usedVocalIsolation: true,
                notice: nil
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: originalMixURL)
            Memory.clearCache()
            throw CancellationError()
        } catch {
            // Model indirilemezse veya ayırma cihazda tamamlanamazsa analiz tamamen
            // kaybolmaz; önceden hazırlanan 16 kHz orijinal karışımla devam eder.
            Memory.clearCache()
            progressUpdate(1)
            return PreparedRecognitionAudio(
                primaryURL: originalMixURL,
                fallbackURL: nil,
                generatedURLs: [originalMixURL],
                usedVocalIsolation: false,
                notice: "Vokal ayırma kullanılamadı; orijinal karışım güvenli yedek olarak analiz edildi."
            )
        }
    }

    private func loadVocalsOnlySeparator(
        progress: @escaping (Double, String) -> Void
    ) async throws -> SourceSeparator {
        let cacheDirectory = try HuggingFaceDownloader.getCacheDirectory(
            for: Self.modelID
        )

        progress(0, "Vokal ayırma modeli kontrol ediliyor…")
        try await HuggingFaceDownloader.downloadWeights(
            modelId: Self.modelID,
            to: cacheDirectory,
            additionalFiles: [
                "vocals.safetensors",
                "config.json"
            ]
        ) { fraction in
            progress(fraction * 0.72, "Vokal ayırma modeli indiriliyor…")
        }
        try Task.checkCancellation()

        progress(0.76, "Vokal ayırma modeli yükleniyor…")
        let weightsURL = cacheDirectory.appendingPathComponent(
            "vocals.safetensors"
        )
        guard FileManager.default.fileExists(atPath: weightsURL.path) else {
            throw IsolationError.missingVocals
        }

        let model = OpenUnmixStemModel(
            hiddenSize: OpenUnmixConfig.umxhq.hiddenSize
        )
        let weights = try MLX.loadArrays(url: weightsURL)
        model.update(
            parameters: ModuleParameters.unflattened(weights)
        )
        model.train(false)
        model.prepareForInference()
        progress(1, "Vokal ayırma modeli hazır.")

        // Paket varsayılan olarak dört stemin 136 MB ağırlığını birden yükler.
        // Uygulama yalnız vokale ihtiyaç duyduğu için tek 34 MB modeli bağlıyoruz.
        return SourceSeparator(
            config: .umxhq,
            models: [.vocals: model]
        )
    }

    private func isolateChunked(
        stereo: [[Float]],
        separator: SourceSeparator,
        progress: @escaping (Double) -> Void
    ) throws -> [Float] {
        let totalSamples = stereo[0].count
        let chunks = Self.chunkPlan(
            totalSamples: totalSamples,
            coreSamples: Self.coreChunkSamples,
            contextSamples: Self.contextSamples
        )
        guard !chunks.isEmpty else {
            throw IsolationError.invalidAudio
        }

        var output = [Float](repeating: 0, count: totalSamples)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            let monoSegment: [Float]? = autoreleasepool {
                let left = Array(stereo[0][chunk.inputRange])
                let right = Array(stereo[1][chunk.inputRange])
                let stems = separator.separate(
                    audio: [left, right],
                    sampleRate: Self.modelSampleRate,
                    targets: [.vocals],
                    wiener: false
                )
                guard let vocals = stems[.vocals],
                      vocals.count == 2,
                      vocals[0].count >= chunk.localOutputRange.upperBound,
                      vocals[1].count >= chunk.localOutputRange.upperBound else {
                    return nil
                }
                return chunk.localOutputRange.map { sampleIndex in
                    (vocals[0][sampleIndex] + vocals[1][sampleIndex]) * 0.5
                }
            }
            guard let monoSegment,
                  monoSegment.count == chunk.outputRange.count else {
                throw IsolationError.missingVocals
            }

            for (localIndex, sample) in monoSegment.enumerated() {
                output[chunk.outputRange.lowerBound + localIndex] = sample
            }
            Memory.clearCache()
            progress(Double(index + 1) / Double(chunks.count))
        }
        return output
    }

    static func chunkPlan(
        totalSamples: Int,
        coreSamples: Int,
        contextSamples: Int
    ) -> [VocalIsolationChunk] {
        guard totalSamples > 0, coreSamples > 0 else { return [] }
        let safeContext = max(0, contextSamples)
        var chunks: [VocalIsolationChunk] = []
        var outputStart = 0

        while outputStart < totalSamples {
            let outputEnd = min(totalSamples, outputStart + coreSamples)
            let inputStart = max(0, outputStart - safeContext)
            let inputEnd = min(totalSamples, outputEnd + safeContext)
            chunks.append(
                VocalIsolationChunk(
                    inputRange: inputStart..<inputEnd,
                    outputRange: outputStart..<outputEnd
                )
            )
            outputStart = outputEnd
        }
        return chunks
    }

    static func downmixToMono(left: [Float], right: [Float]) -> [Float] {
        let count = min(left.count, right.count)
        guard count > 0 else { return [] }
        return (0..<count).map { (left[$0] + right[$0]) * 0.5 }
    }

    private func temporaryWAVURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + "_" + UUID().uuidString)
            .appendingPathExtension("wav")
    }
}
