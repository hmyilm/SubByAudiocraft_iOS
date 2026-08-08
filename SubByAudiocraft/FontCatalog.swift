import Foundation
import Combine
import CoreText

enum SubtitleFontWeight: String, CaseIterable, Identifiable {
    case thin
    case regular
    case bold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thin: return "Thin"
        case .regular: return "Regular"
        case .bold: return "Bold"
        }
    }

    // Libass'ta 0/1 kullanmak stilin varsayılan Bold değerine geri dönebilir.
    // Sayısal ağırlıklar her fontta Thin/Regular/Bold sonucunu açıkça sabitler.
    var assTag: String {
        switch self {
        case .thin: return "\\b100"
        case .regular: return "\\b400"
        case .bold: return "\\b700"
        }
    }
}

enum FontCategory: String, CaseIterable, Identifiable {
    case modern
    case poster
    case serif
    case handwriting
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modern: return "Modern"
        case .poster: return "Afiş"
        case .serif: return "Sinematik"
        case .handwriting: return "El Yazısı"
        case .custom: return "Benim Fontlarım"
        }
    }

    var icon: String {
        switch self {
        case .modern: return "textformat"
        case .poster: return "rectangle.portrait"
        case .serif: return "film"
        case .handwriting: return "pencil.line"
        case .custom: return "square.and.arrow.down"
        }
    }
}

// Uygulamadaki tüm altyazı fontlarının tek kaynağı.
// psName SwiftUI/CoreText, assFamily ise libass/fontconfig eşlemesi için kullanılır.
// bitisik fontlarda harf bağlarını koruyan iki katmanlı karaoke yolu seçilir.
struct FontOption: Identifiable, Hashable {
    let psName: String
    let display: String
    let assFamily: String
    let kalin: Bool
    let category: FontCategory
    var regularPSName: String? = nil
    var boldPSName: String? = nil
    var thinPSName: String? = nil
    var bitisik: Bool = false
    var sourceFileName: String? = nil

    var id: String { psName }

    var regularFaceName: String { regularPSName ?? psName }
    var thinFaceName: String { thinPSName ?? regularFaceName }
    var hasRealBoldFace: Bool { boldPSName != nil }
    var hasRealThinFace: Bool { thinPSName != nil }
    var availableWeights: [SubtitleFontWeight] {
        hasRealThinFace ? SubtitleFontWeight.allCases : [.regular, .bold]
    }
    var usesDistinctPrimaryFace: Bool {
        psName != regularFaceName && psName != boldPSName && psName != thinPSName
    }
    var assRenderName: String { usesDistinctPrimaryFace ? psName : assFamily }
    var assUsesBoldStyle: Bool { kalin && !usesDistinctPrimaryFace }

    func faceName(for weight: SubtitleFontWeight) -> String {
        switch weight {
        case .thin: return thinPSName ?? regularFaceName
        case .regular: return regularFaceName
        case .bold: return boldPSName ?? regularFaceName
        }
    }

    func hasRealFace(for weight: SubtitleFontWeight) -> Bool {
        switch weight {
        case .thin: return thinPSName != nil
        case .regular: return true
        case .bold: return boldPSName != nil
        }
    }

    // Gerçek Thin/Light yüzü bulunmayan ailelerde sentetik inceltme uygulanmaz.
    // Pasif metin doğrudan Regular, aktif metin ailenin gerçek/sentetik Bold yüzüdür.
    func assTag(for weight: SubtitleFontWeight) -> String {
        if weight == .thin, !hasRealThinFace {
            return SubtitleFontWeight.regular.assTag
        }
        return weight.assTag
    }
}

