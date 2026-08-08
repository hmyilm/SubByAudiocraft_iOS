import Foundation
import AVFoundation
import WhisperKit
import Qwen3ASR
import Photos
import ffmpegkit
import CoreText

enum AnalysisQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case best
    case cloud

    // large-v3 modeli sıkıştırılmış olsa da Core ML özelleştirme ve çözümleme
    // sırasında bunun birkaç katı geçici bellek kullanabilir. 8 GB altındaki
    // cihazlarda iOS uygulamayı hata vermeden (jetsam) kapatabildiği için bu
    // cihazlarda zaman hizalaması small modele güvenli biçimde düşürülür.
    // Şarkı sözlerini ise large Whisper yerine, şarkı/BGM tanıma için eğitilmiş
    // Qwen3-ASR 0.6B çözer. İki model hiçbir zaman aynı anda bellekte tutulmaz.
    static let largeModelMinimumPhysicalMemory = UInt64(8) * 1_024 * 1_024 * 1_024
    // iOS, ayrılmış sistem belleği nedeniyle 6 GB donanımı ProcessInfo'da biraz
    // daha düşük raporlayabilir. 5 GB eşiği iPhone 14 sınıfını güvenle kapsar.
    static let qwenFiveBitMinimumPhysicalMemory = UInt64(5) * 1_024 * 1_024 * 1_024

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Hızlı"
        case .balanced: return "Dengeli"
        case .best: return "En İyi"
        case .cloud: return "Bulut"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            return "Yalnız yerel Whisper • en az indirme ve en hızlı analiz"
        case .balanced:
            return "Önerilen • Qwen3 şarkı modeli + hassas kelime zamanlaması"
        case .best:
            if usesMemorySafeFallback {
                return "Qwen3 söz motoru + çift geçişli, bellek dostu zaman hizalama"
            }
            return "Qwen3 söz motoru + büyük modelle çift geçişli zaman hizalama"
        case .cloud:
            return "Whisper Large V3 • güçlü bulut analizi ve doğrudan kelime zamanları"
        }
    }

    var usesMemorySafeFallback: Bool {
        self == .best && ProcessInfo.processInfo.physicalMemory < Self.largeModelMinimumPhysicalMemory
    }

    var usesDedicatedLyricModel: Bool {
        self == .balanced || self == .best
    }

    var usesSecondTimingPass: Bool {
        self == .balanced || self == .best
    }

    var usesCloudTranscription: Bool {
        self == .cloud
    }

    var localFallbackQuality: AnalysisQuality {
        self == .cloud ? .balanced : self
    }

    func qwenModelID(
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> String? {
        guard usesDedicatedLyricModel else { return nil }
        if physicalMemory >= Self.qwenFiveBitMinimumPhysicalMemory {
            return "aufklarer/Qwen3-ASR-0.6B-MLX-5bit"
        }
        return "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
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
        case .cloud:
            return AnalysisQuality.balanced.modelCandidates(
                physicalMemory: physicalMemory
            )
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
            return "Okunaklı sabit cümle düzeni ve harf harf karaoke takibi."
        case .kinetic:
            return "Vokal temposu ve anlam vurgusuna göre boyut, kompozisyon ve hareket üretir."
        }
    }

    static func resolved(_ rawValue: String?) -> KaraokeMode {
        guard let rawValue else { return .classic }
        return KaraokeMode(rawValue: rawValue) ?? .classic
    }
}

