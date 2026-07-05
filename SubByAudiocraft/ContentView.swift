import SwiftUI
import PhotosUI
import AVKit

enum AppStep {
    case selectVideo
    case editSubtitles
    case processing
    case done
}

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var statusMessage: String = "Video Seçin"
    @State private var isProcessing: Bool = false

    // Workflow States
    @State private var currentStep: AppStep = .selectVideo
    @State private var processingStage: ProcessingStage = .extractingAudio
    @State private var modelDownloadProgress: Double? = nil
    @State private var words: [VideoProcessor.WordTimestamp] = []
    @State private var videoURL: URL? = nil
    @State private var audioURL: URL? = nil
    @State private var player: AVPlayer? = nil

    // Config
    @State private var fontName: String = "Anton-Regular"
    @State private var fontSize: Double = 70.0
    @State private var marginV: Double = 120.0

    // Popüler Fontlar (Georgia iOS'ta yerleşiktir, diğerleri uygulamaya gömülüdür)
    let popularFonts = [
        "Georgia",
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
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        StepIndicator(currentIndex: stepIndex)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)

                        switch currentStep {
                        case .selectVideo:
                            SelectVideoView(
                                selectedItem: $selectedItem,
                                player: player,
                                fontName: $fontName,
                                fontSize: $fontSize,
                                marginV: $marginV,
                                fonts: popularFonts
                            )
                        case .editSubtitles:
                            EditWordsView(
                                words: $words,
                                player: player,
                                fontName: fontName,
                                fontSize: $fontSize,
                                marginV: $marginV
                            )
                        case .processing:
                            ProcessingView(stage: processingStage, message: statusMessage, downloadProgress: modelDownloadProgress)
                        case .done:
                            SuccessView(onNewVideo: resetToImport)
                        }

                        if showBanner {
                            StatusBanner(message: statusMessage)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedItem) { newValue in
            if newValue != nil {
                statusMessage = "Video yüklendi. Stili ayarlayıp analizi başlatabilirsin."
                loadAndPreviewVideo()
            }
        }
        // Döngüsel oynatma (observer sızıntısı yaratmadan)
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            if let item = note.object as? AVPlayerItem, item === player?.currentItem {
                player?.seek(to: .zero)
                player?.play()
            }
        }
        // Uzun süren analiz/kodlama sırasında ekranın kilitlenip işlemin kesilmesini önler
        .onChange(of: isProcessing) { processing in
            UIApplication.shared.isIdleTimerDisabled = processing
        }
    }

    // MARK: - Alt Görünümler

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.yellow)
                    .frame(width: 36, height: 36)
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Sub by Audiocraft")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Yapay Zeka Altyazı Stüdyosu")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if currentStep == .selectVideo || currentStep == .editSubtitles {
            VStack(spacing: 10) {
                if currentStep == .selectVideo {
                    Button(action: startAnalysis) {
                        Label("Analizi Başlat", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: selectedItem != nil && !isProcessing))
                    .disabled(selectedItem == nil || isProcessing)
                } else {
                    Button(action: burnFinalVideo) {
                        Label("Videoya Göm ve Kaydet", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(action: resetToImport) {
                        Text("Geri Dön (Videoyu Değiştir)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(
                Color(white: 0.06)
                    .opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private var stepIndex: Int {
        switch currentStep {
        case .selectVideo: return 0
        case .editSubtitles: return 1
        case .processing: return processingStage.rawValue >= ProcessingStage.burning.rawValue ? 2 : 0
        case .done: return 3
        }
    }

    // Banner yalnızca hata ve anlamlı başarı mesajlarında görünür
    private var showBanner: Bool {
        guard currentStep == .selectVideo || currentStep == .editSubtitles else { return false }
        return statusMessage.hasPrefix("Hata:") || statusMessage.contains("başarıyla")
    }

    // MARK: - İş Mantığı

    // Galeriden seçilen videoyu kopyalayıp player'a yerleştirir
    func loadAndPreviewVideo() {
        guard let item = selectedItem else { return }

        // Yeni video seçildiğinde önceki videonun geçici dosyalarını temizle
        player?.pause()
        if let oldVideo = videoURL { VideoProcessor.shared.deleteFile(at: oldVideo) }
        if let oldAudio = audioURL { VideoProcessor.shared.deleteFile(at: oldAudio) }
        videoURL = nil
        audioURL = nil

        item.loadTransferable(type: Movie.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let movie?):
                    self.videoURL = movie.url
                    self.player = AVPlayer(url: movie.url)
                    self.player?.isMuted = true
                case .success(nil), .failure(_):
                    self.statusMessage = "Hata: Ön izleme yüklenirken sorun oluştu."
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
        processingStage = .extractingAudio
        currentStep = .processing

        VideoProcessor.shared.extractAudio(from: url) { audioURL in
            guard let audioURL = audioURL else {
                DispatchQueue.main.async {
                    // Video dosyası silinmez; kullanıcı tekrar deneyebilir
                    self.statusMessage = "Hata: Ses çıkarılamadı. Lütfen tekrar deneyin."
                    self.isProcessing = false
                    self.currentStep = .selectVideo
                }
                return
            }

            self.audioURL = audioURL

            DispatchQueue.main.async {
                self.processingStage = .transcribing
                self.statusMessage = "Yapay Zeka sözleri analiz ediyor (İlk kullanımda ~500 MB model indirilir, Wi-Fi önerilir)..."
            }

            VideoProcessor.shared.runSpeechRecognition(audioURL: audioURL, downloadProgress: { fraction in
                DispatchQueue.main.async {
                    self.modelDownloadProgress = fraction >= 1.0 ? nil : fraction
                }
            }) { words, speechError in
                if let speechError = speechError {
                    DispatchQueue.main.async {
                        self.modelDownloadProgress = nil
                        self.statusMessage = "Hata: \(speechError)"
                        self.isProcessing = false
                        self.currentStep = .selectVideo
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        self.audioURL = nil
                    }
                    return
                }

                guard !words.isEmpty else {
                    DispatchQueue.main.async {
                        self.modelDownloadProgress = nil
                        self.statusMessage = "Hata: Videoda net bir konuşma bulunamadı."
                        self.isProcessing = false
                        self.currentStep = .selectVideo
                        VideoProcessor.shared.deleteFile(at: audioURL)
                        self.audioURL = nil
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.modelDownloadProgress = nil
                    self.words = words
                    self.isProcessing = false
                    self.currentStep = .editSubtitles
                    self.statusMessage = "Ses başarıyla yazıya çevrildi. Kelimeleri düzenleyip stili ayarlayabilirsin."
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
        processingStage = .burning
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
                        // Video ve ses dosyaları korunur; kullanıcı düzenleme ekranından tekrar deneyebilir
                        self.statusMessage = "Hata: \(errorMessage ?? "Bilinmeyen FFmpeg hatası")"
                        self.isProcessing = false
                        self.currentStep = .editSubtitles
                        VideoProcessor.shared.deleteFile(at: assURL)
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.processingStage = .saving
                    self.statusMessage = "Galeriye kaydediliyor..."
                }

                VideoProcessor.shared.saveToGallery(videoURL: outputURL) { success, galleryError in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        VideoProcessor.shared.deleteFile(at: assURL)

                        if success {
                            self.statusMessage = "Tebrikler! Altyazılı video galerinize başarıyla kaydedildi. 🎉"
                            self.currentStep = .done
                            self.selectedItem = nil
                            self.player = nil
                            self.words = []

                            // Başarılı bitişte tüm geçici dosyaları temizle
                            VideoProcessor.shared.deleteFile(at: audioURL)
                            VideoProcessor.shared.deleteFile(at: url)
                            VideoProcessor.shared.deleteFile(at: outputURL)
                            self.audioURL = nil
                            self.videoURL = nil
                        } else {
                            // Girdi dosyaları korunur: kullanıcı izni verip tekrar deneyebilir
                            self.statusMessage = "Hata: \(galleryError ?? "Galeriye kaydedilemedi.")"
                            self.currentStep = .editSubtitles
                            VideoProcessor.shared.deleteFile(at: outputURL)
                        }
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
        self.statusMessage = "Video Seçin"
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
