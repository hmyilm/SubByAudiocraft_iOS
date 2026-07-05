import Foundation
import AVFoundation
import Speech
import Photos
import ffmpegkit

class VideoProcessor: ObservableObject {
    static let shared = VideoProcessor()
    
    // Uygulama içi fısıltı sonuçları (Identifiable, Hashable ve Codable uyumlu)
    struct WordTimestamp: Identifiable, Hashable, Codable {
        var id = UUID()
        var text: String
        var start: Double
        var end: Double
    }
    
    // 1. Sesi Videodan Çıkarma
    func extractAudio(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: videoURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil)
            return
        }
        
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        
        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a
        
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                completion(audioURL)
            } else {
                print("Audio export failed: \(String(describing: exportSession.error))")
                completion(nil)
            }
        }
    }
    
    // 2. Apple Native Speech (Siri) ile Sesi Metne Çevirme (Detaylı hata ve izin kontrollü)
    func runSpeechRecognition(audioURL: URL, completion: @escaping ([WordTimestamp], String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")) else {
                    completion([], "Türkçe dil desteği bu cihazda mevcut değil.")
                    return
                }
                
                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                request.shouldReportPartialResults = true
                request.taskHint = .unspecified // Kesintisiz video konuşmalarını yakalamak için unspecified (varsayılan) moduna geçiyoruz (dictation modundaki erken durma hatasını çözer)
                if #available(iOS 13.0, *) {
                    request.requiresOnDeviceRecognition = false // İnternet desteği ile yüksek doğruluk ve tüm cihazlarda çalışma
                }
                
                var bestWords: [WordTimestamp] = []
                var hasCompleted = false
                
                recognizer.recognitionTask(with: request) { result, error in
                    if hasCompleted { return }
                    
                    if let result = result {
                        var currentWords: [WordTimestamp] = []
                        for segment in result.bestTranscription.segments {
                            currentWords.append(WordTimestamp(
                                text: segment.substring,
                                start: segment.timestamp,
                                end: segment.timestamp + segment.duration
                            ))
                        }
                        if !currentWords.isEmpty {
                            bestWords = currentWords
                        }
                        
                        if result.isFinal {
                            hasCompleted = true
                            completion(bestWords, nil)
                            return
                        }
                    }
                    
                    if let error = error {
                        hasCompleted = true
                        // Hata oluşsa bile (bağlantı kesintisi, zaman aşımı vb.), şimdiye kadar yakalanan kelimeleri geri dönüyoruz ki emek boşa gitmesin
                        if !bestWords.isEmpty {
                            completion(bestWords, nil)
                        } else {
                            completion([], "Ses analiz edilirken bir hata oluştu: \(error.localizedDescription)")
                        }
                        return
                    }
                }
            case .denied, .restricted:
                completion([], "Ses tanıma izni reddedildi. Lütfen Ayarlar'dan izin verin.")
            case .notDetermined:
                completion([], "Ses tanıma izni henüz verilmedi.")
            @unknown default:
                completion([], "Bilinmeyen ses tanıma yetki hatası.")
            }
        }
    }
    
    // Font PostScript isimlerini libass/fontconfig'in tanıyacağı Font Family isimlerine dönüştürür.
    private func getFontFamilyName(for fontName: String) -> String {
        switch fontName {
        case "Anton-Regular": return "Anton"
        case "Bangers-Regular": return "Bangers"
        case "BebasNeue-Regular": return "Bebas Neue"
        case "Lato-Bold": return "Lato"
        case "Pacifico-Regular": return "Pacifico"
        case "PermanentMarker-Regular": return "Permanent Marker"
        case "Poppins-Bold": return "Poppins"
        case "Lobster-Regular": return "Lobster"
        case "Creepster-Regular": return "Creepster"
        case "AbrilFatface-Regular": return "Abril Fatface"
        case "AlfaSlabOne-Regular": return "Alfa Slab One"
        case "Righteous-Regular": return "Righteous"
        case "FrancoisOne-Regular": return "Francois One"
        case "Shrikhand-Regular": return "Shrikhand"
        case "BlackOpsOne-Regular": return "Black Ops One"
        default: return fontName.replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Heavy", with: "").replacingOccurrences(of: "-Regular", with: "")
        }
    }
    
    // 3. ASS Altyazı Dosyası Oluşturma (iOS 16+ uyumlu asenkron yapı)
    func generateASS(words: [WordTimestamp], fontName: String, fontSize: Int, marginV: Int, videoURL: URL) async -> URL? {
        let asset = AVAsset(url: videoURL)
        
        // Modern async API'ler ile video izlerini yükleme
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first else { return nil }
              
        // Deprecated naturalSize yerine load(.naturalSize) kullanımı
        guard let size = try? await track.load(.naturalSize) else { return nil }
        
        let width = Double(abs(size.width))
        let height = Double(abs(size.height))
        
        let aspectRatio = width / height
        let virtualHeight = 1080
        let virtualWidth = Int(1080.0 * aspectRatio)
        
        let familyName = getFontFamilyName(for: fontName)
        
        var assContent = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(virtualWidth)
        PlayResY: \(virtualHeight)
        
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,\(familyName),\(fontSize),&H00FFFFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,3,1.5,2,10,10,\(marginV),1
        
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        
        """
        
        // Basit bir kelime birleştirici algoritması (yan yana gelenleri gruplama)
        // Şimdilik her kelimeyi ayrı bir cümle gibi gösteriyoruz
        for word in words {
            let startStr = formatASSTime(word.start)
            let endStr = formatASSTime(word.end)
            
            // Dinamik Geçiş Efekti
            let text = word.text
            let chars = Array(text)
            var effectText = ""
            if chars.count > 0 {
                let durationMs = (word.end - word.start) * 1000
                let letterDur = durationMs / Double(chars.count)
                
                for (i, char) in chars.enumerated() {
                    let lStartMs = Int(Double(i) * letterDur)
                    let fadeEnd = lStartMs + 100
                    effectText += "{\\alpha&H00&\\t(\(lStartMs),\(fadeEnd),\\alpha&HA0&)}\(char)"
                }
            }
            
            assContent += "Dialogue: 0,\(startStr),\(endStr),Default,,0,0,0,,\(effectText)\n"
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
    
    // 4. FFmpegKit ile Videoyu Oluşturma
    func burnSubtitles(videoURL: URL, assURL: URL, completion: @escaping (URL?, String?) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        
        // Font kütüphanesini FFmpegKit'e tanıtıyoruz (Özel yüklediğimiz fontlar uygulamanın kök dizininde yer alır)
        FFmpegKitConfig.setFontDirectoryList([Bundle.main.bundlePath, "/System/Library/Fonts", "/System/Library/Fonts/Core"], with: nil)
        
        let inPath = videoURL.path
        let outPath = outputURL.path
        
        // ASS filtresi içinde geçebilecek özel karakterleri FFmpeg için escape ediyoruz
        let escapedAssPath = assURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: ",", with: "\\,")
        
        let vfString = "ass='\(escapedAssPath)'"
        
        // Hardware accelerated encoding on iOS using h264_videotoolbox. Much faster and uses less battery.
        let args = [
            "-y",
            "-i", inPath,
            "-vf", vfString,
            "-c:v", "h264_videotoolbox",
            "-b:v", "30M",
            "-c:a", "copy",
            outPath
        ]
        
        FFmpegKit.execute(withArgumentsAsync: args) { session in
            guard let session = session else {
                completion(nil, "Bilinmeyen bir oturum hatası")
                return
            }
            
            let returnCode = session.getReturnCode()
            
            if ReturnCode.isSuccess(returnCode) {
                completion(outputURL, nil)
            } else {
                let logs = session.getLogsAsString() ?? "Log alınamadı"
                print("FFMPEG HATASI: \(logs)")
                // Tam logu veya en azından son 5000 karakteri göstererek hatayı yakalıyoruz
                let shortLog = String(logs.suffix(5000))
                completion(nil, shortLog)
            }
        }
    }
    
    // 5. Videoyu Galeriye Kaydet (iOS 14+ addOnly ile daha güvenli ve detaylı hata dönüşlü)
    func saveToGallery(videoURL: URL, completion: @escaping (Bool, String?) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized {
            performSave(videoURL: videoURL, completion: completion)
        } else {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized {
                    self.performSave(videoURL: videoURL, completion: completion)
                } else {
                    completion(false, "Galeriye kaydetme izni reddedildi. Lütfen Ayarlar'dan izin verin.")
                }
            }
        }
    }
    
    private func performSave(videoURL: URL, completion: @escaping (Bool, String?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { success, error in
            if success {
                completion(true, nil)
            } else {
                completion(false, error?.localizedDescription ?? "Bilinmeyen galeri kaydetme hatası.")
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
