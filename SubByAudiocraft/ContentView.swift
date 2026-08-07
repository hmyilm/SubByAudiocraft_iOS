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

// ContentView'daki her düzenleyici alan için ayrı bir SwiftUI modifier zinciri
// kurmak Xcode 26'da body'nin generic tipini aşırı büyütüyordu. Metin ve stil
// değişikliklerini iki küçük Equatable değerde toplamak aynı autosave davranışını
// korurken derleyicinin çözeceği View tipini belirgin biçimde küçültür.
private struct TranscriptAutosaveToken: Equatable {
    let words: [VideoProcessor.WordTimestamp]
    let lineBreaks: Set<UUID>
    let inlineLineBreaks: Set<UUID>
    let emphasisWordIDs: Set<UUID>
}

private struct StyleAutosaveToken: Equatable {
    let fontName: String
    let fontSize: Double
    let marginV: Double
    let karaokeMode: String
    let lyricTrackingMode: String
    let kineticStyle: String
    let kineticAccent: String
    let kineticCustomColorHex: String
    let kineticIntensity: String
    let kineticLetterStyle: String
    let kineticOverlayStyle: String
}

private struct BottomBarSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            content
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
    @State private var inlineLineBreaks: Set<UUID> = []
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
    @AppStorage("subtitle.lyricTrackingMode") private var lyricTrackingModeRaw: String = LyricTrackingMode.karaoke.rawValue
    @AppStorage("subtitle.kineticStyle") private var kineticStyleRaw: String = KineticStyle.automatic.rawValue
    @AppStorage("subtitle.kineticAccent") private var kineticAccentRaw: String = KineticAccent.gold.rawValue
    @AppStorage("subtitle.kineticCustomColorHex") private var kineticCustomColorHex: String = KineticAccent.defaultCustomHex
    @AppStorage("subtitle.kineticIntensity") private var kineticIntensityRaw: String = KineticIntensity.balanced.rawValue
    @AppStorage("subtitle.kineticLetterStyle") private var kineticLetterStyleRaw: String = KineticLetterStyle.automatic.rawValue
    @AppStorage("subtitle.kineticOverlayStyle") private var kineticOverlayStyleRaw: String = KineticOverlayStyle.none.rawValue
    @AppStorage("subtitle.cleanTextStyleMigrationV1") private var didMigrateCleanTextStyle = false
    @AppStorage("analysis.quality") private var analysisQualityRaw: String = AnalysisQuality.balanced.rawValue
    @AppStorage("analysis.vocalIsolation") private var vocalIsolationRaw: String = VocalIsolationMode.automatic.rawValue
    @State private var groqAPIKey: String = SecureAPIKeyStore.loadGroqAPIKey()

    // Geçmiş (kaydedilmiş projeler): analizden sonra proje otomatik kaydedilir,
    // buradan yeniden açılıp düzenlenebilir ve tekrar dışa aktarılabilir.
    @ObservedObject private var store = ProjectStore.shared
    @State private var showHistory = false
    @State private var currentProjectID: UUID? = nil

    var body: some View {
        lifecycleObservedContent
    }

    // MARK: - Derleyici Dostu Görünüm Katmanları

    private var baseContent: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 16) {
                        if currentStep != .processing {
                            StepIndicator(currentIndex: stepIndex)
                                .padding(.horizontal, 24)
                                .padding(.top, 4)
                        }

                        currentStepContent

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
    }

    private var presentationObservedContent: some View {
        baseContent
        .preferredColorScheme(.dark)
        .onAppear(perform: prepareInitialState)
        .sheet(isPresented: $showHistory) {
            HistoryView(store: store, protectedProjectID: currentProjectID, onOpen: openProject)
        }
        .onChange(of: selectedItem) {
            selectedVideoItemDidChange(selectedItem)
        }
        // Döngüsel oynatma (observer sızıntısı yaratmadan)
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            playerItemDidFinish(note)
        }
    }

    private var editorObservedContent: some View {
        presentationObservedContent
        // Uzun süren analiz/kodlama sırasında ekranın kilitlenip işlemin kesilmesini önler
        .onChange(of: isProcessing) {
            UIApplication.shared.isIdleTimerDisabled = isProcessing
        }
        .onChange(of: transcriptAutosaveToken) {
            editorContentDidChange()
        }
        .onChange(of: styleAutosaveToken) {
            editorContentDidChange()
        }
    }

    private var lifecycleObservedContent: some View {
        editorObservedContent
        .onChange(of: scenePhase) {
            scenePhaseDidChange(scenePhase)
        }
        .onDisappear(perform: cleanupViewState)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch currentStep {
        case .selectVideo:
            selectVideoContent
        case .editLines:
            LineEditView(
                words: $words,
                breaks: $lineBreaks,
                inlineBreaks: $inlineLineBreaks
            )
        case .editSubtitles:
            editSubtitlesContent
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
                onEditAgain: editAgain
            )
        }
    }

    private var selectVideoContent: some View {
        SelectVideoView(
            selectedItem: $selectedItem,
            player: player,
            analysisQuality: analysisQualityBinding,
            vocalIsolationMode: vocalIsolationBinding,
            groqAPIKey: $groqAPIKey,
            isLoadingVideo: isLoadingVideo
        )
    }

    private var editSubtitlesContent: some View {
        EditWordsView(
            words: $words,
            breaks: $lineBreaks,
            inlineBreaks: $inlineLineBreaks,
            player: player,
            fontName: $fontName,
            fontSize: $fontSize,
            marginV: $marginV,
            karaokeMode: karaokeModeBinding,
            lyricTrackingMode: lyricTrackingModeBinding,
            kineticStyle: kineticStyleBinding,
            kineticAccent: kineticAccentBinding,
            kineticCustomColorHex: $kineticCustomColorHex,
            kineticIntensity: kineticIntensityBinding,
            kineticLetterStyle: kineticLetterStyleBinding,
            kineticOverlayStyle: kineticOverlayStyleBinding,
            kineticEmphasisWordIDs: $kineticEmphasisWordIDs
        )
    }

    private var transcriptAutosaveToken: TranscriptAutosaveToken {
        TranscriptAutosaveToken(
            words: words,
            lineBreaks: lineBreaks,
            inlineLineBreaks: inlineLineBreaks,
            emphasisWordIDs: kineticEmphasisWordIDs
        )
    }

    private var styleAutosaveToken: StyleAutosaveToken {
        StyleAutosaveToken(
            fontName: fontName,
            fontSize: fontSize,
            marginV: marginV,
            karaokeMode: karaokeModeRaw,
            lyricTrackingMode: lyricTrackingModeRaw,
            kineticStyle: kineticStyleRaw,
            kineticAccent: kineticAccentRaw,
            kineticCustomColorHex: kineticCustomColorHex,
            kineticIntensity: kineticIntensityRaw,
            kineticLetterStyle: kineticLetterStyleRaw,
            kineticOverlayStyle: kineticOverlayStyleRaw
        )
    }

    private func prepareInitialState() {
        // Önceki sürümlerde "Otomatik" overlay varsayılan olarak kaydediliyordu.
        // Kullanıcı seçmeden gelen siyah plaka/gölgeyi bir kez temizle; bundan sonra
        // kullanıcı Otomatik veya Alt Gölge'yi seçerse tercihi aynen korunur.
        if !didMigrateCleanTextStyle {
            if kineticOverlayStyleRaw == KineticOverlayStyle.automatic.rawValue {
                kineticOverlayStyleRaw = KineticOverlayStyle.none.rawValue
            }
            didMigrateCleanTextStyle = true
        }
        if FontCatalog.secenek(fontName) == nil { fontName = "Anton-Regular" }
        fontSize = min(max(fontSize, 30), 150)
        marginV = min(max(marginV, 30), 950)
        karaokeModeRaw = KaraokeMode.resolved(karaokeModeRaw).rawValue
        lyricTrackingModeRaw = LyricTrackingMode.resolved(lyricTrackingModeRaw).rawValue
        kineticStyleRaw = KineticStyle.resolved(kineticStyleRaw).rawValue
        kineticAccentRaw = KineticAccent.resolved(kineticAccentRaw).rawValue
        kineticCustomColorHex = KineticResolvedColor.normalizedHex(kineticCustomColorHex)
            ?? KineticAccent.defaultCustomHex
        kineticIntensityRaw = KineticIntensity.resolved(kineticIntensityRaw).rawValue
        kineticLetterStyleRaw = KineticLetterStyle(rawValue: kineticLetterStyleRaw)?.rawValue
            ?? KineticLetterStyle.automatic.rawValue
        kineticOverlayStyleRaw = KineticOverlayStyle(
            rawValue: kineticOverlayStyleRaw
        )?.rawValue ?? KineticOverlayStyle.none.rawValue
        VideoProcessor.shared.cleanupStaleTemporaryFiles()
    }

    private func selectedVideoItemDidChange(_ item: PhotosPickerItem?) {
        guard item != nil else { return }
        statusMessage = "Video yükleniyor..."
        loadAndPreviewVideo()
    }

    private func playerItemDidFinish(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item === player?.currentItem else { return }
        player?.seek(to: .zero)
        player?.play()
    }

    private func scenePhaseDidChange(_ phase: ScenePhase) {
        guard phase != .active else { return }
        autosaveWorkItem?.cancel()
        SecureAPIKeyStore.saveGroqAPIKey(groqAPIKey)
        saveProjectEdits(exported: false)
    }

    private func cleanupViewState() {
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func editAgain() {
        currentStep = .editSubtitles
        statusMessage = "Düzenlemeye geri dönüldü. Değişiklik yapıp yeniden dışa aktarabilirsin."
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
                    Text("Projeler")
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
        switch currentStep {
        case .selectVideo:
            selectVideoBottomBar
        case .editLines:
            lineEditorBottomBar
        case .editSubtitles:
            subtitleEditorBottomBar
        case .processing, .done:
            EmptyView()
        }
    }

    private var selectVideoBottomBar: some View {
        let cloudKeyIsReady = !analysisQualityBinding.wrappedValue.usesCloudTranscription
            || GroqSpeechClient.isPlausibleAPIKey(groqAPIKey)
        return BottomBarSurface {
            Button(action: startAnalysis) {
                Label(
                    isLoadingVideo
                        ? "Video Yükleniyor"
                        : (cloudKeyIsReady ? "Sözleri Çıkar" : "Önce Groq Anahtarı Gir"),
                    systemImage: isLoadingVideo
                        ? "hourglass"
                        : (cloudKeyIsReady ? "text.badge.plus" : "key.fill")
                )
            }
            .buttonStyle(
                PrimaryButtonStyle(
                    enabled: videoURL != nil
                        && !isLoadingVideo
                        && !isProcessing
                        && cloudKeyIsReady
                )
            )
            .disabled(
                videoURL == nil
                    || isLoadingVideo
                    || isProcessing
                    || !cloudKeyIsReady
            )
        }
    }

    private var lineEditorBottomBar: some View {
        BottomBarSurface {
            Button(action: confirmLineLayout) {
                Label("Tasarımı Aç", systemImage: "paintbrush.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: resetToImport) {
                Text("İptal (Başa Dön)")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
    }

    private var subtitleEditorBottomBar: some View {
        BottomBarSurface {
            if pendingOutputURL != nil {
                Button(action: retryGallerySave) {
                    Label(
                        "Hazır Videoyu Galeriye Kaydet",
                        systemImage: "photo.badge.arrow.down"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: recreateFinalVideo) {
                    Text("Videoyu Yeniden Oluştur")
                        .font(.footnote)
                        .foregroundColor(Theme.yellow)
                }
            } else {
                Button(action: burnFinalVideo) {
                    Label(
                        "Videoyu Oluştur ve Kaydet",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button(action: returnToLineLayout) {
                Text("Satır Düzenine Dön")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
    }

    private func confirmLineLayout() {
        currentStep = .editSubtitles
        saveProjectEdits(exported: false)
        statusMessage = "Satırlar onaylandı. Şimdi zamanlamaları kontrol edebilirsin."
    }

    private func recreateFinalVideo() {
        discardPendingOutput()
        burnFinalVideo()
    }

    private func returnToLineLayout() {
        saveProjectEdits(exported: false)
        currentStep = .editLines
        statusMessage = "Satır düzenine dönüldü."
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
        return statusMessage.hasPrefix("Hata:")
            || statusMessage.contains("başarıyla")
            || statusMessage.hasPrefix("Bulut kullanılamadı")
            || statusMessage.hasPrefix("Analiz notu:")
    }

    private var analysisQualityBinding: Binding<AnalysisQuality> {
        Binding(
            get: { AnalysisQuality(rawValue: analysisQualityRaw) ?? .balanced },
            set: { analysisQualityRaw = $0.rawValue }
        )
    }

    private var vocalIsolationBinding: Binding<VocalIsolationMode> {
        Binding(
            get: { VocalIsolationMode.resolved(vocalIsolationRaw) },
            set: { vocalIsolationRaw = $0.rawValue }
        )
    }

    private var karaokeModeBinding: Binding<KaraokeMode> {
        Binding(
            get: { KaraokeMode.resolved(karaokeModeRaw) },
            set: { karaokeModeRaw = $0.rawValue }
        )
    }

    private var lyricTrackingModeBinding: Binding<LyricTrackingMode> {
        Binding(
            get: { LyricTrackingMode.resolved(lyricTrackingModeRaw) },
            set: { lyricTrackingModeRaw = $0.rawValue }
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

    private var kineticOverlayStyleBinding: Binding<KineticOverlayStyle> {
        Binding(
            get: {
                KineticOverlayStyle(rawValue: kineticOverlayStyleRaw) ?? .none
            },
            set: { kineticOverlayStyleRaw = $0.rawValue }
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
                    self.statusMessage = "Video hazır. Sözleri çıkarmaya başlayabilirsin."
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

        let quality = AnalysisQuality(rawValue: analysisQualityRaw) ?? .balanced
        let vocalIsolationMode = VocalIsolationMode.resolved(vocalIsolationRaw)
        if quality.usesCloudTranscription,
           !GroqSpeechClient.isPlausibleAPIKey(groqAPIKey) {
            statusMessage = "Hata: Bulut Hassas için geçerli bir Groq API anahtarı girin."
            return
        }
        let operationID = UUID()
        activeOperationID = operationID
        isProcessing = true
        statusMessage = "Video dosyası hazırlanıyor..."
        processingStage = .extractingAudio
        currentStep = .processing

        VideoProcessor.shared.extractAudio(
            from: url,
            forVocalIsolation: vocalIsolationMode.usesVocalIsolation
        ) { audioURL in
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
            if quality.usesCloudTranscription {
                self.statusMessage = "Whisper Large V3 bulutta Türkçe sözleri ve kelime saniyelerini birlikte çözüyor."
            } else if quality.usesDedicatedLyricModel {
                self.statusMessage = "Qwen3 şarkı sözlerini çözüyor; Whisper kelime saniyelerini hizalıyor. Modeller belleği korumak için sırayla çalışır. İlk kullanımda Wi‑Fi önerilir."
            } else {
                self.statusMessage = "Hızlı yerel model sözleri ve kelime saniyelerini analiz ediyor. İlk kullanımda model indirilir; Wi‑Fi önerilir."
            }

            VideoProcessor.shared.runSpeechRecognition(
                audioURL: audioURL,
                quality: quality,
                vocalIsolationMode: vocalIsolationMode,
                cloudAPIKey: quality.usesCloudTranscription ? self.groqAPIKey : nil,
                statusUpdate: { message in
                    DispatchQueue.main.async {
                        guard self.activeOperationID == operationID else { return }
                        self.statusMessage = message
                    }
                },
                downloadProgress: { fraction in
                DispatchQueue.main.async {
                    guard self.activeOperationID == operationID else { return }
                    self.modelDownloadProgress = fraction >= 1.0 ? nil : fraction
                }
            }) { words, speechError, analysisNotice in
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
                self.inlineLineBreaks = []
                self.kineticEmphasisWordIDs = []

                // Projeyi Geçmiş'e kaydet: video kalıcı proje klasörüne taşınır,
                // player yeni adresle tazelenir.
                var projectWasSaved = false
                if let vURL = self.videoURL,
                   let proje = self.store.olustur(
                        videoURL: vURL,
                        kelimeler: words,
                        satirSonlari: self.lineBreaks,
                        icSatirSonlari: self.inlineLineBreaks,
                        fontAdi: self.fontName,
                        fontBoyu: self.fontSize,
                        dikeyKonum: self.marginV,
                        karaokeModu: KaraokeMode.resolved(self.karaokeModeRaw),
                        sozTakibi: LyricTrackingMode.resolved(self.lyricTrackingModeRaw),
                        kinetikStil: KineticStyle.resolved(self.kineticStyleRaw),
                        kinetikVurgu: KineticAccent.resolved(self.kineticAccentRaw),
                        kinetikOzelRenk: self.kineticCustomColorHex,
                        kinetikYogunluk: KineticIntensity.resolved(self.kineticIntensityRaw),
                        kinetikVurgular: self.kineticEmphasisWordIDs,
                        kinetikHarfStili: KineticLetterStyle(
                            rawValue: self.kineticLetterStyleRaw
                        ) ?? .automatic,
                        kinetikOverlay: KineticOverlayStyle(
                            rawValue: self.kineticOverlayStyleRaw
                        ) ?? .none
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
                    if let analysisNotice {
                        self.statusMessage = "Analiz notu: \(analysisNotice) "
                            + "Sözler çıkarıldı; satır düzenini kontrol edin."
                    } else {
                        self.statusMessage = "Sözler çıkarıldı. Satır düzenini kontrol edip onaylayın."
                    }
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

        // Dışa aktarım başladığı anda ekrandaki seçimi tek bir anlık görüntüye
        // kilitle. Asenkron ASS hazırlığı sırasında AppStorage/proje yenilenirse
        // render'ın varsayılan Klasik + Karaoke değerine geri düşmesini önler.
        let renderWords = words
        let renderLineBreaks = lineBreaks
        let renderInlineLineBreaks = inlineLineBreaks
        let renderFontSelection = fontName
        let renderFontName = FontCatalog.regularPSName(for: fontName)
        let renderFontSize = Int(fontSize)
        let renderMarginV = Int(marginV)
        let renderKaraokeMode = KaraokeMode.resolved(karaokeModeRaw)
        let renderTrackingMode = LyricTrackingMode.resolved(lyricTrackingModeRaw)
        let renderKineticStyle = KineticStyle.resolved(kineticStyleRaw)
        let renderKineticAccent = KineticAccent.resolved(kineticAccentRaw)
        let renderCustomColorHex = kineticCustomColorHex
        let renderIntensity = KineticIntensity.resolved(kineticIntensityRaw)
        let renderLetterStyle = KineticLetterStyle(
            rawValue: kineticLetterStyleRaw
        ) ?? .automatic
        let renderOverlayStyle = KineticOverlayStyle(
            rawValue: kineticOverlayStyleRaw
        ) ?? .none
        let renderEmphasisWordIDs = kineticEmphasisWordIDs
        statusMessage = "\(renderKaraokeMode.title) · \(renderTrackingMode.title) hazırlanıyor..."

        Task {
            let assURL = await VideoProcessor.shared.generateASS(
                words: renderWords,
                lineBreaks: renderLineBreaks,
                inlineLineBreaks: renderInlineLineBreaks,
                fontName: renderFontName,
                fontSize: renderFontSize,
                marginV: renderMarginV,
                karaokeMode: renderKaraokeMode,
                lyricTrackingMode: renderTrackingMode,
                kineticStyle: renderKineticStyle,
                kineticAccent: renderKineticAccent,
                kineticCustomColorHex: renderCustomColorHex,
                kineticIntensity: renderIntensity,
                kineticLetterStyle: renderLetterStyle,
                kineticOverlayStyle: renderOverlayStyle,
                kineticEmphasisWordIDs: renderEmphasisWordIDs,
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

            VideoProcessor.shared.burnSubtitles(
                videoURL: url,
                assURL: assURL,
                fontName: renderFontSelection
            ) { outputURL, errorMessage in
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
        self.inlineLineBreaks = []
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
            icSatirSonlari: inlineLineBreaks,
            fontAdi: fontName,
            fontBoyu: fontSize,
            dikeyKonum: marginV,
            karaokeModu: KaraokeMode.resolved(karaokeModeRaw),
            sozTakibi: LyricTrackingMode.resolved(lyricTrackingModeRaw),
            kinetikStil: KineticStyle.resolved(kineticStyleRaw),
            kinetikVurgu: KineticAccent.resolved(kineticAccentRaw),
            kinetikOzelRenk: kineticCustomColorHex,
            kinetikYogunluk: KineticIntensity.resolved(kineticIntensityRaw),
            kinetikVurgular: kineticEmphasisWordIDs,
            kinetikHarfStili: KineticLetterStyle(
                rawValue: kineticLetterStyleRaw
            ) ?? .automatic,
            kinetikOverlay: KineticOverlayStyle(
                rawValue: kineticOverlayStyleRaw
            ) ?? .none,
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
        inlineLineBreaks = proje.inlineLineBreakIDs
        kineticEmphasisWordIDs = proje.kineticEmphasisWordIDs
        if FontCatalog.secenek(proje.fontAdi) != nil { fontName = proje.fontAdi }
        fontSize = proje.fontBoyu
        marginV = proje.dikeyKonum
        karaokeModeRaw = proje.karaokeMode.rawValue
        lyricTrackingModeRaw = proje.lyricTrackingMode.rawValue
        kineticStyleRaw = proje.kineticStyle.rawValue
        kineticAccentRaw = proje.kineticAccent.rawValue
        kineticCustomColorHex = proje.kineticCustomColorHex
        kineticIntensityRaw = proje.kineticIntensity.rawValue
        kineticLetterStyleRaw = proje.kineticLetterStyle.rawValue
        kineticOverlayStyleRaw = proje.kineticOverlayStyle.rawValue
        currentProjectID = proje.id
        selectedItem = nil

        showHistory = false
        currentStep = .editLines
        statusMessage = "Proje açıldı. Düzenleyip yeniden dışa aktarabilirsin."
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
