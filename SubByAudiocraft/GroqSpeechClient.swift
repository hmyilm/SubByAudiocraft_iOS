import Foundation

final class GroqSpeechClient {
    static let shared = GroqSpeechClient()

    // Ücretsiz Groq katmanı doğrudan yüklemede 25 MB kabul ediyor. HTTP gövde
    // başlıkları için küçük bir güvenlik payı bırakılır.
    static let maximumAudioBytes = Int64(24 * 1_024 * 1_024)

    private let endpoint = URL(
        string: "https://api.groq.com/openai/v1/audio/transcriptions"
    )!
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 240
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    private struct TranscriptionResponse: Decodable {
        struct Word: Decodable {
            let word: String
            let start: Double
            let end: Double
        }

        let text: String?
        let words: [Word]?
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    enum ClientError: LocalizedError {
        case invalidAPIKey
        case audioTooLarge
        case unreadableAudio
        case invalidResponse
        case missingWordTimestamps
        case service(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidAPIKey:
                return "Groq API anahtarı eksik veya geçersiz görünüyor."
            case .audioTooLarge:
                return "Ses dosyası ücretsiz bulut yükleme sınırını aşıyor."
            case .unreadableAudio:
                return "Ses dosyası bulut analizi için okunamadı."
            case .invalidResponse:
                return "Bulut servisi geçerli bir yanıt döndürmedi."
            case .missingWordTimestamps:
                return "Bulut servisi kelime zaman damgalarını döndürmedi."
            case .service(let statusCode, let message):
                let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let detail, !detail.isEmpty {
                    return "Bulut servisi \(statusCode) hatası verdi: \(detail)"
                }
                return "Bulut servisi \(statusCode) hatası verdi."
            }
        }
    }

    static func normalizedAPIKey(_ rawKey: String) -> String {
        rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isPlausibleAPIKey(_ rawKey: String) -> Bool {
        let key = normalizedAPIKey(rawKey)
        return key.hasPrefix("gsk_") && key.count >= 24 && !key.contains(where: \.isWhitespace)
    }

    func transcribe(
        audioURL: URL,
        apiKey rawAPIKey: String
    ) async throws -> [VideoProcessor.WordTimestamp] {
        let apiKey = Self.normalizedAPIKey(rawAPIKey)
        guard Self.isPlausibleAPIKey(apiKey) else {
            throw ClientError.invalidAPIKey
        }

        let values = try audioURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 0 else {
            throw ClientError.unreadableAudio
        }
        guard Int64(fileSize) <= Self.maximumAudioBytes else {
            throw ClientError.audioTooLarge
        }

        try Task.checkCancellation()
        let boundary = "SubByAudiocraft-\(UUID().uuidString)"
        let bodyURL = try makeMultipartBodyFile(
            audioURL: audioURL,
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.upload(
            for: request,
            fromFile: bodyURL
        )
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(
                ErrorResponse.self,
                from: data
            )
            throw ClientError.service(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error?.message
            )
        }
        return try decodeWordTimestamps(from: data)
    }

    func decodeWordTimestamps(
        from data: Data
    ) throws -> [VideoProcessor.WordTimestamp] {
        let response: TranscriptionResponse
        do {
            response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch {
            throw ClientError.invalidResponse
        }
        guard let responseWords = response.words, !responseWords.isEmpty else {
            throw ClientError.missingWordTimestamps
        }

        let words = responseWords.compactMap { item -> VideoProcessor.WordTimestamp? in
            let text = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  item.start.isFinite,
                  item.end.isFinite,
                  item.end > item.start else {
                return nil
            }
            return VideoProcessor.WordTimestamp(
                text: text,
                start: max(0, item.start),
                end: max(0.05, item.end)
            )
        }
        guard !words.isEmpty else {
            throw ClientError.missingWordTimestamps
        }
        guard let transcript = response.text,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return words
        }
        return VideoProcessor.shared.applyTranscriptPunctuation(
            transcript,
            to: words
        )
    }

    private func makeMultipartBodyFile(
        audioURL: URL,
        boundary: String
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subby_groq_upload_\(UUID().uuidString)")
            .appendingPathExtension("multipart")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw ClientError.unreadableAudio
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }

            func write(_ string: String) throws {
                guard let data = string.data(using: .utf8) else {
                    throw ClientError.unreadableAudio
                }
                try output.write(contentsOf: data)
            }

            let fields: [(String, String)] = [
                ("model", "whisper-large-v3"),
                ("language", "tr"),
                ("response_format", "verbose_json"),
                ("timestamp_granularities[]", "word"),
                ("temperature", "0")
            ]
            for (name, value) in fields {
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                try write("\(value)\r\n")
            }

            try write("--\(boundary)\r\n")
            try write(
                "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
            )
            try write("Content-Type: audio/wav\r\n\r\n")

            let input = try FileHandle(forReadingFrom: audioURL)
            defer { try? input.close() }
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: 512 * 1_024),
                      !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
            try write("\r\n--\(boundary)--\r\n")
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