enum FontCatalog {
    // Paket fontlarının tamamı açık lisanslıdır ve Türkçe ÇĞİÖŞÜçğıöşü glifleri
    // dosya düzeyinde doğrulanmıştır.
    static let gomulu: [FontOption] = [
        FontOption(psName: "Montserrat-ExtraBold", display: "Montserrat", assFamily: "Montserrat", kalin: true, category: .modern, regularPSName: "Montserrat-Regular", boldPSName: "Montserrat-Bold", thinPSName: "Montserrat-Light"),
        FontOption(psName: "Poppins-Bold", display: "Poppins", assFamily: "Poppins", kalin: true, category: .modern, regularPSName: "Poppins-Regular", boldPSName: "Poppins-Bold", thinPSName: "Poppins-Light"),
        FontOption(psName: "Lato-Bold", display: "Lato", assFamily: "Lato", kalin: true, category: .modern, regularPSName: "Lato-Regular", boldPSName: "Lato-Bold", thinPSName: "Lato-Light"),
        FontOption(psName: "SpaceMono-Bold", display: "Space Mono", assFamily: "Space Mono", kalin: true, category: .modern, regularPSName: "SpaceMono-Regular", boldPSName: "SpaceMono-Bold"),
        FontOption(psName: "Righteous-Regular", display: "Righteous", assFamily: "Righteous", kalin: false, category: .modern),
        FontOption(psName: "FrancoisOne-Regular", display: "Francois One", assFamily: "Francois One", kalin: false, category: .modern),

        FontOption(psName: "ArchivoBlack-Regular", display: "Archivo Black", assFamily: "Archivo Black", kalin: false, category: .poster),
        FontOption(psName: "LeagueSpartan-Bold", display: "League Spartan", assFamily: "League Spartan", kalin: true, category: .poster, regularPSName: "LeagueSpartan-Regular", boldPSName: "LeagueSpartan-Bold"),
        FontOption(psName: "Oswald-Bold", display: "Oswald", assFamily: "Oswald", kalin: true, category: .poster, regularPSName: "Oswald-Regular", boldPSName: "Oswald-Bold"),
        FontOption(psName: "Anton-Regular", display: "Anton", assFamily: "Anton", kalin: false, category: .poster),
        FontOption(psName: "BebasNeue-Regular", display: "Bebas Neue", assFamily: "Bebas Neue", kalin: false, category: .poster),
        FontOption(psName: "Bangers-Regular", display: "Bangers", assFamily: "Bangers", kalin: false, category: .poster),
        FontOption(psName: "AlfaSlabOne-Regular", display: "Alfa Slab One", assFamily: "Alfa Slab One", kalin: false, category: .poster),
        FontOption(psName: "BlackOpsOne-Regular", display: "Black Ops One", assFamily: "Black Ops One", kalin: false, category: .poster),
        FontOption(psName: "Shrikhand-Regular", display: "Shrikhand", assFamily: "Shrikhand", kalin: false, category: .poster),

        FontOption(psName: "PlayfairDisplayRoman-Black", display: "Playfair Display", assFamily: "Playfair Display", kalin: true, category: .serif, regularPSName: "PlayfairDisplayRoman-Regular", boldPSName: "PlayfairDisplayRoman-Bold"),
        FontOption(psName: "AbrilFatface-Regular", display: "Abril Fatface", assFamily: "Abril Fatface", kalin: false, category: .serif),

        FontOption(psName: "CaveatRoman-Bold", display: "Caveat", assFamily: "Caveat", kalin: true, category: .handwriting, regularPSName: "CaveatRoman-Regular", boldPSName: "CaveatRoman-Bold"),
        FontOption(psName: "Pacifico-Regular", display: "Pacifico", assFamily: "Pacifico", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "Lobster-Regular", display: "Lobster", assFamily: "Lobster", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "GreatVibes-Regular", display: "Great Vibes", assFamily: "Great Vibes", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "PetitFormalScript-Regular", display: "Petit Formal Script", assFamily: "Petit Formal Script", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "Allura-Regular", display: "Allura", assFamily: "Allura", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "Sacramento-Regular", display: "Sacramento", assFamily: "Sacramento", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "Parisienne-Regular", display: "Parisienne", assFamily: "Parisienne", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "KaushanScript-Regular", display: "Kaushan", assFamily: "Kaushan Script", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "MarckScript-Regular", display: "Marck Script", assFamily: "Marck Script", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "Courgette-Regular", display: "Courgette", assFamily: "Courgette", kalin: false, category: .handwriting, bitisik: true)
    ]

