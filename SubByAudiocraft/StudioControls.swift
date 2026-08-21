import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Tasarım ekranının hızlı başlangıç seçenekleri. Bunlar yeni bir render modu
// oluşturmaz; mevcut ve test edilmiş ayarları anlaşılır paketler halinde uygular.
enum StudioPreset: String, CaseIterable, Identifiable {
    case smart
    case minimal
    case karaoke
    case viral
    case podcast
    case cinematic
    case neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "Akıllı"
        case .minimal: return "Minimal"
        case .karaoke: return "Karaoke"
        case .viral: return "Viral Pop"
        case .podcast: return "Podcast"
        case .cinematic: return "Sinematik"
        case .neon: return "Neon"
        }
    }

    var icon: String {
        switch self {
        case .smart: return "wand.and.stars"
        case .minimal: return "captions.bubble"
        case .karaoke: return "music.note"
        case .viral: return "bolt.fill"
        case .podcast: return "mic.fill"
        case .cinematic: return "film"
        case .neon: return "sparkles"
        }
    }

    var detail: String {
        switch self {
        case .smart: return "Parçanın bölümlerine göre kendi sahne akışını kurar."
        case .minimal: return "Temiz, sabit ve her videoda kolay okunan altyazı."
        case .karaoke: return "Söylenen harfi altın renkle klasik biçimde takip eder."
        case .viral: return "Kısa video için büyük, hızlı ve kelime odaklı görünüm."
        case .podcast: return "Cümleyi korur, aktif kelimeyi kalın ve renkli gösterir."
        case .cinematic: return "Sakin hareket, serif başlık ve film bandı dengesi."
        case .neon: return "Modern cam katman ve mor renkli kinetik vurgu."
        }
    }
}

struct StudioTypographyControls: View {
    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var marginV: Double
    @Binding var subtitleTextColorHex: String
    @Binding var karaokeMode: KaraokeMode
    @Binding var lyricTrackingMode: LyricTrackingMode
    @Binding var kineticStyle: KineticStyle
    @Binding var kineticAccent: KineticAccent
    @Binding var kineticCustomColorHex: String
    @Binding var kineticIntensity: KineticIntensity
    @Binding var kineticLetterStyle: KineticLetterStyle
    @Binding var kineticOverlayStyle: KineticOverlayStyle

    @State private var showsAdvancedOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            presetControls
            Divider().overlay(Theme.cardStroke)
            movementModeControls
            trackingControls
            textColorControls

            if usesKineticDirectorControls {
                kineticStyleControls
            }

            if showsAccentControls {
                accentControls
            }

            if lyricTrackingMode == .boldWord {
                boldWordReadabilityControls
            }

