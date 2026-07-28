import Foundation
import AVFoundation
import WhisperKit
import Photos
import ffmpegkit
import CoreText

enum AnalysisQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case best

    // large-v3 Turbo modeli 626 MB olsa da Core ML özelleştirme ve çözümleme
    // sırasında bunun birkaç katı geçici bellek kullanabilir. 8 GB altındaki
    // cihazlarda iOS uygulamayı hata vermeden (jetsam) kapatabildiği için bu
    // cihazlarda "En İyi" seçiminde small modele güvenli biçimde düşülür.
    static let largeModelMinimumPhysicalMemory = UInt64(8) * 1_024 * 1_024 * 1_024

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Hızlı"
        case .balanced: return "Dengeli"
        case .best: return "En İyi"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            return "Daha küçük model • eski cihazlar ve konuşma için"
        case .balanced:
            return "Önerilen • iyi Türkçe doğruluğu ve düşük çökme riski"
        case .best:
            if usesMemorySafeFallback {
                return "Bu cihazda çökme riskini azaltmak için bellek dostu model kullanılır"
            }
            return "Şarkı sözlerinde daha isabetli • daha fazla bellek kullanır"
        }
    }

    var usesMemorySafeFallback: Bool {
        self == .best && ProcessInfo.processInfo.physicalMemory < Self.largeModelMinimumPhysicalMemory
    }

    func modelCandidates(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> [String] {
        switch self {
        case .fast:
            return ["openai_whisper-base"]
        case .balanced:
            return ["openai_whisper-small", "openai_whisper-base"]
        case .best:
            guard physicalMemory >= Self.largeModelMinimumPhysicalMemory else {
                return ["openai_whisper-small", "openai_whisper-base"]
            }
            return [
                "openai_whisper-large-v3-v20240930_626MB",
                "openai_whisper-small",
                "openai_whisper-base"
            ]
        }
    }
}

enum KaraokeMode: String, CaseIterable, Identifiable, Codable {
    case classic
    case kinetic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Klasik"
        case .kinetic: return "Kinetik"
        }
    }

    var detail: String {
        switch self {
        case .classic:
            return "Okunaklı satır düzeni ve harf harf karaoke takibi."
        case .kinetic:
            return "Vokal temposu ve anlam vurgusuna göre boyut, kompozisyon ve hareket üretir."
        }
    }

    static func resolved(_ rawValue: String?) -> KaraokeMode {
        guard let rawValue else { return .classic }
        return KaraokeMode(rawValue: rawValue) ?? .classic
    }
}

enum KineticStyle: String, CaseIterable, Identifiable, Codable {
    case automatic
    case cinematic
    case editorial
    case impact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .cinematic: return "Sinematik"
        case .editorial: return "Editoryal"
        case .impact: return "Vurucu"
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .cinematic: return "film.stack"
        case .editorial: return "rectangle.3.group"
        case .impact: return "bolt.fill"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Parçanın tamamından tek bir görsel kimlik çıkarır; nakarat, bölüm ve enerji değişimlerinde yalnız uyumlu sahneleri birlikte kullanır."
        case .cinematic:
            return "Yumuşak girişler, sakin ölçek ve temiz cümle kompozisyonları kullanır."
        case .editorial:
            return "Sözü afiş gibi iki veya üç katmanlı, güçlü bir tipografik düzende kurar."
        case .impact:
            return "Her kelimeyi ritim üzerinde tek tek, büyük ve net kesmelerle öne çıkarır."
        }
    }

    static func resolved(_ rawValue: String?) -> KineticStyle {
        guard let rawValue else { return .automatic }
        return KineticStyle(rawValue: rawValue) ?? .automatic
    }
}

enum KineticAccent: String, CaseIterable, Identifiable, Codable {
    case gold
    case coral
    case ice
    case violet
    case mint
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gold: return "Altın"
        case .coral: return "Mercan"
        case .ice: return "Buz"
        case .violet: return "Menekşe"
        case .mint: return "Nane"
        case .custom: return "Özel"
        }
    }

    static let defaultCustomHex = "#FECC2F"

    static var presetCases: [KineticAccent] {
        allCases.filter { $0 != .custom }
    }

    private var presetHex: String {
        switch self {
        case .gold: return "#FECC2F"
        case .coral: return "#FF5C7A"
        case .ice: return "#58D5FF"
        case .violet: return "#A78BFA"
        case .mint: return "#54E6A5"
        case .custom: return Self.defaultCustomHex
        }
    }

    func resolvedColor(customHex: String?) -> KineticResolvedColor {
        KineticResolvedColor(
            hex: self == .custom
                ? (customHex ?? Self.defaultCustomHex)
                : presetHex
        )
    }

    // ASS renkleri BBGGRR sırasındadır.
    var assColor: String {
        resolvedColor(customHex: nil).assColor
    }

    var rgb: (red: Double, green: Double, blue: Double) {
        let color = resolvedColor(customHex: nil)
        return (color.red, color.green, color.blue)
    }

    static func resolved(_ rawValue: String?) -> KineticAccent {
        guard let rawValue else { return .gold }
        return KineticAccent(rawValue: rawValue) ?? .gold
    }
}

struct KineticResolvedColor: Equatable {
    let hex: String
    let redByte: Int
    let greenByte: Int
    let blueByte: Int

    init(hex rawValue: String) {
        let normalized = Self.normalizedHex(rawValue) ?? KineticAccent.defaultCustomHex
        let digits = String(normalized.dropFirst())
        let value = UInt32(digits, radix: 16) ?? 0xFECC2F
        hex = normalized
        redByte = Int((value >> 16) & 0xFF)
        greenByte = Int((value >> 8) & 0xFF)
        blueByte = Int(value & 0xFF)
    }

    var red: Double { Double(redByte) / 255.0 }
    var green: Double { Double(greenByte) / 255.0 }
    var blue: Double { Double(blueByte) / 255.0 }

    // ASS renkleri BBGGRR sırasındadır.
    var assColor: String {
        String(format: "%02X%02X%02X", blueByte, greenByte, redByte)
    }

    // WCAG göreli parlaklığın sadeleştirilmiş, video üstü metin için daha güvenli eşiği.
    // Parlak kapsüllerde siyah, koyu kapsüllerde beyaz aktif metin kullanılır.
    var usesDarkForeground: Bool {
        let luminance = (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
        return luminance >= 0.56
    }

    var foregroundASSColor: String {
        usesDarkForeground ? "000000" : "FFFFFF"
    }

    static func normalizedHex(_ rawValue: String?) -> String? {
        guard var digits = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(), !digits.isEmpty else {
            return nil
        }
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6,
              digits.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789ABCDEF").contains($0)
              }) else {
            return nil
        }
        return "#" + digits
    }
}

enum KineticOverlayStyle: String, CaseIterable, Identifiable, Codable {
    case automatic
    case none
    case glass
    case cinematicBand
    case accentPanel
    case spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .none: return "Kapalı"
        case .glass: return "Cam"
        case .cinematicBand: return "Sinema"
        case .accentPanel: return "Panel"
        case .spotlight: return "Spot"
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "wand.and.rays"
        case .none: return "rectangle.slash"
        case .glass: return "rectangle.fill"
        case .cinematicBand: return "rectangle.split.3x1.fill"
        case .accentPanel: return "rectangle.split.2x1.fill"
        case .spotlight: return "scope"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Parçanın görsel kimliğine göre uyumlu iki veya üç katmanı bölüm boyunca yönetir; bağımsız ve rastgele seçim yapmaz."
        case .none:
            return "Arka katman kullanmaz; yalnız tipografi ve kelime vurguları görünür."
        case .glass:
            return "Yazı grubunu ince konturlu, yarı saydam sinematik bir kartta toplar."
        case .cinematicBand:
            return "Alt bölgeyi yatay bir film bandı ve ince vurgu çizgisiyle sakinleştirir."
        case .accentPanel:
            return "Editoryal kompozisyona koyu bir plaka ve renkli kenar imzası ekler."
        case .spotlight:
            return "Söylenen kelimenin arkasında ritimle değişen kontrollü bir odak plakası kullanır."
        }
    }

    func resolved(for scene: KineticScene) -> KineticOverlayStyle {
        guard self == .automatic else { return self }
        switch scene {
        case .phraseBuild, .captionWindow:
            return .glass
        case .editorialStack, .chorusLockup:
            return .accentPanel
        case .focusCut, .impactSequence:
            return .spotlight
        }
    }

    func resolved(for plan: KineticTypographyPlan) -> KineticOverlayStyle {
        guard self == .automatic else { return self }
        switch plan.creativeDirection {
        case .cinematicFlow:
            switch plan.scene {
            case .editorialStack, .chorusLockup: return .accentPanel
            case .phraseBuild, .captionWindow, .focusCut, .impactSequence: return .glass
            }
        case .editorialStory:
            switch plan.scene {
            case .editorialStack, .chorusLockup: return .accentPanel
            case .phraseBuild, .captionWindow, .focusCut, .impactSequence: return .glass
            }
        case .rhythmicPulse:
            switch plan.scene {
            case .focusCut, .impactSequence: return .spotlight
            case .captionWindow: return .cinematicBand
            case .editorialStack, .chorusLockup: return .accentPanel
            case .phraseBuild: return .glass
            }
        case .anthemLift:
            switch plan.scene {
            case .editorialStack, .chorusLockup: return .accentPanel
            case .focusCut, .impactSequence: return .spotlight
            case .phraseBuild, .captionWindow: return .cinematicBand
            }
        }
    }

    static func resolved(_ rawValue: String?) -> KineticOverlayStyle {
        // Eski projelerin görünümü kendiliğinden değişmesin.
        guard let rawValue else { return .none }
        return KineticOverlayStyle(rawValue: rawValue) ?? .none
    }
}

enum KineticIntensity: String, CaseIterable, Identifiable, Codable {
    case subtle
    case balanced
    case energetic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: return "Sakin"
        case .balanced: return "Dengeli"
        case .energetic: return "Enerjik"
        }
    }

    var detail: String {
        switch self {
        case .subtle:
            return "Daha küçük hareket ve yumuşak vurgu; melankolik ve sakin parçalar için."
        case .balanced:
            return "Önerilen; okunabilirlik ile kinetik hareket arasında kontrollü denge."
        case .energetic:
            return "Daha hızlı giriş ve güçlü aktif kelime darbesi; yüksek tempolu parçalar için."
        }
    }

    var motionMultiplier: Double {
        switch self {
        case .subtle: return 0.58
        case .balanced: return 1
        case .energetic: return 1.18
        }
    }

    var durationMultiplier: Double {
        switch self {
        case .subtle: return 1.16
        case .balanced: return 1
        case .energetic: return 0.84
        }
    }

    var activeScale: Int {
        switch self {
        case .subtle: return 102
        case .balanced: return 105
        case .energetic: return 109
        }
    }

    static func resolved(_ rawValue: String?) -> KineticIntensity {
        guard let rawValue else { return .balanced }
        return KineticIntensity(rawValue: rawValue) ?? .balanced
    }
}

enum KineticLetterStyle: String, CaseIterable, Identifiable, Codable {
    case automatic
    case clean
    case poster
    case rhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .clean: return "Temiz"
        case .poster: return "Afiş"
        case .rhythm: return "Ritim"
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "wand.and.rays"
        case .clean: return "textformat"
        case .poster: return "character.textbox"
        case .rhythm: return "waveform.path"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Sahneye göre temiz, geniş, afiş veya ritmik harf düzenini kontrollü seçer."
        case .clean:
            return "Bütün harfleri aynı ölçüde tutar; mevcut sade ve güvenli görünüm."
        case .poster:
            return "Yalnız odak kelimesinin anlam merkezindeki bir harfi büyütür."
        case .rhythm:
            return "Odak kelimesinde sesli harfleri hece akışına göre ölçülü dalgalandırır."
        }
    }

    static func resolved(_ rawValue: String?) -> KineticLetterStyle {
        guard let rawValue else { return .clean }
        return KineticLetterStyle(rawValue: rawValue) ?? .clean
    }
}

enum KineticGlyphTreatment: String, Equatable {
    case standard
    case wide
    case poster
    case rhythm
}

struct KineticGlyphDesign {
    let characters: [Character]
    let scaleFactors: [Double]
    let trackingFactor: Double
    let treatment: KineticGlyphTreatment

    var maximumScale: Double {
        scaleFactors.max() ?? 1
    }
}

enum KineticScene: String, Equatable {
    case phraseBuild
    case captionWindow
    case focusCut
    case editorialStack
    case chorusLockup
    case impactSequence
}

enum KineticMotion: String, Equatable {
    case softLift
    case pagePop
    case sideReveal
    case lockedReveal
    case punchCut
}

enum KineticHighlight: String, Equatable {
    case color
    case pill
    case underline
    case glow
}

enum KineticEnergy: String, Equatable {
    case calm
    case steady
    case driving
}

enum KineticCreativeDirection: String, Equatable {
    case cinematicFlow
    case editorialStory
    case rhythmicPulse
    case anthemLift

    var title: String {
        switch self {
        case .cinematicFlow: return "Sinematik Akış"
        case .editorialStory: return "Editoryal Anlatı"
        case .rhythmicPulse: return "Ritmik Darbe"
        case .anthemLift: return "Nakarat Yükselişi"
        }
    }