    // iOS sistem fontları uygulama boyutunu artırmaz. Georgia da paket fontu değil,
    // sistem fontu olduğu için burada tutulur.
    static let sistem: [FontOption] = [
        FontOption(psName: "AvenirNext-Bold", display: "Avenir Next", assFamily: "Avenir Next", kalin: true, category: .modern, regularPSName: "AvenirNext-Regular", boldPSName: "AvenirNext-Bold", thinPSName: "AvenirNext-UltraLight"),
        FontOption(psName: "ArialRoundedMTBold", display: "Arial Rounded", assFamily: "Arial Rounded MT Bold", kalin: false, category: .modern),
        FontOption(psName: "Futura-Bold", display: "Futura", assFamily: "Futura", kalin: true, category: .modern, regularPSName: "Futura-Medium", boldPSName: "Futura-Bold"),
        FontOption(psName: "GillSans-Bold", display: "Gill Sans", assFamily: "Gill Sans", kalin: true, category: .modern, regularPSName: "GillSans", boldPSName: "GillSans-Bold", thinPSName: "GillSans-Light"),
        FontOption(psName: "TrebuchetMS-Bold", display: "Trebuchet", assFamily: "Trebuchet MS", kalin: true, category: .modern, regularPSName: "TrebuchetMS", boldPSName: "TrebuchetMS-Bold"),
        FontOption(psName: "Verdana-Bold", display: "Verdana", assFamily: "Verdana", kalin: true, category: .modern, regularPSName: "Verdana", boldPSName: "Verdana-Bold"),

        FontOption(psName: "Copperplate-Bold", display: "Copperplate", assFamily: "Copperplate", kalin: true, category: .poster, regularPSName: "Copperplate", boldPSName: "Copperplate-Bold", thinPSName: "Copperplate-Light"),
        FontOption(psName: "Chalkduster", display: "Chalkduster", assFamily: "Chalkduster", kalin: false, category: .poster),

        FontOption(psName: "Georgia", display: "Georgia", assFamily: "Georgia", kalin: false, category: .serif, regularPSName: "Georgia", boldPSName: "Georgia-Bold"),
        FontOption(psName: "Baskerville-Bold", display: "Baskerville", assFamily: "Baskerville", kalin: true, category: .serif, regularPSName: "Baskerville", boldPSName: "Baskerville-Bold"),
        FontOption(psName: "Didot-Bold", display: "Didot", assFamily: "Didot", kalin: true, category: .serif, regularPSName: "Didot", boldPSName: "Didot-Bold"),
        FontOption(psName: "TimesNewRomanPS-BoldMT", display: "Times New Roman", assFamily: "Times New Roman", kalin: true, category: .serif, regularPSName: "TimesNewRomanPSMT", boldPSName: "TimesNewRomanPS-BoldMT"),
        FontOption(psName: "AmericanTypewriter-Bold", display: "Typewriter", assFamily: "American Typewriter", kalin: true, category: .serif, regularPSName: "AmericanTypewriter", boldPSName: "AmericanTypewriter-Bold", thinPSName: "AmericanTypewriter-Light"),

        FontOption(psName: "ChalkboardSE-Bold", display: "Chalkboard", assFamily: "Chalkboard SE", kalin: true, category: .handwriting, regularPSName: "ChalkboardSE-Regular", boldPSName: "ChalkboardSE-Bold", thinPSName: "ChalkboardSE-Light"),
        FontOption(psName: "MarkerFelt-Wide", display: "Marker Felt", assFamily: "Marker Felt", kalin: true, category: .handwriting, regularPSName: "MarkerFelt-Thin", boldPSName: "MarkerFelt-Wide", thinPSName: "MarkerFelt-Thin"),
        FontOption(psName: "Noteworthy-Bold", display: "Noteworthy", assFamily: "Noteworthy", kalin: true, category: .handwriting, regularPSName: "Noteworthy-Light", boldPSName: "Noteworthy-Bold", thinPSName: "Noteworthy-Light"),
        FontOption(psName: "SavoyeLetPlain", display: "Savoye", assFamily: "Savoye LET", kalin: false, category: .handwriting, bitisik: true),
        FontOption(psName: "SnellRoundhand-Bold", display: "Snell Roundhand", assFamily: "Snell Roundhand", kalin: true, category: .handwriting, regularPSName: "SnellRoundhand", boldPSName: "SnellRoundhand-Bold", thinPSName: "SnellRoundhand", bitisik: true),
        FontOption(psName: "Zapfino", display: "Zapfino", assFamily: "Zapfino", kalin: false, category: .handwriting, bitisik: true)
    ]

