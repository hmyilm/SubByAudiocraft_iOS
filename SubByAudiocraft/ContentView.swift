import SwiftUI
import PhotosUI
import AVKit

enum AppStep {
    case selectVideo
    case editSubtitles
    case processing
}

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var statusMessage: String = "Video Seçin"
    @State private var isProcessing: Bool = false
    @State private var segments: [String] = [] // Will hold Whisper results
    @State private var isFontListExpanded: Bool = false
    
    // Workflow States
    @State private var currentStep: AppStep = .selectVideo
    @State private var words: [VideoProcessor.WordTimestamp] = []
    @State private var videoURL: URL? = nil
    @State private var audioURL: URL? = nil
    @State private var player: AVPlayer? = nil
    
    // Config
    @State private var fontName: String = "Anton-Regular"
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
    
    var logFileURL: URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ffmpeg_error_log.txt")
        try? statusMessage.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Sub by Audiocraft")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding(.top)
                        
                        if currentStep == .selectVideo {
                            // --- ADIM 1: VİDEO SEÇİMİ VE STİL AYARLARI ---
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text("1. Video Seçimi")
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
                                        loadAndPreviewVideo()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                            
                            // Canlı Ön İzleme Paneli (Eğer video seçildiyse gösterilir)
                            if player != nil {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Canlı Stil Ön İzlemesi")
                                        .font(.headline)
                                    
                                    GeometryReader { geo in
                                        ZStack(alignment: .bottom) {
                                            if let player = player {
                                                VideoPlayer(player: player)
                                                    .onAppear {
                                                        player.isMuted = true
                                                        player.play()
                                                        // Döngüsel oynatma
                                                        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                                                            player.seek(to: .zero)
                                                            player.play()
                                                        }
                                                    }
                                                    .onDisappear {
                                                        player.pause()
                                                    }
                                            }
                                            
                                            // Dinamik SwiftUI Altyazı Bindings (1080p referans yüksekliğine göre ölçekleme)
                                            Text("Altyazı Ön İzleme")
                                                .font(.custom(fontName, size: CGFloat(fontSize) * (geo.size.height / 1080.0)))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(6)
                                                .padding(.bottom, CGFloat(marginV) * (geo.size.height / 1080.0))
                                        }
                                    }
                                    .frame(height: 280)
                                    .cornerRadius(12)
                                    .clipped()
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(16)
                            }
                            
                            // Stil Ayarları Paneli
                            VStack(alignment: .leading, spacing: 16) {
                                Text("2. Altyazı Tasarım Ayarları")
                                    .font(.headline)
                                
                                // Font Seçimi (Aşağı açılır şık ve ön izlemeli özel liste)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Yazı Tipi:")
                                        .fontWeight(.semibold)
                                    
                                    Button(action: { withAnimation { isFontListExpanded.toggle() } }) {
                                        HStack {
                                            Text(fontName.replacingOccurrences(of: "-Regular", with: "").replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Heavy", with: ""))
                                                .font(.custom(fontName, size: 18))
                                            Spacer()
                                            Image(systemName: isFontListExpanded ? "chevron.up" : "chevron.down")
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 12)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .cornerRadius(10)
                                    }
                                    .foregroundColor(.primary)
                                    
                                    if isFontListExpanded {
                                        VStack(spacing: 0) {
                                            ScrollView(.vertical, showsIndicators: true) {
                                                VStack(spacing: 0) {
                                                    ForEach(popularFonts, id: \.self) { font in
                                                        Button(action: {
                                                            fontName = font
                                                            withAnimation { isFontListExpanded = false }
                                                        }) {
                                                            HStack {
                                                                Text(font.replacingOccurrences(of: "-Regular", with: "").replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Heavy", with: ""))
                                                                    .font(.custom(font, size: 20))
                                                                    .foregroundColor(.primary)
                                                                Spacer()
                                                                if fontName == font {
                                                                    Image(systemName: "checkmark")
                                                                        .foregroundColor(.purple)
                                                                }
                                                            }
                                                            .padding()
                                                            .background(Color(UIColor.secondarySystemGroupedBackground))
                                                        }
                                                        Divider()
                                                    }
                                                }
                                            }
                                            .frame(maxHeight: 200)
                                        }
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
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
                                    Slider(value: $marginV, in: 30...950, step: 5)
                                        .accentColor(.purple)
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                            
                        } else if currentStep == .editSubtitles {
                            // --- ADIM 2: İNTERAKTİF SÖZ DÜZENLEYİCİ VE YAZMA ---
                            
                            // Üstte Canlı Ön İzleme Her Zaman Aktif
                            if player != nil {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ön İzleme ve Tasarım Sürgüsü")
                                        .font(.headline)
                                    
                                    GeometryReader { geo in
                                        ZStack(alignment: .bottom) {
                                            if let player = player {
                                                VideoPlayer(player: player)
                                                    .onAppear {
                                                        player.isMuted = true
                                                        player.play()
                                                    }
                                            }
                                            
                                            Text("Altyazı Ön İzleme")
                                                .font(.custom(fontName, size: CGFloat(fontSize) * (geo.size.height / 1080.0)))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(6)
                                                .padding(.bottom, CGFloat(marginV) * (geo.size.height / 1080.0))
                                        }
                                    }
                                    .frame(height: 200)
                                    .cornerRadius(12)
                                    .clipped()
                                    
                                    // Hızlı Tasarım Kaydırıcıları (Dikey konumu ön izlerken düzeltmek için)
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading) {
                                            Text("Boyut: \(Int(fontSize))").font(.caption).fontWeight(.semibold)
                                            Slider(value: $fontSize, in: 30...150, step: 2).accentColor(.purple)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("Konum: \(Int(marginV))").font(.caption).fontWeight(.semibold)
                                            Slider(value: $marginV, in: 30...950, step: 5).accentColor(.purple)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(16)
                            }
                            
                            // Söz Düzeltme Listesi
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("3. Sözleri Düzenleyin")
                                        .font(.headline)
                                    Spacer()
                                    Button(action: {
                                        let newWord = VideoProcessor.WordTimestamp(
                                            text: "Yeni",
                                            start: words.last?.end ?? 0.0,
                                            end: (words.last?.end ?? 0.0) + 1.0
                                        )
                                        words.append(newWord)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Kelime Ekle")
                                        }
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.purple)
                                    }
                                    .padding(.trailing, 4)
                                    
                                    Text("\(words.count) Kelime").font(.caption).foregroundColor(.gray)
                                }
                                
                                ScrollView {
                                    VStack(spacing: 12) {
                                        ForEach(0..<words.count, id: \.self) { index in
                                            HStack(spacing: 8) {
                                                // Kelime Giriş Alanı
                                                TextField("Kelime", text: $words[index].text)
                                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                                    .font(.body)
                                                
                                                // Süre Bilgisi ve Kontrolleri
                                                VStack(spacing: 2) {
                                                    HStack(spacing: 4) {
                                                        Button(action: { if words[index].start > 0.1 { words[index].start -= 0.1 } }) {
                                                            Image(systemName: "minus.circle").font(.caption).foregroundColor(.gray)
                                                        }
                                                        Text(String(format: "%.1fs", words[index].start))
                                                            .font(.system(.caption, design: .monospaced))
                                                            .frame(width: 40)
                                                        Button(action: { words[index].start += 0.1 }) {
                                                            Image(systemName: "plus.circle").font(.caption).foregroundColor(.gray)
                                                        }
                                                    }
                                                    HStack(spacing: 4) {
                                                        Button(action: { if words[index].end > 0.1 { words[index].end -= 0.1 } }) {
                                                            Image(systemName: "minus.circle").font(.caption).foregroundColor(.gray)
                                                        }
                                                        Text(String(format: "%.1fs", words[index].end))
                                                            .font(.system(.caption, design: .monospaced))
                                                            .frame(width: 40)
                                                        Button(action: { words[index].end += 0.1 }) {
                                                            Image(systemName: "plus.circle").font(.caption).foregroundColor(.gray)
                                                        }
                                                    }
                                                }
                                                
                                                // Silme Butonu
                                                Button(action: {
                                                    words.remove(at: index)
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                        .padding(.horizontal, 4)
                                                }
                                            }
                                            .padding(8)
                                            .background(Color(UIColor.tertiarySystemBackground))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .frame(maxHeight: 280)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                            
                        } else if currentStep == .processing {
                            // --- ADIM 3: İŞLEM SÜRECİ EKRANI ---
                            VStack(spacing: 24) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                    .scaleEffect(2.0)
                                
                                Text("İşlem Yapılıyor...")
                                    .font(.headline)
                                
                                Text(statusMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                        }
                        
                        // Alt Durum Mesajı (Sadece hata veya bilgilendirme)
                        if currentStep != .processing {
                            Text(statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .textSelection(.enabled)
                            
                            if statusMessage.hasPrefix("Hata:") {
                                VStack(spacing: 12) {
                                    Button(action: {
                                        UIPasteboard.general.string = statusMessage
                                    }) {
                                        HStack {
                                            Image(systemName: "doc.on.doc.fill")
                                            Text("Hata Logunu Kopyala")
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    
                                    if let fileURL = logFileURL {
                                        ShareLink(item: fileURL) {
                                            HStack {
                                                Image(systemName: "folder.fill")
                                                Text("Dosyalara Kaydet / Paylaş")
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        
                    }
                    .padding()
                }
                
                // --- EKRANIN ALTINA SABİTLENEN DİNAMİK BUTON BAR ---
                if currentStep != .processing {
                    VStack(spacing: 12) {
                        if currentStep == .selectVideo {
                            Button(action: startAnalysis) {
                                Text("Videoyu Analiz Et (Whisper)")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(selectedItem == nil ? Color.gray : Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(selectedItem == nil || isProcessing)
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        } else if currentStep == .editSubtitles {
                            Button(action: burnFinalVideo) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Altyazıları Videoya Göm ve Kaydet")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            
                            Button(action: resetToImport) {
                                Text("Geri Dön (Videoyu Değiştir)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -4)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    // Galeriden seçilen videoyu kopyalayıp player'a yerleştirir
    func loadAndPreviewVideo() {
        guard let item = selectedItem else { return }
        
        item.loadTransferable(type: Movie.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let movie?):
                    self.videoURL = movie.url
                    self.player = AVPlayer(url: movie.url)
                    self.player?.isMuted = true
                case .success(nil), .failure(_):
                    self.statusMessage = "Ön izleme yüklenirken hata oluştu."
                }
            }
        }
    }
    
    // Adım 1'den Adım 2'ye geçişi başlatır (Sesi çıkarır ve analiz eder)
    func startAnalysis() {
        guard let url = videoURL else {
            statusMessage = "Öncelikle video seçmelisiniz."
            return
        }
        isProcessing = true
        statusMessage = "Video dosyası hazırlanıyor..."
        currentStep = .processing
        
        VideoProcessor.shared.extractAudio(from: url) { audioURL in
            guard let audioURL = audioURL else {
                DispatchQueue.main.async {
                    self.statusMessage = "Hata: Ses çıkarılamadı."
                    self.isProcessing = false
                    self.currentStep = .selectVideo
                    VideoProcessor.shared.deleteFile(at: url)
                }
                return
            }
            
            self.audioURL = audioURL
            
            DispatchQueue.main.async { self.statusMessage = "Yapay Zeka sözleri analiz ediyor..." }
            
            VideoProcessor.shared.runSpeechRecognition(audioURL: audioURL) { words, speechError in
                if let speechError = speechError {
                    DispatchQueue.main.async {
                        self.statusMessage = "Hata: \(speechError)"
                        self.isProcessing = false
                        self.currentStep = .selectVideo
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        VideoProcessor.shared.deleteFile(at: url)
                    }
                    return
                }
                
                guard !words.isEmpty else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Hata: Videoda net bir konuşma bulunamadı."
                        self.isProcessing = false
                        self.currentStep = .selectVideo
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        VideoProcessor.shared.deleteFile(at: url)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.words = words
                    self.isProcessing = false
                    self.currentStep = .editSubtitles
                    self.statusMessage = "Ses başarıyla yazıya çevrildi. Kelimeleri düzenleyip stili ayarlayabilirsiniz."
                }
            }
        }
    }
    
    // Adım 2'deki düzenlenmiş verilerle videoyu işler ve galeriye kaydeder
    func burnFinalVideo() {
        guard let url = videoURL, let audioURL = audioURL else {
            statusMessage = "Hata: Video veya ses dosyası bulunamadı."
            return
        }
        
        currentStep = .processing
        statusMessage = "Altyazı dosyası hazırlanıyor..."
        isProcessing = true
        
        // Video oynatıcıyı durdur
        player?.pause()
        
        Task {
            let actualFontName = fontName
            let assURL = await VideoProcessor.shared.generateASS(words: words, fontName: actualFontName, fontSize: Int(fontSize), marginV: Int(marginV), videoURL: url)
            
            guard let assURL = assURL else {
                DispatchQueue.main.async {
                    self.statusMessage = "Hata: Altyazı dosyası oluşturulamadı."
                    self.isProcessing = false
                    self.currentStep = .editSubtitles
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
                        self.currentStep = .editSubtitles
                        VideoProcessor.shared.deleteFile(at: assURL)
                    }
                    return
                }
                
                DispatchQueue.main.async { self.statusMessage = "Galeriye kaydediliyor..." }
                
                VideoProcessor.shared.saveToGallery(videoURL: outputURL) { success, galleryError in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        if success {
                            self.statusMessage = "Tebrikler! Altyazılı video galerinize başarıyla kaydedildi. 🎉"
                            self.currentStep = .selectVideo
                            self.selectedItem = nil
                            self.player = nil
                            self.words = []
                        } else {
                            self.statusMessage = "Hata: \(galleryError ?? "Galeriye kaydedilemedi.")"
                            self.currentStep = .editSubtitles
                        }
                        
                        // Garbage Collection (Tüm geçici dosyaları temizleme)
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        VideoProcessor.shared.deleteFile(at: assURL)
                        VideoProcessor.shared.deleteFile(at: url)
                        VideoProcessor.shared.deleteFile(at: outputURL)
                        
                        self.audioURL = nil
                        self.videoURL = nil
                    }
                }
            }
        }
    }
    
    // Adım 2'den vazgeçip sıfırlayarak geri döner
    func resetToImport() {
        player?.pause()
        if let url = videoURL { VideoProcessor.shared.deleteFile(at: url) }
        if let aURL = audioURL { VideoProcessor.shared.deleteFile(at: aURL) }
        
        self.videoURL = nil
        self.audioURL = nil
        self.player = nil
        self.selectedItem = nil
        self.words = []
        self.currentStep = .selectVideo
        self.statusMessage = "Seçim sıfırlandı. Yeni video seçebilirsiniz."
    }
}

// Fotoğraf kütüphanesinden videoyu geçici klasöre almak için yardımcı yapı
struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let isSecurityScoped = received.file.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    received.file.stopAccessingSecurityScopedResource()
                }
            }
            let copy = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copy.path) {
                try? FileManager.default.removeItem(at: copy)
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
