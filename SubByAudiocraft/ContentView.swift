import SwiftUI
import PhotosUI
import AVKit

enum AppStep {
    case selectVideo
    case editLines
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
    @State private var lineBreaks: Set<UUID> = []
    @State private var videoURL: URL? = nil
    @State private var audioURL: URL? = nil
    @State private var player: AVPlayer? = nil

    // Config
    @State private var fontName: String = "Anton-Regular"
    @State private var fontSize: Double = 70.0
    @State private var marginV: Double = 120.0

    // Geçmiş (kaydedilmiş projeler): analizden sonra proje otomatik kaydedilir,
    // buradan yeniden açılıp düzenlenebilir ve tekrar dışa aktarılabilir.
    @ObservedObject private var store = ProjectStore.shared
    @State private var showHistory = false
    @State private var currentProjectID: UUID? = nil

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
                                fonts: FontCatalog.hepsi
                            )
                        case .editLines:
                            LineEditView(words: $words, breaks: $lineBreaks)
                        case .editSubtitles:
                            EditWordsView(
                                words: $words,
                                lines: currentLines,
                                player: player,
                                fontName: fontName,
                                fontSize: $fontSize,
                                marginV: $marginV
                            )
                        case .processing:
                            ProcessingView(stage: processingStage, message: statusMessage, downloadProgress: modelDownloadProgress)
                        case .done:
                            SuccessView(
                                onNewVideo: resetToImport,
                                onEditAgain: {
                                    currentStep = .editSubtitles
                                    statusMessage = "Düzenlemeye geri dönüldü. Değişiklik yapıp yeniden dışa aktarabilirsin."
                                }
                            )
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
        .sheet(isPresented: $showHistory) {
            HistoryView(store: store, onOpen: openProject)
        }
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

            Button {
                Theme.haptic()
                showHistory = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Geçmiş")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.yellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(white: 0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if currentStep == .selectVideo || currentStep == .editLines || currentStep == .editSubtitles {
            VStack(spacing: 10) {
                if currentStep == .selectVideo {
                    Button(action: startAnalysis) {
                        Label("Analizi Başlat", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: selectedItem != nil && !isProcessing))
                    .disabled(selectedItem == nil || isProcessing)
                } else if currentStep == .editLines {
                    Button(action: {
                        currentStep = .editSubtitles
                        saveProjectEdits(exported: false)
                        statusMessage = "Satırlar onaylandı. Şimdi zamanlamaları kontrol edebilirsin."
                    }) {
                        Label("Satırları Onayla", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(action: resetToImport) {
                        Text("İptal (Başa Dön)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                } else {
                    Button(action: burnFinalVideo) {
                        Label("Videoya Göm ve Kaydet", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(action: {
                        currentStep = .editLines
                        statusMessage = "Satır düzenine dönüldü."
                    }) {
                        Text("Satır Düzenine Dön")
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
        case .editLines: return 1
        case .editSubtitles: return 2
        case .processing: return processingStage.rawValue >= ProcessingStage.burning.rawValue ? 3 : 0
        case .done: return 4
        }
    }

    // Kullanıcının onayladığı satır düzeni (ön izleme ve ASS üretimi bunları kullanır)
    private var currentLines: [[VideoProcessor.WordTimestamp]] {
        var groups: [[VideoProcessor.WordTimestamp]] = []
        var current: [VideoProcessor.WordTimestamp] = []
        for word in words {
            current.append(word)
            if lineBreaks.contains(word.id) {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // Banner yalnızca hata ve anlamlı başarı mesajlarında görünür
    private var showBanner: Bool {
        guard currentStep == .selectVideo || currentStep == .editLines || currentStep == .editSubtitles else { return false }
        return statusMessage.hasPrefix("Hata:") || statusMessage.contains("başarıyla")
    }

    // MARK: - İş Mantığı

    // Galeriden seçilen videoyu kopyalayıp player'a yerleştirir
    func loadAndPreviewVideo() {
        guard let item = selectedItem else { return }

        // Yeni video seçildiğinde önceki videonun geçici dosyalarını temizle
        // (proje klasörüne taşınmış videolar Geçmiş'e aittir, silinmez)
        player?.pause()
        if let oldVideo = videoURL, !store.projeDosyasiMi(oldVideo) { VideoProcessor.shared.deleteFile(at: oldVideo) }
        if let oldAudio = audioURL { VideoProcessor.shared.deleteFile(at: oldAudio) }
        videoURL = nil
        audioURL = nil
        currentProjectID = nil

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
                    self.lineBreaks = VideoProcessor.shared.autoLineBreaks(for: words)

                    // Projeyi Geçmiş'e kaydet: video kalıcı proje klasörüne taşınır,
                    // player yeni adresle tazelenir. Böylece uygulama kapansa bile
                    // proje sonradan açılıp yeniden düzenlenebilir.
                    if let vURL = self.videoURL,
                       let proje = self.store.olustur(
                            videoURL: vURL,
                            kelimeler: words,
                            satirSonlari: self.lineBreaks,
                            fontAdi: self.fontName,
                            fontBoyu: self.fontSize,
                            dikeyKonum: self.marginV
                       ) {
                        self.currentProjectID = proje.id
                        let yeniURL = self.store.videoURL(proje)
                        self.videoURL = yeniURL
                        self.player = AVPlayer(url: yeniURL)
                        self.player?.isMuted = true
                    }

                    self.isProcessing = false
                    self.currentStep = .editLines
                    self.statusMessage = "Sözler çıkarıldı. Satır düzenini kontrol edip onaylayın."
                }
            }
        }
    }

    // Adım 2'deki düzenlenmiş verilerle videoyu işler ve galeriye kaydeder.
    // Ses dosyası gerekmez: yalnız analiz aşamasında kullanılır; Geçmiş'ten açılan
    // projelerde ses dosyası yoktur ama yeniden dışa aktarma yapılabilir.
    func burnFinalVideo() {
        guard let url = videoURL else {
            statusMessage = "Hata: Video dosyası bulunamadı."
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
            let assURL = await VideoProcessor.shared.generateASS(words: words, lineBreaks: lineBreaks, fontName: actualFontName, fontSize: Int(fontSize), marginV: Int(marginV), videoURL: url)

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
                        VideoProcessor.shared.deleteFile(at: outputURL)

                        if success {
                            self.statusMessage = "Tebrikler! Altyazılı video galerinize başarıyla kaydedildi. 🎉"
                            self.currentStep = .done

                            // Son düzenlemeleri Geçmiş'e işle (dışa aktarım sayacıyla)
                            self.saveProjectEdits(exported: true)

                            // Yalnız geçici dosyalar silinir. Kaynak video proje klasöründe
                            // kalır ve düzenleyici durumu korunur: kullanıcı "Tekrar Düzenle"
                            // ile geri dönüp beğenmediği yeri değiştirebilir.
                            if let aURL = self.audioURL {
                                VideoProcessor.shared.deleteFile(at: aURL)
                                self.audioURL = nil
                            }
                        } else {
                            // Girdi dosyaları korunur: kullanıcı izni verip tekrar deneyebilir
                            self.statusMessage = "Hata: \(galleryError ?? "Galeriye kaydedilemedi.")"
                            self.currentStep = .editSubtitles
                        }
                    }
                }
            }
        }
    }

    // Adım 2'den vazgeçip sıfırlayarak geri döner
    // (proje klasöründeki videolar Geçmiş'e aittir; yalnız geçici dosyalar silinir)
    func resetToImport() {
        player?.pause()
        if let url = videoURL, !store.projeDosyasiMi(url) { VideoProcessor.shared.deleteFile(at: url) }
        if let aURL = audioURL { VideoProcessor.shared.deleteFile(at: aURL) }

        self.videoURL = nil
        self.audioURL = nil
        self.player = nil
        self.selectedItem = nil
        self.words = []
        self.lineBreaks = []
        self.currentProjectID = nil
        self.currentStep = .selectVideo
        self.statusMessage = "Video Seçin"
    }

    // Düzenleyicideki güncel durumu (sözler, satırlar, stil) açık projeye kaydeder
    private func saveProjectEdits(exported: Bool) {
        guard let pid = currentProjectID else { return }
        store.guncelle(
            id: pid,
            kelimeler: words,
            satirSonlari: lineBreaks,
            fontAdi: fontName,
            fontBoyu: fontSize,
            dikeyKonum: marginV,
            disaAktarildi: exported
        )
    }

    // Geçmişten seçilen projeyi düzenleyicide açar
    func openProject(_ proje: SavedProject) {
        let url = store.videoURL(proje)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showHistory = false
            statusMessage = "Hata: Projenin video dosyası bulunamadı."
            return
        }

        player?.pause()
        if let old = videoURL, !store.projeDosyasiMi(old) { VideoProcessor.shared.deleteFile(at: old) }
        if let aURL = audioURL {
            VideoProcessor.shared.deleteFile(at: aURL)
            audioURL = nil
        }

        videoURL = url
        player = AVPlayer(url: url)
        player?.isMuted = true
        words = proje.kelimeler
        lineBreaks = Set(proje.satirSonlari)
        if FontCatalog.secenek(proje.fontAdi) != nil { fontName = proje.fontAdi }
        fontSize = proje.fontBoyu
        marginV = proje.dikeyKonum
        currentProjectID = proje.id
        selectedItem = nil

        showHistory = false
        currentStep = .editLines
        statusMessage = "Proje geçmişten açıldı. Düzenleyip yeniden dışa aktarabilirsin."
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
