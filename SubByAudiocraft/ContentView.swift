import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var statusMessage: String = "Video Seçin"
    @State private var isProcessing: Bool = false
    @State private var segments: [String] = [] // Will hold Whisper results
    
    // Config
    @State private var fontName: String = "Avenir-Heavy"
    @State private var fontSize: Double = 70.0
    @State private var marginV: Double = 120.0
    
    // Popüler Özel Fontlar (Uygulamaya Gömülü - 15 Adet)
    let popularFonts = [
        "Anton-Regular",
        "Bangers-Regular",
        "BebasNeue-Regular",
        "Lato-Bold",
        "Pacifico-Regular",
        "PermanentMarker-Regular",
        "Poppins-Bold",
        "Lobster-Regular",
        "Creepster-Regular",
        "AbrilFatface-Regular",
        "AlfaSlabOne-Regular",
        "Righteous-Regular",
        "FrancoisOne-Regular",
        "Shrikhand-Regular",
        "BlackOpsOne-Regular"
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Sub by Audiocraft")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    
                    // 1. Video Seçimi
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1. Video ve Ayarlar")
                            .font(.headline)
                        
                        PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                            HStack {
                                Image(systemName: "video.fill")
                                Text(selectedItem == nil ? "Galeriden Video Seç" : "Video Seçildi ✓")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .onChange(of: selectedItem) { newValue in
                            if newValue != nil {
                                statusMessage = "Video yüklendi. Ayarları yapıp analiz edebilirsiniz."
                            }
                        }
                        
                        Divider()
                        
                        // Ayarlar
                        VStack(alignment: .leading, spacing: 16) {
                            // Font Seçimi
                            HStack {
                                Text("Yazı Tipi:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Picker("Yazı Tipi", selection: $fontName) {
                                    ForEach(popularFonts, id: \.self) { font in
                                        Text(font.replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Heavy", with: ""))
                                            .font(.custom(font, size: 16))
                                            .tag(font)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            
                            // Boyut Seçimi
                            VStack(alignment: .leading) {
                                Text("Yazı Büyüklüğü: \(Int(fontSize))")
                                    .fontWeight(.semibold)
                                Slider(value: $fontSize, in: 30...150, step: 1)
                                    .accentColor(.purple)
                            }
                            
                            // Konum Seçimi
                            VStack(alignment: .leading) {
                                Text("Aşağı/Yukarı Konum: \(Int(marginV))")
                                    .fontWeight(.semibold)
                                Slider(value: $marginV, in: 0...500, step: 5)
                                    .accentColor(.purple)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                    
                    // 2. Analiz Butonu
                    Button(action: startAnalysis) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(12)
                        } else {
                            Text("Videoyu Analiz Et (Whisper)")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(selectedItem == nil || isProcessing)
                    
                    // Durum
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
    
    func startAnalysis() {
        guard let item = selectedItem else { return }
        isProcessing = true
        statusMessage = "Video dosyası hazırlanıyor..."
        
        item.loadTransferable(type: Movie.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let movie?):
                    self.processVideo(url: movie.url)
                case .success(nil), .failure(_):
                    self.statusMessage = "Video yüklenirken hata oluştu."
                    self.isProcessing = false
                }
            }
        }
    }
    
    func processVideo(url: URL) {
        statusMessage = "Sesi ayrıştırıyor..."
        VideoProcessor.shared.extractAudio(from: url) { audioURL in
            guard let audioURL = audioURL else {
                DispatchQueue.main.async {
                    self.statusMessage = "Hata: Ses çıkarılamadı."
                    self.isProcessing = false
                    VideoProcessor.shared.deleteFile(at: url) // Orijinal geçici video kopyasını sil
                }
                return
            }
            
            DispatchQueue.main.async { self.statusMessage = "Yapay Zeka sözleri analiz ediyor..." }
            VideoProcessor.shared.runSpeechRecognition(audioURL: audioURL) { words, speechError in
                if let speechError = speechError {
                    DispatchQueue.main.async {
                        self.statusMessage = "Hata: \(speechError)"
                        self.isProcessing = false
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        VideoProcessor.shared.deleteFile(at: url)
                    }
                    return
                }
                
                guard !words.isEmpty else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Hata: Videoda net bir konuşma bulunamadı."
                        self.isProcessing = false
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        VideoProcessor.shared.deleteFile(at: url)
                    }
                    return
                }
                
                DispatchQueue.main.async { self.statusMessage = "Altyazılar tasarlanıyor..." }
                
                Task {
                    let assURL = await VideoProcessor.shared.generateASS(words: words, fontName: fontName, fontSize: Int(fontSize), marginV: Int(marginV), videoURL: url)
                    
                    guard let assURL = assURL else {
                        DispatchQueue.main.async {
                            self.statusMessage = "Hata: Altyazı dosyası oluşturulamadı."
                            self.isProcessing = false
                            VideoProcessor.shared.deleteFile(at: audioURL)
                            VideoProcessor.shared.deleteFile(at: url)
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.statusMessage = "Altyazılar videoya gömülüyor (Bu işlem cihaz hızına göre biraz sürebilir)..."
                    }
                    
                    VideoProcessor.shared.burnSubtitles(videoURL: url, assURL: assURL) { outputURL, errorMessage in
                        guard let outputURL = outputURL else {
                            DispatchQueue.main.async {
                                self.statusMessage = "Hata: \(errorMessage ?? "Bilinmeyen FFmpeg hatası")"
                                self.isProcessing = false
                                VideoProcessor.shared.deleteFile(at: audioURL)
                                VideoProcessor.shared.deleteFile(at: assURL)
                                VideoProcessor.shared.deleteFile(at: url)
                            }
                            return
                        }
                        
                        DispatchQueue.main.async { self.statusMessage = "Galeriye kaydediliyor..." }
                        VideoProcessor.shared.saveToGallery(videoURL: outputURL) { success, galleryError in
                            DispatchQueue.main.async {
                                self.isProcessing = false
                                if success {
                                    self.statusMessage = "Tebrikler! Altyazılı video galerinize başarıyla kaydedildi. 🎉"
                                } else {
                                    self.statusMessage = "Hata: \(galleryError ?? "Galeriye kaydedilemedi.")"
                                }
                                // İşlem bitsin veya hata versin, tüm geçici dosyaları siliyoruz (Çöp toplama)
                                VideoProcessor.shared.deleteFile(at: audioURL)
                                VideoProcessor.shared.deleteFile(at: assURL)
                                VideoProcessor.shared.deleteFile(at: url)
                                VideoProcessor.shared.deleteFile(at: outputURL)
                            }
                        }
                    }
                }
        }
    }
}

// Fotoğraf kütüphanesinden videoyu geçici klasöre almak için yardımcı yapı
struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