    static var hepsi: [FontOption] {
        gomulu + sistem + CustomFontStore.shared.fonts
    }

    static func secenek(_ psName: String) -> FontOption? {
        hepsi.first {
            $0.psName == psName
                || $0.regularPSName == psName
                || $0.boldPSName == psName
                || $0.thinPSName == psName
        }
    }

    static func regularPSName(for selection: String) -> String {
        secenek(selection)?.regularFaceName ?? selection
    }

    static func boldPSName(for selection: String) -> String? {
        secenek(selection)?.boldPSName
    }

    static func thinPSName(for selection: String) -> String? {
        secenek(selection)?.thinPSName
    }

    static func faceName(
        for selection: String,
        weight: SubtitleFontWeight
    ) -> String {
        secenek(selection)?.faceName(for: weight) ?? selection
    }

    static func hasRealFace(
        for selection: String,
        weight: SubtitleFontWeight
    ) -> Bool {
        secenek(selection)?.hasRealFace(for: weight) ?? (weight == .regular)
    }

    static func assTag(
        for selection: String,
        weight: SubtitleFontWeight
    ) -> String {
        secenek(selection)?.assTag(for: weight) ?? weight.assTag
    }

    static func renderPSNames(for selection: String) -> [String] {
        guard let option = secenek(selection) else { return [selection] }
        // Seçilen yüzü (ör. ExtraBold/Black) mutlaka kopyala. Önceki sürüm yalnız
        // Regular + Bold dosyalarını libass'a verdiği için Montserrat ExtraBold ve
        // Playfair Black ön izlemede doğru, dışa aktarımda daha ince görünüyordu.
        var names = [option.regularFaceName]
        if option.psName != option.regularFaceName {
            names.append(option.psName)
        }
        if let bold = option.boldPSName, bold != option.regularFaceName {
            names.append(bold)
        }
        if let thin = option.thinPSName, thin != option.regularFaceName && thin != option.boldPSName {
            names.append(thin)
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    static func onerilen(
        karaokeMode: KaraokeMode,
        kineticStyle: KineticStyle
    ) -> [FontOption] {
        let ids: [String]

        if karaokeMode == .classic {
            ids = [
                "Montserrat-ExtraBold",
                "Poppins-Bold",
                "Lato-Bold",
                "AvenirNext-Bold",
                "Verdana-Bold"
            ]
        } else {
            switch kineticStyle {
            case .automatic:
                ids = [
                    "Montserrat-ExtraBold",
                    "LeagueSpartan-Bold",
                    "Anton-Regular",
                    "PlayfairDisplayRoman-Black",
                    "ArchivoBlack-Regular",
                    "Poppins-Bold"
                ]
            case .cinematic:
                ids = [
                    "PlayfairDisplayRoman-Black",
                    "Montserrat-ExtraBold",
                    "Lato-Bold",
                    "AbrilFatface-Regular",
                    "BebasNeue-Regular"
                ]
            case .editorial:
                ids = [
                    "LeagueSpartan-Bold",
                    "Oswald-Bold",
                    "PlayfairDisplayRoman-Black",
                    "Montserrat-ExtraBold",
                    "AbrilFatface-Regular"
                ]
            case .impact:
                ids = [
                    "ArchivoBlack-Regular",
                    "Anton-Regular",
                    "LeagueSpartan-Bold",
                    "AlfaSlabOne-Regular",
                    "Bangers-Regular",
                    "BlackOpsOne-Regular"
                ]
            }
        }

        return ids.compactMap(secenek)
    }
}

enum CustomFontStoreError: LocalizedError {
    case unsupportedFile
    case unreadableFont
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Yalnız .ttf ve .otf font dosyaları eklenebilir."
        case .unreadableFont:
            return "Font dosyası okunamadı veya geçerli bir yazı tipi içermiyor."
        case .copyFailed:
            return "Font uygulama klasörüne kopyalanamadı. Cihazdaki boş alanı kontrol edin."
        }
    }
}