    var detail: String {
        switch self {
        case .cinematicFlow:
            return "Uzun vokaller ve geniş boşluklar için sakin plakalar, nefesli harf aralığı ve yumuşak geçişler."
        case .editorialStory:
            return "Orta tempolu anlatıda Cam ve Panel kompozisyonlarını afiş vurgularıyla dengeler."
        case .rhythmicPulse:
            return "Hızlı vokalde Sinema bandı ve Spot katmanını kısa kelime kesmeleriyle birlikte kullanır."
        case .anthemLift:
            return "Tekrarlanan nakaratları sabit bir imza düzeninde tutup bölüm yükselişlerini kontrollü büyütür."
        }
    }
}

struct KineticTypographyPlan: Equatable {
    let scene: KineticScene
    let motion: KineticMotion
    let highlight: KineticHighlight
    let energy: KineticEnergy
    let creativeDirection: KineticCreativeDirection
    let emphasisIndex: Int
    let rows: [[Int]]
    let pages: [[Int]]
    let repeatCount: Int
}

class VideoProcessor: ObservableObject {
    static let shared = VideoProcessor()
    
    // Uygulama içi fısıltı sonuçları (Identifiable, Hashable ve Codable uyumlu)
    struct WordTimestamp: Identifiable, Hashable, Codable {
        var id = UUID()
        var text: String
        var start: Double
        var end: Double
    }
    
    // 1. Sesi Videodan 16kHz Mono WAV (PCM) olarak çıkarma
    func extractAudio(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subby_audio_" + UUID().uuidString)
            .appendingPathExtension("wav")
        
        let inPath = videoURL.path
        let outPath = outputURL.path

        // Whisper için ideal format: 16kHz, Tek Kanal (Mono), 16-bit PCM WAV
        // Not: Bandpass filtresi kullanılmıyor; Whisper tam bant ses ile eğitildiği için
        // 3kHz üstünü kesmek ünsüz seslerini silip transkripsiyon kalitesini düşürür.
        let args = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", inPath,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            outPath
        ]
        