            if usesKineticDirectorControls {
                advancedControls
            }
        }
        .onChange(of: lyricTrackingMode) {
            if !kineticOverlayStyle.isAvailable(for: lyricTrackingMode) {
                kineticOverlayStyle = .none
            }
        }
    }

    private var presetControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingTitle("Hazır Görünüm", icon: "square.grid.2x2")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StudioPreset.allCases) { preset in
                        let selected = selectedPreset == preset
                        Button {
                            Theme.haptic()
                            apply(preset)
                        } label: {
                            Label(preset.title, systemImage: preset.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selected ? .black : .white)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule()
                                        .fill(selected ? Theme.yellow : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(selected ? Theme.yellow : Theme.cardStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            Text(selectedPreset?.detail ?? "Bir hazır görünüm seç; istersen aşağıdaki ayarlarla kendine göre değiştir.")
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var movementModeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTitle("Yazı Stili", icon: "textformat.alt")

            if usesDedicatedTrackingLayout {
                Label(
                    "\(lyricTrackingMode.title), kendi sabit ve test edilmiş yerleşimini kullanır.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.yellow.opacity(0.08))
                )
            } else {
                Picker("Yazı Stili", selection: $karaokeMode) {
                    ForEach(KaraokeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(
                usesDedicatedTrackingLayout
                    ? lyricTrackingMode.detail
                    : (
                        karaokeMode == .classic
                            ? "Sade, okunaklı ve güvenli altyazı görünümü."
                            : "Boyut, kompozisyon ve hareketi parçanın ritmine göre yönetir."
                    )
            )
            .font(.caption2)
            .foregroundColor(.gray)
        }
    }

    private var trackingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTitle("Sözlerin Gelişi", icon: "waveform")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(LyricTrackingMode.allCases) { mode in
                    let selected = lyricTrackingMode == mode
                    Button {
                        Theme.haptic()
                        lyricTrackingMode = mode
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: mode.icon)
                                .font(.caption.weight(.bold))
                            Text(trackingTitle(mode))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(selected ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selected ? Theme.yellow : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(selected ? Theme.yellow : Theme.cardStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Text(trackingDetail)
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kineticStyleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTitle("Hareket Stili", icon: "sparkles")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(KineticStyle.allCases) { style in
                        let selected = kineticStyle == style
                        Button {
                            Theme.haptic()
                            kineticStyle = style
                        } label: {
                            Label(style.title, systemImage: style.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selected ? .black : .white)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule()
                                        .fill(selected ? Theme.yellow : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            Text(kineticStyle == .automatic ? "Parçanın yapısına göre otomatik seçim yapar." : kineticStyle.detail)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                settingTitle("Vurgu Rengi", icon: "paintpalette")
                Spacer()
                Text(kineticAccent == .custom ? resolvedAccent.hex : kineticAccent.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(resolvedAccentColor)
            }

            HStack(spacing: 10) {
                ForEach(KineticAccent.presetCases) { accent in
                    let selected = kineticAccent == accent
                    Button {
                        Theme.haptic()
                        kineticAccent = accent
                    } label: {
                        Circle()
                            .fill(color(for: accent))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(selected ? Color.white : Color.clear, lineWidth: 3)
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Özel vurgu rengi")
            }
        }
    }

    private var textColorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                settingTitle("Yazı Rengi", icon: "paintbrush.pointed")
                Spacer()
                Text(resolvedTextColor.hex)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(resolvedTextColorColor)
            }

            HStack(spacing: 10) {
                ForEach(["#FFFFFF", "#111111", "#FEF3C7", "#FFE45C", "#A7F3D0"], id: \.self) { hex in
                    let selected = resolvedTextColor.hex == hex
                    Button {
                        Theme.haptic()
                        subtitleTextColorHex = hex
                    } label: {
                        Circle()
                            .fill(previewColor(for: hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().stroke(
                                    selected ? Theme.yellow : Color.white.opacity(0.25),
                                    lineWidth: selected ? 3 : 1
                                )
                            )
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Yazı rengi \(hex)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                ColorPicker("Özel yazı rengi", selection: textColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Özel yazı rengi")
            }

            Text("Ana yazı rengini değiştirir. Okunan kelimenin vurgu rengi ayrı ayarlanır.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    private var advancedControls: some View {
        DisclosureGroup(isExpanded: $showsAdvancedOptions) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    settingTitle("Hareket Yoğunluğu", icon: "dial.medium")
                    Picker("Hareket Yoğunluğu", selection: $kineticIntensity) {
                        ForEach(KineticIntensity.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if FontCatalog.secenek(fontName)?.bitisik == true {
                    Label(
                        "Bitişik el yazısı fontunda harf bağlarını korumak için Harf Stili otomatik olarak Temiz kullanılır.",
                        systemImage: "pencil.and.scribble"
                    )
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    optionScroller(
                        title: "Harf Stili",
                        icon: "character.textbox",
                        values: KineticLetterStyle.allCases,
                        selection: $kineticLetterStyle,
                        titleFor: { $0.title },
                        iconFor: { $0.icon }
                    )
                }

                optionScroller(
                    title: "Arka Vurgu",
                    icon: "rectangle.on.rectangle",
                    values: availableOverlays,
                    selection: $kineticOverlayStyle,
                    titleFor: { $0.title },
                    iconFor: { $0.icon }
                )
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(Theme.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gelişmiş Kinetik Ayarlar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Yoğunluk, harf stili ve arka vurgu")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .frame(minHeight: 44)
        }
        .tint(Theme.yellow)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func optionScroller<Value: Identifiable & Hashable>(
        title: String,
        icon: String,
        values: [Value],
        selection: Binding<Value>,
        titleFor: @escaping (Value) -> String,
        iconFor: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            settingTitle(title, icon: icon)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values) { value in
                        let selected = selection.wrappedValue == value
                        Button {
                            Theme.haptic()
                            selection.wrappedValue = value
                        } label: {
                            Label(titleFor(value), systemImage: iconFor(value))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(selected ? .black : .white)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule()
                                        .fill(selected ? Theme.yellow : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func settingTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
    }

    private var selectedPreset: StudioPreset? {
        if karaokeMode == .kinetic &&
            lyricTrackingMode == .karaoke &&
            kineticStyle == .automatic &&
            kineticIntensity == .balanced &&
            kineticLetterStyle == .automatic &&
            kineticOverlayStyle == .automatic &&
            kineticAccent == .gold &&
            fontName == "Montserrat-ExtraBold" {
            return .smart
        }
        if karaokeMode == .classic &&
            lyricTrackingMode == .off &&
            fontName == "Lato-Bold" {
            return .minimal
        }
        if karaokeMode == .classic &&
            lyricTrackingMode == .karaoke &&
            kineticAccent == .gold &&
            fontName == "Montserrat-ExtraBold" {
            return .karaoke
        }
        if karaokeMode == .kinetic &&
            lyricTrackingMode == .karaoke &&
            kineticStyle == .impact &&
            kineticIntensity == .energetic &&
            kineticLetterStyle == .rhythm &&
            kineticOverlayStyle == .spotlight &&
            kineticAccent == .coral &&
            fontName == "ArchivoBlack-Regular" {
            return .viral
        }
        if lyricTrackingMode == .boldWord &&
            kineticAccent == .gold &&
            fontName == "Poppins-Bold" {
            return .podcast
        }
        if karaokeMode == .kinetic &&
            lyricTrackingMode == .off &&
            kineticStyle == .cinematic &&
            kineticIntensity == .subtle &&
            kineticLetterStyle == .clean &&
            kineticOverlayStyle == .cinematicBand &&
            fontName == "PlayfairDisplayRoman-Black" {
            return .cinematic
        }
        if karaokeMode == .kinetic &&
            lyricTrackingMode == .karaoke &&
            kineticStyle == .editorial &&
            kineticOverlayStyle == .glass &&
            kineticAccent == .violet &&
            fontName == "Poppins-Bold" {
            return .neon
        }
        return nil
    }

    private func apply(_ preset: StudioPreset) {
        switch preset {
        case .smart:
            fontName = "Montserrat-ExtraBold"
            fontSize = 72
            marginV = 120
            karaokeMode = .kinetic
            lyricTrackingMode = .karaoke
            kineticStyle = .automatic
            kineticAccent = .gold
            kineticIntensity = .balanced
            kineticLetterStyle = .automatic
            kineticOverlayStyle = .automatic
        case .minimal:
            fontName = "Lato-Bold"
            fontSize = 58
            marginV = 100
            karaokeMode = .classic
            lyricTrackingMode = .off
            kineticAccent = .ice
            kineticLetterStyle = .clean
            kineticOverlayStyle = .none
        case .karaoke:
            fontName = "Montserrat-ExtraBold"
            fontSize = 68
            marginV = 120
            karaokeMode = .classic
            lyricTrackingMode = .karaoke
            kineticAccent = .gold
            kineticLetterStyle = .clean
            kineticOverlayStyle = .none
        case .viral:
            fontName = "ArchivoBlack-Regular"
            fontSize = 84
            marginV = 180
            karaokeMode = .kinetic
            lyricTrackingMode = .karaoke
            kineticStyle = .impact
            kineticAccent = .coral
            kineticIntensity = .energetic
            kineticLetterStyle = .rhythm
            kineticOverlayStyle = .spotlight
        case .podcast:
            fontName = "Poppins-Bold"
            fontSize = 72
            marginV = 210
            karaokeMode = .classic
            lyricTrackingMode = .boldWord
            kineticAccent = .gold
            kineticIntensity = .balanced
            kineticLetterStyle = .clean
            kineticOverlayStyle = .none
        case .cinematic:
            fontName = "PlayfairDisplayRoman-Black"
            fontSize = 64
            marginV = 145
            karaokeMode = .kinetic
            lyricTrackingMode = .off
            kineticStyle = .cinematic
            kineticAccent = .ice
            kineticIntensity = .subtle
            kineticLetterStyle = .clean
            kineticOverlayStyle = .cinematicBand
        case .neon:
            fontName = "Poppins-Bold"
            fontSize = 76
            marginV = 165
            karaokeMode = .kinetic
            lyricTrackingMode = .karaoke
            kineticStyle = .editorial
            kineticAccent = .violet
            kineticIntensity = .balanced
            kineticLetterStyle = .poster
            kineticOverlayStyle = .glass
        }
    }

    private func trackingTitle(_ mode: LyricTrackingMode) -> String {
        switch mode {
        case .off: return "Kapalı"
        case .karaoke: return "Harf Takibi"
        case .boldWord: return "Cümle + Kalın"
        case .centeredReveal: return "Harf Harf"
        case .centeredWordReveal: return "Kelime Kelime"
        }
    }

    private var trackingDetail: String {
        switch lyricTrackingMode {
        case .off:
            return "Cümle zamanında görünür; söylenen bölüm ayrıca işaretlenmez."
        case .karaoke:
            return karaokeMode == .classic
                ? "Cümle sabit kalır; vokal ilerledikçe harfler soldan sağa takip edilir."
                : "Kinetik kompozisyon içinde söylenen kelime zamanına göre takip edilir."
        case .boldWord:
            return "Tam cümle sabit kalır; aktif kelime aynı konumda Bold ve seçilen renkte görünür."
        case .centeredReveal:
            return "Harfler tek tek gelir; büyüyen cümle sürekli ortada kalır."
        case .centeredWordReveal:
            return "Kelimeler birer parça halinde gelir; cümle sürekli ortada kalır."
        }
    }

    private var availableOverlays: [KineticOverlayStyle] {
        KineticOverlayStyle.allCases.filter {
            $0.isAvailable(for: lyricTrackingMode)
        }
    }

    private var boldWordReadabilityControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingTitle("Okunabilirlik", icon: "shadow")

            Toggle(
                isOn: Binding(
                    get: { kineticOverlayStyle == .underShadow },
                    set: { enabled in
                        Theme.haptic()
                        kineticOverlayStyle = enabled ? .underShadow : .none
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alt Gölge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Tüm cümle bloğunun arkasına sabit, yumuşak koyu bir gölge ekler.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .tint(Theme.yellow)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        }
    }

    private var usesKineticDirectorControls: Bool {
        karaokeMode == .kinetic
            && !lyricTrackingMode.isProgressiveReveal
            && lyricTrackingMode != .boldWord
    }

    private var usesDedicatedTrackingLayout: Bool {
        lyricTrackingMode.isProgressiveReveal || lyricTrackingMode == .boldWord
    }

    private var showsAccentControls: Bool {
        if lyricTrackingMode.isProgressiveReveal || lyricTrackingMode == .boldWord {
            return true
        }
        guard karaokeMode == .kinetic else { return false }
        return lyricTrackingMode == .karaoke || kineticOverlayStyle != .none
    }

    private var resolvedTextColor: KineticResolvedColor {
        KineticResolvedColor(hex: subtitleTextColorHex)
    }

    private var resolvedTextColorColor: Color {
        Color(
            red: resolvedTextColor.red,
            green: resolvedTextColor.green,
            blue: resolvedTextColor.blue
        )
    }

    private func previewColor(for hex: String) -> Color {
        let color = KineticResolvedColor(hex: hex)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private var resolvedAccent: KineticResolvedColor {
        kineticAccent.resolvedColor(customHex: kineticCustomColorHex)
    }

    private var resolvedAccentColor: Color {
        Color(red: resolvedAccent.red, green: resolvedAccent.green, blue: resolvedAccent.blue)
    }

    private func color(for accent: KineticAccent) -> Color {
        let rgb = accent.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { resolvedAccentColor },
            set: { color in
                let components = UIColor(color).cgColor.components ?? [1, 1, 1, 1]
                let red: CGFloat
                let green: CGFloat
                let blue: CGFloat
                if components.count >= 3 {
                    red = components[0]
                    green = components[1]
                    blue = components[2]
                } else {
                    red = components[0]
                    green = components[0]
                    blue = components[0]
                }
                kineticCustomColorHex = String(
                    format: "#%02X%02X%02X",
                    Int((red * 255).rounded()),
                    Int((green * 255).rounded()),
                    Int((blue * 255).rounded())
                )
                kineticAccent = .custom
            }
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { resolvedTextColorColor },
            set: { color in
                let components = UIColor(color).cgColor.components ?? [1, 1, 1, 1]
                let red: CGFloat
                let green: CGFloat
                let blue: CGFloat
                if components.count >= 3 {
                    red = components[0]
                    green = components[1]
                    blue = components[2]
                } else {
                    red = components[0]
                    green = components[0]
                    blue = components[0]
                }
                subtitleTextColorHex = String(
                    format: "#%02X%02X%02X",
                    Int((red * 255).rounded()),
                    Int((green * 255).rounded()),
                    Int((blue * 255).rounded())
                )
            }
        )
    }
}

struct CompactFontPicker: View {
    let fonts: [FontOption]
    @Binding var selection: String
    let karaokeMode: KaraokeMode
    let kineticStyle: KineticStyle
    var sampleText: String = "Sesini görünür kıl"

    @State private var showsLibrary = false
    @AppStorage("subtitle.favoriteFontIDs") private var favoriteFontIDsRaw = ""
    @AppStorage("subtitle.recentFontIDs") private var recentFontIDsRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Font", systemImage: "textformat")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(fonts.count) seçenek")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Button {
                Theme.haptic()
                showsLibrary = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(previewSample)
                        .font(.custom(selectedFont.psName, size: 24))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    HStack(spacing: 7) {
                        ForEach(selectedFont.availableWeights) { weight in
                            Text(weight.title)
                                .font(
                                    .custom(
                                        selectedFont.faceName(for: weight),
                                        size: 11
                                    )
                                )
                                .fontWeight(previewWeight(for: selectedFont, weight: weight))
                                .foregroundColor(weight == .bold ? Theme.yellow : .gray)
                                .padding(.horizontal, 7)
                                .frame(minHeight: 28)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.06))
                                )
                        }
                    }

                    HStack(spacing: 8) {
                        Text(selectedFont.display)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.yellow)
                        Text(selectedFont.category.title)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("Kütüphaneyi Aç")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.yellow)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Font, \(selectedFont.display)")
            .accessibilityHint("Font kütüphanesini açar.")

            if !recommendedFonts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Önerilen")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        ForEach(recommendedFonts.prefix(4)) { font in
                            Button {
                                Theme.haptic()
                                selection = font.psName
                                recordRecent(font.psName)
                            } label: {
                                Text(font.display)
                                    .font(.custom(font.psName, size: 13))
                                    .foregroundColor(selection == font.psName ? .black : .white)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 44)
                                    .background(
                                        Capsule()
                                            .fill(selection == font.psName ? Theme.yellow : Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection == font.psName ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsLibrary) {
            FontLibrarySheet(
                selection: $selection,
                favoriteFontIDsRaw: $favoriteFontIDsRaw,
                recentFontIDsRaw: $recentFontIDsRaw,
                sampleText: previewSample,
                karaokeMode: karaokeMode,
                kineticStyle: kineticStyle
            )
        }
        .onChange(of: selection) {
            recordRecent(selection)
        }
    }

    private var selectedFont: FontOption {
        fonts.first(where: { $0.psName == selection })
            ?? FontCatalog.secenek(selection)
            ?? fonts.first
            ?? FontOption(
                psName: "Helvetica-Bold",
                display: "Helvetica",
                assFamily: "Helvetica",
                kalin: true,
                category: .modern
            )
    }

    private var previewSample: String {
        let clean = sampleText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Sesini görünür kıl" : String(clean.prefix(34))
    }

    private var recommendedFonts: [FontOption] {
        let allowed = Set(fonts.map(\.psName))
        return FontCatalog.onerilen(karaokeMode: karaokeMode, kineticStyle: kineticStyle)
            .filter { allowed.contains($0.psName) }
    }

    private func recordRecent(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = recentFontIDsRaw.split(separator: "|").map(String.init)
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        recentFontIDsRaw = ids.prefix(8).joined(separator: "|")
    }

    private func previewWeight(
        for font: FontOption,
        weight: SubtitleFontWeight
    ) -> Font.Weight? {
        guard !font.hasRealFace(for: weight) else { return nil }
        switch weight {
        case .thin: return .regular
        case .regular: return .regular
        case .bold: return .bold
        }
    }
}

private enum FontLibraryFilter: String, CaseIterable, Identifiable {
    case recommended
    case favorites
    case recent
    case all
    case modern
    case poster
    case serif
    case handwriting
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Önerilen"
        case .favorites: return "Favoriler"
        case .recent: return "Son"
        case .all: return "Tümü"
        case .modern: return FontCategory.modern.title
        case .poster: return FontCategory.poster.title
        case .serif: return FontCategory.serif.title
        case .handwriting: return FontCategory.handwriting.title
        case .custom: return FontCategory.custom.title
        }
    }

    var category: FontCategory? {
        switch self {
        case .modern: return .modern
        case .poster: return .poster
        case .serif: return .serif
        case .handwriting: return .handwriting
        case .custom: return .custom
        case .recommended, .favorites, .recent, .all: return nil
        }
    }
}

private struct FontLibrarySheet: View {
    @Binding var selection: String
    @Binding var favoriteFontIDsRaw: String
    @Binding var recentFontIDsRaw: String
    let sampleText: String
    let karaokeMode: KaraokeMode
    let kineticStyle: KineticStyle

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var customFonts = CustomFontStore.shared
    @State private var filter: FontLibraryFilter = .recommended
    @State private var searchText = ""
    @State private var showsFontImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        categoryFilters

                        if filteredFonts.isEmpty {
                            ContentUnavailableView(
                                emptyTitle,
                                systemImage: filter == .custom ? "text.badge.plus" : "text.magnifyingglass",
                                description: Text(emptyDetail)
                            )
                            .foregroundStyle(.white, .gray)
                            .frame(maxWidth: .infinity, minHeight: 260)
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)
                                ],
                                spacing: 10
                            ) {
                                ForEach(filteredFonts) { font in
                                    fontCard(font)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Font Kütüphanesi")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Font ara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsFontImporter = true
                    } label: {
                        Label("Font Ekle", systemImage: "plus")
                    }
                    .foregroundColor(Theme.yellow)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                        .foregroundColor(Theme.yellow)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showsFontImporter,
            allowedContentTypes: allowedFontTypes,
            allowsMultipleSelection: false
        ) { result in
            importFont(result)
        }
        .alert("Font Kütüphanesi", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FontLibraryFilter.allCases) { value in
                    let selected = filter == value
                    Button {
                        Theme.haptic()
                        filter = value
                    } label: {
                        Text(value.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selected ? .black : .white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                Capsule()
                                    .fill(selected ? Theme.yellow : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fontCard(_ font: FontOption) -> some View {
        let selected = selection == font.psName
        let favorite = favoriteIDs.contains(font.psName)
        return ZStack(alignment: .topTrailing) {
            Button {
                Theme.haptic()
                selection = font.psName
                recordRecent(font.psName)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sampleText)
                        .font(.custom(font.psName, size: 20))
                        .foregroundColor(selected ? Theme.yellow : .white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

                    HStack(spacing: 5) {
                        Text(font.display)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(selected ? Theme.yellow : .gray)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            ForEach(font.availableWeights) { weight in
                                Text(weight == .thin ? "T" : (weight == .regular ? "R" : "B"))
                                    .font(.custom(font.faceName(for: weight), size: 10))
                                    .fontWeight(previewWeight(for: font, weight: weight))
                                    .foregroundColor(
                                        weight == .bold ? Theme.yellow : .gray
                                    )
                            }
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(selected ? 0.10 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(selected ? Theme.yellow : Theme.cardStroke, lineWidth: selected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(font.display)
            .accessibilityAddTraits(selected ? .isSelected : [])

            HStack(spacing: 0) {
                if font.sourceFileName != nil {
                    Button(role: .destructive) {
                        if selection == font.psName { selection = "Montserrat-ExtraBold" }
                        customFonts.remove(font)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Özel fontu sil")
                }

                Button {
                    toggleFavorite(font.psName)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(favorite ? Theme.yellow : .gray)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? "Favorilerden çıkar" : "Favorilere ekle")
            }
            .padding(3)
        }
    }

    private var allFonts: [FontOption] { FontCatalog.hepsi }

    private var filteredFonts: [FontOption] {
        let base: [FontOption]
        switch filter {
        case .recommended:
            let ids = FontCatalog.onerilen(
                karaokeMode: karaokeMode,
                kineticStyle: kineticStyle
            ).map(\.psName)
            base = orderedFonts(ids: ids)
        case .favorites:
            base = orderedFonts(ids: Array(favoriteIDs))
        case .recent:
            base = orderedFonts(ids: recentIDs)
        case .all:
            base = allFonts
        case .modern, .poster, .serif, .handwriting, .custom:
            base = allFonts.filter { $0.category == filter.category }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.display.localizedCaseInsensitiveContains(query)
                || $0.psName.localizedCaseInsensitiveContains(query)
        }
    }

    private var favoriteIDs: Set<String> {
        Set(favoriteFontIDsRaw.split(separator: "|").map(String.init))
    }

    private var recentIDs: [String] {
        recentFontIDsRaw.split(separator: "|").map(String.init)
    }

    private func orderedFonts(ids: [String]) -> [FontOption] {
        let byID = Dictionary(uniqueKeysWithValues: allFonts.map { ($0.psName, $0) })
        return ids.compactMap { byID[$0] }
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteFontIDsRaw = ids.sorted().joined(separator: "|")
        Theme.haptic()
    }

    private func recordRecent(_ id: String) {
        var ids = recentIDs
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        recentFontIDsRaw = ids.prefix(8).joined(separator: "|")
    }

    private func previewWeight(
        for font: FontOption,
        weight: SubtitleFontWeight
    ) -> Font.Weight? {
        guard !font.hasRealFace(for: weight) else { return nil }
        switch weight {
        case .thin: return .regular
        case .regular: return .regular
        case .bold: return .bold
        }
    }

    private var allowedFontTypes: [UTType] {
        ["ttf", "otf"].compactMap { UTType(filenameExtension: $0) }
    }

    private func importFont(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw CustomFontStoreError.unreadableFont
            }
            let imported = try customFonts.importFont(from: url)
            selection = imported.psName
            recordRecent(imported.psName)
            filter = .custom
            importMessage = "\(imported.display) eklendi. Ön izleme ve final videoda aynı font kullanılacak."
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private var emptyTitle: String {
        if filter == .favorites { return "Favori font yok" }
        if filter == .recent { return "Son kullanılan font yok" }
        if filter == .custom { return "Özel font eklenmedi" }
        return "Font bulunamadı"
    }

    private var emptyDetail: String {
        if filter == .custom {
            return "Kullanım hakkına sahip olduğun .ttf veya .otf dosyasını Font Ekle ile içe aktar."
        }
        return "Aramayı veya filtreyi değiştir."
    }
}