// Kullanıcının lisansına sahip olduğu TTF/OTF dosyalarını kalıcı olarak saklar.
// CoreText kaydı hem SwiftUI ön izlemesinin hem de VideoProcessor'ın aynı gerçek
// font dosyasını kullanmasını sağlar; böylece özel font final videoda da korunur.
final class CustomFontStore: ObservableObject {
    static let shared = CustomFontStore()

    @Published private(set) var fonts: [FontOption] = []

    private let directoryURL: URL
    private let fileManager = FileManager.default

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = documents.appendingPathComponent("CustomFonts", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        reload()
    }

    @discardableResult
    func importFont(from sourceURL: URL) throws -> FontOption {
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "ttf" || ext == "otf" else {
            throw CustomFontStoreError.unsupportedFile
        }

        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let destination = uniqueDestination(for: sourceURL)
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw CustomFontStoreError.copyFailed
        }

        let options = describeAndRegister(destination)
        guard let first = options.first else {
            try? fileManager.removeItem(at: destination)
            throw CustomFontStoreError.unreadableFont
        }

        reload()
        return fonts.first(where: { $0.psName == first.psName }) ?? first
    }

    func remove(_ font: FontOption) {
        guard let sourceFileName = font.sourceFileName else { return }
        let url = directoryURL.appendingPathComponent(sourceFileName)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? fileManager.removeItem(at: url)
        reload()
    }

    private func reload() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        fonts = urls
            .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            .flatMap(describeAndRegister)
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    private func describeAndRegister(_ url: URL) -> [FontOption] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor], !descriptors.isEmpty else {
            return []
        }

        // Zaten kayıtlı olması hata sayılmaz; descriptor bilgisi geçerliyse font
        // kullanılabilir. Bu durum uygulama yeniden öne geldiğinde normaldir.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

        return descriptors.compactMap { descriptor in
            guard let postScriptName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String, !postScriptName.isEmpty else {
                return nil
            }

            let family = (CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontFamilyNameAttribute
            ) as? String) ?? postScriptName
            let display = (CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontDisplayNameAttribute
            ) as? String) ?? family
            let font = CTFontCreateWithFontDescriptor(descriptor, 24, nil)
            let traits = CTFontGetSymbolicTraits(font)
            let isBold = traits.contains(.traitBold)

            return FontOption(
                psName: postScriptName,
                display: display,
                assFamily: family,
                kalin: isBold,
                category: .custom,
                regularPSName: postScriptName,
                boldPSName: isBold ? postScriptName : nil,
                sourceFileName: url.lastPathComponent
            )
        }
    }

    private func uniqueDestination(for sourceURL: URL) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let ext = sourceURL.pathExtension.lowercased()
        var destination = directoryURL
            .appendingPathComponent(base)
            .appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directoryURL
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        return destination
    }
}