        FFmpegKit.execute(withArgumentsAsync: args) { session in
            guard let session = session else {
                self.completeOnMain { completion(nil) }
                return
            }
            
            let returnCode = session.getReturnCode()
            if ReturnCode.isSuccess(returnCode),
               FileManager.default.fileExists(atPath: outputURL.path) {
                self.completeOnMain { completion(outputURL) }
            } else {
                let logs = session.getLogsAsString() ?? ""
                print("FFmpeg ses çıkarma hatası: \(logs)")
                self.deleteFile(at: outputURL)
                self.completeOnMain { completion(nil) }
            }
        }
    }

    private let recognitionLock = NSLock()
    private var recognitionTask: Task<Void, Never>?
    private var recognitionID: UUID?

    // Seçilen kalite için ilk çalışan modeli indirir. prewarm, Core ML modellerini
    // sırayla özelleştirip tepe bellek kullanımını belirgin biçimde düşürür.
    private func loadModel(
        quality: AnalysisQuality,
        downloadProgress: @escaping (Double) -> Void
    ) async throws -> WhisperKit {
        var lastError: Error?
        for candidate in quality.modelCandidates() {
            try Task.checkCancellation()
            do {
                let modelFolder = try await WhisperKit.download(
                    variant: candidate,
                    progressCallback: { progress in
                        downloadProgress(min(max(progress.fractionCompleted, 0), 1))
                    }
                )
                try Task.checkCancellation()
                downloadProgress(1.0)

                let config = WhisperKitConfig(
                    modelFolder: modelFolder.path,
                    verbose: false,
                    prewarm: true
                )
                return try await WhisperKit(config)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                print("Model '\(candidate)' yüklenemedi, sıradakine geçiliyor: \(error.localizedDescription)")
                lastError = error
            }
        }
        throw lastError ?? NSError(
            domain: "VideoProcessor",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Hiçbir yapay zeka modeli yüklenemedi."]
        )
    }

    // 2. Yapay Zeka WhisperKit (CoreML) ile Sesi Metne Çevirme (Python hassasiyetinde kelime kelime zamanlama)
    // downloadProgress: model ilk kez indirilirken 0.0-1.0 arası ilerleme bildirir
    func runSpeechRecognition(
        audioURL: URL,
        quality: AnalysisQuality,
        downloadProgress: @escaping (Double) -> Void,
        completion: @escaping ([WordTimestamp], String?) -> Void
    ) {
        cancelSpeechRecognition()
        let recognitionID = UUID()
        recognitionLock.lock()
        self.recognitionID = recognitionID
        recognitionLock.unlock()

        let task = Task(priority: .userInitiated) {
            var whisperKit: WhisperKit?
            do {
                // Model ilk kullanımda indirilir; daha sonraki analizlerde disk önbelleğinden yüklenir.
                let loadedModel = try await self.loadModel(
                    quality: quality,
                    downloadProgress: downloadProgress
                )
                whisperKit = loadedModel
                try Task.checkCancellation()

                // VAD uzun müzik dosyalarını konuşma bölgelerine böler. Tek işçi kullanmak,
                // büyük modelde birden fazla Core ML çözümlemesinin aynı anda belleğe
                // binmesini ve iOS'un uygulamayı sonlandırmasını önler.
                var options = DecodingOptions()
                options.language = "tr"
                options.wordTimestamps = true
                options.skipSpecialTokens = true
                options.chunkingStrategy = .vad
                options.concurrentWorkerCount = 1

                let results = try await loadedModel.transcribe(
                    audioPath: audioURL.path,
                    decodeOptions: options,
                    callback: { [weak self] _ in
                        self?.isRecognitionActive(recognitionID) ?? false
                    }
                )

                var words: [WordTimestamp] = []
                for result in results {
                    for segment in result.segments {
                        if let segmentWords = segment.words, !segmentWords.isEmpty {
                            for word in segmentWords {
                                let text = self.cleanRecognizedText(word.word)
                                let start = Double(word.start)
                                let end = Double(word.end)
                                if !text.isEmpty, start.isFinite, end.isFinite {
                                    words.append(WordTimestamp(
                                        text: text,
                                        start: max(0, start),
                                        end: max(max(0, start) + 0.05, end)
                                    ))
                                }
                            }
                        } else {
                            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            let rawWords = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                            let rawStart = Double(segment.start)
                            let rawEnd = Double(segment.end)
                            guard rawStart.isFinite, rawEnd.isFinite, !rawWords.isEmpty else { continue }
                            let segmentStart = max(0, rawStart)
                            let minimumDuration = Double(rawWords.count) * 0.05
                            let segmentEnd = max(segmentStart + minimumDuration, rawEnd)
                            let wordDur = (segmentEnd - segmentStart) / Double(rawWords.count)

                            for (index, wordText) in rawWords.enumerated() {
                                let cleanText = self.cleanRecognizedText(wordText)
                                if !cleanText.isEmpty {
                                    let start = segmentStart + (Double(index) * wordDur)
                                    words.append(WordTimestamp(
                                        text: cleanText,
                                        start: start,
                                        end: start + wordDur
                                    ))
                                }
                            }
                        }
                    }
                }

                try Task.checkCancellation()
                let normalizedWords = self.normalizeRecognizedWords(words)
                await loadedModel.unloadModels()
                whisperKit = nil
                try Task.checkCancellation()

                guard self.finishRecognitionIfActive(recognitionID) else { return }
                self.completeOnMain {
                    if normalizedWords.isEmpty {
                        completion([], "Videoda deşifre edilebilecek net bir vokal veya konuşma bulunamadı.")
                    } else {
                        completion(normalizedWords, nil)
                    }
                }
            } catch is CancellationError {
                if let whisperKit {
                    await whisperKit.unloadModels()
                }
                if self.finishRecognitionIfActive(recognitionID) {
                    self.completeOnMain {
                        completion([], "İşlem iptal edildi.")
                    }
                }
            } catch {
                if let whisperKit {
                    await whisperKit.unloadModels()
                }
                print("WhisperKit hatası: \(error.localizedDescription)")
                let message = self.friendlyRecognitionError(error)
                if self.finishRecognitionIfActive(recognitionID) {
                    self.completeOnMain {
                        completion([], message)
                    }
                }
            }
        }

        recognitionLock.lock()
        if self.recognitionID == recognitionID {
            recognitionTask = task
        } else {
            task.cancel()
        }
        recognitionLock.unlock()
    }

    func cancelSpeechRecognition() {
        recognitionLock.lock()
        let task = recognitionTask
        recognitionTask = nil
        recognitionID = nil
        recognitionLock.unlock()
        task?.cancel()
    }

    private func isRecognitionActive(_ id: UUID) -> Bool {
        recognitionLock.lock()
        defer { recognitionLock.unlock() }
        return recognitionID == id
    }

    // Yalnız hâlâ güncel olan analizin sonucu arayüze ulaşır. Kullanıcı yeni bir
    // video seçtiğinde eski model görevinin gecikmiş callback'i yeni akışı bozamaz.
    private func finishRecognitionIfActive(_ id: UUID) -> Bool {
        recognitionLock.lock()
        defer { recognitionLock.unlock() }
        guard recognitionID == id else { return false }
        recognitionTask = nil
        recognitionID = nil
        return true
    }

    func cancelAllProcessing() {
        cancelSpeechRecognition()
        FFmpegKit.cancel()
    }

    // Render sırasında kaynak video ile çıktı bir süre aynı anda diskte kalır.
    // En az 350 MB veya kaynak boyutunun iki katı boşluk yoksa işlemi başlatmayarak
    // yarım çıktı ve anlaşılmaz FFmpeg hatalarının önüne geçer.
    func hasEnoughSpaceToRender(videoURL: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? videoURL.resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            // Kapasite sorgusu bazı dosya sağlayıcılarında desteklenmez; FFmpeg'in
            // gerçek hatasına izin vermek, geçerli videoyu yanlışlıkla engellemekten iyidir.
            return true
        }
        let inputSize = Int64(values.fileSize ?? 0)
        let required = renderSpaceRequirement(forInputBytes: inputSize)
        return available > required
    }

    func renderSpaceRequirement(forInputBytes inputSize: Int64) -> Int64 {
        let minimum = Int64(350 * 1_024 * 1_024)
        let safeInputSize = max(0, inputSize)
        let scaledSize = safeInputSize > Int64.max / 2 ? Int64.max : safeInputSize * 2
        return max(minimum, scaledSize)
    }

    // Yarım kalan analiz/kodlama işlemlerinin geçici dosyaları sonraki açılışlarda
    // depolamayı şişirmesin. Yalnız uygulamanın kendi önekleri hedeflenir.
    func cleanupStaleTemporaryFiles(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("subby_") || name.hasPrefix("ass_fonts_") else { continue }
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard (values?.contentModificationDate ?? .distantPast) < cutoff else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    func cleanRecognizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.,!?;:]+$", with: "", options: .regularExpression)
    }

    // VAD sınırlarında oluşabilen yinelenen kelimeleri temizler, bozuk/çakışan
    // zamanları onarır ve Whisper'ın sessizlikte üretebildiği müzik işaretlerini atar.
    // İç erişim testlerin gerçek üretim algoritmasını doğrulayabilmesi içindir.
    func normalizeRecognizedWords(_ words: [WordTimestamp]) -> [WordTimestamp] {
        let ignoredMarkers = Set([
            "[müzik]", "(müzik)", "[music]", "(music)",
            "[alkış]", "(alkış)", "[applause]", "(applause)",
            "♪", "♫"
        ])
        let sorted = words.compactMap { word -> WordTimestamp? in
            let text = cleanRecognizedText(word.text)
            guard word.start.isFinite, word.end.isFinite, !text.isEmpty else { return nil }
            guard !ignoredMarkers.contains(text.lowercased(with: Locale(identifier: "tr_TR"))) else {
                return nil
            }
            let start = max(0, word.start)
            return WordTimestamp(
                id: word.id,
                text: text,
                start: start,
                end: max(start + 0.05, word.end)
            )
        }.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }

        var normalized: [WordTimestamp] = []
        for var word in sorted {
            if let previous = normalized.last,
               previous.text.compare(word.text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
               duplicateOverlapRatio(previous, word) >= 0.6 {
                if word.end > previous.end {
                    normalized[normalized.count - 1].end = word.end
                }
                continue
            }

            // Tek vokal hattındaki sözcükler çakıştığında iki kelime arasındaki
            // sınırı ortalar. Bu, ASS animasyonunun geri sıçramasını engeller.
            if var previous = normalized.last, previous.end > word.start {
                let midpoint = (previous.end + word.start) / 2
                let lowerBound = previous.start + 0.05
                let upperBound = max(lowerBound, word.end - 0.05)
                let boundary = min(max(midpoint, lowerBound), upperBound)
                previous.end = boundary
                normalized[normalized.count - 1] = previous
                word.start = boundary
                word.end = max(word.start + 0.05, word.end)
            }
            normalized.append(word)
        }
        return normalized
    }

    private func duplicateOverlapRatio(_ lhs: WordTimestamp, _ rhs: WordTimestamp) -> Double {
        let overlap = max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
        let shorterDuration = max(0.05, min(lhs.end - lhs.start, rhs.end - rhs.start))
        return overlap / shorterDuration
    }

    private func friendlyRecognitionError(_ error: Error) -> String {
        let description = error.localizedDescription
        let lowercased = description.lowercased()
        if lowercased.contains("network") || lowercased.contains("internet") ||
            lowercased.contains("offline") || lowercased.contains("timed out") {
            return "Yapay zeka modeli indirilemedi. İnternet bağlantını kontrol edip tekrar dene."
        }
        if lowercased.contains("space") || lowercased.contains("disk") {
            return "Model için yeterli boş alan yok. Cihazda yer açıp tekrar dene."
        }
        if lowercased.contains("memory") || lowercased.contains("allocation") {
            return "Cihaz belleği bu model için yetersiz kaldı. Analiz kalitesini “Dengeli” veya “Hızlı” seçip tekrar dene."
        }
        return "Yapay zeka analizi tamamlanamadı: \(description)"
    }

    private func completeOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
    
    // Font PostScript isimlerini libass/fontconfig'in tanıyacağı Font Family isimlerine dönüştürür.
    private func getFontFamilyName(for fontName: String) -> String {
        if let secenek = FontCatalog.secenek(fontName) { return secenek.assFamily }
        return fontName.replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Heavy", with: "").replacingOccurrences(of: "-Regular", with: "")
    }
    
    // Kelimeler arası boşluk ve satır uzunluğuna göre otomatik satır önerisi üretir
    // (en fazla 4 kelime / ~18 karakter; 0.8 sn'den uzun boşlukta yeni satır)
    func autoLineGroups(for words: [WordTimestamp]) -> [[WordTimestamp]] {
        var groups: [[WordTimestamp]] = []
        var current: [WordTimestamp] = []
        var currentChars = 0

        for word in words {
            let wordLength = word.text.count
            if let lastWord = current.last {
                let gap = word.start - lastWord.end
                if current.count >= 4 || currentChars + wordLength > 18 || gap > 0.8 {
                    groups.append(current)
                    current = []
                    currentChars = 0
                }
            }
            current.append(word)
            currentChars += wordLength + 1
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // Otomatik önerinin "satır sonu" kelime kimliklerini döndürür (satır düzenleyici için)
    func autoLineBreaks(for words: [WordTimestamp]) -> Set<UUID> {
        var result = Set<UUID>()
        for group in autoLineGroups(for: words) {
            if let last = group.last { result.insert(last.id) }
        }
        return result
    }

    // El yazısı süpürmesi için: satırdaki her karakterin BİTİŞ x konumunu ve toplam satır
    // genişliğini ASS piksel biriminde ölçer. libass, font boyutunu "hücre yüksekliği"
    // (çıkıcı+inici) olarak yorumlar (FreeType REAL_DIM); CoreText ise em puntosuyla
    // çalışır — punto bu orana göre çevrilir. Ölçüm CTLine ile, bitişik şekillendirme
    // (kern/liga/calt) açıkken yapılır; libass'ın HarfBuzz çıktısıyla örtüşür.
    private func harfSinirlariniOlc(metin: String, fontName: String, assFontSize: Int) -> (genislik: Double, sinirlar: [Double])? {
        guard !metin.isEmpty else { return nil }

        let probe = CTFontCreateWithName(fontName as CFString, 1000, nil)
        // CoreText fontu bulamayıp başka fonta düştüyse ölçüm geçersizdir
        let resolvedName = CTFontCopyPostScriptName(probe) as String
        guard resolvedName.caseInsensitiveCompare(fontName) == .orderedSame else { return nil }

        let hucre = CTFontGetAscent(probe) + CTFontGetDescent(probe)
        guard hucre > 0 else { return nil }
        let punto = Double(assFontSize) * 1000.0 / Double(hucre)

        let font = CTFontCreateWithName(fontName as CFString, CGFloat(punto), nil)
        let attr = NSAttributedString(string: metin, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let genislik = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard genislik > 0 else { return nil }

        var sinirlar: [Double] = []
        for i in 1...metin.utf16.count {
            sinirlar.append(Double(CTLineGetOffsetForStringIndex(line, i, nil)))
        }
        return (genislik, sinirlar)
    }

    // Kullanıcı eski bir projede bozuk/çakışan zamanlar kaydetmiş olsa bile ASS
    // üretimi geçerli ve ileri doğru akan zamanlarla devam eder. Kimlikler korunur;
    // böylece onaylanmış satır sonları bozulmaz.
    func prepareWordsForRendering(_ words: [WordTimestamp], maximumTime: Double? = nil) -> [WordTimestamp] {
        let safeMaximum = maximumTime.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var prepared: [WordTimestamp] = []

        for original in words {
            var word = original
            word.text = word.text
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let fallbackStart = prepared.last?.end ?? 0
            word.start = word.start.isFinite ? max(0, word.start) : fallbackStart
            word.end = word.end.isFinite ? max(word.start + 0.05, word.end) : word.start + 0.05

            if let safeMaximum {
                guard word.start < safeMaximum else { continue }
                word.end = min(word.end, safeMaximum)
                guard word.end > word.start else { continue }
            }

            if var previous = prepared.last, previous.end > word.start {
                let midpoint = (previous.end + word.start) / 2
                let lowerBound = previous.start + 0.05
                let upperBound = max(lowerBound, word.end - 0.05)
                let boundary = min(max(midpoint, lowerBound), upperBound)
                previous.end = boundary
                prepared[prepared.count - 1] = previous
                word.start = boundary
                word.end = max(word.start + 0.05, word.end)
                if let safeMaximum {
                    word.end = min(word.end, safeMaximum)
                    guard word.start < safeMaximum, word.end > word.start else { continue }
                }
            }

            prepared.append(word)
        }
        return prepared
    }

    // Kinetik yönetmen önce sabit bir tipografik iskelet kurar, ardından hareketi bu
    // iskeletin çevresinde uygular. Kelimeler artık satır numarasına göre rastgele
    // büyütülmez, döndürülmez veya zıplatılmaz. Aynı nakarat metni her tekrarında aynı
    // sahneyi kullanır; yalnız karaoke vurgusu gerçek kelime zamanlamasını takip eder.
    func kineticTypographyPlan(
        for words: [WordTimestamp],
        lineIndex: Int,
        style: KineticStyle = .automatic,
        repeatCount: Int = 1,
        emphasisWordID: UUID? = nil,
        creativeDirection: KineticCreativeDirection? = nil
    ) -> KineticTypographyPlan {
        let direction = creativeDirection
            ?? kineticCreativeDirection(for: [words], style: style)
        guard !words.isEmpty else {
            return KineticTypographyPlan(
                scene: .phraseBuild,
                motion: .softLift,
                highlight: .color,
                energy: .calm,
                creativeDirection: direction,
                emphasisIndex: 0,
                rows: [],
                pages: [],
                repeatCount: max(1, repeatCount)
            )
        }

        let durations = words.map { max(0.05, $0.end - $0.start) }
        let lineStart = words.first?.start ?? 0
        let lineEnd = words.last?.end ?? lineStart + 0.05
        let lineDuration = max(0.05, lineEnd - lineStart)
        let cadence = Double(words.count) / lineDuration
        let longestDuration = durations.max() ?? 0
        let automaticEmphasisIndex = semanticEmphasisIndex(words: words, durations: durations)
        let emphasisIndex = emphasisWordID
            .flatMap { selectedID in words.firstIndex(where: { $0.id == selectedID }) }
            ?? automaticEmphasisIndex
        let energy: KineticEnergy
        if cadence >= 3.4 {
            energy = .driving
        } else if cadence <= 1.7 || longestDuration >= 0.72 {
            energy = .calm
        } else {
            energy = .steady
        }
        let scene: KineticScene

        switch style {
        case .automatic:
            scene = automaticKineticScene(
                wordCount: words.count,
                energy: energy,
                repeatCount: repeatCount,
                direction: direction
            )
        case .cinematic:
            scene = words.count <= 2 ? .focusCut : .phraseBuild
        case .editorial:
            scene = words.count <= 2 ? .focusCut : .editorialStack
        case .impact:
            scene = .impactSequence
        }

        // lineIndex API uyumluluğu ve ön izleme çağrılarında satır kimliği için korunur.
        // Sahne seçimi özellikle bu değere bağlanmaz; satır sırası tasarımı değiştirmez.
        _ = lineIndex
        return composeKineticPlan(
            for: words,
            scene: scene,
            energy: energy,
            emphasisIndex: emphasisIndex,
            repeatCount: repeatCount,
            style: style,
            creativeDirection: direction
        )
    }

    private func automaticKineticScene(
        wordCount: Int,
        energy: KineticEnergy,
        repeatCount: Int,
        direction: KineticCreativeDirection
    ) -> KineticScene {
        if repeatCount > 1, wordCount > 2 {
            return .chorusLockup
        }
        if wordCount <= 2 {
            return .focusCut
        }

        switch direction {
        case .cinematicFlow:
            return energy == .driving ? .captionWindow : .phraseBuild
        case .editorialStory:
            return energy == .calm ? .phraseBuild : .captionWindow
        case .rhythmicPulse:
            switch energy {
            case .driving: return .impactSequence
            case .steady: return .captionWindow
            case .calm: return .phraseBuild
            }
        case .anthemLift:
            switch energy {
            case .driving: return .impactSequence
            case .steady: return .captionWindow
            case .calm: return .phraseBuild
            }
        }
    }

    private func composeKineticPlan(
        for words: [WordTimestamp],
        scene: KineticScene,
        energy: KineticEnergy,
        emphasisIndex: Int,
        repeatCount: Int,
        style: KineticStyle,
        creativeDirection: KineticCreativeDirection
    ) -> KineticTypographyPlan {
        let pages: [[Int]]
        if scene == .captionWindow {
            pages = kineticCaptionPages(for: words)
        } else {
            pages = [Array(words.indices)]
        }

        let rows: [[Int]]
        switch scene {
        case .focusCut, .impactSequence:
            rows = [Array(words.indices)]
        case .captionWindow:
            rows = pages.first.map { [$0] } ?? []
        case .phraseBuild:
            let characterCount = words.reduce(0) { $0 + $1.text.count }
            rows = (words.count >= 6 || characterCount > 28)
                ? balancedKineticRows(for: words)
                : [Array(words.indices)]
        case .chorusLockup:
            rows = words.count >= 4 ? balancedKineticRows(for: words) : [Array(words.indices)]
        case .editorialStack:
            var designedRows: [[Int]] = []
            let before = Array(words.indices.filter { $0 < emphasisIndex })
            let after = Array(words.indices.filter { $0 > emphasisIndex })
            if !before.isEmpty { designedRows.append(before) }
            designedRows.append([emphasisIndex])
            if !after.isEmpty { designedRows.append(after) }
            rows = designedRows
        }

        let motion: KineticMotion
        switch scene {
        case .phraseBuild: motion = .softLift
        case .captionWindow: motion = .pagePop
        case .focusCut, .impactSequence: motion = .punchCut
        case .editorialStack: motion = .sideReveal
        case .chorusLockup: motion = .lockedReveal
        }

        let highlight: KineticHighlight
        switch style {
        case .cinematic:
            highlight = .color
        case .editorial:
            highlight = .underline
        case .impact:
            highlight = .glow
        case .automatic:
            switch creativeDirection {
            case .cinematicFlow:
                switch scene {
                case .editorialStack, .chorusLockup: highlight = .underline
                case .phraseBuild, .captionWindow, .focusCut, .impactSequence:
                    highlight = .color
                }
            case .editorialStory:
                switch scene {
                case .editorialStack, .chorusLockup, .focusCut: highlight = .underline
                case .captionWindow: highlight = .pill
                case .phraseBuild, .impactSequence: highlight = .color
                }
            case .rhythmicPulse, .anthemLift:
                switch scene {
                case .captionWindow: highlight = .pill
                case .editorialStack, .chorusLockup: highlight = .underline
                case .focusCut, .impactSequence: highlight = .glow
                case .phraseBuild: highlight = .color
                }
            }
        }

        return KineticTypographyPlan(
            scene: scene,
            motion: motion,
            highlight: highlight,
            energy: energy,
            creativeDirection: creativeDirection,
            emphasisIndex: emphasisIndex,
            rows: rows,
            pages: pages,
            repeatCount: max(1, repeatCount)
        )
    }

    func kineticCreativeDirection(
        for groups: [[WordTimestamp]],
        style: KineticStyle = .automatic
    ) -> KineticCreativeDirection {
        switch style {
        case .cinematic: return .cinematicFlow
        case .editorial: return .editorialStory
        case .impact: return .rhythmicPulse
        case .automatic: break
        }

        let validGroups = groups.filter { !$0.isEmpty }
        guard !validGroups.isEmpty else { return .editorialStory }

        let keys = validGroups.map { kineticLineKey($0) }
        let frequencies = Dictionary(
            keys.map { ($0, 1) },
            uniquingKeysWith: { first, second in first + second }
        )
        var cadences: [Double] = []
        var calmLines = 0
        var drivingLines = 0
        var sectionOpenings = 0
        var totalCharacters = 0

        for (index, group) in validGroups.enumerated() {
            let start = group.first?.start ?? 0
            let end = group.last?.end ?? start + 0.05
            let duration = max(0.05, end - start)
            let cadence = Double(group.count) / duration
            let longestHold = group.map { max(0.05, $0.end - $0.start) }.max() ?? 0
            cadences.append(cadence)
            totalCharacters += group.reduce(0) { $0 + $1.text.count }
            if cadence <= 1.7 || longestHold >= 0.72 { calmLines += 1 }
            if cadence >= 3.4 { drivingLines += 1 }

            if index > 0, let previousEnd = validGroups[index - 1].last?.end {
                let gap = max(0, (group.first?.start ?? previousEnd) - previousEnd)
                if gap >= 0.75 { sectionOpenings += 1 }
            }
        }

        let sortedCadences = cadences.sorted()
        let midpoint = sortedCadences.count / 2
        let medianCadence: Double
        if sortedCadences.count.isMultiple(of: 2), midpoint > 0 {
            medianCadence = (sortedCadences[midpoint - 1] + sortedCadences[midpoint]) / 2
        } else {
            medianCadence = sortedCadences[midpoint]
        }
        let lineCount = Double(validGroups.count)
        let repeatedLineRatio = Double(
            keys.filter { frequencies[$0, default: 0] > 1 }.count
        ) / lineCount
        let calmRatio = Double(calmLines) / lineCount
        let drivingRatio = Double(drivingLines) / lineCount
        let sectionRatio = Double(sectionOpenings) / Double(max(1, validGroups.count - 1))
        let averageCharacters = Double(totalCharacters) / lineCount

        // Öncelik sırası da parçanın yapısından gelir: belirgin nakarat kimliği tempodan,
        // yoğun hızlı vokal ise tek tek uzun kelimelerden daha baskın bir tasarım sinyalidir.
        if repeatedLineRatio >= 0.28 {
            return .anthemLift
        }
        if drivingRatio >= 0.34 || medianCadence >= 3.25 {
            return .rhythmicPulse
        }
        if calmRatio >= 0.42 || medianCadence <= 1.75 {
            return .cinematicFlow
        }
        if sectionRatio >= 0.24 || averageCharacters >= 22 {
            return .editorialStory
        }
        return .editorialStory
    }

    func kineticScenePlans(
        for groups: [[WordTimestamp]],
        style: KineticStyle = .automatic,
        emphasisWordIDs: Set<UUID> = []
    ) -> [KineticTypographyPlan] {
        let creativeDirection = kineticCreativeDirection(for: groups, style: style)
        let keys = groups.map { kineticLineKey($0) }
        let frequencies = Dictionary(
            keys.map { ($0, 1) },
            uniquingKeysWith: { first, second in first + second }
        )

        var directed: [KineticTypographyPlan] = []
        var currentScene: KineticScene?
        var currentSceneRun = 0

        for (index, group) in groups.enumerated() {
            let repeatCount = frequencies[keys[index], default: 1]
            let emphasisWordID = group.first(where: { emphasisWordIDs.contains($0.id) })?.id
            let basePlan = kineticTypographyPlan(
                for: group,
                lineIndex: index,
                style: style,
                repeatCount: repeatCount,
                emphasisWordID: emphasisWordID,
                creativeDirection: creativeDirection
            )
            var plan = basePlan
            let previousEnd = index > 0 ? groups[index - 1].last?.end : nil
            let sectionGap = previousEnd.map { max(0, (group.first?.start ?? $0) - $0) }
                ?? Double.greatestFiniteMagnitude
            let isSectionOpening = style == .automatic
                && sectionGap >= 0.75
                && group.count > 2
                && repeatCount == 1

            if isSectionOpening,
               basePlan.scene == .phraseBuild || basePlan.scene == .captionWindow {
                // Sessizlikten sonraki açılış da parçanın seçilmiş görsel ailesinde kalır.
                let openingScene: KineticScene
                switch creativeDirection {
                case .cinematicFlow: openingScene = .phraseBuild
                case .editorialStory, .anthemLift: openingScene = .editorialStack
                case .rhythmicPulse: openingScene = .captionWindow
                }
                plan = composeKineticPlan(
                    for: group,
                    scene: openingScene,
                    energy: basePlan.energy,
                    emphasisIndex: basePlan.emphasisIndex,
                    repeatCount: repeatCount,
                    style: .automatic,
                    creativeDirection: creativeDirection
                )
            }

            if style == .automatic,
               !group.isEmpty,
               repeatCount == 1,
               !isSectionOpening,
               let previousPlan = directed.last {
                let backToBackPunch = plan.motion == .punchCut
                    && previousPlan.motion == .punchCut
                let overusedScene = plan.scene == currentScene && currentSceneRun >= 2

                if backToBackPunch || overusedScene {
                    // Yorucu arka arkaya kesmeleri ve üçten fazla aynı sahneyi engeller.
                    // Alternatif yine satırın gerçek enerjisinden türetilir; sıra numarası,
                    // rastgelelik veya yapay bir şablon döngüsü kullanılmaz.
                    let breathingScene = kineticBreathingScene(
                        after: plan.scene,
                        wordCount: group.count,
                        direction: creativeDirection
                    )
                    plan = composeKineticPlan(
                        for: group,
                        scene: breathingScene,
                        energy: basePlan.energy,
                        emphasisIndex: basePlan.emphasisIndex,
                        repeatCount: repeatCount,
                        style: .automatic,
                        creativeDirection: creativeDirection
                    )
                }
            }

            if plan.scene == currentScene {
                currentSceneRun += 1
            } else {
                currentScene = plan.scene
                currentSceneRun = 1
            }
            directed.append(plan)
        }
        return directed
    }

    private func kineticBreathingScene(
        after scene: KineticScene,
        wordCount: Int,
        direction: KineticCreativeDirection
    ) -> KineticScene {
        switch direction {
        case .cinematicFlow:
            switch scene {
            case .phraseBuild:
                return wordCount >= 3 ? .editorialStack : .focusCut
            case .editorialStack, .captionWindow, .impactSequence:
                return .phraseBuild
            case .focusCut:
                return .phraseBuild
            case .chorusLockup:
                return .chorusLockup
            }
        case .editorialStory:
            break
        case .rhythmicPulse:
            switch scene {
            case .focusCut, .impactSequence:
                return wordCount >= 3 ? .captionWindow : .phraseBuild
            case .captionWindow:
                return .phraseBuild
            case .phraseBuild, .editorialStack:
                return wordCount >= 3 ? .captionWindow : .focusCut
            case .chorusLockup:
                return .chorusLockup
            }
        case .anthemLift:
            switch scene {
            case .focusCut, .impactSequence:
                return wordCount >= 3 ? .editorialStack : .phraseBuild
            case .editorialStack, .captionWindow:
                return .phraseBuild
            case .phraseBuild:
                return wordCount >= 3 ? .editorialStack : .focusCut
            case .chorusLockup:
                return .chorusLockup
            }
        }

        switch scene {
        case .focusCut, .impactSequence:
            return wordCount >= 3 ? .captionWindow : .phraseBuild
        case .captionWindow:
            return .phraseBuild
        case .phraseBuild:
            return wordCount >= 3 ? .captionWindow : .focusCut
        case .editorialStack:
            return .phraseBuild
        case .chorusLockup:
            return .chorusLockup
        }
    }

    private func kineticCaptionPages(for words: [WordTimestamp]) -> [[Int]] {
        guard !words.isEmpty else { return [] }
        let maximumPageDuration = 1.35
        let maximumWords = 4
        let naturalPause = 0.38
        var pages: [[Int]] = []
        var current: [Int] = []
        var pageStart = words[0].start

        for index in words.indices {
            if let previousIndex = current.last {
                let gap = max(0, words[index].start - words[previousIndex].end)
                let pageDuration = words[index].end - pageStart
                if current.count >= maximumWords
                    || (current.count >= 2 && pageDuration > maximumPageDuration)
                    || (current.count >= 2 && gap >= naturalPause) {
                    pages.append(current)
                    current = []
                    pageStart = words[index].start
                }
            }
            current.append(index)
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    private func kineticLineKey(_ words: [WordTimestamp]) -> String {
        let locale = Locale(identifier: "tr_TR")
        return words.map(\.text)
            .joined(separator: " ")
            .lowercased(with: locale)
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func balancedKineticRows(for words: [WordTimestamp]) -> [[Int]] {
        guard words.count > 1 else { return [Array(words.indices)] }
        let totalCharacters = words.reduce(0) { $0 + max(1, $1.text.count) } + words.count - 1
        var bestSplit = 1
        var bestDifference = Int.max

        for split in 1..<words.count {
            let left = words[..<split].reduce(0) { $0 + max(1, $1.text.count) } + split - 1
            let right = max(0, totalCharacters - left - 1)
            let difference = abs(left - right)
            if difference < bestDifference {
                bestDifference = difference
                bestSplit = split
            }
        }
        return [Array(0..<bestSplit), Array(bestSplit..<words.count)]
    }

    private func semanticEmphasisIndex(words: [WordTimestamp], durations: [Double]) -> Int {
        let stopWords = Set([
            "acaba", "ama", "ancak", "artık", "aslında", "az", "bazı", "belki",
            "ben", "beni", "benim", "bir", "biz", "bu", "bunu", "da", "daha",
            "de", "diye", "en", "gibi", "hem", "hep", "her", "için", "ile",
            "ise", "ki", "kim", "mi", "mı", "mu", "mü", "ne", "o", "sen",
            "seni", "senin", "şey", "ve", "veya", "ya"
        ])
        let locale = Locale(identifier: "tr_TR")
        var bestIndex = 0
        var bestScore = -Double.greatestFiniteMagnitude

        for (index, word) in words.enumerated() {
            let normalized = word.text
                .lowercased(with: locale)
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            let letterCount = normalized.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }.count
            let duration = durations.indices.contains(index) ? durations[index] : 0.05
            let stopWordPenalty = stopWords.contains(normalized) ? 12.0 : 0
            let score = (Double(letterCount) * 1.8) + (min(duration, 1.5) * 3.2) - stopWordPenalty

            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    func kineticGlyphDesign(
        text: String,
        wordIndex: Int,
        plan: KineticTypographyPlan,
        letterStyle: KineticLetterStyle
    ) -> KineticGlyphDesign {
        let treatment: KineticGlyphTreatment
        switch letterStyle {
        case .clean:
            treatment = .standard
        case .poster:
            treatment = wordIndex == plan.emphasisIndex ? .poster : .standard
        case .rhythm:
            treatment = wordIndex == plan.emphasisIndex ? .rhythm : .standard
        case .automatic:
            guard wordIndex == plan.emphasisIndex else {
                return KineticGlyphDesign(
                    characters: Array(text),
                    scaleFactors: Array(repeating: 1, count: text.count),
                    trackingFactor: 0,
                    treatment: .standard
                )
            }
            switch plan.creativeDirection {
            case .cinematicFlow:
                switch plan.scene {
                case .editorialStack, .chorusLockup: treatment = .poster
                case .phraseBuild, .captionWindow, .focusCut, .impactSequence:
                    treatment = .wide
                }
            case .editorialStory, .rhythmicPulse:
                switch plan.scene {
                case .phraseBuild: treatment = .wide
                case .captionWindow, .chorusLockup: treatment = .rhythm
                case .focusCut, .editorialStack, .impactSequence: treatment = .poster
                }
            case .anthemLift:
                switch plan.scene {
                case .phraseBuild: treatment = .wide
                case .captionWindow: treatment = .rhythm
                case .focusCut, .editorialStack, .chorusLockup, .impactSequence:
                    treatment = .poster
                }
            }
        }

        let locale = Locale(identifier: "tr_TR")
        let displayedText = treatment == .standard
            ? text
            : text.uppercased(with: locale)
        let characters = Array(displayedText)
        guard !characters.isEmpty else {
            return KineticGlyphDesign(
                characters: [],
                scaleFactors: [],
                trackingFactor: 0,
                treatment: treatment
            )
        }

        switch treatment {
        case .standard:
            return KineticGlyphDesign(
                characters: characters,
                scaleFactors: Array(repeating: 1, count: characters.count),
                trackingFactor: 0,
                treatment: treatment
            )
        case .wide:
            return KineticGlyphDesign(
                characters: characters,
                scaleFactors: Array(repeating: 1, count: characters.count),
                trackingFactor: 0.075,
                treatment: treatment
            )
        case .poster:
            let anchor = kineticAnchorGlyphIndex(in: characters)
            let scales = characters.indices.map { index -> Double in
                if characters.count <= 2 { return index == anchor ? 1.18 : 0.96 }
                if index == anchor { return 1.32 }
                if abs(index - anchor) == 1 { return 1.02 }
                return 0.90
            }
            return KineticGlyphDesign(
                characters: characters,
                scaleFactors: scales,
                trackingFactor: 0.025,
                treatment: treatment
            )
        case .rhythm:
            let anchor = kineticAnchorGlyphIndex(in: characters)
            let scales = characters.indices.map { index -> Double in
                if index == anchor { return 1.18 }
                if kineticIsTurkishVowel(characters[index]) { return 1.10 }
                return index.isMultiple(of: 2) ? 0.94 : 1.02
            }
            return KineticGlyphDesign(
                characters: characters,
                scaleFactors: scales,
                trackingFactor: 0.018,
                treatment: treatment
            )
        }
    }

    private func kineticAnchorGlyphIndex(in characters: [Character]) -> Int {
        guard !characters.isEmpty else { return 0 }
        let midpoint = Double(characters.count - 1) / 2
        let vowelIndices = characters.indices.filter {
            kineticIsTurkishVowel(characters[$0])
        }
        return (vowelIndices.isEmpty ? Array(characters.indices) : vowelIndices)
            .min {
                abs(Double($0) - midpoint) < abs(Double($1) - midpoint)
            } ?? characters.count / 2
    }

    private func kineticIsTurkishVowel(_ character: Character) -> Bool {
        let locale = Locale(identifier: "tr_TR")
        let normalized = String(character).lowercased(with: locale)
        return ["a", "e", "ı", "i", "o", "ö", "u", "ü"].contains(normalized)
    }

    // Satır genişliği ekrana taşarsa tüm yazıyı yatay olarak ezmek yerine fontu
    // orantılı küçültür. Normal satırlarda istenen boyut aynen korunur.
    func fittedFontSize(requested: Int, measuredWidth: Double, maximumWidth: Double) -> Int {
        let safeRequested = max(1, requested)
        guard measuredWidth.isFinite, maximumWidth.isFinite,
              measuredWidth > maximumWidth, maximumWidth > 0 else {
            return safeRequested
        }
        let scaled = Int(floor(Double(safeRequested) * maximumWidth / measuredWidth))
        return max(24, min(safeRequested, scaled))
    }

    private func cleanASSWord(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func kineticWordWidth(text: String, fontName: String, fontSize: Int) -> Double {
        if let measured = harfSinirlariniOlc(
            metin: text,
            fontName: fontName,
            assFontSize: fontSize
        )?.genislik, measured.isFinite, measured > 0 {
            return measured
        }
        // CoreText nadiren fontu çözemediğinde de kompozisyon taşmasın. Bu yalnız
        // yerleşim yedeğidir; dışa aktarımda libass gerçek gömülü fontu kullanır.
        return max(Double(fontSize) * 0.55, Double(text.count) * Double(fontSize) * 0.55)
    }

    private func kineticDesignedWordWidth(
        design: KineticGlyphDesign,
        fontName: String,
        fontSize: Int
    ) -> Double {
        guard design.treatment != .standard else {
            return kineticWordWidth(
                text: String(design.characters),
                fontName: fontName,
                fontSize: fontSize
            )
        }
        let glyphWidths = design.characters.enumerated().map { index, character -> Double in
            let scale = design.scaleFactors.indices.contains(index)
                ? design.scaleFactors[index]
                : 1
            let glyphSize = max(1, Int((Double(fontSize) * scale).rounded()))
            return kineticWordWidth(
                text: String(character),
                fontName: fontName,
                fontSize: glyphSize
            )
        }
        let tracking = Double(fontSize) * design.trackingFactor
        return glyphWidths.reduce(0, +)
            + tracking * Double(max(0, design.characters.count - 1))
    }

    private struct KineticWordPlacement {
        let index: Int
        let rowIndex: Int
        let fontSize: Int
        let visualFontSize: Int
        let width: Double
        let x: Int
        let y: Int
        let glyphDesign: KineticGlyphDesign
    }

    private func kineticRowScale(
        plan: KineticTypographyPlan,
        rowIndex: Int,
        row: [Int],
        rowCount: Int
    ) -> Double {
        switch plan.scene {
        case .phraseBuild:
            return rowCount > 1 ? 0.88 : 1
        case .captionWindow:
            return rowCount > 1 ? 0.90 : 1.04
        case .focusCut:
            return 1.32
        case .impactSequence:
            return 1.20
        case .editorialStack:
            return row.contains(plan.emphasisIndex) ? 1.28 : 0.72
        case .chorusLockup:
            guard rowCount > 1 else { return 1.08 }
            return rowIndex == rowCount - 1 ? 1.04 : 0.82
        }
    }

    private func kineticEmphasisScale(
        plan: KineticTypographyPlan,
        wordIndex: Int,
        treatment: KineticGlyphTreatment
    ) -> Double {
        guard wordIndex == plan.emphasisIndex else { return 1 }
        if treatment == .poster || treatment == .rhythm { return 1 }
        switch plan.scene {
        case .phraseBuild: return 1.10
        case .captionWindow: return 1.08
        case .chorusLockup: return 1.12
        case .focusCut, .editorialStack, .impactSequence: return 1
        }
    }

    private func kineticPlacements(
        cleaned: [(word: WordTimestamp, text: String)],
        plan: KineticTypographyPlan,
        fontName: String,
        requestedFontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        letterStyle: KineticLetterStyle,
        rowsOverride: [[Int]]? = nil
    ) -> [KineticWordPlacement] {
        let baseSize = max(24, requestedFontSize)
        let safeWidth = Double(virtualWidth) * 0.90
        let layoutRows = rowsOverride ?? plan.rows
        let targetY = min(
            Double(virtualHeight) - 30,
            max(Double(baseSize) + 30, Double(virtualHeight - marginV) - Double(baseSize) * 0.38)
        )

        if plan.scene == .focusCut || plan.scene == .impactSequence {
            return cleaned.indices.map { index in
                let glyphDesign = kineticGlyphDesign(
                    text: cleaned[index].text,
                    wordIndex: index,
                    plan: plan,
                    letterStyle: letterStyle
                )
                let proposed = max(24, Int((Double(baseSize) * kineticRowScale(
                    plan: plan,
                    rowIndex: 0,
                    row: Array(cleaned.indices),
                    rowCount: 1
                )).rounded()))
                let measured = kineticDesignedWordWidth(
                    design: glyphDesign,
                    fontName: fontName,
                    fontSize: proposed
                )
                let fitted = fittedFontSize(
                    requested: proposed,
                    measuredWidth: measured,
                    maximumWidth: safeWidth
                )
                let fittedWidth = kineticDesignedWordWidth(
                    design: glyphDesign,
                    fontName: fontName,
                    fontSize: fitted
                )
                let visualSize = max(
                    fitted,
                    Int((Double(fitted) * glyphDesign.maximumScale).rounded(.up))
                )
                return KineticWordPlacement(
                    index: index,
                    rowIndex: 0,
                    fontSize: fitted,
                    visualFontSize: visualSize,
                    width: fittedWidth,
                    x: virtualWidth / 2,
                    y: Int(targetY.rounded()),
                    glyphDesign: glyphDesign
                )
            }
        }

        let rowGap = max(44, Double(baseSize) * 0.92)
        let firstY = targetY - (Double(max(0, layoutRows.count - 1)) * rowGap / 2)
        var placements: [KineticWordPlacement] = []

        for (rowIndex, row) in layoutRows.enumerated() where !row.isEmpty {
            let scale = kineticRowScale(
                plan: plan,
                rowIndex: rowIndex,
                row: row,
                rowCount: layoutRows.count
            )
            var rowSize = max(24, Int((Double(baseSize) * scale).rounded()))
            var spacing = max(7, Double(rowSize) * 0.13)
            if plan.highlight == .pill {
                spacing = max(spacing, Double(rowSize) * 0.30)
            }
            let glyphDesigns = row.map {
                kineticGlyphDesign(
                    text: cleaned[$0].text,
                    wordIndex: $0,
                    plan: plan,
                    letterStyle: letterStyle
                )
            }
            var wordSizes = row.enumerated().map { offset, wordIndex in
                max(24, Int((
                    Double(rowSize) * kineticEmphasisScale(
                        plan: plan,
                        wordIndex: wordIndex,
                        treatment: glyphDesigns[offset].treatment
                    )
                ).rounded()))
            }
            var widths = row.enumerated().map { offset, _ in
                kineticDesignedWordWidth(
                    design: glyphDesigns[offset],
                    fontName: fontName,
                    fontSize: wordSizes[offset]
                )
            }
            var rowWidth = widths.reduce(0, +) + spacing * Double(max(0, row.count - 1))

            if rowWidth > safeWidth {
                let ratio = safeWidth / rowWidth
                rowSize = max(24, Int((Double(rowSize) * ratio).rounded(.down)))
                let minimumSpacing = plan.highlight == .pill
                    ? Double(rowSize) * 0.22
                    : 5
                spacing = max(minimumSpacing, spacing * ratio)
                wordSizes = row.enumerated().map { offset, wordIndex in
                    max(24, Int((
                        Double(rowSize) * kineticEmphasisScale(
                            plan: plan,
                            wordIndex: wordIndex,
                            treatment: glyphDesigns[offset].treatment
                        )
                    ).rounded(.down)))
                }
                widths = row.enumerated().map { offset, _ in
                    kineticDesignedWordWidth(
                        design: glyphDesigns[offset],
                        fontName: fontName,
                        fontSize: wordSizes[offset]
                    )
                }
                rowWidth = widths.reduce(0, +) + spacing * Double(max(0, row.count - 1))
            }

            var xCursor = (Double(virtualWidth) - rowWidth) / 2
            let rawY = firstY + Double(rowIndex) * rowGap
            let visualSizes = wordSizes.enumerated().map { offset, size in
                max(
                    size,
                    Int((Double(size) * glyphDesigns[offset].maximumScale).rounded(.up))
                )
            }
            let tallestSize = visualSizes.max() ?? rowSize
            let y = Int(min(
                Double(virtualHeight) - Double(tallestSize) * 0.55 - 16,
                max(Double(tallestSize) * 0.55 + 16, rawY)
            ).rounded())

            for (offset, wordIndex) in row.enumerated() {
                let width = widths[offset]
                placements.append(KineticWordPlacement(
                    index: wordIndex,
                    rowIndex: rowIndex,
                    fontSize: wordSizes[offset],
                    visualFontSize: visualSizes[offset],
                    width: width,
                    x: Int((xCursor + width / 2).rounded()),
                    y: y,
                    glyphDesign: glyphDesigns[offset]
                ))
                xCursor += width + spacing
            }
        }
        return placements.sorted { $0.index < $1.index }
    }

    private func kineticWholeLineTags(
        plan: KineticTypographyPlan,
        style: KineticStyle,
        intensity: KineticIntensity
    ) -> String {
        let baseInitialScale: Int
        switch plan.scene {
        case .focusCut, .impactSequence: baseInitialScale = 84
        case .captionWindow: baseInitialScale = 90
        case .chorusLockup: baseInitialScale = 90
        case .editorialStack: baseInitialScale = 92
        case .phraseBuild: baseInitialScale = style == .cinematic ? 96 : 92
        }
        let depth = Double(100 - baseInitialScale) * intensity.motionMultiplier
        let initialScale = max(76, min(99, 100 - Int(depth.rounded())))
        let duration = max(140, Int((240.0 * intensity.durationMultiplier).rounded()))
        return "\\fad(120,140)\\fscx\(initialScale)\\fscy\(initialScale)\\blur1.0" +
            "\\t(0,\(duration),1.8,\\fscx100\\fscy100\\blur0.25)"
    }

    private func kineticRoundedRectanglePath(
        width: Int,
        height: Int,
        radius: Int
    ) -> String {
        let safeWidth = max(2, width)
        let safeHeight = max(2, height)
        let safeRadius = max(1, min(radius, min(safeWidth, safeHeight) / 2))
        return [
            "m \(safeRadius) 0",
            "l \(safeWidth - safeRadius) 0",
            "b \(safeWidth) 0 \(safeWidth) 0 \(safeWidth) \(safeRadius)",
            "l \(safeWidth) \(safeHeight - safeRadius)",
            "b \(safeWidth) \(safeHeight) \(safeWidth) \(safeHeight) \(safeWidth - safeRadius) \(safeHeight)",
            "l \(safeRadius) \(safeHeight)",
            "b 0 \(safeHeight) 0 \(safeHeight) 0 \(safeHeight - safeRadius)",
            "l 0 \(safeRadius)",
            "b 0 0 0 0 \(safeRadius) 0"
        ].joined(separator: " ")
    }

    private func kineticDecorationDialogue(
        placement: KineticWordPlacement,
        word: WordTimestamp,
        plan: KineticTypographyPlan,
        accent: KineticResolvedColor,
        intensity: KineticIntensity,
        segmentStart: Double,
        segmentEnd: Double
    ) -> String {
        guard plan.highlight == .pill || plan.highlight == .underline else { return "" }
        let start = max(segmentStart, word.start - 0.045)
        let end = min(segmentEnd, max(start + 0.08, word.end + 0.08))
        guard end > start else { return "" }

        let width: Int
        let height: Int
        let radius: Int
        let left: Int
        let top: Int
        let tags: String
        let decorationDuration = max(
            55,
            Int((80.0 * intensity.durationMultiplier).rounded())
        )

        if plan.highlight == .pill {
            width = max(26, Int(placement.width.rounded(.up)) + max(18, placement.fontSize / 3))
            height = max(22, Int((Double(placement.visualFontSize) * 1.18).rounded()))
            radius = max(6, height / 4)
            left = placement.x - width / 2
            top = placement.y - height / 2
            let lift = max(2, Int((6.0 * intensity.motionMultiplier).rounded()))
            tags = "{\\an7\\move(\(left),\(top + lift),\(left),\(top),0,\(decorationDuration))" +
                "\\p1\\bord0\\shad0\\c&H\(accent.assColor)&\\alpha&H12&\\fad(45,70)}"
        } else {
            width = max(24, Int((placement.width * 0.94).rounded(.up)))
            height = max(4, Int((Double(placement.visualFontSize) * 0.075).rounded()))
            radius = max(2, height / 2)
            left = placement.x - width / 2
            top = placement.y + Int((Double(placement.visualFontSize) * 0.57).rounded())
            tags = "{\\an7\\pos(\(left),\(top))\\p1\\bord0\\shad0\\c&H\(accent.assColor)&" +
                "\\fscx0\\fad(35,70)\\t(0,\(decorationDuration + 20),1.8,\\fscx100)}"
        }

        let path = kineticRoundedRectanglePath(width: width, height: height, radius: radius)
        return "Dialogue: 0,\(formatASSTime(start)),\(formatASSTime(end)),Default,,0,0,0,,\(tags)\(path)\n"
    }

    private struct KineticOverlayGroup {
        let placements: [KineticWordPlacement]
        let start: Double
        let end: Double
    }

    private struct KineticOverlayBounds {
        let left: Int
        let top: Int
        let width: Int
        let height: Int
        let radius: Int
    }

    private func kineticOverlayGroups(
        placements: [KineticWordPlacement],
        cleaned: [(word: WordTimestamp, text: String)],
        plan: KineticTypographyPlan,
        overlay: KineticOverlayStyle,
        segmentStart: Double,
        segmentEnd: Double
    ) -> [KineticOverlayGroup] {
        if overlay == .spotlight {
            return placements.compactMap { placement in
                guard cleaned.indices.contains(placement.index) else { return nil }
                let word = cleaned[placement.index].word
                let start = max(segmentStart, word.start - 0.07)
                let end = min(segmentEnd, max(start + 0.10, word.end + 0.09))
                guard end > start else { return nil }
                return KineticOverlayGroup(
                    placements: [placement],
                    start: start,
                    end: end
                )
            }
        }

        if plan.scene == .captionWindow {
            return plan.pages.compactMap { page in
                let pagePlacements = placements.filter { page.contains($0.index) }
                guard let firstIndex = page.first,
                      let lastIndex = page.last,
                      cleaned.indices.contains(firstIndex),
                      cleaned.indices.contains(lastIndex),
                      !pagePlacements.isEmpty else {
                    return nil
                }
                let start = max(segmentStart, cleaned[firstIndex].word.start - 0.11)
                let end = min(segmentEnd, cleaned[lastIndex].word.end + 0.13)
                guard end > start else { return nil }
                return KineticOverlayGroup(
                    placements: pagePlacements,
                    start: start,
                    end: end
                )
            }
        }

        guard !placements.isEmpty, segmentEnd > segmentStart else { return [] }
        return [
            KineticOverlayGroup(
                placements: placements,
                start: segmentStart,
                end: segmentEnd
            )
        ]
    }

    private func kineticOverlayBounds(
        placements: [KineticWordPlacement],
        style: KineticOverlayStyle,
        virtualWidth: Int,
        virtualHeight: Int
    ) -> KineticOverlayBounds? {
        guard !placements.isEmpty else { return nil }
        let rawLeft = placements.map {
            Double($0.x) - ($0.width / 2)
        }.min() ?? 0
        let rawRight = placements.map {
            Double($0.x) + ($0.width / 2)
        }.max() ?? Double(virtualWidth)
        let rawTop = placements.map {
            Double($0.y) - (Double($0.visualFontSize) * 0.62)
        }.min() ?? 0
        let rawBottom = placements.map {
            Double($0.y) + (Double($0.visualFontSize) * 0.62)
        }.max() ?? Double(virtualHeight)

        let padX: Double
        let padY: Double
        switch style {
        case .glass:
            padX = 25
            padY = 16
        case .cinematicBand:
            padX = 0
            padY = 22
        case .accentPanel:
            padX = 32
            padY = 21
        case .spotlight:
            padX = 17
            padY = 11
        case .automatic, .none:
            return nil
        }

        let left: Int
        let right: Int
        if style == .cinematicBand {
            left = 0
            right = virtualWidth
        } else {
            left = max(8, Int(floor(rawLeft - padX)))
            right = min(virtualWidth - 8, Int(ceil(rawRight + padX)))
        }
        let top = max(8, Int(floor(rawTop - padY)))
        let bottom = min(virtualHeight - 8, Int(ceil(rawBottom + padY)))
        guard right > left, bottom > top else { return nil }
        let height = bottom - top
        let radius: Int
        switch style {
        case .cinematicBand: radius = 1
        case .spotlight: radius = max(7, min(18, height / 4))
        case .glass, .accentPanel: radius = max(10, min(24, height / 5))
        case .automatic, .none: radius = 1
        }
        return KineticOverlayBounds(
            left: left,
            top: top,
            width: right - left,
            height: height,
            radius: radius
        )
    }

    private func kineticOverlayShapeDialogue(
        layer: Int,
        start: Double,
        end: Double,
        bounds: KineticOverlayBounds,
        color: String,
        alpha: String,
        extraTags: String = ""
    ) -> String {
        let path = kineticRoundedRectanglePath(
            width: bounds.width,
            height: bounds.height,
            radius: bounds.radius
        )
        let tags = "{\\an7\\pos(\(bounds.left),\(bounds.top))\\p1\\bord0\\shad0" +
            "\\c&H\(color)&\\alpha&H\(alpha)&\(extraTags)}"
        return "Dialogue: \(layer),\(formatASSTime(start)),\(formatASSTime(end)),Default,,0,0,0,,\(tags)\(path)\n"
    }

    private func kineticOverlayDialogues(
        placements: [KineticWordPlacement],
        cleaned: [(word: WordTimestamp, text: String)],
        plan: KineticTypographyPlan,
        overlayStyle: KineticOverlayStyle,
        accent: KineticResolvedColor,
        intensity: KineticIntensity,
        virtualWidth: Int,
        virtualHeight: Int,
        segmentStart: Double,
        segmentEnd: Double
    ) -> String {
        let resolvedStyle = overlayStyle.resolved(for: plan)
        guard resolvedStyle != .none else { return "" }
        let groups = kineticOverlayGroups(
            placements: placements,
            cleaned: cleaned,
            plan: plan,
            overlay: resolvedStyle,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd
        )
        var result = ""
        let spotlightAlpha: String
        switch intensity {
        case .subtle: spotlightAlpha = "82"
        case .balanced: spotlightAlpha = "72"
        case .energetic: spotlightAlpha = "64"
        }

        for group in groups {
            guard let bounds = kineticOverlayBounds(
                placements: group.placements,
                style: resolvedStyle,
                virtualWidth: virtualWidth,
                virtualHeight: virtualHeight
            ) else {
                continue
            }
            switch resolvedStyle {
            case .glass:
                let shadowBounds = KineticOverlayBounds(
                    left: bounds.left,
                    top: bounds.top + 6,
                    width: bounds.width,
                    height: bounds.height,
                    radius: bounds.radius
                )
                result += kineticOverlayShapeDialogue(
                    layer: 0,
                    start: group.start,
                    end: group.end,
                    bounds: shadowBounds,
                    color: "000000",
                    alpha: "82",
                    extraTags: "\\blur5\\fad(75,100)"
                )
                result += kineticOverlayShapeDialogue(
                    layer: 0,
                    start: group.start,
                    end: group.end,
                    bounds: bounds,
                    color: "0D0D10",
                    alpha: "4E",
                    extraTags: "\\bord1.2\\3c&HFFFFFF&\\3a&HD5&\\fad(75,100)"
                )
                let hairline = KineticOverlayBounds(
                    left: bounds.left + max(12, bounds.radius),
                    top: bounds.top,
                    width: min(max(40, bounds.width / 3), 110),
                    height: 3,
                    radius: 1
                )
                result += kineticOverlayShapeDialogue(
                    layer: 1,
                    start: group.start,
                    end: group.end,
                    bounds: hairline,
                    color: accent.assColor,
                    alpha: "20",
                    extraTags: "\\fad(90,100)"
                )
            case .cinematicBand:
                result += kineticOverlayShapeDialogue(
                    layer: 0,
                    start: group.start,
                    end: group.end,
                    bounds: bounds,
                    color: "08080A",
                    alpha: "48",
                    extraTags: "\\fad(100,120)"
                )
                let topLine = KineticOverlayBounds(
                    left: 0,
                    top: bounds.top,
                    width: bounds.width,
                    height: 2,
                    radius: 1
                )
                result += kineticOverlayShapeDialogue(
                    layer: 1,
                    start: group.start,
                    end: group.end,
                    bounds: topLine,
                    color: accent.assColor,
                    alpha: "48",
                    extraTags: "\\fad(120,120)"
                )
            case .accentPanel:
                result += kineticOverlayShapeDialogue(
                    layer: 0,
                    start: group.start,
                    end: group.end,
                    bounds: bounds,
                    color: "09090B",
                    alpha: "42",
                    extraTags: "\\bord1\\3c&HFFFFFF&\\3a&HE0&\\fad(80,110)"
                )
                let sideBar = KineticOverlayBounds(
                    left: bounds.left,
                    top: bounds.top + max(9, bounds.radius / 2),
                    width: 5,
                    height: max(12, bounds.height - max(18, bounds.radius)),
                    radius: 2
                )
                result += kineticOverlayShapeDialogue(
                    layer: 1,
                    start: group.start,
                    end: group.end,
                    bounds: sideBar,
                    color: accent.assColor,
                    alpha: "08",
                    extraTags: "\\fad(90,110)"
                )
            case .spotlight:
                result += kineticOverlayShapeDialogue(
                    layer: 0,
                    start: group.start,
                    end: group.end,
                    bounds: bounds,
                    color: accent.assColor,
                    alpha: spotlightAlpha,
                    extraTags: "\\bord1.4\\3c&H\(accent.assColor)&\\3a&H38&\\fad(45,80)"
                )
            case .automatic, .none:
                break
            }
        }
        return result
    }

    private func kineticWholeLineOverlayDialogues(
        text: String,
        measuredWidth: Double,
        fontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        plan: KineticTypographyPlan,
        overlayStyle: KineticOverlayStyle,
        accent: KineticResolvedColor,
        intensity: KineticIntensity,
        segmentStart: Double,
        segmentEnd: Double
    ) -> String {
        guard !text.isEmpty, measuredWidth > 0, segmentEnd > segmentStart else { return "" }
        let y = Int(min(
            Double(virtualHeight - 30),
            max(
                Double(fontSize + 30),
                Double(virtualHeight - marginV) - Double(fontSize) * 0.38
            )
        ).rounded())
        let design = KineticGlyphDesign(
            characters: Array(text),
            scaleFactors: Array(repeating: 1, count: text.count),
            trackingFactor: 0,
            treatment: .standard
        )
        let placement = KineticWordPlacement(
            index: 0,
            rowIndex: 0,
            fontSize: fontSize,
            visualFontSize: fontSize,
            width: min(measuredWidth, Double(virtualWidth - 24)),
            x: virtualWidth / 2,
            y: y,
            glyphDesign: design
        )
        let word = WordTimestamp(
            text: text,
            start: segmentStart,
            end: segmentEnd
        )
        // Bitişik font tek parça şekillendirilmeye devam eder. Plan yalnız overlay
        // gruplamasında tek satıra indirgenir; gliflerin içine ASS etiketi sokulmaz.
        let singleLinePlan = KineticTypographyPlan(
            scene: plan.scene,
            motion: plan.motion,
            highlight: plan.highlight,
            energy: plan.energy,
            creativeDirection: plan.creativeDirection,
            emphasisIndex: 0,
            rows: [[0]],
            pages: [[0]],
            repeatCount: plan.repeatCount
        )
        return kineticOverlayDialogues(
            placements: [placement],
            cleaned: [(word: word, text: text)],
            plan: singleLinePlan,
            overlayStyle: overlayStyle,
            accent: accent,
            intensity: intensity,
            virtualWidth: virtualWidth,
            virtualHeight: virtualHeight,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd
        )
    }

    // İç erişim, gerçek ASS üretiminin regresyon testlerinde doğrulanabilmesi içindir.
    func makeKineticDialogues(
        group: [WordTimestamp],
        lineIndex: Int,
        segStart: Double,
        segEnd: Double,
        fontName: String,
        requestedFontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        style: KineticStyle = .automatic,
        accent: KineticAccent = .gold,
        customColorHex: String = KineticAccent.defaultCustomHex,
        intensity: KineticIntensity = .balanced,
        letterStyle: KineticLetterStyle = .clean,
        overlayStyle: KineticOverlayStyle = .none,
        repeatCount: Int = 1,
        scenePlan: KineticTypographyPlan? = nil
    ) -> String {
        let cleaned: [(word: WordTimestamp, text: String)] = group.compactMap { word in
            let text = cleanASSWord(word.text)
            return text.isEmpty ? nil : (word, text)
        }
        guard !cleaned.isEmpty else { return "" }

        let plan = scenePlan ?? kineticTypographyPlan(
            for: cleaned.map { $0.word },
            lineIndex: lineIndex,
            style: style,
            repeatCount: repeatCount
        )
        let placements: [KineticWordPlacement]
        if plan.scene == .captionWindow {
            placements = plan.pages.flatMap { page in
                kineticPlacements(
                    cleaned: cleaned,
                    plan: plan,
                    fontName: fontName,
                    requestedFontSize: requestedFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    letterStyle: letterStyle,
                    rowsOverride: [page]
                )
            }.sorted { $0.index < $1.index }
        } else {
            placements = kineticPlacements(
                cleaned: cleaned,
                plan: plan,
                fontName: fontName,
                requestedFontSize: requestedFontSize,
                marginV: marginV,
                virtualWidth: virtualWidth,
                virtualHeight: virtualHeight,
                letterStyle: letterStyle
            )
        }
        let resolvedAccent = accent.resolvedColor(customHex: customColorHex)
        var result = kineticOverlayDialogues(
            placements: placements,
            cleaned: cleaned,
            plan: plan,
            overlayStyle: overlayStyle,
            accent: resolvedAccent,
            intensity: intensity,
            virtualWidth: virtualWidth,
            virtualHeight: virtualHeight,
            segmentStart: segStart,
            segmentEnd: segEnd
        )

        for placement in placements {
            let index = placement.index
            let item = cleaned[index]
            let emphasis = index == plan.emphasisIndex
            let pageIndex = plan.pages.firstIndex { $0.contains(index) } ?? 0
            let page = plan.pages.indices.contains(pageIndex) ? plan.pages[pageIndex] : [index]
            let localIndex = page.firstIndex(of: index) ?? index
            let isolatedWord = plan.motion == .punchCut
            let pagedWords = plan.scene == .captionWindow

            let eventStart: Double
            let eventEnd: Double
            if isolatedWord {
                eventStart = max(segStart, item.word.start - 0.12)
                eventEnd = min(segEnd, max(eventStart + 0.20, item.word.end + 0.18))
            } else if pagedWords, let firstIndex = page.first, let lastIndex = page.last {
                let rawStart = cleaned[firstIndex].word.start - 0.10
                let rawEnd = cleaned[lastIndex].word.end + 0.12
                let previousBoundary: Double
                if pageIndex > 0, let previousLast = plan.pages[pageIndex - 1].last {
                    previousBoundary = (
                        cleaned[previousLast].word.end + cleaned[firstIndex].word.start
                    ) / 2
                } else {
                    previousBoundary = segStart
                }
                let nextBoundary: Double
                if pageIndex + 1 < plan.pages.count,
                   let nextFirst = plan.pages[pageIndex + 1].first {
                    nextBoundary = (
                        cleaned[lastIndex].word.end + cleaned[nextFirst].word.start
                    ) / 2
                } else {
                    nextBoundary = segEnd
                }
                eventStart = max(segStart, max(rawStart, previousBoundary))
                eventEnd = min(segEnd, min(rawEnd, nextBoundary))
            } else {
                eventStart = segStart
                eventEnd = segEnd
            }
            let safeEventEnd = max(eventStart + 0.05, eventEnd)
            let eventDurationMs = max(200, Int((safeEventEnd - eventStart) * 1000))
            let wordStartMs = min(
                eventDurationMs,
                max(0, Int((max(eventStart, item.word.start) - eventStart) * 1000))
            )
            let wordEndMs = min(
                eventDurationMs,
                max(wordStartMs + 30, Int((item.word.end - eventStart) * 1000))
            )

            var text = ""
            let characters = placement.glyphDesign.characters
            let letterDuration = max(0.01, (item.word.end - item.word.start) / Double(max(1, characters.count)))
            for (characterIndex, character) in characters.enumerated() {
                let characterStart = item.word.start + (Double(characterIndex) * letterDuration)
                let characterEnd = item.word.start + (Double(characterIndex + 1) * letterDuration)
                let startMs = min(eventDurationMs, max(0, Int((characterStart - eventStart) * 1000)))
                let rawEndMs = min(eventDurationMs, max(startMs + 20, Int((characterEnd - eventStart) * 1000)))
                let fadeEnd = min(eventDurationMs, max(startMs + 20, min(rawEndMs, startMs + 100)))
                let glyphScale = placement.glyphDesign.scaleFactors.indices.contains(characterIndex)
                    ? placement.glyphDesign.scaleFactors[characterIndex]
                    : 1
                let glyphSize = max(
                    1,
                    Int((Double(placement.fontSize) * glyphScale).rounded())
                )
                text += "{\\fs\(glyphSize)\\alpha&H00&" +
                    "\\t(\(startMs),\(fadeEnd),\\alpha&HA0&)}\(character)"
            }

            let entryStart = isolatedWord ? 0 : min(90, localIndex * 22)
            let baseEntranceDuration: Int
            switch plan.energy {
            case .calm: baseEntranceDuration = 220
            case .steady: baseEntranceDuration = 170
            case .driving: baseEntranceDuration = 120
            }
            let entranceDuration = max(
                80,
                Int((Double(baseEntranceDuration) * intensity.durationMultiplier).rounded())
            )
            let entryPeak = min(eventDurationMs, entryStart + entranceDuration)
            let entryEnd = min(eventDurationMs, entryPeak + (isolatedWord ? 90 : 70))
            let baseEntranceScale: Int
            switch plan.motion {
            case .punchCut: baseEntranceScale = 72
            case .pagePop: baseEntranceScale = 86
            case .lockedReveal: baseEntranceScale = 90
            case .sideReveal: baseEntranceScale = 92
            case .softLift: baseEntranceScale = style == .cinematic ? 96 : 93
            }
            let entranceDepth = Double(100 - baseEntranceScale) * intensity.motionMultiplier
            let entranceScale = max(66, min(99, 100 - Int(entranceDepth.rounded())))
            let motionOffset: (Int) -> Int = { base in
                max(1, Int((Double(base) * intensity.motionMultiplier).rounded()))
            }

            var tags = "{\\an5"
            switch plan.motion {
            case .sideReveal:
                let distance = motionOffset(18)
                let slide = placement.rowIndex.isMultiple(of: 2) ? -distance : distance
                tags += "\\move(\(placement.x + slide),\(placement.y),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .punchCut:
                tags += "\\move(\(placement.x),\(placement.y + motionOffset(16)),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .softLift:
                tags += "\\move(\(placement.x),\(placement.y + motionOffset(10)),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .pagePop:
                tags += "\\move(\(placement.x),\(placement.y + motionOffset(12)),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .lockedReveal:
                tags += "\\pos(\(placement.x),\(placement.y))"
            }
            let fadeIn = isolatedWord ? 70 : (pagedWords ? 75 : 110)
            let fadeOut = isolatedWord ? 100 : (pagedWords ? 95 : 140)
            tags += "\\fs\(placement.fontSize)\\c&HFFFFFF&\\fad(\(fadeIn),\(fadeOut))"
            let tracking = Int((
                Double(placement.fontSize) * placement.glyphDesign.trackingFactor
            ).rounded())
            if tracking > 0 {
                tags += "\\fsp\(tracking)"
            }
            tags += "\\fscx\(entranceScale)\\fscy\(entranceScale)\\blur\(isolatedWord ? "1.3" : "0.9")"
            let peakScale: Int
            if isolatedWord {
                switch intensity {
                case .subtle: peakScale = 104
                case .balanced: peakScale = 108
                case .energetic: peakScale = 112
                }
            } else if plan.motion == .pagePop {
                switch intensity {
                case .subtle: peakScale = 101
                case .balanced: peakScale = 103
                case .energetic: peakScale = 106
                }
            } else {
                peakScale = 100
            }
            tags += "\\t(\(entryStart),\(entryPeak),1.8,\\fscx\(peakScale)\\fscy\(peakScale)\\blur0.2)"
            if (isolatedWord || plan.motion == .pagePop), entryEnd > entryPeak {
                tags += "\\t(\(entryPeak),\(entryEnd),1.4,\\fscx100\\fscy100)"
            }
            let colorInEnd = min(eventDurationMs, wordStartMs + 70)
            let colorOutEnd = min(eventDurationMs, wordEndMs + 100)
            let activeColor = plan.highlight == .pill
                ? resolvedAccent.foregroundASSColor
                : resolvedAccent.assColor
            let shouldPulse = !isolatedWord && wordStartMs >= entryPeak
            let highlightScale = plan.highlight == .glow
                ? min(112, intensity.activeScale + 2)
                : intensity.activeScale
            let activeScaleTags = shouldPulse
                ? "\\fscx\(highlightScale)\\fscy\(highlightScale)"
                : ""
            let restingScaleTags = shouldPulse ? "\\fscx100\\fscy100" : ""
            if plan.highlight == .pill {
                tags += "\\t(\(wordStartMs),\(colorInEnd),\\c&H\(activeColor)&\\3a&HFF&\\4a&HFF&\(activeScaleTags))"
                tags += "\\t(\(wordEndMs),\(colorOutEnd),\\c&HFFFFFF&\\3a&H00&\\4a&H00&\(restingScaleTags))"
            } else {
                tags += "\\t(\(wordStartMs),\(colorInEnd),\\c&H\(activeColor)&\(activeScaleTags))"
                tags += "\\t(\(wordEndMs),\(colorOutEnd),\\c&HFFFFFF&\(restingScaleTags))"
            }
            if plan.highlight == .glow {
                tags += "\\4c&H\(resolvedAccent.assColor)&\\4a&H55&\\shad2.4"
            }
            if emphasis {
                tags += "\\3c&H3A2610&\\bord3.4"
            }
            tags += "}"

            result += kineticDecorationDialogue(
                placement: placement,
                word: item.word,
                plan: plan,
                accent: resolvedAccent,
                intensity: intensity,
                segmentStart: eventStart,
                segmentEnd: safeEventEnd
            )
            let layer = emphasis ? 3 : 2
            result += "Dialogue: \(layer),\(formatASSTime(eventStart)),\(formatASSTime(safeEventEnd)),Default,,0,0,0,,\(tags)\(text)\n"
        }
        return result
    }

    // 3. ASS Altyazı Dosyası Oluşturma (iOS 16+ uyumlu asenkron yapı)
    // lineBreaks: kullanıcının onayladığı satır sonları (boşsa otomatik öneri kullanılır)
    func generateASS(
        words: [WordTimestamp],
        lineBreaks: Set<UUID>,
        fontName: String,
        fontSize: Int,
        marginV: Int,
        karaokeMode: KaraokeMode = .classic,
        kineticStyle: KineticStyle = .automatic,
        kineticAccent: KineticAccent = .gold,
        kineticCustomColorHex: String = KineticAccent.defaultCustomHex,
        kineticIntensity: KineticIntensity = .balanced,
        kineticLetterStyle: KineticLetterStyle = .clean,
        kineticOverlayStyle: KineticOverlayStyle = .none,
        kineticEmphasisWordIDs: Set<UUID> = [],
        videoURL: URL
    ) async -> URL? {
        let asset = AVAsset(url: videoURL)
        
        // Modern async API'ler ile video izlerini yükleme
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first else { return nil }
              
        // Deprecated naturalSize yerine load(.naturalSize) kullanımı
        guard let size = try? await track.load(.naturalSize) else { return nil }

        // Rotasyon metadatasını hesaba kat: dikey çekilen videolar naturalSize'ı yatay raporlar.
        // preferredTransform uygulanmazsa dikey videolarda font oranı ve konum bozulur.
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let rotatedRect = CGRect(origin: .zero, size: size).applying(transform)

        let width = Double(abs(rotatedRect.width))
        let height = Double(abs(rotatedRect.height))
        guard width > 0, height > 0 else { return nil }

        let duration = try? await asset.load(.duration)
        let durationSeconds = duration.map { CMTimeGetSeconds($0) }
        let renderWords = prepareWordsForRendering(words, maximumTime: durationSeconds)
        guard !renderWords.isEmpty else { return nil }

        let aspectRatio = width / height
        let virtualHeight = 1080
        let virtualWidth = Int(1080.0 * aspectRatio)
        
        let familyName = getFontFamilyName(for: fontName)

        // Bold bayrağı yalnız gerçekten kalın kesimi olan fontlarda açılır. Eskiden her font
        // için -1 (açık) yazılıyordu; kalın kesimi olmayan fontlarda libass yapay kalınlaştırma
        // uyguluyor ve gömülen yazı ön izlemedekinden farklı ("font değişmiş gibi") görünüyordu.
        let boldFlag = (FontCatalog.secenek(fontName)?.kalin ?? fontName.contains("Bold")) ? -1 : 0

        // Bitişik (el yazısı) fontlarda harf başına etiket bloğu, animasyon sırasında harf
        // bağlarını/konturu koparıp harfi "normal" gösteriyordu. Çözüm iki katman hilesi:
        // altta etiketsiz BİTİŞİK soluk kopya (hiç bozulmaz), üstte harf harf tam saydama
        // ERİYEN opak kopya. Harf harf soluklaşma hissi korunur, yazı hep bitişik görünür.
        let bitisikFont = FontCatalog.secenek(fontName)?.bitisik ?? false

        var assContent = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(virtualWidth)
        PlayResY: \(virtualHeight)

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,\(familyName),\(fontSize),&H00FFFFFF,&H000000FF,&H00000000,&H00000000,\(boldFlag),0,0,0,100,100,0,0,1,3,1.5,2,10,10,\(marginV),1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
        
        // Satır grupları: kullanıcının satır düzenleyicide onayladığı düzen esas alınır;
        // satır sonu bilgisi yoksa otomatik öneri kullanılır.
        var groups: [[WordTimestamp]] = []
        if lineBreaks.isEmpty {
            groups = autoLineGroups(for: renderWords)
        } else {
            var currentGroup: [WordTimestamp] = []
            for word in renderWords {
                currentGroup.append(word)
                if lineBreaks.contains(word.id) {
                    groups.append(currentGroup)
                    currentGroup = []
                }
            }
            if !currentGroup.isEmpty { groups.append(currentGroup) }
        }

        // Efekt (kullanıcının Python sistemiyle birebir aynı):
        // Satırın tamamı TAM GÖRÜNÜR (&H00&) gelir; her harf, söylendiği anda
        // yarı saydama (&HA0&) soluklaşır. Satır 0.2 sn erken görünüp 0.2 sn geç kaybolur.
        //
        // ÖNEMLİ: Ardışık satırların zaman aralıkları KESİNLİKLE çakışmamalıdır.
        // İki Dialogue satırı aynı anda ekrandaysa libass onları üst üste istifler:
        // yeni satır önce yukarıda belirir, eski satır kaybolunca aşağı zıplar
        // ("yazı hareket ediyor / font değişip geliyor" şikayetinin kaynağı buydu).
        // Bu yüzden komşu satırlar arasında TEK ortak sınır hesaplanır ve bir imleç
        // (cursor) ile hiçbir satırın bir öncekinden erken başlamaması garanti edilir.
        var rawSegs: [(start: Double, end: Double, group: [WordTimestamp])] = []
        for group in groups {
            guard let firstWord = group.first, let lastWord = group.last else { continue }
            let rawStart = max(0, firstWord.start)
            let rawEnd = max(rawStart + 0.2, lastWord.end)
            rawSegs.append((rawStart, rawEnd, group))
        }
        let kineticPlans = kineticScenePlans(
            for: rawSegs.map(\.group),
            style: kineticStyle,
            emphasisWordIDs: kineticEmphasisWordIDs
        )

        var boundaries: [Double] = []
        if rawSegs.count > 1 {
            for i in 0..<(rawSegs.count - 1) {
                boundaries.append((rawSegs[i].end + rawSegs[i + 1].start) / 2)
            }
        }

        var cursor = 0.0
        for (index, seg) in rawSegs.enumerated() {
            var segStart = max(0, seg.start - 0.2)
            if index > 0 { segStart = max(segStart, boundaries[index - 1]) }
            segStart = max(segStart, cursor)

            var segEnd = seg.end + 0.2
            if index < rawSegs.count - 1 { segEnd = min(segEnd, boundaries[index]) }
            // En az 0.2 sn görünürlük; imleç sayesinde bu uzatma da çakışma yaratamaz
            if segEnd < segStart + 0.2 { segEnd = segStart + 0.2 }
            cursor = segEnd

            let lineText = seg.group.map {
                $0.text
                    .replacingOccurrences(of: "\\", with: "")
                    .replacingOccurrences(of: "{", with: "")
                    .replacingOccurrences(of: "}", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }.joined(separator: " ")
            guard !lineText.isEmpty else { continue }

            let maximumLineWidth = max(1, Double(virtualWidth - 40))
            let measuredWidth = harfSinirlariniOlc(
                metin: lineText,
                fontName: fontName,
                assFontSize: fontSize
            )?.genislik ?? 0
            let lineFontSize = fittedFontSize(
                requested: fontSize,
                measuredWidth: measuredWidth,
                maximumWidth: maximumLineWidth
            )

            // Normal fontlarda Kinetik mod her kelimeyi bağımsız bir tipografi katmanı
            // olarak yerleştirir. Böylece yalnız font boyutu değil, satır hiyerarşisi,
            // vurgu, mikro hareket ve ritim de kelime zamanına bağlanır.
            if karaokeMode == .kinetic && !bitisikFont {
                assContent += makeKineticDialogues(
                    group: seg.group,
                    lineIndex: index,
                    segStart: segStart,
                    segEnd: segEnd,
                    fontName: fontName,
                    requestedFontSize: fontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    style: kineticStyle,
                    accent: kineticAccent,
                    customColorHex: kineticCustomColorHex,
                    intensity: kineticIntensity,
                    letterStyle: kineticLetterStyle,
                    overlayStyle: kineticOverlayStyle,
                    repeatCount: kineticPlans[index].repeatCount,
                    scenePlan: kineticPlans[index]
                )
                continue
            }

            if karaokeMode == .kinetic && bitisikFont {
                let fittedLineWidth = harfSinirlariniOlc(
                    metin: lineText,
                    fontName: fontName,
                    assFontSize: lineFontSize
                )?.genislik ?? min(measuredWidth, maximumLineWidth)
                assContent += kineticWholeLineOverlayDialogues(
                    text: lineText,
                    measuredWidth: fittedLineWidth,
                    fontSize: lineFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    plan: kineticPlans[index],
                    overlayStyle: kineticOverlayStyle,
                    accent: kineticAccent.resolvedColor(customHex: kineticCustomColorHex),
                    intensity: kineticIntensity,
                    segmentStart: segStart,
                    segmentEnd: segEnd
                )
            }

            // Bitişik el yazısı fontlarında kelimeyi ayrı katmanlara bölmek harf bağlarını
            // bozabilir. Bu fontlarda mevcut kusursuz süpürme korunur, kinetik mod yalnız
            // bütün satıra kontrollü bir giriş hareketi uygular.
            let lineMotionTags: String
            if karaokeMode == .kinetic {
                lineMotionTags = kineticWholeLineTags(
                    plan: kineticPlans[index],
                    style: kineticStyle,
                    intensity: kineticIntensity
                )
            } else {
                lineMotionTags = ""
            }

            var effectText = "{\\fs\(lineFontSize)\(lineMotionTags)}"   // normal fontlar: tek katman; bitişik fontlarda yedek üst katman
            var plainText = ""    // bitişik fontlar: etiketsiz tam satır metni
            var harfZamanlar: [(sonUTF16: Int, s: Int, e: Int)] = []  // süpürme sınırı için harf zamanları
            var utf16Pos = 0
            for word in seg.group {
                // ASS formatını bozabilecek özel karakterleri temizle ({, }, \ ve satır sonları)
                let cleanText = word.text
                    .replacingOccurrences(of: "\\", with: "")
                    .replacingOccurrences(of: "{", with: "")
                    .replacingOccurrences(of: "}", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanText.isEmpty { continue }

                // Kelime zamanlarını kelepçele (ters girilmiş süreleri de düzeltir)
                let wordStart = max(segStart, word.start)
                let wordEnd = max(wordStart + 0.05, word.end)

                let chars = Array(cleanText)
                let letterDur = (wordEnd - wordStart) / Double(chars.count)

                // Bitişik fontta yedek katman harfi TAM SAYDAMA (&HFF&) erir; normal fontta
                // harf doğrudan yarı saydama (&HA0&) soluklaşır.
                let hedefAlpha = bitisikFont ? "FF" : "A0"

                for (i, char) in chars.enumerated() {
                    let lStartMs = Int((wordStart + Double(i) * letterDur - segStart) * 1000)
                    let lEndMs = Int((wordStart + Double(i + 1) * letterDur - segStart) * 1000)
                    let fadeEnd = max(lStartMs + 20, min(lEndMs, lStartMs + 100))
                    effectText += "{\\alpha&H00&\\t(\(lStartMs),\(fadeEnd),\\alpha&H\(hedefAlpha)&)}\(char)"
                    utf16Pos += String(char).utf16.count
                    harfZamanlar.append((utf16Pos, lStartMs, max(lStartMs + 10, lEndMs)))
                }

                effectText += " "
                plainText += cleanText + " "
                utf16Pos += 1
            }

            if plainText.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let t0 = formatASSTime(segStart)
            let t1 = formatASSTime(segEnd)

            if bitisikFont {
                let metin = plainText.trimmingCharacters(in: .whitespaces)
                // El yazısında harf takibi KAYAN KIRPMA SINIRIYLA (karaoke süpürmesi) yapılır:
                // metnin içine tek etiket bile girmediği için satır tek parça şekillenir,
                // harf bağları ve yerleşim hiçbir karede DEĞİŞEMEZ. Alt katman satırın soluk
                // bitişik kopyası; üstteki opak kopyayı \clip penceresi soldan sağa eritir.
                // Sınır her harfi tam kendi zaman aralığında geçer (CoreText ölçümü).
                if let olcum = harfSinirlariniOlc(metin: metin, fontName: fontName, assFontSize: lineFontSize),
                   olcum.genislik <= Double(virtualWidth - 40) {
                    let x0 = (Double(virtualWidth) - olcum.genislik) / 2
                    var tags = "{\\clip(0,0,\(virtualWidth),\(virtualHeight))"
                    var cursorMs = 0
                    for h in harfZamanlar where h.sonUTF16 - 1 < olcum.sinirlar.count {
                        let s = max(h.s, cursorMs)
                        let e = max(s + 10, h.e)
                        cursorMs = e
                        let x = min(max(0, Int((x0 + olcum.sinirlar[h.sonUTF16 - 1]).rounded())), virtualWidth)
                        tags += "\\t(\(s),\(e),\\clip(\(x),0,\(virtualWidth),\(virtualHeight)))"
                    }
                    tags += "}"
                    assContent += "Dialogue: 0,\(t0),\(t1),Default,,0,0,0,,{\\fs\(lineFontSize)\(lineMotionTags)\\alpha&HA0&}\(metin)\n"
                    assContent += "Dialogue: 1,\(t0),\(t1),Default,,0,0,0,,{\\fs\(lineFontSize)\(lineMotionTags)}\(tags)\(metin)\n"
                } else {
                    // Ölçüm yapılamadı veya satır ekrana sığmayıp sarılacak: yedek yöntem
                    // (altta bitişik soluk kopya + üstte harf harf eriyen opak kopya)
                    assContent += "Dialogue: 0,\(t0),\(t1),Default,,0,0,0,,{\\fs\(lineFontSize)\(lineMotionTags)\\alpha&HA0&}\(metin)\n"
                    assContent += "Dialogue: 1,\(t0),\(t1),Default,,0,0,0,,\(effectText)\n"
                }
            } else {
                assContent += "Dialogue: 0,\(t0),\(t1),Default,,0,0,0,,\(effectText)\n"
            }
        }
        
        let assURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ass")
        do {
            try assContent.write(to: assURL, atomically: true, encoding: .utf8)
            return assURL
        } catch {
            print("Failed to write ASS file: \(error)")
            return nil
        }
    }
    
    // Filtre argümanlarında geçebilecek özel karakterleri FFmpeg için escape eder
    private func escapeForFilter(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    // Seçilen fontun GERÇEK dosyasını CoreText üzerinden bulup geçici bir klasöre kopyalar.
    // Bu klasör libass'a fontsdir ile doğrudan verilir: fontconfig'in sistem klasörü
    // taraması bazı sistem fontlarını bulamıyor ve libass sessizce varsayılan fonta
    // düşüyordu ("video, ön izlemedeki fonttan farklı çıkıyor" şikayetinin nedeni).
    // Dosya bulunamazsa nil döner ve eski fontconfig yolu yedek olarak devrede kalır.
    private func prepareFontsDir(for fontName: String) -> URL? {
        let ctFont = CTFontCreateWithName(fontName as CFString, 24, nil)

        // CoreText istenen fontu bulamazsa sessizce başka bir fonta düşer;
        // yanlış dosyayı kopyalamamak için çözümlenen adı doğruluyoruz.
        let resolvedName = CTFontCopyPostScriptName(ctFont) as String
        guard resolvedName.caseInsensitiveCompare(fontName) == .orderedSame,
              let fontFileURL = CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL else {
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ass_fonts_" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fontFileURL, to: dir.appendingPathComponent(fontFileURL.lastPathComponent))
            return dir
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }

    // 4. FFmpegKit ile Videoyu Oluşturma
    func burnSubtitles(videoURL: URL, assURL: URL, fontName: String, completion: @escaping (URL?, String?) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("subby_render_" + UUID().uuidString + ".mp4")

        // Yedek yol: fontconfig sistem klasörlerini de tanır (fontsdir başarısız olursa)
        FFmpegKitConfig.setFontDirectoryList([
            Bundle.main.bundlePath,
            "/System/Library/Fonts",
            "/System/Library/Fonts/Core",
            "/System/Library/Fonts/CoreAddition",
            "/System/Library/Fonts/CoreUI",
            "/System/Library/Fonts/AppFonts",
            "/System/Library/Fonts/Extra"
        ], with: nil)

        // Asıl yol: seçilen fontun dosyası libass'a doğrudan verilir
        let fontsDir = prepareFontsDir(for: fontName)

        let inPath = videoURL.path
        let outPath = outputURL.path

        var vfString = "ass='\(escapeForFilter(assURL.path))'"
        if let fontsDir = fontsDir {
            vfString += ":fontsdir='\(escapeForFilter(fontsDir.path))'"
        }
        
        // Hardware accelerated encoding on iOS using h264_videotoolbox. Much faster and uses less battery.
        // -allow_sw 1: donanım kodlayıcı kullanılamazsa yazılım kodlayıcıya düşerek çökmesini önler.
        // 12M bitrate 1080p için yüksek kalite sağlar; 30M gereksiz büyük dosyalar üretiyordu.
        let args = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", inPath,
            "-vf", vfString,
            "-c:v", "h264_videotoolbox",
            "-allow_sw", "1",
            "-b:v", "12M",
            "-movflags", "+faststart",
            // Kaynak videodaki PCM/Opus gibi MP4 ile uyumsuz sesleri de güvenle dışa aktar.
            "-c:a", "aac",
            "-b:a", "192k",
            outPath
        ]

        FFmpegKit.execute(withArgumentsAsync: args) { session in
            // Kodlama bitti; geçici font kopyası artık gerekmez
            if let fontsDir {
                try? FileManager.default.removeItem(at: fontsDir)
            }

            guard let session = session else {
                self.deleteFile(at: outputURL)
                self.completeOnMain { completion(nil, "Bilinmeyen bir oturum hatası") }
                return
            }

            let returnCode = session.getReturnCode()

            if ReturnCode.isSuccess(returnCode) {
                self.completeOnMain { completion(outputURL, nil) }
            } else if ReturnCode.isCancel(returnCode) {
                self.deleteFile(at: outputURL)
                self.completeOnMain { completion(nil, "İşlem iptal edildi.") }
            } else {
                let logs = session.getLogsAsString() ?? "Log alınamadı"
                print("FFMPEG HATASI: \(logs)")
                self.deleteFile(at: outputURL)
                let shortLog = String(logs.suffix(2000))
                self.completeOnMain { completion(nil, shortLog) }
            }
        }
    }
    
    // 5. Videoyu Galeriye Kaydet (iOS 14+ addOnly ile daha güvenli ve detaylı hata dönüşlü)
    func saveToGallery(videoURL: URL, completion: @escaping (Bool, String?) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited {
            performSave(videoURL: videoURL, completion: completion)
        } else {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    self.performSave(videoURL: videoURL, completion: completion)
                } else {
                    self.completeOnMain {
                        completion(false, "Galeriye kaydetme izni reddedildi. Ayarlar > Gizlilik ve Güvenlik > Fotoğraflar bölümünden izin verip tekrar dene.")
                    }
                }
            }
        }
    }
    
    private func performSave(videoURL: URL, completion: @escaping (Bool, String?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { success, error in
            self.completeOnMain {
                if success {
                    completion(true, nil)
                } else {
                    completion(false, error?.localizedDescription ?? "Bilinmeyen galeri kaydetme hatası.")
                }
            }
        }
    }
    
    // Geçici dosyaları silerek telefon hafızasının şişmesini önler.
    func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    private func formatASSTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let cs = Int(round((seconds - floor(seconds)) * 100))
        return String(format: "%d:%02d:%02d.%02d", h, m, s, min(cs, 99))
    }
}
