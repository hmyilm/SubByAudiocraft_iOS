import Foundation

// Uygulamadaki tüm altyazı fontlarının tek listesi.
// psName: SwiftUI .custom() için PostScript adı (aynı zamanda seçim kimliği)
// display: font çipinde görünen kısa ad
// assFamily: libass/fontconfig'in tanıdığı font ailesi adı (videoya gömme aşaması)
// kalin: ASS stilindeki Bold bayrağı. Yalnız gerçekten kalın kesimi olan fontlarda açılır;
//        her fontta açık olursa libass kalın kesimi olmayan fontları YAPAY kalınlaştırır ve
//        gömülen yazı, uygulamadaki ön izlemeden farklı (font değişmiş gibi) görünür.
// bitisik: El yazısı gibi harfleri birbirine BAĞLI çizilen fontlar. Bu fontlarda harf
//        başına ayrı ASS etiket bloğu, animasyon sırasında harf bağlarını/konturu koparıp
//        harfi anlık "normal" forma döndürür. Çözüm iki katman hilesi (VideoProcessor.
//        generateASS): altta etiketsiz BİTİŞİK soluk kopya (hiç bozulmaz), üstte harfleri
//        sırası geldikçe tam saydama ERİYEN opak kopya — harf harf his korunur.
struct FontOption: Identifiable, Hashable {
    let psName: String
    let display: String
    let assFamily: String
    let kalin: Bool
    var bitisik: Bool = false
    var id: String { psName }
}

enum FontCatalog {
    // Uygulama paketine gömülü fontlar (Fonts/ klasöründeki .ttf dosyaları)
    static let gomulu: [FontOption] = [
        FontOption(psName: "Georgia", display: "Georgia", assFamily: "Georgia", kalin: false),
        FontOption(psName: "Anton-Regular", display: "Anton", assFamily: "Anton", kalin: false),
        FontOption(psName: "Bangers-Regular", display: "Bangers", assFamily: "Bangers", kalin: false),
        FontOption(psName: "BebasNeue-Regular", display: "Bebas Neue", assFamily: "Bebas Neue", kalin: false),
        FontOption(psName: "Lato-Bold", display: "Lato", assFamily: "Lato", kalin: true),
        FontOption(psName: "Pacifico-Regular", display: "Pacifico", assFamily: "Pacifico", kalin: false, bitisik: true),
        FontOption(psName: "PermanentMarker-Regular", display: "Permanent Marker", assFamily: "Permanent Marker", kalin: false),
        FontOption(psName: "Poppins-Bold", display: "Poppins", assFamily: "Poppins", kalin: true),
        FontOption(psName: "Lobster-Regular", display: "Lobster", assFamily: "Lobster", kalin: false, bitisik: true),
        FontOption(psName: "Creepster-Regular", display: "Creepster", assFamily: "Creepster", kalin: false),
        FontOption(psName: "AbrilFatface-Regular", display: "Abril Fatface", assFamily: "Abril Fatface", kalin: false),
        FontOption(psName: "AlfaSlabOne-Regular", display: "Alfa Slab One", assFamily: "Alfa Slab One", kalin: false),
        FontOption(psName: "Righteous-Regular", display: "Righteous", assFamily: "Righteous", kalin: false),
        FontOption(psName: "FrancoisOne-Regular", display: "Francois One", assFamily: "Francois One", kalin: false),
        FontOption(psName: "Shrikhand-Regular", display: "Shrikhand", assFamily: "Shrikhand", kalin: false),
        FontOption(psName: "BlackOpsOne-Regular", display: "Black Ops One", assFamily: "Black Ops One", kalin: false),
        // El yazısı (bitişik) fontlar — Google Fonts, tam Türkçe karakter destekli
        FontOption(psName: "GreatVibes-Regular", display: "Great Vibes", assFamily: "Great Vibes", kalin: false, bitisik: true),
        FontOption(psName: "Allura-Regular", display: "Allura", assFamily: "Allura", kalin: false, bitisik: true),
        FontOption(psName: "Sacramento-Regular", display: "Sacramento", assFamily: "Sacramento", kalin: false, bitisik: true),
        FontOption(psName: "Parisienne-Regular", display: "Parisienne", assFamily: "Parisienne", kalin: false, bitisik: true),
        FontOption(psName: "KaushanScript-Regular", display: "Kaushan", assFamily: "Kaushan Script", kalin: false, bitisik: true),
        FontOption(psName: "MarckScript-Regular", display: "Marck Script", assFamily: "Marck Script", kalin: false, bitisik: true),
        FontOption(psName: "Courgette-Regular", display: "Courgette", assFamily: "Courgette", kalin: false, bitisik: true)
    ]

    // iOS ile birlikte gelen sistem fontları — indirme gerektirmez, uygulamayı büyütmez.
    // Videoya gömme için sistem font klasörleri VideoProcessor.burnSubtitles içinde
    // fontconfig'e tanıtılır (CoreAddition klasörü dahil).
    static let sistem: [FontOption] = [
        FontOption(psName: "AmericanTypewriter-Bold", display: "Typewriter", assFamily: "American Typewriter", kalin: true),
        FontOption(psName: "ArialRoundedMTBold", display: "Arial Rounded", assFamily: "Arial Rounded MT Bold", kalin: false),
        FontOption(psName: "AvenirNext-Bold", display: "Avenir Next", assFamily: "Avenir Next", kalin: true),
        FontOption(psName: "Baskerville-Bold", display: "Baskerville", assFamily: "Baskerville", kalin: true),
        FontOption(psName: "ChalkboardSE-Bold", display: "Chalkboard", assFamily: "Chalkboard SE", kalin: true),
        FontOption(psName: "Chalkduster", display: "Chalkduster", assFamily: "Chalkduster", kalin: false),
        FontOption(psName: "Copperplate-Bold", display: "Copperplate", assFamily: "Copperplate", kalin: true),
        FontOption(psName: "Didot-Bold", display: "Didot", assFamily: "Didot", kalin: true),
        FontOption(psName: "Futura-Bold", display: "Futura", assFamily: "Futura", kalin: true),
        FontOption(psName: "GillSans-Bold", display: "Gill Sans", assFamily: "Gill Sans", kalin: true),
        FontOption(psName: "MarkerFelt-Wide", display: "Marker Felt", assFamily: "Marker Felt", kalin: true),
        FontOption(psName: "Noteworthy-Bold", display: "Noteworthy", assFamily: "Noteworthy", kalin: true),
        FontOption(psName: "SavoyeLetPlain", display: "Savoye", assFamily: "Savoye LET", kalin: false, bitisik: true),
        FontOption(psName: "SnellRoundhand-Bold", display: "Snell Roundhand", assFamily: "Snell Roundhand", kalin: true, bitisik: true),
        FontOption(psName: "TimesNewRomanPS-BoldMT", display: "Times New Roman", assFamily: "Times New Roman", kalin: true),
        FontOption(psName: "TrebuchetMS-Bold", display: "Trebuchet", assFamily: "Trebuchet MS", kalin: true),
        FontOption(psName: "Verdana-Bold", display: "Verdana", assFamily: "Verdana", kalin: true),
        FontOption(psName: "Zapfino", display: "Zapfino", assFamily: "Zapfino", kalin: false, bitisik: true)
    ]

    static let hepsi: [FontOption] = gomulu + sistem

    static func secenek(_ psName: String) -> FontOption? {
        hepsi.first { $0.psName == psName }
    }
}