enum LyricTrackingMode: String, CaseIterable, Identifiable, Codable {
    case off
    case karaoke
    case boldWord
    case centeredReveal
    case centeredWordReveal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .karaoke: return "Harf Takibi"
        case .boldWord: return "Cümle + Kalın"
        case .centeredReveal: return "Harf Akışı"
        case .centeredWordReveal: return "Kelime Akışı"
        }
    }

    var icon: String {
        switch self {
        case .off: return "pause.circle"
        case .karaoke: return "waveform"
        case .boldWord: return "bold"
        case .centeredReveal: return "character.cursor.ibeam"
        case .centeredWordReveal: return "text.append"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Satır zamanında görünür; söylenen kelime veya harf ayrıca işaretlenmez."
        case .karaoke:
            return "Cümle sabit kalır; okuma ilerledikçe harfler vokal zamanına göre tek tek takip edilir."
        case .boldWord:
            return "Cümlenin tamamı sabit kalır; yalnız okunan kelime kalınlaşır, geçince yeniden normal olur."
        case .centeredReveal:
            return "Harfler vokalle birlikte eklenir; metin büyürken önceki harfler sola kayar ve cümle daima ortada kalır."
        case .centeredWordReveal:
            return "Her kelime söylendiği anda tek parça halinde gelir; yeni kelimeyle cümle yeniden ortalanır ve önceki kelimeler sola kayar."
        }
    }

    var isProgressiveReveal: Bool {
        self == .centeredReveal || self == .centeredWordReveal
    }

    static func resolved(_ rawValue: String?) -> LyricTrackingMode {
        guard let rawValue else { return .karaoke }
        return LyricTrackingMode(rawValue: rawValue) ?? .karaoke
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
            return "Parçanın tamamından tek kimlik çıkarır; açılış, kıta, yükseliş, nakarat ve rahatlama anlarında yalnız uyumlu kompozisyonları yönetir."
        case .cinematic:
            return "Sakin cümle akışını korur; hızlı bölümlerde kısa sayfalara, nakaratta sabit imza düzenine kontrollü geçer."
        case .editorial:
            return "Sözü afiş gibi katmanlar; vurgu satırını sağ-sol ekseninde kurar, hızlı ve sakin bölümlerde aynı editoryal kimliği korur."
        case .impact:
            return "Güçlü kelimeleri ritim üzerinde kademeli sahneye taşır; arka arkaya darbeleri nefes sayfaları ve nakarat kilidiyle dengeler."
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
    case underShadow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .none: return "Yok · Temiz"
        case .glass: return "Cam"
        case .cinematicBand: return "Sinema"
        case .accentPanel: return "Panel"
        case .spotlight: return "Spot"
        case .underShadow: return "Alt Gölge"
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
        case .underShadow: return "shadow"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Parçanın görsel kimliğine göre uyumlu iki veya üç katmanı bölüm boyunca yönetir; bağımsız ve rastgele seçim yapmaz."
        case .none:
            return "Kontur, gölge veya arka katman eklemez; tipografi temiz ve düz görünür."
        case .glass:
            return "Yazı grubunu ince konturlu, yarı saydam sinematik bir kartta toplar."
        case .cinematicBand:
            return "Alt bölgeyi yatay bir film bandı ve ince vurgu çizgisiyle sakinleştirir."
        case .accentPanel:
            return "Editoryal kompozisyona koyu bir plaka ve renkli kenar imzası ekler."
        case .spotlight:
            return "Söylenen kelimenin arkasında ritimle değişen kontrollü bir odak plakası kullanır."
        case .underShadow:
            return "Okunan kelimenin hemen altında hafif koyu, yumuşak bir derinlik oluşturur; renk vurgusunu boğmaz."
        }
    }

    var requiresKaraokeTracking: Bool {
        self == .spotlight || self == .underShadow
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
    case signature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .clean: return "Temiz"
        case .poster: return "Afiş"
        case .rhythm: return "Ritim"
        case .signature: return "İmza"
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "wand.and.rays"
        case .clean: return "textformat"
        case .poster: return "character.textbox"
        case .rhythm: return "waveform.path"
        case .signature: return "textformat.alt"
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
        case .signature:
            return "Odak kelimesini baş, merkez ve son harf arasında kontrollü boyut kontrastıyla bir başlık imzasına dönüştürür."
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
    case signature
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

enum KineticComposition: String, Equatable {
    case centered
    case leading
    case trailing
    case splitLeading
    case splitTrailing
    case staircase

    var title: String {
        switch self {
        case .centered: return "Merkez Kilit"
        case .leading: return "Sol Eksen"
        case .trailing: return "Sağ Eksen"
        case .splitLeading: return "Sol Vurgu Bölünümü"
        case .splitTrailing: return "Sağ Vurgu Bölünümü"
        case .staircase: return "Ritim Kademesi"
        }
    }
}

enum KineticSectionRole: String, Equatable {
    case opening
    case verse
    case lift
    case chorus
    case release

    var title: String {
        switch self {
        case .opening: return "Açılış"
        case .verse: return "Kıta Akışı"
        case .lift: return "Yükseliş"
        case .chorus: return "Nakarat"
        case .release: return "Rahatlama"
        }
    }
}

struct KineticTypographyPlan: Equatable {
    let scene: KineticScene
    let motion: KineticMotion
    let highlight: KineticHighlight
    let energy: KineticEnergy
    let creativeDirection: KineticCreativeDirection
    let composition: KineticComposition
    let sectionRole: KineticSectionRole
    let motionGain: Double
    let emphasisIndex: Int
    let rows: [[Int]]
    let pages: [[Int]]
    let repeatCount: Int

    init(
        scene: KineticScene,
        motion: KineticMotion,
        highlight: KineticHighlight,
        energy: KineticEnergy,
        creativeDirection: KineticCreativeDirection,
        composition: KineticComposition = .centered,
        sectionRole: KineticSectionRole = .verse,
        motionGain: Double = 1,
        emphasisIndex: Int,
        rows: [[Int]],
        pages: [[Int]],
        repeatCount: Int
    ) {
        self.scene = scene
        self.motion = motion
        self.highlight = highlight
        self.energy = energy
        self.creativeDirection = creativeDirection
        self.composition = composition
        self.sectionRole = sectionRole
        self.motionGain = min(1.22, max(0.72, motionGain))
        self.emphasisIndex = emphasisIndex
        self.rows = rows
        self.pages = pages
        self.repeatCount = repeatCount
    }
}

enum SubtitleRenderPath: Equatable {
    case centeredCharacterReveal
    case centeredWordReveal
    case kinetic
    case connectedKinetic
    case boldWord
    case staticLine
    case classicKaraoke
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

    // Düzenleyicide zaman değiştirilen veya sonradan eklenen kelimeleri kronolojik
    // sıraya getirir. Eşit zamanlı kelimelerde mevcut sıra korunur.
    func chronologicallySortedWords(_ words: [WordTimestamp]) -> [WordTimestamp] {
        words.enumerated()
            .sorted { left, right in
                let leftStart = left.element.start.isFinite
                    ? left.element.start
                    : Double.greatestFiniteMagnitude
                let rightStart = right.element.start.isFinite
                    ? right.element.start
                    : Double.greatestFiniteMagnitude
                if leftStart != rightStart {
                    return leftStart < rightStart
                }

                let leftEnd = left.element.end.isFinite
                    ? left.element.end
                    : Double.greatestFiniteMagnitude
                let rightEnd = right.element.end.isFinite
                    ? right.element.end
                    : Double.greatestFiniteMagnitude
                if leftEnd != rightEnd {
                    return leftEnd < rightEnd
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    // AVPlayer videoyu aspect-fit ile gösterir. Ön izleme katmanı da aynı gerçek
    // görüntü dikdörtgenini kullanmazsa özellikle 9:16 videoda yazılar siyah
    // kenarlara taşar ve dışa aktarımda bambaşka bir düzene dönüşür.
    func aspectFitRect(contentSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard contentSize.width.isFinite,
              contentSize.height.isFinite,
              containerSize.width.isFinite,
              containerSize.height.isFinite,
              contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = min(
            containerSize.width / contentSize.width,
            containerSize.height / contentSize.height
        )
        let fittedSize = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func subtitleRenderPath(
        karaokeMode: KaraokeMode,
        lyricTrackingMode: LyricTrackingMode,
        usesConnectedFont: Bool
    ) -> SubtitleRenderPath {
        switch lyricTrackingMode {
        case .centeredReveal:
            return .centeredCharacterReveal
        case .centeredWordReveal:
            return .centeredWordReveal
        case .boldWord:
            return .boldWord
        case .off, .karaoke:
            break
        }

        if karaokeMode == .kinetic {
            return usesConnectedFont ? .connectedKinetic : .kinetic
        }
        switch lyricTrackingMode {
        case .boldWord:
            return .boldWord
        case .off:
            return .staticLine
        case .karaoke:
            return .classicKaraoke
        case .centeredReveal:
            return .centeredCharacterReveal
        case .centeredWordReveal:
            return .centeredWordReveal
        }
    }

    func resolvedKineticOverlayStyle(
        requested: KineticOverlayStyle,
        plan: KineticTypographyPlan,
        trackingMode: LyricTrackingMode
    ) -> KineticOverlayStyle {
        let resolved = requested.resolved(for: plan)
        if trackingMode != .karaoke, resolved.requiresKaraokeTracking {
            return .none
        }
        return resolved
    }

    struct LyricRecognitionWindow: Equatable {
        let wordRange: Range<Int>
        let start: Double
        let end: Double
    }

    private enum SequenceStep: UInt8 {
        case diagonal
        case deletion
        case insertion
    }
    
    // 1. Sesi videodan çıkarma. Vokal ayrılacaksa modelin doğal girişi olan
    // 44.1 kHz stereo korunur; doğrudan tanımada 16 kHz mono hazırlanır.
    func extractAudio(
        from videoURL: URL,
        forVocalIsolation: Bool = false,
        completion: @escaping (URL?) -> Void
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("subby_audio_" + UUID().uuidString)
            .appendingPathExtension("wav")
        
        let inPath = videoURL.path
        let outPath = outputURL.path

        let sampleRate = forVocalIsolation ? "44100" : "16000"
        let channelCount = forVocalIsolation ? "2" : "1"

        // Whisper için ideal format 16 kHz mono; Open-Unmix için 44.1 kHz stereo.
        // Not: Bandpass filtresi kullanılmıyor; Whisper tam bant ses ile eğitildiği için
        // 3kHz üstünü kesmek ünsüz seslerini silip transkripsiyon kalitesini düşürür.
        let args = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", inPath,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", sampleRate,
            "-ac", channelCount,
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
        progressRange: ClosedRange<Double> = 0...1,
        downloadProgress: @escaping (Double) -> Void
    ) async throws -> WhisperKit {
        var lastError: Error?
        for candidate in quality.modelCandidates() {
            try Task.checkCancellation()
            do {
                let modelFolder = try await WhisperKit.download(
                    variant: candidate,
                    progressCallback: { progress in
                        let fraction = min(max(progress.fractionCompleted, 0), 1)
                        let mapped = progressRange.lowerBound
                            + ((progressRange.upperBound - progressRange.lowerBound) * fraction)
                        downloadProgress(mapped)
                    }
                )
                try Task.checkCancellation()
                downloadProgress(progressRange.upperBound)

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

    // 2. WhisperKit ile zaman çıkarma, Qwen3-ASR ile şarkı sözünü düzeltme.
    // downloadProgress: model ilk kez indirilirken 0.0-1.0 arası ilerleme bildirir
    func runSpeechRecognition(
        audioURL: URL,
        quality: AnalysisQuality,
        vocalIsolationMode: VocalIsolationMode,
        cloudAPIKey: String?,
        statusUpdate: @escaping (String) -> Void,
        downloadProgress: @escaping (Double) -> Void,
        completion: @escaping ([WordTimestamp], String?, String?) -> Void
    ) {
        cancelSpeechRecognition()
        let recognitionID = UUID()
        recognitionLock.lock()
        self.recognitionID = recognitionID
        recognitionLock.unlock()

        let task = Task(priority: .userInitiated) {
            var whisperKit: WhisperKit?
            var qwenModel: Qwen3ASRModel?
            var analysisAudioURL = audioURL
            var fallbackAudioURL: URL?
            var generatedAnalysisURLs: [URL] = []
            var analysisNotices: [String] = []
            var recognitionProgressBase = 0.0
            defer {
                generatedAnalysisURLs.forEach { self.deleteFile(at: $0) }
            }
            do {
                if vocalIsolationMode.usesVocalIsolation {
                    let prepared = try await VocalIsolationService.shared.prepare(
                        sourceURL: audioURL,
                        statusUpdate: statusUpdate,
                        progressUpdate: { fraction in
                            downloadProgress(min(max(fraction, 0), 1) * 0.18)
                        }
                    )
                    analysisAudioURL = prepared.primaryURL
                    fallbackAudioURL = prepared.fallbackURL
                    generatedAnalysisURLs = prepared.generatedURLs
                    recognitionProgressBase = 0.18
                    if let notice = prepared.notice {
                        analysisNotices.append(notice)
                    } else if prepared.usedVocalIsolation {
                        statusUpdate("Vokal ayrıldı. Şimdi sözler ve kelime saniyeleri çözümleniyor.")
                    }
                }

                let progressBase = recognitionProgressBase
                let recognitionProgress: (Double) -> Void = { fraction in
                    let safeFraction = min(max(fraction, 0), 1)
                    downloadProgress(
                        progressBase
                            + ((1 - progressBase) * safeFraction)
                    )
                }

                if quality.usesCloudTranscription {
                    do {
                        statusUpdate(
                            "Ses güvenli bağlantıyla Bulut Hassas motora gönderiliyor. "
                            + "Whisper Large V3 sözleri ve kelime saniyelerini birlikte çözüyor."
                        )
                        let cloudWords = try await GroqSpeechClient.shared.transcribe(
                            audioURL: analysisAudioURL,
                            apiKey: cloudAPIKey ?? ""
                        )
                        let normalizedCloudWords = self.normalizeRecognizedWords(cloudWords)
                        guard !normalizedCloudWords.isEmpty else {
                            throw GroqSpeechClient.ClientError.missingWordTimestamps
                        }
                        recognitionProgress(1.0)
                        try Task.checkCancellation()
                        guard self.finishRecognitionIfActive(recognitionID) else { return }
                        self.completeOnMain {
                            let notice = analysisNotices.isEmpty
                                ? nil
                                : analysisNotices.joined(separator: " ")
                            completion(normalizedCloudWords, nil, notice)
                        }
                        return
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        let cloudFallbackReason = self.friendlyCloudFallbackReason(error)
                        analysisNotices.append(
                            "Bulut kullanılamadı: \(cloudFallbackReason); Dengeli yerel motora geçildi."
                        )
                        print(
                            "Bulut Hassas kullanılamadı; yerel motora geçiliyor: "
                            + error.localizedDescription
                        )
                        statusUpdate(
                            "Bulut kullanılamadı: \(cloudFallbackReason). "
                            + "Analiz kaybolmadan Dengeli yerel motorla sürdürülüyor."
                        )
                        recognitionProgress(0)
                    }
                }

                let effectiveQuality = quality.localFallbackQuality
                // Whisper yalnız kelime başlangıç/bitişlerini bulur. Qwen kullanılacaksa
                // indirme göstergesinin ilk %40'ı hizalama modeline ayrılır.
                let whisperProgressRange: ClosedRange<Double> = effectiveQuality.usesDedicatedLyricModel
                    ? 0...0.4
                    : 0...1
                let loadedModel = try await self.loadModel(
                    quality: effectiveQuality,
                    progressRange: whisperProgressRange,
                    downloadProgress: recognitionProgress
                )
                whisperKit = loadedModel
                try Task.checkCancellation()

                let vadWords = try await self.transcribeTimingPass(
                    model: loadedModel,
                    audioURL: analysisAudioURL,
                    chunkingStrategy: .vad,
                    recognitionID: recognitionID
                )

                var normalizedWords = vadWords
                if effectiveQuality.usesSecondTimingPass {
                    try Task.checkCancellation()
                    // VAD şarkı vokallerini bazen konuşma dışı sayıp kelime başlarını
                    // kesebilir. İkinci geçiş aynı modeli sabit 30 sn pencerelerle
                    // çalıştırır; yalnız iki geçişin aynı sırada bulduğu zamanlar
                    // birleştirilir.
                    let continuousWords = try await self.transcribeTimingPass(
                        model: loadedModel,
                        audioURL: analysisAudioURL,
                        chunkingStrategy: .none,
                        recognitionID: recognitionID
                    )
                    normalizedWords = self.mergeTimingPasses(
                        primary: vadWords,
                        secondary: continuousWords
                    )
                }

                if normalizedWords.isEmpty, let fallbackAudioURL {
                    statusUpdate(
                        "Ayrılmış vokalde yeterli söz bulunamadı. Zaman kaybetmeden orijinal karışımla yeniden deneniyor."
                    )
                    analysisAudioURL = fallbackAudioURL
                    let fallbackVADWords = try await self.transcribeTimingPass(
                        model: loadedModel,
                        audioURL: fallbackAudioURL,
                        chunkingStrategy: .vad,
                        recognitionID: recognitionID
                    )
                    normalizedWords = fallbackVADWords
                    if effectiveQuality.usesSecondTimingPass {
                        let fallbackContinuousWords = try await self.transcribeTimingPass(
                            model: loadedModel,
                            audioURL: fallbackAudioURL,
                            chunkingStrategy: .none,
                            recognitionID: recognitionID
                        )
                        normalizedWords = self.mergeTimingPasses(
                            primary: fallbackVADWords,
                            secondary: fallbackContinuousWords
                        )
                    }
                    analysisNotices.append(
                        "Ayrılmış vokal yeterli sonuç vermedi; orijinal karışım otomatik yedek olarak kullanıldı."
                    )
                }

                try Task.checkCancellation()
                await loadedModel.unloadModels()
                whisperKit = nil
                try Task.checkCancellation()

                // Bellek güvenliği: Qwen ancak Whisper tamamen boşaltıldıktan sonra
                // yüklenir. Böylece iPhone 14'te iki modelin tepe belleği üst üste binmez.
                if let qwenModelID = effectiveQuality.qwenModelID(), !normalizedWords.isEmpty {
                    do {
                        let loadedQwenModel = try await Qwen3ASRModel.fromPretrained(
                            modelId: qwenModelID,
                            progressHandler: { fraction, _ in
                                let safeFraction = min(max(fraction, 0), 1)
                                recognitionProgress(0.4 + (safeFraction * 0.6))
                            }
                        )
                        qwenModel = loadedQwenModel
                        try Task.checkCancellation()

                        if let enhancedWords = try self.enhanceLyricsWithQwen(
                            model: loadedQwenModel,
                            audioURL: analysisAudioURL,
                            timedWords: normalizedWords
                        ), !enhancedWords.isEmpty {
                            normalizedWords = enhancedWords
                        }

                        loadedQwenModel.unload()
                        qwenModel = nil
                        recognitionProgress(1.0)
                    } catch is CancellationError {
                        qwenModel?.unload()
                        qwenModel = nil
                        throw CancellationError()
                    } catch {
                        // Yeni söz motoru indirilemez veya cihazda çalışamazsa eldeki
                        // güvenilir zamanlı Whisper sonucu kaybolmaz.
                        qwenModel?.unload()
                        qwenModel = nil
                        recognitionProgress(1.0)
                        print("Qwen3-ASR kullanılamadı; yerel zamanlama sonucu korunuyor: \(error.localizedDescription)")
                    }
                } else {
                    recognitionProgress(1.0)
                }

                try Task.checkCancellation()
                guard self.finishRecognitionIfActive(recognitionID) else { return }
                self.completeOnMain {
                    let notice = analysisNotices.isEmpty
                        ? nil
                        : analysisNotices.joined(separator: " ")
                    if normalizedWords.isEmpty {
                        completion(
                            [],
                            "Videoda deşifre edilebilecek net bir vokal veya konuşma bulunamadı.",
                            notice
                        )
                    } else {
                        completion(normalizedWords, nil, notice)
                    }
                }
            } catch is CancellationError {
                if let whisperKit {
                    await whisperKit.unloadModels()
                }
                qwenModel?.unload()
                if self.finishRecognitionIfActive(recognitionID) {
                    self.completeOnMain {
                        let notice = analysisNotices.isEmpty
                            ? nil
                            : analysisNotices.joined(separator: " ")
                        completion([], "İşlem iptal edildi.", notice)
                    }
                }
            } catch {
                if let whisperKit {
                    await whisperKit.unloadModels()
                }
                qwenModel?.unload()
                print("WhisperKit hatası: \(error.localizedDescription)")
                let message = self.friendlyRecognitionError(error)
                if self.finishRecognitionIfActive(recognitionID) {
                    self.completeOnMain {
                        let notice = analysisNotices.isEmpty
                            ? nil
                            : analysisNotices.joined(separator: " ")
                        completion([], message, notice)
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

    private func friendlyCloudFallbackReason(_ error: Error) -> String {
        if let clientError = error as? GroqSpeechClient.ClientError {
            switch clientError {
            case .invalidAPIKey:
                return "API anahtarı geçersiz"
            case .audioTooLarge:
                return "ses dosyası ücretsiz 24 MB sınırını aşıyor"
            case .unreadableAudio:
                return "ses dosyası okunamadı"
            case .invalidResponse:
                return "servis geçersiz yanıt verdi"
            case .missingWordTimestamps:
                return "servis kelime zamanlarını döndürmedi"
            case .service(let statusCode, _):
                switch statusCode {
                case 401, 403: return "API anahtarı reddedildi"
                case 413: return "ses dosyası yükleme sınırını aşıyor"
                case 429: return "ücretsiz kullanım limiti doldu"
                default: return "servis \(statusCode) hatası verdi"
                }
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "internet bağlantısı kurulamadı"
            case .timedOut:
                return "servis zaman aşımına uğradı"
            default:
                return "ağ bağlantısı başarısız oldu"
            }
        }
        return "beklenmeyen servis hatası oluştu"
    }

    private func transcribeTimingPass(
        model: WhisperKit,
        audioURL: URL,
        chunkingStrategy: ChunkingStrategy,
        recognitionID: UUID
    ) async throws -> [WordTimestamp] {
        // Şarkıda düşük olasılıklı heceler konuşmaya göre daha sık görülür. Biraz
        // daha toleranslı eşikler, kelimeyi tamamen atmak yerine zaman adayı üretir.
        var options = DecodingOptions()
        options.language = "tr"
        options.wordTimestamps = true
        options.skipSpecialTokens = true
        options.chunkingStrategy = chunkingStrategy
        options.concurrentWorkerCount = 1
        options.temperature = 0
        options.temperatureFallbackCount = 3
        options.suppressBlank = true
        options.logProbThreshold = -1.25
        options.firstTokenLogProbThreshold = -2
        options.noSpeechThreshold = 0.75
        options.windowClipTime = 0.25

        let results = try await model.transcribe(
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
                        let text = cleanRecognizedText(word.word)
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
                    continue
                }

                // Eski/eksik model paketlerinde kelime hizalaması dönmezse segment
                // kaybolmasın. Bu yol yalnız son çare; Qwen metni daha sonra gerçek
                // Whisper segment aralığına yeniden oturtulur.
                let rawWords = lyricWords(from: segment.text)
                let rawStart = Double(segment.start)
                let rawEnd = Double(segment.end)
                guard rawStart.isFinite, rawEnd.isFinite, !rawWords.isEmpty else { continue }
                let segmentStart = max(0, rawStart)
                let minimumDuration = Double(rawWords.count) * 0.05
                let segmentEnd = max(segmentStart + minimumDuration, rawEnd)
                let wordDuration = (segmentEnd - segmentStart) / Double(rawWords.count)

                for (index, text) in rawWords.enumerated() {
                    let start = segmentStart + (Double(index) * wordDuration)
                    words.append(WordTimestamp(
                        text: text,
                        start: start,
                        end: start + wordDuration
                    ))
                }
            }
        }
        return normalizeRecognizedWords(words)
    }

    // VAD ve sabit pencere geçişlerini kelime sırasına göre eşleştirir. VAD
    // kelime başlangıçlarında ana zaman kaynağıdır. İkinci geçiş yalnız çok yakın
    // bir eşleşmede kelime sonunu hafifçe iyileştirir; başlangıcı ortalamak şarkı
    // sözlerinde karaoke vurgusunu duyulan heceden yüzlerce ms uzağa taşıyabiliyor.
    func mergeTimingPasses(
        primary: [WordTimestamp],
        secondary: [WordTimestamp]
    ) -> [WordTimestamp] {
        guard !primary.isEmpty else { return normalizeRecognizedWords(secondary) }
        guard !secondary.isEmpty else { return normalizeRecognizedWords(primary) }

        let mapping = sequenceMapping(
            source: primary.map(\.text),
            target: secondary.map(\.text)
        )
        var merged = primary

        for index in merged.indices {
            guard let secondaryIndex = mapping[index],
                  secondary.indices.contains(secondaryIndex) else { continue }
            let second = secondary[secondaryIndex]
            let similarity = tokenSimilarity(merged[index].text, second.text)
            guard similarity >= 0.60,
                  abs(merged[index].start - second.start) <= 0.25,
                  abs(merged[index].end - second.end) <= 0.45 else { continue }

            // Başlangıcı olduğu gibi koru. İkinci geçiş yalnız uzatılmış hecenin
            // sonunu destekliyorsa küçük bir katkı yapabilir ve hiçbir zaman bir
            // sonraki VAD başlangıcını aşamaz.
            guard second.end > merged[index].end else { continue }
            let blendedEnd = (merged[index].end * 0.75) + (second.end * 0.25)
            let nextStart = index + 1 < primary.count
                ? primary[index + 1].start
                : .infinity
            merged[index].end = min(blendedEnd, nextStart)
        }
        return normalizeRecognizedWords(merged)
    }

    private func enhanceLyricsWithQwen(
        model: Qwen3ASRModel,
        audioURL: URL,
        timedWords: [WordTimestamp]
    ) throws -> [WordTimestamp]? {
        let normalizedTiming = normalizeRecognizedWords(timedWords)
        guard !normalizedTiming.isEmpty else { return nil }

        let audioFile = try AVAudioFile(forReading: audioURL)
        let audioFormat = audioFile.processingFormat
        guard audioFormat.sampleRate.isFinite,
              audioFormat.sampleRate > 0 else {
            throw NSError(
                domain: "VideoProcessor",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: "Ses örnekleme hızı geçersiz."]
            )
        }
        let sampleRate = Int(audioFormat.sampleRate.rounded())
        let maximumSafeFrames = AVAudioFramePosition(
            max(1, audioFormat.sampleRate) * 20 * 60
        )
        guard sampleRate > 0,
              audioFile.length > 0,
              audioFile.length <= maximumSafeFrames else {
            throw NSError(
                domain: "VideoProcessor",
                code: -20,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Ses dosyası güvenli süre sınırının dışında veya okunamıyor."
                ]
            )
        }

        let duration = Double(audioFile.length) / audioFormat.sampleRate
        let windows = lyricRecognitionWindows(
            for: normalizedTiming,
            maximumTime: duration
        )
        guard !windows.isEmpty else { return nil }

        var enhanced: [WordTimestamp] = []
        for window in windows {
            try Task.checkCancellation()
            guard let frameRange = audioFrameRange(
                start: window.start,
                end: window.end,
                sampleRate: audioFormat.sampleRate,
                totalFrameCount: audioFile.length
            ) else {
                enhanced.append(contentsOf: normalizedTiming[window.wordRange])
                continue
            }

            let localSlice = Array(normalizedTiming[window.wordRange])
            let tokenBudget = min(448, max(128, localSlice.count * 4))
            let qwenWords = try autoreleasepool {
                // Yalnız bu 12–15 saniyelik pencereyi oku. Önceki uygulama tüm
                // şarkıyı [Float] dizisine alıp sonra dilimliyordu; model belleği
                // ile birleşen bu kopya iPhone 14'te jetsam riskini büyütüyordu.
                let chunk = try loadMonoAudioWindow(
                    from: audioFile,
                    frameRange: frameRange
                )
                let transcript = model.transcribe(
                    audio: chunk,
                    sampleRate: sampleRate,
                    language: "tr",
                    maxTokens: tokenBudget
                )
                return lyricWords(from: transcript)
            }

            if let aligned = alignEnhancedTranscriptWords(
                qwenWords,
                to: localSlice
            ), !aligned.isEmpty {
                enhanced.append(contentsOf: aligned)
            } else {
                enhanced.append(contentsOf: localSlice)
            }
        }

        let result = normalizeRecognizedWords(enhanced)
        guard !result.isEmpty else { return nil }

        // Modelin hata mesajını veya anlamsız kısa bir çıktıyı söz diye kabul
        // etme. Her pencere kendi yerel sonucuna düştüğü için bu son kontrol
        // yalnız tüm şarkıda beklenmeyen aşırı kelime kaybını yakalar.
        let minimumCount = max(1, Int(Double(normalizedTiming.count) * 0.38))
        return result.count >= minimumCount ? result : nil
    }

    func audioFrameRange(
        start: Double,
        end: Double,
        sampleRate: Double,
        totalFrameCount: AVAudioFramePosition
    ) -> Range<AVAudioFramePosition>? {
        guard start.isFinite,
              end.isFinite,
              sampleRate.isFinite,
              sampleRate > 0,
              totalFrameCount > 0 else {
            return nil
        }

        let duration = Double(totalFrameCount) / sampleRate
        let clampedStart = min(max(0, start), duration)
        let clampedEnd = min(max(clampedStart, end), duration)
        let lowerBound = min(
            totalFrameCount,
            AVAudioFramePosition((clampedStart * sampleRate).rounded(.down))
        )
        let upperBound = min(
            totalFrameCount,
            AVAudioFramePosition((clampedEnd * sampleRate).rounded(.up))
        )
        guard upperBound > lowerBound else { return nil }
        return lowerBound..<upperBound
    }

    private func loadMonoAudioWindow(
        from audioFile: AVAudioFile,
        frameRange: Range<AVAudioFramePosition>
    ) throws -> [Float] {
        let requestedFrames = frameRange.upperBound - frameRange.lowerBound
        guard requestedFrames > 0,
              requestedFrames <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(requestedFrames)
              ) else {
            throw NSError(
                domain: "VideoProcessor",
                code: -21,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Ses penceresi belleğe güvenli biçimde alınamadı."
                ]
            )
        }

        audioFile.framePosition = frameRange.lowerBound
        try audioFile.read(
            into: buffer,
            frameCount: AVAudioFrameCount(requestedFrames)
        )
        guard let channelData = buffer.floatChannelData else {
            throw NSError(
                domain: "VideoProcessor",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "Ses örnekleri okunamadı."]
            )
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        var samples = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            let input = channelData[channel]
            for frame in 0..<frameCount {
                samples[frame] += input[frame] / Float(channelCount)
            }
        }
        return samples
    }

    // Qwen uzun şarkıyı tek seferde belleğe yığmaz. Whisper'ın bulduğu doğal
    // kelime boşluklarında 15 saniyeden kısa vokal pencereleri oluşturur.
    // Böylece Qwen'in uzun-girdi yolu tetiklenmez, iPhone 14'te ses kodlayıcının
    // geçici belleği sınırlı kalır ve enstrümantal aralar modele gönderilmez.
    func lyricRecognitionWindows(
        for words: [WordTimestamp],
        maximumTime: Double
    ) -> [LyricRecognitionWindow] {
        guard !words.isEmpty, maximumTime.isFinite, maximumTime > 0 else { return [] }

        let preferredDuration = 12.0
        let minimumBreakDuration = 7.0
        let maximumDuration = 14.5
        var windows: [LyricRecognitionWindow] = []
        var firstIndex = 0

        while firstIndex < words.count {
            let paddedStart = max(0, min(maximumTime, words[firstIndex].start - 0.3))
            // Ardışık pencerelerin aynı heceyi iki kez çözmesini engelle.
            let windowStart = max(windows.last?.end ?? 0, paddedStart)
            var lastIndex = firstIndex
            while lastIndex + 1 < words.count,
                  words[lastIndex + 1].end - windowStart <= preferredDuration {
                lastIndex += 1
            }

            if lastIndex + 1 < words.count {
                var candidate = lastIndex
                var bestGap = -Double.infinity
                let searchStart = max(firstIndex, lastIndex - 7)
                var index = searchStart
                while index <= lastIndex {
                    let elapsed = words[index].end - windowStart
                    let gap = max(0, words[index + 1].start - words[index].end)
                    if elapsed >= minimumBreakDuration, gap > bestGap {
                        bestGap = gap
                        candidate = index
                    }
                    index += 1
                }
                lastIndex = candidate

                // Çok uzun tek vokal dizisinde 12 saniyede uygun ara yoksa birkaç
                // kelime daha ilerleyebilir; 14,5 saniyelik sınır aşılmaz.
                while lastIndex + 1 < words.count,
                      words[lastIndex + 1].end - windowStart <= maximumDuration,
                      words[lastIndex + 1].start - words[lastIndex].end < 0.12 {
                    lastIndex += 1
                }
            } else {
                lastIndex = words.count - 1
            }

            let nextStart = lastIndex + 1 < words.count
                ? words[lastIndex + 1].start
                : maximumTime
            let naturalEnd = min(
                words[lastIndex].end + 0.4,
                max(words[lastIndex].end, (words[lastIndex].end + nextStart) / 2)
            )
            let windowEnd = min(
                maximumTime,
                max(windowStart + 0.1, min(windowStart + maximumDuration, naturalEnd))
            )
            windows.append(LyricRecognitionWindow(
                wordRange: firstIndex..<(lastIndex + 1),
                start: windowStart,
                end: windowEnd
            ))
            firstIndex = lastIndex + 1
        }
        return windows
    }

    func alignEnhancedTranscriptWords(
        _ enhancedWords: [String],
        to timedWords: [WordTimestamp]
    ) -> [WordTimestamp]? {
        let cleanedEnhanced = enhancedWords.compactMap { raw -> String? in
            let value = cleanRecognizedText(raw)
            guard !value.isEmpty, !isNonLexicalVocalization(value) else { return nil }
            return value
        }
        let local = normalizeRecognizedWords(timedWords)
        guard !cleanedEnhanced.isEmpty, !local.isEmpty else { return nil }

        let countRatio = Double(cleanedEnhanced.count) / Double(local.count)
        guard (0.50...1.75).contains(countRatio) else { return nil }

        let mapping = sequenceMapping(
            source: cleanedEnhanced,
            target: local.map(\.text)
        )
        let mappedPairs = mapping.enumerated().compactMap { sourceIndex, targetIndex
            -> (source: Int, target: Int, similarity: Double)? in
            guard let targetIndex, local.indices.contains(targetIndex) else { return nil }
            return (
                sourceIndex,
                targetIndex,
                tokenSimilarity(cleanedEnhanced[sourceIndex], local[targetIndex].text)
            )
        }
        let anchors = mappedPairs.filter { $0.similarity >= 0.62 }
        let comparablePairs = mappedPairs.filter { $0.similarity >= 0.48 }
        let minimumAnchorCount = min(2, min(cleanedEnhanced.count, local.count))
        let comparableCoverage = Double(comparablePairs.count)
            / Double(max(cleanedEnhanced.count, local.count))
        guard anchors.count >= minimumAnchorCount,
              comparableCoverage >= 0.40 else {
            return nil
        }

        // Qwen burada metin düzelticisidir, zaman üreticisi değildir. Güvenilir
        // eşleşmeler Whisper kelimesinin gerçek başlangıç/bitişini aynen korur.
        // Düşük benzerlikli çapraz eşleşmeler sözün tamamını bozmasın.
        var replacementByTarget: [Int: String] = [:]
        for pair in comparablePairs {
            let enhancedKeyLength = comparisonKey(cleanedEnhanced[pair.source]).count
            let requiredSimilarity = enhancedKeyLength <= 3 ? 0.66 : 0.48
            guard pair.similarity >= requiredSimilarity else { continue }
            replacementByTarget[pair.target] = cleanedEnhanced[pair.source]
        }

        // Bir kelime iki sağlam komşu tarafından aynı konumda çevreleniyorsa Qwen
        // tamamen farklı yazılmış bir Whisper hatasını da düzeltebilir. Komşu
        // bağlamı olmayan düşük benzerlikli kelimeler ise aynen bırakılır.
        let sortedAnchors = anchors.sorted { $0.source < $1.source }
        for pair in mappedPairs where pair.similarity < 0.48 {
            guard let left = sortedAnchors.last(where: { $0.source < pair.source }),
                  let right = sortedAnchors.first(where: { $0.source > pair.source }),
                  pair.source - left.source == pair.target - left.target,
                  right.source - pair.source == right.target - pair.target else {
                continue
            }
            replacementByTarget[pair.target] = cleanedEnhanced[pair.source]
        }

        // Whisper'ın atladığı bir kelimeyi yalnız iki güvenilir kelimenin arasında
        // gerçekten zaman bırakılmışsa ekle. Pencere başı/sonunda ekstrapolasyon
        // yapılmaz; böylece Qwen'in "aaa/na" veya hayalî kelimeleri zaman çizelgesine
        // zorla yerleştirilmez.
        var insertionsAfterTarget: [Int: [(source: Int, text: String)]] = [:]
        let anchorTargetBySource = Dictionary(
            uniqueKeysWithValues: sortedAnchors.map { ($0.source, $0.target) }
        )
        let anchorSources = anchorTargetBySource.keys.sorted()
        if anchorSources.count >= 2 {
            for pairIndex in 0..<(anchorSources.count - 1) {
                let leftSource = anchorSources[pairIndex]
                let rightSource = anchorSources[pairIndex + 1]
                guard rightSource - leftSource > 1,
                      let leftTarget = anchorTargetBySource[leftSource],
                      let rightTarget = anchorTargetBySource[rightSource],
                      rightTarget == leftTarget + 1 else { continue }

                let candidates = ((leftSource + 1)..<rightSource).compactMap {
                    sourceIndex -> (source: Int, text: String)? in
                    guard mapping[sourceIndex] == nil else { return nil }
                    let text = cleanedEnhanced[sourceIndex]
                    guard !isNonLexicalVocalization(text) else { return nil }
                    return (sourceIndex, text)
                }
                guard !candidates.isEmpty else { continue }

                let gap = local[rightTarget].start - local[leftTarget].end
                let requiredGap = Double(candidates.count) * 0.16
                guard gap >= requiredGap else { continue }
                insertionsAfterTarget[leftTarget] = candidates
            }
        }

        var result: [WordTimestamp] = []
        for targetIndex in local.indices {
            var word = local[targetIndex]
            if let replacement = replacementByTarget[targetIndex] {
                word.text = replacement
            }
            result.append(word)

            guard let insertions = insertionsAfterTarget[targetIndex],
                  targetIndex + 1 < local.count else { continue }
            let gapStart = local[targetIndex].end
            let gapEnd = local[targetIndex + 1].start
            let slot = (gapEnd - gapStart) / Double(insertions.count + 1)
            for (offset, insertion) in insertions.enumerated() {
                let center = gapStart + (Double(offset + 1) * slot)
                let halfDuration = min(0.12, slot * 0.32)
                result.append(WordTimestamp(
                    text: insertion.text,
                    start: max(gapStart, center - halfDuration),
                    end: min(gapEnd, center + halfDuration)
                ))
            }
        }
        return normalizeRecognizedWords(result)
    }

    func lyricWords(from transcript: String) -> [String] {
        let markerPattern = #"(?i)\[(music|müzik|instrumental|applause|alkış)[^\]]*\]|\((music|müzik|instrumental|applause|alkış)[^\)]*\)"#
        let withoutMarkers = transcript.replacingOccurrences(
            of: markerPattern,
            with: " ",
            options: .regularExpression
        )
        let wrapperCharacters = CharacterSet(
            charactersIn: "\"“”«»()[]{}"
        )
        let markerKeys = Set([
            "muzik", "music", "instrumental", "applause", "alkis"
        ])
        return withoutMarkers
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { token -> String? in
                // Yalnız dış tırnak/parantezleri kaldır. Kelimeye ait virgül,
                // nokta, soru ve ünlem işaretleri zaman damgasıyla birlikte kalır.
                let trimmed = token.trimmingCharacters(in: wrapperCharacters)
                let clean = cleanRecognizedText(trimmed)
                let key = comparisonKey(clean)
                guard !clean.isEmpty,
                      !key.isEmpty,
                      !markerKeys.contains(key),
                      !clean.hasPrefix("<"),
                      !clean.hasSuffix(">") else { return nil }
                return clean
            }
    }

    // Bazı servisler tam cümlede noktalama döndürürken `words` alanında yalnız
    // çıplak kelimeleri verir. Tam metni sözcük zamanlarıyla sıralı biçimde
    // eşleştirip yalnız noktalama ekini geri taşır; zaman ve tanınan kelime değişmez.
    func applyTranscriptPunctuation(
        _ transcript: String,
        to timedWords: [WordTimestamp]
    ) -> [WordTimestamp] {
        let transcriptWords = lyricWords(from: transcript)
        let normalizedTiming = normalizeRecognizedWords(timedWords)
        guard !transcriptWords.isEmpty, !normalizedTiming.isEmpty else {
            return normalizedTiming
        }

        let mapping = sequenceMapping(
            source: transcriptWords,
            target: normalizedTiming.map(\.text)
        )
        var result = normalizedTiming
        for (sourceIndex, targetIndex) in mapping.enumerated() {
            guard let targetIndex,
                  result.indices.contains(targetIndex),
                  tokenSimilarity(
                    transcriptWords[sourceIndex],
                    result[targetIndex].text
                  ) >= 0.62 else { continue }
            result[targetIndex].text = mergingTrailingPunctuation(
                from: transcriptWords[sourceIndex],
                into: result[targetIndex].text
            )
        }
        return result
    }

    private func sequenceMapping(
        source: [String],
        target: [String]
    ) -> [Int?] {
        guard !source.isEmpty else { return [] }
        guard !target.isEmpty else { return [Int?](repeating: nil, count: source.count) }

        let width = target.count + 1
        let cellCount = (source.count + 1) * width
        let gapCost = 0.9
        var costs = [Double](repeating: 0, count: cellCount)
        var steps = [UInt8](repeating: SequenceStep.diagonal.rawValue, count: cellCount)

        for sourceIndex in 1...source.count {
            costs[sourceIndex * width] = Double(sourceIndex) * gapCost
            steps[sourceIndex * width] = SequenceStep.deletion.rawValue
        }
        for targetIndex in 1...target.count {
            costs[targetIndex] = Double(targetIndex) * gapCost
            steps[targetIndex] = SequenceStep.insertion.rawValue
        }

        for sourceIndex in 1...source.count {
            for targetIndex in 1...target.count {
                let similarity = tokenSimilarity(
                    source[sourceIndex - 1],
                    target[targetIndex - 1]
                )
                let substitutionCost = similarity >= 0.999
                    ? 0
                    : 1.05 - (similarity * 0.68)
                let diagonal = costs[((sourceIndex - 1) * width) + targetIndex - 1]
                    + substitutionCost
                let deletion = costs[((sourceIndex - 1) * width) + targetIndex] + gapCost
                let insertion = costs[(sourceIndex * width) + targetIndex - 1] + gapCost
                let cell = (sourceIndex * width) + targetIndex

                if diagonal <= deletion, diagonal <= insertion {
                    costs[cell] = diagonal
                    steps[cell] = SequenceStep.diagonal.rawValue
                } else if deletion <= insertion {
                    costs[cell] = deletion
                    steps[cell] = SequenceStep.deletion.rawValue
                } else {
                    costs[cell] = insertion
                    steps[cell] = SequenceStep.insertion.rawValue
                }
            }
        }

        var mapping = [Int?](repeating: nil, count: source.count)
        var sourceIndex = source.count
        var targetIndex = target.count
        while sourceIndex > 0 || targetIndex > 0 {
            let step = SequenceStep(
                rawValue: steps[(sourceIndex * width) + targetIndex]
            ) ?? .diagonal
            switch step {
            case .diagonal where sourceIndex > 0 && targetIndex > 0:
                mapping[sourceIndex - 1] = targetIndex - 1
                sourceIndex -= 1
                targetIndex -= 1
            case .deletion where sourceIndex > 0:
                sourceIndex -= 1
            case .insertion where targetIndex > 0:
                targetIndex -= 1
            default:
                if sourceIndex > 0 { sourceIndex -= 1 }
                if targetIndex > 0 { targetIndex -= 1 }
            }
        }
        return mapping
    }

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = comparisonKey(lhs)
        let right = comparisonKey(rhs)
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        var previous = Array(0...rightCharacters.count)
        var current = [Int](repeating: 0, count: rightCharacters.count + 1)

        for leftIndex in 1...leftCharacters.count {
            current[0] = leftIndex
            for rightIndex in 1...rightCharacters.count {
                let substitution = previous[rightIndex - 1]
                    + (leftCharacters[leftIndex - 1] == rightCharacters[rightIndex - 1] ? 0 : 1)
                current[rightIndex] = min(
                    min(previous[rightIndex] + 1, current[rightIndex - 1] + 1),
                    substitution
                )
            }
            swap(&previous, &current)
        }
        let distance = previous[rightCharacters.count]
        return max(0, 1 - (Double(distance) / Double(max(leftCharacters.count, rightCharacters.count))))
    }

    private func comparisonKey(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
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
            .replacingOccurrences(
                of: #"\s+([.,!?;:…])"#,
                with: "$1",
                options: .regularExpression
            )
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
               comparisonKey(previous.text) == comparisonKey(word.text),
               duplicateOverlapRatio(previous, word) >= 0.6 {
                normalized[normalized.count - 1].text = mergingTrailingPunctuation(
                    from: word.text,
                    into: previous.text
                )
                if word.end > previous.end {
                    normalized[normalized.count - 1].end = word.end
                }
                continue
            }

            // Şarkıcının uzattığı ünlü Whisper/Qwen tarafından bazen "aaaa",
            // "üüü" veya ayrı bir "a" kelimesi gibi döner. Yakındaysa önceki
            // kelimenin karaoke süresini uzat; bağımsızsa söz olmadığı için at.
            if isNonLexicalVocalization(word.text) {
                if let previous = normalized.last,
                   word.start - previous.end <= 0.22 {
                    normalized[normalized.count - 1].end = max(previous.end, word.end)
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
        return addingTurkishQuestionPunctuation(to: normalized)
    }

    // ASR bazı Türkçe soru cümlelerinde kelimeleri doğru bulup soru işaretini
    // üretmeyebiliyor. Soru sözcüğü/eki bulunan konuşma grubunun sonuna güvenli
    // biçimde `?` ekler; var olan . ! ? işaretlerine dokunmaz.
    func addingTurkishQuestionPunctuation(
        to words: [WordTimestamp]
    ) -> [WordTimestamp] {
        guard !words.isEmpty else { return [] }

        var result = words
        var phraseStart = 0
        for index in result.indices {
            let text = result[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTerminalMark = text.last.map { ".!?".contains($0) } ?? false
            let isLast = index == result.index(before: result.endIndex)
            let nextGap = isLast
                ? 0
                : max(0, result[result.index(after: index)].start - result[index].end)
            let endsPhrase = hasTerminalMark || nextGap >= 0.62 || isLast

            guard endsPhrase else { continue }
            let phrase = result[phraseStart...index]
            if !hasTerminalMark,
               phrase.contains(where: { isTurkishQuestionToken($0.text) }) {
                result[index].text = mergingTrailingPunctuation(
                    from: "?",
                    into: result[index].text
                )
            }
            phraseStart = result.index(after: index)
        }
        return result
    }

    private func isTurkishQuestionToken(_ text: String) -> Bool {
        let key = comparisonKey(text)
            .replacingOccurrences(of: "ı", with: "i")
        guard !key.isEmpty else { return false }

        let questionWords = Set([
            "ne", "neden", "niye", "nicin", "kim", "kimi", "kime", "kimden", "kimin",
            "nerede", "neresi", "nereye", "nereden", "kac", "kacinci",
            "hangi", "hangisi", "hangileri"
        ])
        if questionWords.contains(key) || key.hasPrefix("nasil") {
            return true
        }

        let questionParticles = Set([
            "mi", "miyim", "miyiz", "misin", "misiniz", "miydi", "miydin",
            "miydiniz", "midir", "midirlar", "miyse",
            "mu", "muyum", "muyuz", "musun", "musunuz", "muydu", "muydun",
            "muydunuz", "mudur", "mudurlar", "muysa"
        ])
        return questionParticles.contains(key)
    }

    private func mergingTrailingPunctuation(
        from source: String,
        into destination: String
    ) -> String {
        let terminalCharacters = CharacterSet(
            charactersIn: ".,!?;:…\"”’»"
        )
        let sourceSuffix = String(
            source.reversed().prefix { character in
                character.unicodeScalars.allSatisfy(terminalCharacters.contains)
            }.reversed()
        )
        guard !sourceSuffix.isEmpty else { return destination }
        let base = destination.trimmingCharacters(in: terminalCharacters)
        return base + sourceSuffix
    }

    private func isNonLexicalVocalization(_ text: String) -> Bool {
        let key = comparisonKey(text)
        let characters = Array(key)
        guard !characters.isEmpty else { return false }

        let vowels = Set(Array("aeıioöuü"))
        if characters.count == 1, let sound = characters.first {
            // Türkçede "o" gerçek bir sözcüktür; öteki tek ünlüler şarkı
            // deşifresinde neredeyse her zaman uzatma parçasıdır.
            return sound != "o" && vowels.contains(sound)
        }
        let sustainedSounds = vowels.union(Set(Array("hmn")))
        if Set(characters).count == 1,
           let sound = characters.first,
           sustainedSounds.contains(sound) {
            return true
        }
        return characters.count >= 3 && characters.allSatisfy { vowels.contains($0) }
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
        if let secenek = FontCatalog.secenek(fontName) { return secenek.assRenderName }
        return fontName.replacingOccurrences(of: "-Bold", with: "").replacingOccurrences(of: "-Heavy", with: "").replacingOccurrences(of: "-Regular", with: "")
    }

    func makeDefaultASSStyleLine(
        familyName: String,
        fontSize: Int,
        isBold: Bool,
        marginV: Int
    ) -> String {
        let boldFlag = isBold ? -1 : 0
        return "Style: Default,\(familyName),\(fontSize)," +
            "&H00FFFFFF,&H000000FF,&H00000000,&H00000000," +
            "\(boldFlag),0,0,0,100,100,0,0,1,0,0,2,10,10,\(marginV),1"
    }
    
    // Kelimeler arası boşluk, noktalama ve doğal okuma süresine göre otomatik satır
    // önerisi üretir. Kısa dikey video için 4 kelime sınırı korunur; salt karakter
    // sayısı yüzünden anlamlı bir tamlamayı ortadan bölmemek için 26 karaktere kadar
    // izin verilir ve gerçek vokal durakları daha güçlü sınır kabul edilir.
    func autoLineGroups(for words: [WordTimestamp]) -> [[WordTimestamp]] {
        var groups: [[WordTimestamp]] = []
        var current: [WordTimestamp] = []
        var currentChars = 0

        for word in words {
            let wordLength = word.text.count
            if let lastWord = current.last {
                let gap = max(0, word.start - lastWord.end)
                let lineDuration = max(0, word.end - (current.first?.start ?? word.start))
                let previousText = lastWord.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let hardPhraseEnding = previousText.last.map { ".!?;:".contains($0) } ?? false
                let commaPause = (previousText.last == "," || previousText.last == "—")
                    && gap >= 0.08
                let naturalPause = current.count >= 2 && gap >= 0.42
                let readingWindowFull = current.count >= 3 && lineDuration > 2.45

                if current.count >= 4
                    || currentChars + wordLength > 26
                    || gap > 0.8
                    || hardPhraseEnding
                    || commaPause
                    || naturalPause
                    || readingWindowFull {
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

    // Zaman cümlesini değiştirmeden görsel olarak iki satıra böler. Bu kırılmalar
    // lineBreaks'ten ayrıdır: iki görsel satır aynı anda görünür ve aynı segmente aittir.
    func visualLineGroups(
        for group: [WordTimestamp],
        inlineLineBreaks: Set<UUID>
    ) -> [[WordTimestamp]] {
        guard !group.isEmpty else { return [] }
        var rows: [[WordTimestamp]] = []
        var current: [WordTimestamp] = []
        for word in group {
            current.append(word)
            if inlineLineBreaks.contains(word.id), word.id != group.last?.id {
                rows.append(current)
                current = []
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
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
            creativeDirection: direction,
            sectionRole: repeatCount > 1 ? .chorus : .verse
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
        creativeDirection: KineticCreativeDirection,
        sectionRole: KineticSectionRole = .verse
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
            composition: kineticComposition(
                for: words,
                scene: scene,
                style: style,
                direction: creativeDirection,
                sectionRole: sectionRole,
                emphasisIndex: emphasisIndex
            ),
            sectionRole: sectionRole,
            motionGain: kineticMotionGain(energy: energy, sectionRole: sectionRole),
            emphasisIndex: emphasisIndex,
            rows: rows,
            pages: pages,
            repeatCount: max(1, repeatCount)
        )
    }

    private func kineticComposition(
        for words: [WordTimestamp],
        scene: KineticScene,
        style: KineticStyle,
        direction: KineticCreativeDirection,
        sectionRole: KineticSectionRole,
        emphasisIndex: Int
    ) -> KineticComposition {
        if sectionRole == .chorus || scene == .chorusLockup {
            return .centered
        }

        let seed = kineticLineSeed(words)
        let leansLeading = (seed + emphasisIndex).isMultiple(of: 2)
        switch scene {
        case .impactSequence:
            return .staircase
        case .editorialStack:
            return leansLeading ? .splitLeading : .splitTrailing
        case .focusCut:
            if style == .cinematic || direction == .cinematicFlow {
                return .centered
            }
            return leansLeading ? .leading : .trailing
        case .captionWindow:
            switch direction {
            case .cinematicFlow:
                return .centered
            case .editorialStory, .rhythmicPulse:
                return leansLeading ? .leading : .trailing
            case .anthemLift:
                return sectionRole == .lift
                    ? (leansLeading ? .leading : .trailing)
                    : .centered
            }
        case .phraseBuild:
            switch style {
            case .cinematic:
                return .centered
            case .editorial:
                return leansLeading ? .leading : .trailing
            case .impact:
                return words.count > 3 ? .staircase : .centered
            case .automatic:
                switch direction {
                case .cinematicFlow, .anthemLift:
                    return .centered
                case .editorialStory:
                    return leansLeading ? .leading : .trailing
                case .rhythmicPulse:
                    return words.count > 3 ? .staircase : .centered
                }
            }
        case .chorusLockup:
            return .centered
        }
    }

    private func kineticMotionGain(
        energy: KineticEnergy,
        sectionRole: KineticSectionRole
    ) -> Double {
        let energyGain: Double
        switch energy {
        case .calm: energyGain = 0.84
        case .steady: energyGain = 1
        case .driving: energyGain = 1.13
        }

        let sectionGain: Double
        switch sectionRole {
        case .opening: sectionGain = 0.92
        case .verse: sectionGain = 1
        case .lift: sectionGain = 1.08
        case .chorus: sectionGain = 1.06
        case .release: sectionGain = 0.86
        }
        return energyGain * sectionGain
    }

    private func kineticLineSeed(_ words: [WordTimestamp]) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in kineticLineKey(words).unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % 10_007)
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
            let previousEnd = index > 0 ? groups[index - 1].last?.end : nil
            let sectionGap = previousEnd.map { max(0, (group.first?.start ?? $0) - $0) }
                ?? Double.greatestFiniteMagnitude
            let sectionRole = kineticSectionRole(
                index: index,
                repeatCount: repeatCount,
                sectionGap: sectionGap,
                energy: basePlan.energy,
                previousEnergy: directed.last?.energy
            )
            let scene = directedKineticScene(
                baseScene: basePlan.scene,
                style: style,
                direction: creativeDirection,
                sectionRole: sectionRole,
                energy: basePlan.energy,
                wordCount: group.count
            )
            var plan = composeKineticPlan(
                for: group,
                scene: scene,
                energy: basePlan.energy,
                emphasisIndex: basePlan.emphasisIndex,
                repeatCount: repeatCount,
                style: style,
                creativeDirection: creativeDirection,
                sectionRole: sectionRole
            )

            if !group.isEmpty,
               repeatCount == 1,
               sectionRole != .opening,
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
                        style: style,
                        creativeDirection: creativeDirection,
                        sectionRole: sectionRole
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

    private func kineticSectionRole(
        index: Int,
        repeatCount: Int,
        sectionGap: Double,
        energy: KineticEnergy,
        previousEnergy: KineticEnergy?
    ) -> KineticSectionRole {
        if repeatCount > 1 { return .chorus }
        if index == 0 || sectionGap >= 0.75 { return .opening }
        guard let previousEnergy else { return .verse }

        let rank: (KineticEnergy) -> Int = {
            switch $0 {
            case .calm: return 0
            case .steady: return 1
            case .driving: return 2
            }
        }
        let change = rank(energy) - rank(previousEnergy)
        if change > 0 { return .lift }
        if change < 0 { return .release }
        return .verse
    }

    private func directedKineticScene(
        baseScene: KineticScene,
        style: KineticStyle,
        direction: KineticCreativeDirection,
        sectionRole: KineticSectionRole,
        energy: KineticEnergy,
        wordCount: Int
    ) -> KineticScene {
        if sectionRole == .chorus, wordCount > 2 {
            return .chorusLockup
        }
        if wordCount <= 2 {
            return .focusCut
        }

        switch style {
        case .automatic:
            guard sectionRole == .opening,
                  baseScene == .phraseBuild || baseScene == .captionWindow else {
                return baseScene
            }
            switch direction {
            case .cinematicFlow: return .phraseBuild
            case .editorialStory, .anthemLift: return .editorialStack
            case .rhythmicPulse: return .captionWindow
            }
        case .cinematic:
            if energy == .driving { return .captionWindow }
            return .phraseBuild
        case .editorial:
            if sectionRole == .release { return .phraseBuild }
            if energy == .driving { return .captionWindow }
            return .editorialStack
        case .impact:
            if sectionRole == .release || energy == .calm { return .captionWindow }
            return .impactSequence
        }
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
        let phraseMidpoint = Double(max(0, words.count - 1)) / 2

        for (index, word) in words.enumerated() {
            let normalized = word.text
                .lowercased(with: locale)
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            let letterCount = normalized.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }.count
            let duration = durations.indices.contains(index) ? durations[index] : 0.05
            let stopWordPenalty = stopWords.contains(normalized) ? 12.0 : 0
            let emotionalBoost = kineticTurkishMeaningBoost(normalized)
            let phrasePosition = words.count > 1
                ? abs(Double(index) - phraseMidpoint) / phraseMidpoint
                : 0
            let phraseEdgeBoost = min(0.8, phrasePosition * 0.8)
            let score = (Double(letterCount) * 1.55)
                + (min(duration, 1.5) * 3.6)
                + emotionalBoost
                + phraseEdgeBoost
                - stopWordPenalty

            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func kineticTurkishMeaningBoost(_ normalized: String) -> Double {
        // Bu sözlük transkripsiyon üretmez; yalnız aynı satır içindeki görsel vurgu
        // adayını seçer. Kök eşleşmesi çekimli Türkçe sözlerde de "sevdam", "gözlerin",
        // "dönmedin" gibi biçimleri yakalarken bilinmeyen kelimeleri değiştirmez.
        let emotionalRoots = [
            "aşk", "sev", "kalp", "özle", "yalnız", "hasret", "yara", "acı",
            "göz", "ruh", "hayal", "rüya", "umut", "kader", "gece", "karan",
            "sessiz", "yangın", "kül", "veda"
        ]
        let actionRoots = [
            "dön", "git", "kal", "yan", "ağla", "öl", "bekle", "unut",
            "sarıl", "kaç", "sus", "duy", "haykır"
        ]
        if emotionalRoots.contains(where: { normalized.hasPrefix($0) }) { return 6.2 }
        if actionRoots.contains(where: { normalized.hasPrefix($0) }) { return 3.8 }
        return 0
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
        case .signature:
            treatment = wordIndex == plan.emphasisIndex ? .signature : .standard
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
                case .captionWindow: treatment = .rhythm
                case .chorusLockup: treatment = .signature
                case .focusCut, .editorialStack, .impactSequence: treatment = .poster
                }
            case .anthemLift:
                switch plan.scene {
                case .phraseBuild: treatment = .wide
                case .captionWindow: treatment = .rhythm
                case .chorusLockup: treatment = .signature
                case .focusCut, .editorialStack, .impactSequence:
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
        case .signature:
            let anchor = kineticAnchorGlyphIndex(in: characters)
            let scales = characters.indices.map { index -> Double in
                if index == anchor { return characters.count <= 3 ? 1.24 : 1.36 }
                if index == characters.startIndex { return 1.18 }
                if index == characters.index(before: characters.endIndex) { return 0.88 }
                if abs(index - anchor) == 1 { return 1.02 }
                return index.isMultiple(of: 2) ? 0.94 : 0.98
            }
            return KineticGlyphDesign(
                characters: characters,
                scaleFactors: scales,
                trackingFactor: 0.012,
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
        if treatment == .poster || treatment == .rhythm || treatment == .signature { return 1 }
        switch plan.scene {
        case .phraseBuild: return 1.10
        case .captionWindow: return 1.08
        case .chorusLockup: return 1.12
        case .focusCut, .editorialStack, .impactSequence: return 1
        }
    }

    private func kineticIsolatedX(
        plan: KineticTypographyPlan,
        wordIndex: Int,
        wordWidth: Double,
        virtualWidth: Int
    ) -> Int {
        let inset = max(18.0, Double(virtualWidth) * 0.065)
        let minimum = inset + wordWidth / 2
        let maximum = Double(virtualWidth) - inset - wordWidth / 2
        let center = Double(virtualWidth) / 2
        let proposed: Double

        switch plan.composition {
        case .centered:
            proposed = center
        case .leading:
            proposed = minimum
        case .trailing:
            proposed = maximum
        case .splitLeading:
            proposed = wordIndex == plan.emphasisIndex ? minimum : maximum
        case .splitTrailing:
            proposed = wordIndex == plan.emphasisIndex ? maximum : minimum
        case .staircase:
            let stops = [0.30, 0.50, 0.70]
            proposed = Double(virtualWidth) * stops[wordIndex % stops.count]
        }
        return Int(min(maximum, max(minimum, proposed)).rounded())
    }

    private func kineticRowStartX(
        plan: KineticTypographyPlan,
        row: [Int],
        rowIndex: Int,
        rowCount: Int,
        rowWidth: Double,
        virtualWidth: Int
    ) -> Double {
        let inset = max(18.0, Double(virtualWidth) * 0.065)
        let leading = inset
        let trailing = Double(virtualWidth) - inset - rowWidth
        let centered = (Double(virtualWidth) - rowWidth) / 2
        let emphasizedRow = row.contains(plan.emphasisIndex)
        let proposed: Double

        switch plan.composition {
        case .centered:
            proposed = centered
        case .leading:
            proposed = leading
        case .trailing:
            proposed = trailing
        case .splitLeading:
            proposed = emphasizedRow ? leading : trailing
        case .splitTrailing:
            proposed = emphasizedRow ? trailing : leading
        case .staircase:
            let centeredIndex = Double(rowIndex) - (Double(max(1, rowCount) - 1) / 2)
            proposed = centered + centeredIndex * max(12, Double(virtualWidth) * 0.055)
        }
        return min(trailing, max(leading, proposed))
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
        let safeWidth = Double(virtualWidth) * 0.87
        let layoutRows = rowsOverride ?? plan.rows
        let targetY = min(
            Double(virtualHeight) - 30,
            max(Double(baseSize) + 30, Double(virtualHeight - marginV) - Double(baseSize) * 0.38)
        )

        if rowsOverride == nil,
           plan.scene == .focusCut || plan.scene == .impactSequence {
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
                let x = kineticIsolatedX(
                    plan: plan,
                    wordIndex: index,
                    wordWidth: fittedWidth,
                    virtualWidth: virtualWidth
                )
                let staircaseOffset: Double
                if plan.composition == .staircase {
                    staircaseOffset = [-0.16, 0.04, 0.16][index % 3] * Double(baseSize)
                } else {
                    staircaseOffset = 0
                }
                let safeY = min(
                    Double(virtualHeight) - Double(visualSize) * 0.55 - 16,
                    max(
                        Double(visualSize) * 0.55 + 16,
                        targetY + staircaseOffset
                    )
                )
                return KineticWordPlacement(
                    index: index,
                    rowIndex: 0,
                    fontSize: fitted,
                    visualFontSize: visualSize,
                    width: fittedWidth,
                    x: x,
                    y: Int(safeY.rounded()),
                    glyphDesign: glyphDesign
                )
            }
        }

        let rowGapMultiplier: Double
        switch plan.scene {
        case .editorialStack: rowGapMultiplier = 1.10
        case .chorusLockup: rowGapMultiplier = 1.02
        case .phraseBuild, .captionWindow, .focusCut, .impactSequence:
            rowGapMultiplier = 0.94
        }
        let rowGap = max(46, Double(baseSize) * rowGapMultiplier)
        // SwiftUI ön izlemesi gibi son satırı kullanıcının seçtiği alt marja kilitle.
        // Önceki merkezleme çok satırlı düzenin yarısını marjın altına indiriyor,
        // dolayısıyla dışa aktarım ön izlemeden belirgin biçimde aşağıda görünüyordu.
        let firstY = targetY - (Double(max(0, layoutRows.count - 1)) * rowGap)
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

            var xCursor = kineticRowStartX(
                plan: plan,
                row: row,
                rowIndex: rowIndex,
                rowCount: layoutRows.count,
                rowWidth: rowWidth,
                virtualWidth: virtualWidth
            )
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
        let effectiveMotion = intensity.motionMultiplier * plan.motionGain
        let depth = Double(100 - baseInitialScale) * effectiveMotion
        let initialScale = max(76, min(99, 100 - Int(depth.rounded())))
        let duration = max(
            120,
            Int((240.0 * intensity.durationMultiplier / max(0.82, plan.motionGain)).rounded())
        )
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
            Int((
                80.0
                    * intensity.durationMultiplier
                    / max(0.82, plan.motionGain)
            ).rounded())
        )

        if plan.highlight == .pill {
            width = max(26, Int(placement.width.rounded(.up)) + max(18, placement.fontSize / 3))
            height = max(22, Int((Double(placement.visualFontSize) * 1.18).rounded()))
            radius = max(6, height / 4)
            left = placement.x - width / 2
            top = placement.y - height / 2
            let lift = max(
                2,
                Int((6.0 * intensity.motionMultiplier * plan.motionGain).rounded())
            )
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
        segmentEnd: Double,
        forceSingleGroup: Bool = false
    ) -> [KineticOverlayGroup] {
        if overlay.requiresKaraokeTracking {
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

        if plan.scene == .captionWindow && !forceSingleGroup {
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
        case .underShadow:
            padX = 13
            padY = 8
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
        case .underShadow: radius = max(6, min(15, height / 4))
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
        segmentEnd: Double,
        forceSingleGroup: Bool = false
    ) -> String {
        let resolvedStyle = overlayStyle.resolved(for: plan)
        guard resolvedStyle != .none else { return "" }
        let groups = kineticOverlayGroups(
            placements: placements,
            cleaned: cleaned,
            plan: plan,
            overlay: resolvedStyle,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd,
            forceSingleGroup: forceSingleGroup
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
                let hairlineWidth = min(max(40, bounds.width / 3), 110)
                let hairlineLeft: Int
                switch plan.composition {
                case .trailing, .splitTrailing:
                    hairlineLeft = bounds.left + bounds.width - hairlineWidth - max(12, bounds.radius)
                case .centered, .leading, .splitLeading, .staircase:
                    hairlineLeft = bounds.left + max(12, bounds.radius)
                }
                let hairline = KineticOverlayBounds(
                    left: hairlineLeft,
                    top: bounds.top,
                    width: hairlineWidth,
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
                let sideBarOnRight = plan.composition == .trailing
                    || plan.composition == .splitTrailing
                let sideBar = KineticOverlayBounds(
                    left: sideBarOnRight ? bounds.left + bounds.width - 5 : bounds.left,
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
                if plan.sectionRole == .chorus {
                    let chorusRuleWidth = min(max(56, bounds.width / 2), 180)
                    let chorusRule = KineticOverlayBounds(
                        left: bounds.left + (bounds.width - chorusRuleWidth) / 2,
                        top: bounds.top + bounds.height - 3,
                        width: chorusRuleWidth,
                        height: 3,
                        radius: 1
                    )
                    result += kineticOverlayShapeDialogue(
                        layer: 1,
                        start: group.start,
                        end: group.end,
                        bounds: chorusRule,
                        color: accent.assColor,
                        alpha: "18",
                        extraTags: "\\fscx0\\fad(90,110)\\t(0,140,1.8,\\fscx100)"
                    )
                }
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
            case .underShadow:
                let shadowBounds = KineticOverlayBounds(
                    left: bounds.left,
                    top: min(virtualHeight - bounds.height - 4, bounds.top + 7),
                    width: bounds.width,
                    height: bounds.height,
                    radius: bounds.radius
                )
                let shadowAlpha: String
                switch intensity {
                case .subtle: shadowAlpha = "98"
                case .balanced: shadowAlpha = "88"
                case .energetic: shadowAlpha = "78"
                }
                result += kineticOverlayShapeDialogue(
                    layer: 1,
                    start: group.start,
                    end: group.end,
                    bounds: shadowBounds,
                    color: "000000",
                    alpha: shadowAlpha,
                    extraTags: "\\blur5.5\\fad(35,75)"
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
            composition: plan.composition,
            sectionRole: plan.sectionRole,
            motionGain: plan.motionGain,
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
        lyricTrackingMode: LyricTrackingMode = .karaoke,
        inlineLineBreaks: Set<UUID> = [],
        repeatCount: Int = 1,
        scenePlan: KineticTypographyPlan? = nil,
        preserveConnectedGlyphs: Bool = false
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
        var requestedRows: [[Int]] = []
        var requestedRow: [Int] = []
        for (index, item) in cleaned.enumerated() {
            requestedRow.append(index)
            if inlineLineBreaks.contains(item.word.id), index < cleaned.count - 1 {
                requestedRows.append(requestedRow)
                requestedRow = []
            }
        }
        if !requestedRow.isEmpty { requestedRows.append(requestedRow) }
        let manualRows = requestedRows.count > 1 ? requestedRows : nil
        let layoutLetterStyle: KineticLetterStyle = preserveConnectedGlyphs
            ? .clean
            : letterStyle
        let placements: [KineticWordPlacement]
        if let manualRows {
            placements = kineticPlacements(
                cleaned: cleaned,
                plan: plan,
                fontName: fontName,
                requestedFontSize: requestedFontSize,
                marginV: marginV,
                virtualWidth: virtualWidth,
                virtualHeight: virtualHeight,
                letterStyle: layoutLetterStyle,
                rowsOverride: manualRows
            )
        } else if plan.scene == .captionWindow {
            placements = plan.pages.flatMap { page in
                kineticPlacements(
                    cleaned: cleaned,
                    plan: plan,
                    fontName: fontName,
                    requestedFontSize: requestedFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    letterStyle: layoutLetterStyle,
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
                letterStyle: layoutLetterStyle
            )
        }
        let resolvedAccent = accent.resolvedColor(customHex: customColorHex)
        let karaokeTrackingEnabled = lyricTrackingMode == .karaoke
        let boldWordTrackingEnabled = lyricTrackingMode == .boldWord
        let effectiveOverlayStyle = resolvedKineticOverlayStyle(
            requested: overlayStyle,
            plan: plan,
            trackingMode: lyricTrackingMode
        )
        var result = kineticOverlayDialogues(
            placements: placements,
            cleaned: cleaned,
            plan: plan,
            overlayStyle: effectiveOverlayStyle,
            accent: resolvedAccent,
            intensity: intensity,
            virtualWidth: virtualWidth,
            virtualHeight: virtualHeight,
            segmentStart: segStart,
            segmentEnd: segEnd,
            forceSingleGroup: manualRows != nil
        )

        for placement in placements {
            let index = placement.index
            let item = cleaned[index]
            let emphasis = index == plan.emphasisIndex
            let layoutPages = manualRows ?? plan.pages
            let pageIndex = layoutPages.firstIndex { $0.contains(index) } ?? 0
            let page = layoutPages.indices.contains(pageIndex) ? layoutPages[pageIndex] : [index]
            let localIndex = page.firstIndex(of: index) ?? index
            let isolatedWord = manualRows == nil && plan.motion == .punchCut
            let pagedWords = manualRows == nil && plan.scene == .captionWindow

            let eventStart: Double
            let eventEnd: Double
            if isolatedWord {
                eventStart = max(segStart, item.word.start - 0.12)
                eventEnd = min(segEnd, max(eventStart + 0.20, item.word.end + 0.18))
            } else if pagedWords, let firstIndex = page.first, let lastIndex = page.last {
                let rawStart = cleaned[firstIndex].word.start - 0.10
                let rawEnd = cleaned[lastIndex].word.end + 0.12
                let previousBoundary: Double
                if pageIndex > 0, let previousLast = layoutPages[pageIndex - 1].last {
                    previousBoundary = (
                        cleaned[previousLast].word.end + cleaned[firstIndex].word.start
                    ) / 2
                } else {
                    previousBoundary = segStart
                }
                let nextBoundary: Double
                if pageIndex + 1 < layoutPages.count,
                   let nextFirst = layoutPages[pageIndex + 1].first {
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

            var text = item.text
            if !preserveConnectedGlyphs {
                text = ""
                let characters = placement.glyphDesign.characters
                let letterDuration = max(
                    0.01,
                    (item.word.end - item.word.start) / Double(max(1, characters.count))
                )
                for (characterIndex, character) in characters.enumerated() {
                    let characterStart = item.word.start
                        + (Double(characterIndex) * letterDuration)
                    let characterEnd = item.word.start
                        + (Double(characterIndex + 1) * letterDuration)
                    let startMs = min(
                        eventDurationMs,
                        max(0, Int((characterStart - eventStart) * 1000))
                    )
                    let rawEndMs = min(
                        eventDurationMs,
                        max(startMs + 20, Int((characterEnd - eventStart) * 1000))
                    )
                    let fadeEnd = min(
                        eventDurationMs,
                        max(startMs + 20, min(rawEndMs, startMs + 100))
                    )
                    let glyphScale = placement.glyphDesign.scaleFactors.indices.contains(characterIndex)
                        ? placement.glyphDesign.scaleFactors[characterIndex]
                        : 1
                    let glyphSize = max(
                        1,
                        Int((Double(placement.fontSize) * glyphScale).rounded())
                    )
                    if karaokeTrackingEnabled {
                        text += "{\\fs\(glyphSize)\\alpha&H00&" +
                            "\\t(\(startMs),\(fadeEnd),\\alpha&HA0&)}\(character)"
                    } else {
                        text += "{\\fs\(glyphSize)}\(character)"
                    }
                }
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
                Int((
                    Double(baseEntranceDuration)
                        * intensity.durationMultiplier
                        / max(0.82, plan.motionGain)
                ).rounded())
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
            let effectiveMotion = intensity.motionMultiplier * plan.motionGain
            let entranceDepth = Double(100 - baseEntranceScale) * effectiveMotion
            let entranceScale = max(66, min(99, 100 - Int(entranceDepth.rounded())))
            let motionOffset: (Int) -> Int = { base in
                max(1, Int((Double(base) * effectiveMotion).rounded()))
            }

            var tags = "{\\an5"
            switch plan.motion {
            case .sideReveal:
                let distance = motionOffset(18)
                let slide: Int
                switch plan.composition {
                case .leading, .splitLeading:
                    slide = -distance
                case .trailing, .splitTrailing:
                    slide = distance
                case .centered, .staircase:
                    slide = placement.rowIndex.isMultiple(of: 2) ? -distance : distance
                }
                tags += "\\move(\(placement.x + slide),\(placement.y),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .punchCut:
                if plan.composition == .staircase {
                    let horizontal = index.isMultiple(of: 2)
                        ? -motionOffset(12)
                        : motionOffset(12)
                    tags += "\\move(\(placement.x + horizontal),\(placement.y + motionOffset(10)),\(placement.x),\(placement.y),0,\(entryPeak))"
                } else {
                    tags += "\\move(\(placement.x),\(placement.y + motionOffset(16)),\(placement.x),\(placement.y),0,\(entryPeak))"
                }
            case .softLift:
                let horizontal: Int
                switch plan.composition {
                case .leading, .splitLeading: horizontal = -motionOffset(5)
                case .trailing, .splitTrailing: horizontal = motionOffset(5)
                case .centered, .staircase: horizontal = 0
                }
                tags += "\\move(\(placement.x + horizontal),\(placement.y + motionOffset(10)),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .pagePop:
                tags += "\\move(\(placement.x),\(placement.y + motionOffset(12)),\(placement.x),\(placement.y),0,\(entryPeak))"
            case .lockedReveal:
                tags += "\\pos(\(placement.x),\(placement.y))"
            }
            let fadeIn = isolatedWord ? 70 : (pagedWords ? 75 : 110)
            let fadeOut = isolatedWord ? 100 : (pagedWords ? 95 : 140)
            tags += "\\fs\(placement.fontSize)\\c&HFFFFFF&\\fad(\(fadeIn),\(fadeOut))"
            if karaokeTrackingEnabled && preserveConnectedGlyphs {
                tags += "\\alpha&H00&"
            }
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
            if karaokeTrackingEnabled {
                let colorInEnd = min(eventDurationMs, wordStartMs + 70)
                let colorOutEnd = min(eventDurationMs, wordEndMs + 100)
                let activeColor = plan.highlight == .pill
                    ? resolvedAccent.foregroundASSColor
                    : resolvedAccent.assColor
                let shouldPulse = !isolatedWord && wordStartMs >= entryPeak
                let highlightScale = plan.highlight == .glow
                    ? min(
                        114,
                        100 + Int((Double(intensity.activeScale - 98) * plan.motionGain).rounded())
                    )
                    : min(
                        112,
                        100 + Int((Double(intensity.activeScale - 100) * plan.motionGain).rounded())
                    )
                let activeScaleTags = shouldPulse
                    ? "\\fscx\(highlightScale)\\fscy\(highlightScale)"
                    : ""
                let restingScaleTags = shouldPulse ? "\\fscx100\\fscy100" : ""
                let activeAlphaTags = preserveConnectedGlyphs ? "\\alpha&H00&" : ""
                let pastAlphaTags = preserveConnectedGlyphs ? "\\alpha&HA6&" : ""
                if plan.highlight == .pill {
                    tags += "\\t(\(wordStartMs),\(colorInEnd),\\c&H\(activeColor)&" +
                        "\\3a&HFF&\\4a&HFF&\(activeScaleTags)\(activeAlphaTags))"
                    tags += "\\t(\(wordEndMs),\(colorOutEnd),\\c&HFFFFFF&" +
                        "\\3a&H00&\\4a&H00&\(restingScaleTags)\(pastAlphaTags))"
                } else {
                    tags += "\\t(\(wordStartMs),\(colorInEnd),\\c&H\(activeColor)&" +
                        "\(activeScaleTags)\(activeAlphaTags))"
                    tags += "\\t(\(wordEndMs),\(colorOutEnd),\\c&HFFFFFF&" +
                        "\(restingScaleTags)\(pastAlphaTags))"
                }
            }
            if plan.highlight == .glow && effectiveOverlayStyle != .none {
                tags += "\\4c&H\(resolvedAccent.assColor)&\\4a&H55&\\shad2.4"
            }
            if boldWordTrackingEnabled {
                tags += "\\b0\\bord0\\shad0"
                tags += "\\t(\(wordStartMs),\(min(eventDurationMs, wordStartMs + 10)),\\alpha&HFF&)"
                tags += "\\t(\(wordEndMs),\(min(eventDurationMs, wordEndMs + 10)),\\alpha&H00&)"
            }
            tags += "}"

            if karaokeTrackingEnabled {
                result += kineticDecorationDialogue(
                    placement: placement,
                    word: item.word,
                    plan: plan,
                    accent: resolvedAccent,
                    intensity: intensity,
                    segmentStart: eventStart,
                    segmentEnd: safeEventEnd
                )
            }
            let layer = emphasis ? 3 : 2
            result += "Dialogue: \(layer),\(formatASSTime(eventStart)),\(formatASSTime(safeEventEnd)),Default,,0,0,0,,\(tags)\(text)\n"
            if boldWordTrackingEnabled {
                let boldInEnd = min(eventDurationMs, wordStartMs + 10)
                let boldOutEnd = min(eventDurationMs, wordEndMs + 10)
                var boldTags = String(tags.dropLast())
                boldTags += "\\b1\\c&H\(resolvedAccent.assColor)&\\bord0\\shad0" +
                    "\\fscx104\\fscy104\\alpha&HFF&"
                boldTags += "\\t(\(wordStartMs),\(boldInEnd),\\alpha&H00&)"
                boldTags += "\\t(\(wordEndMs),\(boldOutEnd),\\alpha&HFF&)}"
                result += "Dialogue: \(layer + 1),\(formatASSTime(eventStart)),\(formatASSTime(safeEventEnd)),Default,,0,0,0,,\(boldTags)\(text)\n"
            }
        }
        return result
    }

    // Cümle + Kalın: her kelime normal ölçüsüyle sabit bir merkeze yerleştirilir.
    // Aktif aralıkta Regular olay tamamen biter ve yerine tek bir Bold olay çizilir;
    // aynı glifin iki ağırlığı hiçbir karede üst üste binmez. Bold kopya merkezinden
    // %4 büyür, bu nedenle satır yerleşimi değişmeden küçük bir vurgu kazanır.
    func makeBoldWordDialogues(
        group: [WordTimestamp],
        segStart: Double,
        segEnd: Double,
        fontName: String,
        fontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        inlineLineBreaks: Set<UUID> = [],
        extraTags: String = "",
        accent: KineticAccent = .gold,
        customColorHex: String = KineticAccent.defaultCustomHex
    ) -> String {
        struct BoldWordItem {
            let word: WordTimestamp
            let text: String
            let startUTF16: Int
            let endUTF16: Int
        }

        let itemsByRow: [[BoldWordItem]] = visualLineGroups(
            for: group,
            inlineLineBreaks: inlineLineBreaks
        ).compactMap { row in
            var items: [BoldWordItem] = []
            var utf16Cursor = 0
            for word in row {
                let text = cleanASSWord(word.text)
                guard !text.isEmpty else { continue }
                if !items.isEmpty { utf16Cursor += 1 }
                let startUTF16 = utf16Cursor
                utf16Cursor += text.utf16.count
                items.append(
                    BoldWordItem(
                        word: word,
                        text: text,
                        startUTF16: startUTF16,
                        endUTF16: utf16Cursor
                    )
                )
            }
            return items.isEmpty ? nil : items
        }
        guard !itemsByRow.isEmpty, segEnd > segStart else { return "" }

        let rowTexts = itemsByRow.map { $0.map(\.text).joined(separator: " ") }
        let maximumWidth = max(24.0, Double(virtualWidth - 20))
        let baselineY = max(0, virtualHeight - marginV)
        let rowGap = max(1, fontSize)
        let resolvedAccent = accent.resolvedColor(customHex: customColorHex)
        var result = ""

        for (rowIndex, items) in itemsByRow.enumerated() {
            let rowText = rowTexts[rowIndex]
            let measurement = harfSinirlariniOlc(
                metin: rowText,
                fontName: fontName,
                assFontSize: fontSize
            )
            let estimatedWidth = min(
                maximumWidth,
                max(24.0, Double(max(1, rowText.utf16.count)) * Double(fontSize) * 0.56)
            )
            let lineWidth = measurement?.genislik ?? estimatedWidth
            let lineLeft = (Double(virtualWidth) - lineWidth) / 2
            let rowY = baselineY - ((itemsByRow.count - rowIndex - 1) * rowGap)

            for item in items {
                let leftOffset: Double
                let rightOffset: Double
                if let measurement,
                   item.endUTF16 > 0,
                   item.endUTF16 <= measurement.sinirlar.count {
                    leftOffset = item.startUTF16 == 0
                        ? 0
                        : measurement.sinirlar[item.startUTF16 - 1]
                    rightOffset = measurement.sinirlar[item.endUTF16 - 1]
                } else {
                    let denominator = Double(max(1, rowText.utf16.count))
                    leftOffset = lineWidth * Double(item.startUTF16) / denominator
                    rightOffset = lineWidth * Double(item.endUTF16) / denominator
                }

                let wordCenterX = min(
                    virtualWidth,
                    max(0, Int((lineLeft + ((leftOffset + rightOffset) / 2)).rounded()))
                )
                let wordStart = min(segEnd, max(segStart, item.word.start))
                let wordEnd = min(segEnd, max(wordStart, item.word.end))
                let segmentStartText = formatASSTime(segStart)
                let segmentEndText = formatASSTime(segEnd)
                let wordStartText = formatASSTime(wordStart)
                let wordEndText = formatASSTime(wordEnd)
                let hasActiveInterval = wordStartText != wordEndText
                let assFamilyName = FontCatalog.assFamilyName(for: fontName)
                let thinWeightTag = FontCatalog.assTag(for: fontName, weight: .thin)
                let boldWeightTag = FontCatalog.assTag(for: fontName, weight: .bold)

                let unactiveTags = "{\\q2\\an2\\pos(\(wordCenterX),\(rowY))" +
                    "\\fn\(assFamilyName)\\fs\(fontSize)\(thinWeightTag)\\c&HFFFFFF&\(extraTags)\\bord0\\shad0}"

                if !hasActiveInterval {
                    result += "Dialogue: 1,\(segmentStartText)," +
                        "\(segmentEndText),Default,,0,0,0,," +
                        "\(unactiveTags)\(item.text)\n"
                    continue
                }

                if segmentStartText != wordStartText {
                    result += "Dialogue: 1,\(segmentStartText)," +
                        "\(wordStartText),Default,,0,0,0,," +
                        "\(unactiveTags)\(item.text)\n"
                }
                if wordEndText != segmentEndText {
                    result += "Dialogue: 1,\(wordEndText)," +
                        "\(segmentEndText),Default,,0,0,0,," +
                        "\(unactiveTags)\(item.text)\n"
                }

                let boldTags = "{\\q2\\an2\\pos(\(wordCenterX),\(rowY))" +
                    "\\fn\(assFamilyName)\\fs\(fontSize)\(boldWeightTag)\\c&H\(resolvedAccent.assColor)&" +
                    "\(extraTags)\\bord0\\shad0}"
                result += "Dialogue: 2,\(wordStartText)," +
                    "\(wordEndText),Default,,0,0,0,," +
                    "\(boldTags)\(item.text)\n"
            }
        }
        return result
    }

    // Bitişik el yazısı fontlarında iki görsel satırın karaoke süpürmesini, metnin
    // içine harf etiketi sokmadan ayrı ayrı üretir. Her satır tek parça şekillendiği
    // için harf bağları korunur; iki satır da aynı segment boyunca birlikte görünür.
    func makeConnectedKaraokeRowsDialogues(
        group: [WordTimestamp],
        inlineLineBreaks: Set<UUID>,
        segStart: Double,
        segEnd: Double,
        fontName: String,
        fontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        extraTags: String = ""
    ) -> String {
        struct CharacterTiming {
            let endUTF16: Int
            let startMs: Int
            let endMs: Int
        }

        let rows = visualLineGroups(
            for: group,
            inlineLineBreaks: inlineLineBreaks
        )
        guard rows.count > 1, segEnd > segStart else { return "" }

        let t0 = formatASSTime(segStart)
        let t1 = formatASSTime(segEnd)
        let centerX = virtualWidth / 2
        let baselineY = max(0, virtualHeight - marginV)
        let rowGap = max(1, fontSize)
        let maximumWidth = max(24.0, Double(virtualWidth - 20))
        var result = ""

        for (rowIndex, row) in rows.enumerated() {
            var rowText = ""
            var timings: [CharacterTiming] = []
            var utf16Cursor = 0
            let cleanedWords = row.compactMap { word -> (WordTimestamp, String)? in
                let text = cleanASSWord(word.text)
                return text.isEmpty ? nil : (word, text)
            }
            guard !cleanedWords.isEmpty else { continue }

            for (wordIndex, item) in cleanedWords.enumerated() {
                if wordIndex > 0 {
                    rowText += " "
                    utf16Cursor += 1
                }
                let wordStart = max(segStart, item.0.start)
                let wordEnd = min(segEnd, max(wordStart + 0.05, item.0.end))
                let characters = Array(item.1)
                let characterDuration = max(
                    0.01,
                    (wordEnd - wordStart) / Double(max(1, characters.count))
                )
                for (characterIndex, character) in characters.enumerated() {
                    rowText.append(character)
                    utf16Cursor += String(character).utf16.count
                    let startMs = max(
                        0,
                        Int((
                            wordStart
                                + (Double(characterIndex) * characterDuration)
                                - segStart
                        ) * 1000)
                    )
                    let endMs = max(
                        startMs + 10,
                        Int((
                            wordStart
                                + (Double(characterIndex + 1) * characterDuration)
                                - segStart
                        ) * 1000)
                    )
                    timings.append(
                        CharacterTiming(
                            endUTF16: utf16Cursor,
                            startMs: startMs,
                            endMs: endMs
                        )
                    )
                }
            }

            let measurement = harfSinirlariniOlc(
                metin: rowText,
                fontName: fontName,
                assFontSize: fontSize
            )
            let estimatedWidth = min(
                maximumWidth,
                max(24.0, Double(max(1, rowText.utf16.count)) * Double(fontSize) * 0.56)
            )
            let lineWidth = measurement?.genislik ?? estimatedWidth
            let lineLeft = (Double(virtualWidth) - lineWidth) / 2
            let rowY = baselineY - ((rows.count - rowIndex - 1) * rowGap)

            let commonTags = "\\q2\\an2\\pos(\(centerX),\(rowY))" +
                "\\fs\(fontSize)\(extraTags)"
            result += "Dialogue: 0,\(t0),\(t1),Default,,0,0,0,," +
                "{\(commonTags)\\alpha&HA0&}\(rowText)\n"

            var sweepTags = "{\(commonTags)" +
                "\\clip(0,0,\(virtualWidth),\(virtualHeight))"
            var timingCursor = 0
            for timing in timings {
                let startMs = max(timingCursor, timing.startMs)
                let endMs = max(startMs + 10, timing.endMs)
                timingCursor = endMs
                let offset: Double
                if let measurement,
                   timing.endUTF16 > 0,
                   timing.endUTF16 <= measurement.sinirlar.count {
                    offset = measurement.sinirlar[timing.endUTF16 - 1]
                } else {
                    offset = lineWidth * Double(timing.endUTF16) / Double(max(1, rowText.utf16.count))
                }
                let x = min(
                    virtualWidth,
                    max(0, Int((lineLeft + offset).rounded()))
                )
                sweepTags += "\\t(\(startMs),\(endMs)," +
                    "\\clip(\(x),0,\(virtualWidth),\(virtualHeight)))"
            }
            sweepTags += "}"
            result += "Dialogue: 1,\(t0),\(t1),Default,,0,0,0,," +
                "\(sweepTags)\(rowText)\n"
        }
        return result
    }

    // Merkez Yazım: her yeni harfte daha uzun bir metin olayı üretir. Her olay aynı
    // merkez noktasına hizalandığı için metin büyürken önceki harfler doğal olarak sola
    // kayar; görünmeyen harfler yer kaplamaz ve cümlenin görsel merkezi hiç sapmaz.
    func makeCenteredRevealDialogues(
        group: [WordTimestamp],
        segStart: Double,
        segEnd: Double,
        fontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        accent: KineticAccent = .gold,
        customColorHex: String = KineticAccent.defaultCustomHex,
        inlineLineBreaks: Set<UUID> = []
    ) -> String {
        struct RevealEvent {
            let start: Double
            let leading: String
            let latest: Character
        }

        guard segEnd > segStart else { return "" }

        var events: [RevealEvent] = []
        var cumulative = ""
        var previousWordEndedVisualRow = false
        for word in group {
            let clean = cleanASSWord(word.text)
            guard !clean.isEmpty else { continue }
            let characters = Array(clean)
            guard !characters.isEmpty else { continue }

            if !cumulative.isEmpty {
                cumulative += previousWordEndedVisualRow ? "\\N" : " "
            }

            let wordStart = max(segStart, word.start)
            let wordEnd = min(segEnd, max(wordStart + 0.05, word.end))
            let letterDuration = max(
                0.01,
                (wordEnd - wordStart) / Double(characters.count)
            )

            for (index, character) in characters.enumerated() {
                let revealTime = min(
                    segEnd,
                    max(
                        segStart,
                        wordStart + (Double(index) * letterDuration)
                    )
                )
                events.append(
                    RevealEvent(
                        start: revealTime,
                        leading: cumulative,
                        latest: character
                    )
                )
                cumulative.append(character)
            }
            previousWordEndedVisualRow = inlineLineBreaks.contains(word.id)
        }

        guard !events.isEmpty else { return "" }

        let resolvedAccent = accent.resolvedColor(customHex: customColorHex)
        let centerX = virtualWidth / 2
        let halfHeight = max(12, fontSize / 2)
        let centerY = min(
            virtualHeight - halfHeight - 16,
            max(halfHeight + 16, virtualHeight - marginV - halfHeight)
        )
        var result = ""

        for (index, event) in events.enumerated() {
            let eventStart = max(segStart, event.start)
            let eventEnd = index + 1 < events.count
                ? min(segEnd, events[index + 1].start)
                : segEnd
            guard eventEnd > eventStart + 0.008 else { continue }

            let durationMs = max(10, Int((eventEnd - eventStart) * 1000))
            let settleMs = min(90, durationMs)
            let baseTags = "{\\an5\\pos(\(centerX),\(centerY))" +
                "\\fs\(fontSize)\\c&HFFFFFF&\\bord0\\shad0}"
            let latestTags = "{\\c&H\(resolvedAccent.assColor)&\\alpha&H38&" +
                "\\fscx108\\fscy108\\blur0.8" +
                "\\t(0,\(settleMs),1.6,\\c&HFFFFFF&\\alpha&H00&" +
                "\\fscx100\\fscy100\\blur0.2)}"
            let text = event.leading + latestTags + String(event.latest)
            result += "Dialogue: 2,\(formatASSTime(eventStart))," +
                "\(formatASSTime(eventEnd)),Default,,0,0,0,," +
                "\(baseTags)\(text)\n"
        }

        return result
    }

    // Kelime Akışı: her sözcük başlangıcında tamamı tek parça halinde eklenir.
    // Her olay aynı merkez noktasında yeniden dizildiği için genişleyen cümle ortada
    // kalır, önceki kelimeler ise ölçülü biçimde sola kayar.
    func makeCenteredWordRevealDialogues(
        group: [WordTimestamp],
        segStart: Double,
        segEnd: Double,
        fontName: String = "Montserrat-ExtraBold",
        fontSize: Int,
        marginV: Int,
        virtualWidth: Int,
        virtualHeight: Int,
        accent: KineticAccent = .gold,
        customColorHex: String = KineticAccent.defaultCustomHex,
        inlineLineBreaks: Set<UUID> = []
    ) -> String {
        struct RevealEvent {
            let start: Double
            let leading: String
            let latest: String
        }

        guard segEnd > segStart else { return "" }

        var events: [RevealEvent] = []
        var completedText = ""
        var previousWordEndedVisualRow = false
        for word in group {
            let clean = cleanASSWord(word.text)
            guard !clean.isEmpty else { continue }
            if !completedText.isEmpty {
                // ASS'in satır içindeki normal boşluğu font geçişinin yanında
                // daraltmasını/yutmasını önle. \h, aktif Thin yüzün gerçek boşluk
                // glif genişliğini korur ve SwiftUI önizlemedeki NBSP ile eşleşir.
                completedText += previousWordEndedVisualRow ? "\\N" : "\\h"
            }
            events.append(
                RevealEvent(
                    start: min(segEnd, max(segStart, word.start)),
                    leading: completedText,
                    latest: clean
                )
            )
            completedText += clean
            previousWordEndedVisualRow = inlineLineBreaks.contains(word.id)
        }

        guard !events.isEmpty else { return "" }

        let resolvedAccent = accent.resolvedColor(customHex: customColorHex)
        let assFamilyName = FontCatalog.assFamilyName(for: fontName)
        let thinWeightTag = FontCatalog.assTag(for: fontName, weight: .thin)
        let boldWeightTag = FontCatalog.assTag(for: fontName, weight: .bold)
        let centerX = virtualWidth / 2
        let halfHeight = max(12, fontSize / 2)
        let centerY = min(
            virtualHeight - halfHeight - 16,
            max(halfHeight + 16, virtualHeight - marginV - halfHeight)
        )
        var result = ""

        for (index, event) in events.enumerated() {
            let eventStart = max(segStart, event.start)
            let eventEnd = index + 1 < events.count
                ? min(segEnd, events[index + 1].start)
                : segEnd
            guard eventEnd > eventStart + 0.008 else { continue }

            let durationMs = max(10, Int((eventEnd - eventStart) * 1000))
            let settleMs = min(110, durationMs)
            let baseTags = "{\\an5\\pos(\(centerX),\(centerY))" +
                "\\fs\(fontSize)\\fscx100\\fscy100\\fn\(assFamilyName)\(thinWeightTag)" +
                "\\c&HFFFFFF&\\bord0\\shad0}"
            let latestTags = "{\\fn\(assFamilyName)\\fs\(fontSize)\\fscx100\\fscy100" +
                "\(boldWeightTag)\\c&H\(resolvedAccent.assColor)&\\alpha&H18&" +
                "\\blur0.7" +
                "\\t(0,\(settleMs),1.5,\\c&HFFFFFF&\\alpha&H00&" +
                "\\blur0.2)}"
            result += "Dialogue: 2,\(formatASSTime(eventStart))," +
                "\(formatASSTime(eventEnd)),Default,,0,0,0,," +
                "\(baseTags)\(event.leading)\(latestTags)\(event.latest)\n"
        }

        return result
    }

    // 3. ASS Altyazı Dosyası Oluşturma (iOS 16+ uyumlu asenkron yapı)
    // lineBreaks zaman cümlelerini, inlineLineBreaks ise aynı anda görünen cümle
    // içindeki görsel alt satırı belirler.
    func generateASS(
        words: [WordTimestamp],
        lineBreaks: Set<UUID>,
        inlineLineBreaks: Set<UUID> = [],
        fontName: String,
        fontSize: Int,
        marginV: Int,
        karaokeMode: KaraokeMode = .classic,
        lyricTrackingMode: LyricTrackingMode = .karaoke,
        kineticStyle: KineticStyle = .automatic,
        kineticAccent: KineticAccent = .gold,
        kineticCustomColorHex: String = KineticAccent.defaultCustomHex,
        kineticIntensity: KineticIntensity = .balanced,
        kineticLetterStyle: KineticLetterStyle = .clean,
        kineticOverlayStyle: KineticOverlayStyle = .none,
        kineticEmphasisWordIDs: Set<UUID> = [],
        videoURL: URL
    ) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        
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
        let boldFlag = (
            FontCatalog.secenek(fontName)?.assUsesBoldStyle
                ?? fontName.contains("Bold")
        ) ? -1 : 0

        // Bitişik (el yazısı) fontlarda harf başına etiket bloğu, animasyon sırasında harf
        // bağlarını/konturu koparıp harfi "normal" gösteriyordu. Çözüm iki katman hilesi:
        // altta etiketsiz BİTİŞİK soluk kopya (hiç bozulmaz), üstte harf harf tam saydama
        // ERİYEN opak kopya. Harf harf soluklaşma hissi korunur, yazı hep bitişik görünür.
        let bitisikFont = FontCatalog.secenek(fontName)?.bitisik ?? false
        let renderPath = subtitleRenderPath(
            karaokeMode: karaokeMode,
            lyricTrackingMode: lyricTrackingMode,
            usesConnectedFont: bitisikFont
        )

        var assContent = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(virtualWidth)
        PlayResY: \(virtualHeight)

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        \(makeDefaultASSStyleLine(
            familyName: familyName,
            fontSize: fontSize,
            isBold: boldFlag == -1,
            marginV: marginV
        ))

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

            let visualRows = visualLineGroups(
                for: seg.group,
                inlineLineBreaks: inlineLineBreaks
            )
            let cleanVisualRows = visualRows.map { row in
                row.compactMap { word -> String? in
                    let text = cleanASSWord(word.text)
                    return text.isEmpty ? nil : text
                }
            }.filter { !$0.isEmpty }
            let lineText = cleanVisualRows
                .map { $0.joined(separator: " ") }
                .joined(separator: "\\N")
            guard !lineText.isEmpty else { continue }

            let maximumLineWidth = max(1, Double(virtualWidth - 40))
            let measuredWidth = cleanVisualRows.map { row in
                harfSinirlariniOlc(
                    metin: row.joined(separator: " "),
                    fontName: fontName,
                    assFontSize: fontSize
                )?.genislik ?? 0
            }.max() ?? 0
            let lineFontSize = fittedFontSize(
                requested: fontSize,
                measuredWidth: measuredWidth,
                maximumWidth: maximumLineWidth
            )

            if renderPath == .centeredWordReveal {
                assContent += makeCenteredWordRevealDialogues(
                    group: seg.group,
                    segStart: segStart,
                    segEnd: segEnd,
                    fontName: fontName,
                    fontSize: lineFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    accent: kineticAccent,
                    customColorHex: kineticCustomColorHex,
                    inlineLineBreaks: inlineLineBreaks
                )
                continue
            }

            if renderPath == .centeredCharacterReveal {
                assContent += makeCenteredRevealDialogues(
                    group: seg.group,
                    segStart: segStart,
                    segEnd: segEnd,
                    fontSize: lineFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    accent: kineticAccent,
                    customColorHex: kineticCustomColorHex,
                    inlineLineBreaks: inlineLineBreaks
                )
                continue
            }

            // Kinetik seçim her fontta aynı sahne motoruna gider. Bitişik fontlarda
            // harfler parçalanmadan kelime tek glif koşusu olarak korunur; standart
            // karaoke yoluna geri düşülmez.
            if renderPath == .kinetic || renderPath == .connectedKinetic {
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
                    lyricTrackingMode: lyricTrackingMode,
                    inlineLineBreaks: inlineLineBreaks,
                    repeatCount: kineticPlans[index].repeatCount,
                    scenePlan: kineticPlans[index],
                    preserveConnectedGlyphs: renderPath == .connectedKinetic
                )
                continue
            }

            if karaokeMode == .kinetic
                && renderPath != .boldWord
                && bitisikFont
                && visualRows.count == 1 {
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
            if karaokeMode == .kinetic && renderPath != .boldWord {
                lineMotionTags = kineticWholeLineTags(
                    plan: kineticPlans[index],
                    style: kineticStyle,
                    intensity: kineticIntensity
                )
            } else {
                lineMotionTags = ""
            }

            if renderPath == .boldWord {
                assContent += makeBoldWordDialogues(
                    group: seg.group,
                    segStart: segStart,
                    segEnd: segEnd,
                    fontName: fontName,
                    fontSize: lineFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    inlineLineBreaks: inlineLineBreaks,
                    accent: kineticAccent,
                    customColorHex: kineticCustomColorHex
                )
                continue
            }

            if renderPath == .staticLine {
                let t0 = formatASSTime(segStart)
                let t1 = formatASSTime(segEnd)
                assContent += "Dialogue: 1,\(t0),\(t1),Default,,0,0,0,," +
                    "{\\fs\(lineFontSize)\(lineMotionTags)}\(lineText)\n"
                continue
            }

            // İki görsel satırı tek bir \N metninde ölçmek CoreText/ASS koordinatlarını
            // karıştırıyordu. Her fontta satırlar ayrı süpürme katmanı olarak üretilir;
            // ikinci satır artık ilk satırın clip alanını yeniden açamaz.
            if visualRows.count > 1 {
                assContent += makeConnectedKaraokeRowsDialogues(
                    group: seg.group,
                    inlineLineBreaks: inlineLineBreaks,
                    segStart: segStart,
                    segEnd: segEnd,
                    fontName: fontName,
                    fontSize: lineFontSize,
                    marginV: marginV,
                    virtualWidth: virtualWidth,
                    virtualHeight: virtualHeight,
                    extraTags: lineMotionTags
                )
                continue
            }

            var effectText = "{\\fs\(lineFontSize)\(lineMotionTags)}"   // normal fontlar: tek katman; bitişik fontlarda yedek üst katman
            var plainText = ""    // bitişik fontlar: etiketsiz tam satır metni
            var harfZamanlar: [(sonUTF16: Int, s: Int, e: Int)] = []  // süpürme sınırı için harf zamanları
            var utf16Pos = 0
            let renderableWords = seg.group.filter {
                !cleanASSWord($0.text).isEmpty
            }
            for (wordIndex, word) in renderableWords.enumerated() {
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

                plainText += cleanText
                if wordIndex < renderableWords.count - 1 {
                    let separator = inlineLineBreaks.contains(word.id) ? "\\N" : " "
                    effectText += separator
                    plainText += separator
                    if separator == " " { utf16Pos += 1 }
                }
            }

            if plainText.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let t0 = formatASSTime(segStart)
            let t1 = formatASSTime(segEnd)

            let metin = plainText.trimmingCharacters(in: .whitespaces)
            // Harf takibinde harf bağlarını ve orijinal font kerning verisini korumak için
            // KAYAN KIRPMA SINIRI (\clip) kullanılır. Metnin içine harf etiketleri sokulmadığı
            // için satır tek parça şekillenir ve harf boşlukları bozulmaz.
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
                // Ölçüm yapılamadı veya satır sığmayıp sarılacak: harf harf eriyen kopya
                if bitisikFont {
                    assContent += "Dialogue: 0,\(t0),\(t1),Default,,0,0,0,,{\\fs\(lineFontSize)\(lineMotionTags)\\alpha&HA0&}\(metin)\n"
                }
                assContent += "Dialogue: 1,\(t0),\(t1),Default,,0,0,0,,\(effectText)\n"
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

    // Regular ve Bold kesitleri aynı fontsdir içine kopyalanır. Böylece libass,
    // \b1 geldiğinde yapay kontur yerine ailenin gerçek Bold dosyasını seçebilir.
    // Tek ağırlıklı fontlarda yalnız mevcut dosya kopyalanır ve kontrollü sentetik
    // kalınlık yedeği makeBoldWordDialogues içinde uygulanır.
    private func prepareFontsDir(for fontSelection: String) -> URL? {
        let fontFileURLs: [URL] = FontCatalog.renderPSNames(for: fontSelection).compactMap {
            fontName in
            let ctFont = CTFontCreateWithName(fontName as CFString, 24, nil)
            let resolvedName = CTFontCopyPostScriptName(ctFont) as String
            guard resolvedName.caseInsensitiveCompare(fontName) == .orderedSame else {
                return nil
            }
            return CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL
        }
        guard !fontFileURLs.isEmpty else { return nil }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ass_fonts_" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for fontFileURL in Set(fontFileURLs) {
                try FileManager.default.copyItem(
                    at: fontFileURL,
                    to: dir.appendingPathComponent(fontFileURL.lastPathComponent)
                )
            }
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
            // Görüntü ve ses her zaman kaynak videodan seçilir. Analiz için üretilen
            // vokal dosyaları bu komuta hiç girmez; finalde orijinal mix korunur.
            "-map", "0:v:0",
            "-map", "0:a:0?",
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
