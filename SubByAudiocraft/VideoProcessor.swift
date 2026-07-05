import Foundation
import AVFoundation
import Speech
import Photos
import ffmpegkit

class VideoProcessor: ObservableObject {
    static let shared = VideoProcessor()
    
    // Uygulama içi fısıltı sonuçları
    struct WordTimestamp {
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
    
    // 2. Apple Native Speech (Siri) ile Sesi Metne Çevirme
    func runSpeechRecognition(audioURL: URL, completion: @escaping ([WordTimestamp]) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else {
                print("Speech recognition not authorized")
                completion([])
                return
            }
            
            // Türkçe (Türkiye) dil desteği
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")) else {
                print("Turkish locale not supported")
                completion([])
                return
            }
            
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            if #available(iOS 13.0, *) {
                request.requiresOnDeviceRecognition = true // İnternetsiz çalışma (cihaz destekliyorsa)
            }
            
            recognizer.recognitionTask(with: request) { result, error in
                guard let result = result else {
                    print("Recognition failed: \(String(describing: error))")
                    completion([])
                    return
                }
                
                if result.isFinal {
                    var words: [WordTimestamp] = []
                    for segment in result.bestTranscription.segments {
                        words.append(WordTimestamp(
                            text: segment.substring,
                            start: segment.timestamp,
                            end: segment.timestamp + segment.duration
                        ))
                    }
                    completion(words)
                }
            }
        }
    }
    
    // 3. ASS Altyazı Dosyası Oluşturma
    func generateASS(words: [WordTimestamp], fontName: String, fontSize: Int, marginV: Int, videoURL: URL) -> URL? {
        // Video boyutlarını al
        guard let track = AVAsset(url: videoURL).tracks(withMediaType: .video).first else { return nil }
        let size = track.naturalSize
        let width = Int(abs(size.width))
        let height = Int(abs(size.height))
        
        var assContent = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(width)
        PlayResY: \(height)
        
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,\(fontName),\(fontSize),&H00FFFFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,3,1.5,8,10,10,\(marginV),1
        
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
            
            assContent += "Dialogue: 0,\(startStr),\(endStr),Default,,0,0,0,,\(effectText)\\N\n"
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
        
        // Font kütüphanesini FFmpegKit'e tanıtıyoruz (iOS sistem fontları için çok önemli)
        FFmpegKitConfig.setFontDirectoryList(["/System/Library/Fonts", "/System/Library/Fonts/Core", "/System/Library/Fonts/AppFonts"], andFontNameMap: nil)
        
        let inPath = videoURL.path
        let outPath = outputURL.path
        
        // ASS filtresi içinde geçebilecek özel karakterleri FFmpeg için escape ediyoruz
        let escapedAssPath = assURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: ",", with: "\\,")
        
        let vfString = "ass='\(escapedAssPath)'"
        
        // Argümanları dizi olarak vermek komut satırı açıklarını kapatır ve boşluk/tırnak hatalarını önler
        let args = [
            "-y",
            "-i", inPath,
            "-vf", vfString,
            "-c:v", "libx264",
            "-b:v", "15M",
            "-preset", "fast",
            "-c:a", "copy",
            outPath
        ]
        
        FFmpegKit.executeWithArgumentsAsync(args) { session in
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
                // Sadece son 500 karakteri gösterelim ki ekrana sığsın
                let shortLog = String(logs.suffix(500))
                completion(nil, shortLog)
            }
        }
    }
    
    // 5. Videoyu Galeriye Kaydet
    func saveToGallery(videoURL: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                completion(false)
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                completion(success)
            }
        }
    }
    
    private func formatASSTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let cs = Int(round((seconds - floor(seconds)) * 100))
        return String(format: "%d:%02d:%02d.%02d", h, m, s, min(cs, 99))
    }
}
