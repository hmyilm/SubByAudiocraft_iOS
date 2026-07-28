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
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var statusMessage: String = "Video Seçin"
    @State private var isProcessing: Bool = false
    @State private var isLoadingVideo: Bool = false

    // Workflow States
    @State private var currentStep: AppStep = .selectVideo
    @State private var processingStage: ProcessingStage = .extractingAudio
    @State private var modelDownloadProgress: Double? = nil
    @State private var words: [VideoProcessor.WordTimestamp] = []
    @State private var lineBreaks: Set<UUID> = []
    @State private var kineticEmphasisWordIDs: Set<UUID> = []
    @State private var videoURL: URL? = nil
    @State private var audioURL: URL? = nil
    @State private var pendingOutputURL: URL? = nil
    @State private var player: AVPlayer? = nil
    @State private var videoLoadID: UUID? = nil
    @State private var activeOperationID: UUID? = nil
    @State private var autosaveWorkItem: DispatchWorkItem? = nil

    // Config
    @AppStorage("subtitle.fontName") private var fontName: String = "Anton-Regular"
    @AppStorage("subtitle.fontSize") private var fontSize: Double = 70.0
    @AppStorage("subtitle.marginV") private var marginV: Double = 120.0
    @AppStorage("subtitle.karaokeMode") private var karaokeModeRaw: String = KaraokeMode.classic.rawValue
    @AppStorage("subtitle.kineticStyle") private var kineticStyleRaw: String = KineticStyle.automatic.rawValue
    @AppStorage("subtitle.kineticAccent") private var kineticAccentRaw: String = KineticAccent.gold.rawValue
    @AppStorage("subtitle.kineticIntensity") private var kineticIntensityRaw: String = KineticIntensity.balanced.rawValue
    @AppStorage("subtitle.kineticLetterStyle") private var kineticLetterStyleRaw: String = KineticLetterStyle.automatic.rawValue
    @AppStorage("analysis.quality") private var analysisQualityRaw: String = AnalysisQuality.balanced.rawValue

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
                                karaokeMode: karaokeModeBinding,
                                kineticStyle: kineticStyleBinding,
                                kineticAccent: kineticAccentBinding,
                                kineticIntensity: kineticIntensityBinding,
                                kineticLetterStyle: kineticLetterStyleBinding,
                                analysisQuality: analysisQualityBinding,
                                isLoadingVideo: isLoadingVideo,
                                fonts: FontCatalog.hepsi
                            )
                        case .editLines:
                            LineEditView(words: $words, breaks: $lineBreaks)
                        case .editSubtitles:
                            EditWordsView(
                                words: $words,
                                breaks: $lineBreaks,
                                player: player,
                                fontName: $fontName,
                                fontSize: $fontSize,
                                marginV: $marginV,
                                karaokeMode: karaokeModeBinding,
                                kineticStyle: kineticStyleBinding,
                                kineticAccent: kineticAccentBinding,
                                kineticIntensity: kineticIntensityBinding,
                                kineticLetterStyle: kineticLetterStyleBinding,
                                kineticEmphasisWordIDs: $kineticEmphasisWordIDs
                            )
                        case .processing:
                            ProcessingView(
                                stage: processingStage,
                                message: statusMessage,
                                downloadProgress: modelDownloadProgress,
                                onCancel: processingStage == .saving ? nil : cancelCurrentOperation
                            )
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
        .onAppear {
            if FontCatalog.secenek(fontName) == nil { fontName = "Anton-Regular" }
            fontSize = min(max(fontSize, 30), 150)
            marginV = min(max(marginV, 30), 950)
            karaokeModeRaw = KaraokeMode.resolved(karaokeModeRaw).rawValue
            kineticStyleRaw = KineticStyle.resolved(kineticStyleRaw).rawValue
            kineticAccentRaw = KineticAccent.resolved(kineticAccentRaw).rawValue
            kineticIntensityRaw = KineticIntensity.resolved(kineticIntensityRaw).rawValue
            kineticLetterStyleRaw = KineticLetterStyle(rawValue: kineticLetterStyleRaw)?.rawValue
                ?? KineticLetterStyle.automatic.rawValue
            VideoProcessor.shared.cleanupStaleTemporaryFiles()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(store: store, protectedProjectID: currentProjectID, onOpen: openProject)
        }
        .onChange(of: selectedItem) { newValue in
            if newValue != nil {
                statusMessage = "Video yükleniyor..."
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
        .onChange(of: words) { _ in editorContentDidChange() }
        .onChange(of: lineBreaks) { _ in editorContentDidChange() }
        .onChange(of: kineticEmphasisWordIDs) { _ in editorContentDidChange() }
        .onChange(of: fontName) { _ in editorContentDidChange() }
        .onChange(of: fontSize) { _ in editorContentDidChange() }
        .onChange(of: marginV) { _ in editorContentDidChange() }
        .onChange(of: karaokeModeRaw) { _ in editorContentDidChange() }
        .onChange(of: kineticStyleRaw) { _ in editorContentDidChange() }
        .onChange(of: kineticAccentRaw) { _ in editorContentDidChange() }
        .onChange(of: kineticIntensityRaw) { _ in editorContentDidChange() }
        .onChange(of: kineticLetterStyleRaw) { _ in editorContentDidChange() }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                autosaveWorkItem?.cancel()
                saveProjectEdits(exported: false)
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
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
                saveProjectEdits(exported: false)
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
            .disabled(isProcessing || isLoadingVideo)
            .opacity(isProcessing || isLoadingVideo ? 0.45 : 1)
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
                        Label(isLoadingVideo ? "Video Yükleniyor" : "Analizi Başlat", systemImage: isLoadingVideo ? "hourglass" : "wand.and.stars")
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: videoURL != nil && !isLoadingVideo && !isProcessing))
                    .disabled(videoURL == nil || isLoadingVideo || isProcessing)
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
                    if pendingOutputURL != nil {
                        Button(action: retryGallerySave) {
                            Label("Hazır Videoyu Galeriye Kaydet", systemImage: "photo.badge.arrow.down")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            discardPendingOutput()
                            burnFinalVideo()
                        } label: {
                            Text("Videoyu Yeniden Oluştur")
                                .font(.footnote)
                                .foregroundColor(Theme.yellow)
                        }
                    } else {
                        Button(action: burnFinalVideo) {
                            Label("Videoya Göm ve Kaydet", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    Button(action: {
                        saveProjectEdits(exported: false)
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

    // Banner yalnızca hata ve anlamlı başarı mesajlarında görünür
    private var showBanner: Bool {
        guard currentStep == .selectVideo || currentStep == .editLines || currentStep == .editSubtitles else { return false }
        return statusMessage.hasPrefix("Hata:") || statusMessage.contains("başarıyla")
    }

    private var analysisQualityBinding: Binding<AnalysisQuality> {
        Binding(
            get: { AnalysisQuality(rawValue: analysisQualityRaw) ?? .balanced },
            set: { analysisQualityRaw = $0.rawValue }
        )
    }

    private var karaokeModeBinding: Binding<KaraokeMode> {
        Binding(
            get: { KaraokeMode.resolved(karaokeModeRaw) },
            set: { karaokeModeRaw = $0.rawValue }
        )
    }

    private var kineticStyleBinding: Binding<KineticStyle> {
        Binding(
            get: { KineticStyle.resolved(kineticStyleRaw) },
            set: { kineticStyleRaw = $0.rawValue }
        )
    }

    private var kineticAccentBinding: Binding<KineticAccent> {
        Binding(
            get: { KineticAccent.resolved(kineticAccentRaw) },
            set: { kineticAccentRaw = $0.rawValue }
        )
    }

    private var kineticIntensityBinding: Binding<KineticIntensity> {
        Binding(
            get: { KineticIntensity.resolved(kineticIntensityRaw) },
            set: { kineticIntensityRaw = $0.rawValue }
        )
    }

    private var kineticLetterStyleBinding: Binding<KineticLetterStyle> {
        Binding(
            get: {
                KineticLetterStyle(rawValue: kineticLetterStyleRaw) ?? .automatic
            },
            set: { kineticLetterStyleRaw = $0.rawValue }
        )
    }

    // MARK: - İş Mantığı

    // Galeriden seçilen videoyu kopyalayıp player'a yerleştirir
    func loadAndPreviewVideo() {
        guard let item = selectedItem else { return }
        let loadID = UUID()
        videoLoadID = loadID
        isLoadingVideo = true

        // Yeni video seçildiğinde önceki videonun geçici dosyalarını temizle
        // (proje klasörüne taşınmış videolar Geçmiş'e aittir, silinmez)
        saveProjectEdits(exported: false)
        cancelCurrentOperation(showMessage: false)
        discardPendingOutput()
        player?.pause()
        if let oldVideo = videoURL, !store.projeDosyasiMi(oldVideo) { VideoProcessor.shared.deleteFile(at: oldVideo) }
        if let oldAudio = audioURL { VideoProcessor.shared.deleteFile(at: oldAudio) }
        videoURL = nil
        audioURL = nil
        currentProjectID = nil

        item.loadTransferable(type: Movie.self) { result in
            DispatchQueue.main.async {
                guard self.videoLoadID == loadID else {
                    if case .success(let staleMovie?) = result {
                        VideoProcessor.shared.deleteFile(at: staleMovie.url)
                    }
                    return
                }
                self.isLoadingVideo = false
                self.videoLoadID = nil

                switch result {
                case .success(let movie?):
                    guard FileManager.default.fileExists(atPath: movie.url.path) else {
                        self.statusMessage = "Hata: Seçilen video dosyasına erişilemedi."
                        return
                    }
                    self.videoURL = movie.url
                    self.player = AVPlayer(url: movie.url)
                    self.player?.isMuted = true
                    self.statusMessage = "Video hazır. Analiz kalitesini ve altyazı stilini seçebilirsin."
                case .success(nil):
                    self.statusMessage = "Hata: Seçilen video yüklenemedi."
                case .failure(let error):
                    self.statusMessage = "Hata: Video yüklenemedi: \(error.localizedDescription)"
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "Hata: Video dosyası artık mevcut değil. Lütfen yeniden seçin."
            return
        }

        let operationID = UUID()
        activeOperationID = operationID
        let quality = AnalysisQuality(rawValue: analysisQualityRaw) ?? .balanced
        isProcessing = true
        statusMessage = "Video dosyası hazırlanıyor..."
        processingStage = .extractingAudio
        currentStep = .processing

        VideoProcessor.shared.extractAudio(from: url) { audioURL in
            guard self.activeOperationID == operationID else {
                if let audioURL { VideoProcessor.shared.deleteFile(at: audioURL) }
                return
            }
            guard let audioURL = audioURL else {
                self.activeOperationID = nil
                self.statusMessage = "Hata: Videoda kullanılabilir bir ses parçası bulunamadı veya ses çıkarılamadı."
                self.isProcessing = false
                self.currentStep = .selectVideo
                return
            }

            self.audioURL = audioURL
            self.processingStage = .transcribing
            let effectiveQuality = quality.usesMemorySafeFallback ? "Bellek dostu" : quality.title
            self.statusMessage = "\(effectiveQuality) yapay zeka modeli sözleri analiz ediyor. İlk kullanımda model indirilir; Wi‑Fi önerilir."

            VideoProcessor.shared.runSpeechRecognition(audioURL: audioURL, quality: quality, downloadProgress: { fraction in
                DispatchQueue.main.async {
                    guard self.activeOperationID == operationID else { return }
                    self.modelDownloadProgress = fraction >= 1.0 ? nil : fraction
                }
            }) { words, speechError in
                VideoProcessor.shared.deleteFile(at: audioURL)
                if self.audioURL == audioURL { self.audioURL = nil }

                guard self.activeOperationID == operationID else { return }
                self.activeOperationID = nil

                if let speechError = speechError {
                    self.modelDownloadProgress = nil
                    if speechError == "İşlem iptal edildi." {
                        self.statusMessage = speechError
                    } else {
                        self.statusMessage = "Hata: \(speechError)"
                    }
                    self.isProcessing = false
                    self.currentStep = .selectVideo
                    return
                }

                guard !words.isEmpty else {
                    self.modelDownloadProgress = nil
                    self.statusMessage = "Hata: Videoda net bir vokal veya konuşma bulunamadı."
                    self.isProcessing = false
                    self.currentStep = .selectVideo
                    return
                }

                self.modelDownloadProgress = nil
                self.words = words
                self.lineBreaks = VideoProcessor.shared.autoLineBreaks(for: words)
                self.kineticEmphasisWordIDs = []

                // Projeyi Geçmiş'e kaydet: video kalıcı proje klasörüne taşınır,
                // player yeni adresle tazelenir.
                var projectWasSaved = false
                if let vURL = self.videoURL,
                   let proje = self.store.olustur(
                        videoURL: vURL,
                        kelimeler: words,
                        satirSonlari: self.lineBreaks,
                        fontAdi: self.fontName,
                        fontBoyu: self.fontSize,
                        dikeyKonum: self.marginV,
                        karaokeModu: KaraokeMode.resolved(self.karaokeModeRaw),
                        kinetikStil: KineticStyle.resolved(self.kineticStyleRaw),
                        kinetikVurgu: KineticAccent.resolved(self.kineticAccentRaw),
                        kinetikYogunluk: KineticIntensity.resolved(self.kineticIntensityRaw),
                        kinetikVurgular: self.kineticEmphasisWordIDs,
                        kinetikHarfStili: KineticLetterStyle(
                            rawValue: self.kineticLetterStyleRaw
                        ) ?? .automatic
                   ) {
                    self.currentProjectID = proje.id
                    let yeniURL = self.store.videoURL(proje)
                    self.videoURL = yeniURL
                    self.player = AVPlayer(url: yeniURL)
                    self.player?.isMuted = true
                    projectWasSaved = true
                }

                self.isProcessing = false
                self.currentStep = .editLines
                if projectWasSaved {
                    self.statusMessage = "Sözler çıkarıldı. Satır düzenini kontrol edip onaylayın."
                } else {
                    self.statusMessage = "Hata: Sözler çıkarıldı ancak proje Geçmiş'e kaydedilemedi. Cihazdaki boş alanı kontrol edin."
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
        guard !words.isEmpty else {
            statusMessage = "Hata: Dışa aktarılacak altyazı bulunamadı."
            return
        }
        guard VideoProcessor.shared.hasEnoughSpaceToRender(videoURL: url) else {
            statusMessage = "Hata: Videoyu oluşturmak için yeterli boş alan yok. Cihazda yer açıp tekrar dene."
            return
        }

        discardPendingOutput()
        let operationID = UUID()
        activeOperationID = operationID
        currentStep = .processing
        processingStage = .burning
        statusMessage = "Altyazı dosyası hazırlanıyor..."
        isProcessing = true

        // Video oynatıcıyı durdur
        player?.pause()

        Task {
            let actualFontName = fontName
            let assURL = await VideoProcessor.shared.generateASS(
                words: words,
                lineBreaks: lineBreaks,
                fontName: actualFontName,
                fontSize: Int(fontSize),
                marginV: Int(marginV),
                karaokeMode: KaraokeMode.resolved(karaokeModeRaw),
                kineticStyle: KineticStyle.resolved(kineticStyleRaw),
                kineticAccent: KineticAccent.resolved(kineticAccentRaw),
                kineticIntensity: KineticIntensity.resolved(kineticIntensityRaw),
                kineticLetterStyle: KineticLetterStyle(
                    rawValue: kineticLetterStyleRaw
                ) ?? .automatic,
                kineticEmphasisWordIDs: kineticEmphasisWordIDs,
                videoURL: url
            )

            guard self.activeOperationID == operationID else {
                if let assURL { VideoProcessor.shared.deleteFile(at: assURL) }
                return
            }
            guard let assURL = assURL else {
                self.activeOperationID = nil
                self.statusMessage = "Hata: Altyazı dosyası oluşturulamadı."
                self.isProcessing = false
                self.currentStep = .editSubtitles
                return
            }

            self.statusMessage = "Altyazılar videoya gömülüyor. Bu işlem video süresine ve cihaz hızına göre biraz sürebilir..."

            VideoProcessor.shared.burnSubtitles(videoURL: url, assURL: assURL, fontName: actualFontName) { outputURL, errorMessage in
                VideoProcessor.shared.deleteFile(at: assURL)

                guard self.activeOperationID == operationID else {
                    if let outputURL { VideoProcessor.shared.deleteFile(at: outputURL) }
                    return
                }
                guard let outputURL = outputURL else {
                    self.activeOperationID = nil
                    self.statusMessage = "Hata: \(errorMessage ?? "Bilinmeyen video işleme hatası")"
                    self.isProcessing = false
                    self.currentStep = .editSubtitles
                    return
                }

                self.pendingOutputURL = outputURL
                self.savePendingOutput(operationID: operationID)
            }
        }
    }

    private func retryGallerySave() {
        guard pendingOutputURL != nil else { return }
        let operationID = UUID()
        activeOperationID = operationID
        savePendingOutput(operationID: operationID)
    }

    private func savePendingOutput(operationID: UUID) {
        guard let outputURL = pendingOutputURL,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            activeOperationID = nil
            discardPendingOutput()
            statusMessage = "Hata: Hazır video dosyası bulunamadı. Videoyu yeniden oluşturun."
            currentStep = .editSubtitles
            isProcessing = false
            return
        }

        currentStep = .processing
        processingStage = .saving
        statusMessage = "Galeriye kaydediliyor..."
        isProcessing = true

        VideoProcessor.shared.saveToGallery(videoURL: outputURL) { success, galleryError in
            guard self.activeOperationID == operationID else { return }
            self.activeOperationID = nil
            self.isProcessing = false

            if success {
                VideoProcessor.shared.deleteFile(at: outputURL)
                self.pendingOutputURL = nil
                self.statusMessage = "Tebrikler! Altyazılı video galerinize başarıyla kaydedildi. 🎉"
                self.currentStep = .done
                self.saveProjectEdits(exported: true)
            } else {
                // Kodlanmış dosyayı koru; kullanıcı izni düzelttikten sonra yeniden
                // video kodlamadan yalnız galeri kaydını tekrar deneyebilir.
                self.statusMessage = "Hata: \(galleryError ?? "Galeriye kaydedilemedi.")"
                self.currentStep = .editSubtitles
            }
        }
    }

    // Adım 2'den vazgeçip sıfırlayarak geri döner
    // (proje klasöründeki videolar Geçmiş'e aittir; yalnız geçici dosyalar silinir)
    func resetToImport() {
        saveProjectEdits(exported: false)
        cancelCurrentOperation(showMessage: false)
        discardPendingOutput()
        player?.pause()
        if let url = videoURL, !store.projeDosyasiMi(url) { VideoProcessor.shared.deleteFile(at: url) }
        if let aURL = audioURL { VideoProcessor.shared.deleteFile(at: aURL) }

        self.videoURL = nil
        self.audioURL = nil
        self.player = nil
        self.selectedItem = nil
        self.words = []
        self.lineBreaks = []
        self.kineticEmphasisWordIDs = []
        self.currentProjectID = nil
        self.currentStep = .selectVideo
        self.statusMessage = "Video Seçin"
    }

    private func cancelCurrentOperation() {
        cancelCurrentOperation(showMessage: true)
    }

    private func cancelCurrentOperation(showMessage: Bool) {
        guard isProcessing || activeOperationID != nil else { return }
        let wasExporting = processingStage == .burning || processingStage == .saving
        activeOperationID = nil
        VideoProcessor.shared.cancelAllProcessing()
        modelDownloadProgress = nil
        isProcessing = false
        currentStep = wasExporting ? .editSubtitles : .selectVideo
        if showMessage {
            statusMessage = "İşlem iptal edildi. Kaynak videon korunuyor; hazır olduğunda tekrar deneyebilirsin."
        }
    }

    private func discardPendingOutput() {
        guard let url = pendingOutputURL else { return }
        VideoProcessor.shared.deleteFile(at: url)
        pendingOutputURL = nil
    }

    private func editorContentDidChange() {
        discardPendingOutput()
        autosaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            self.saveProjectEdits(exported: false)
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
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
            karaokeModu: KaraokeMode.resolved(karaokeModeRaw),
            kinetikStil: KineticStyle.resolved(kineticStyleRaw),
            kinetikVurgu: KineticAccent.resolved(kineticAccentRaw),
            kinetikYogunluk: KineticIntensity.resolved(kineticIntensityRaw),
            kinetikVurgular: kineticEmphasisWordIDs,
            kinetikHarfStili: KineticLetterStyle(
                rawValue: kineticLetterStyleRaw
            ) ?? .automatic,
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

        saveProjectEdits(exported: false)
        cancelCurrentOperation(showMessage: false)
        discardPendingOutput()
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
        kineticEmphasisWordIDs = proje.kineticEmphasisWordIDs
        if FontCatalog.secenek(proje.fontAdi) != nil { fontName = proje.fontAdi }
        fontSize = proje.fontBoyu
        marginV = proje.dikeyKonum
        karaokeModeRaw = proje.karaokeMode.rawValue
        kineticStyleRaw = proje.kineticStyle.rawValue
        kineticAccentRaw = proje.kineticAccent.rawValue
        kineticIntensityRaw = proje.kineticIntensity.rawValue
        kineticLetterStyleRaw = proje.kineticLetterStyle.rawValue
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
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("subby_source_" + UUID().uuidString)
                .appendingPathExtension(ext)
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
