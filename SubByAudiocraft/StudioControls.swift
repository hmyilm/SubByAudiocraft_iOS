import Foundation
import SwiftUI
import UIKit

// Tasarım ekranının hızlı başlangıç seçenekleri. Bunlar yeni bir render modu
// oluşturmaz; mevcut ve test edilmiş ayarları anlaşılır paketler halinde uygular.
private enum StudioPreset: String, CaseIterable, Identifiable {
    case automatic
    case clean
    case cinematic
    case energetic
    case shadow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Akıllı"
        case .clean: return "Temiz"
        case .cinematic: return "Sinematik"
        case .energetic: return "Enerjik"
        case .shadow: return "Alt Gölge"
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .clean: return "captions.bubble"
        case .cinematic: return "film"
        case .energetic: return "bolt.fill"
        case .shadow: return "shadow"
        }
    }
}

struct StudioTypographyControls: View {
    let fontName: String
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

            if usesKineticDirectorControls {
                kineticStyleControls
            }

            if showsAccentControls {
                accentControls
            }

            if usesKineticDirectorControls {
                advancedControls
            }
        }
        .onChange(of: lyricTrackingMode) { mode in
            if mode != .karaoke, kineticOverlayStyle.requiresKaraokeTracking {
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

            Text("Akıllı görünüm parçanın bölümlerine göre uyumlu kompozisyonları otomatik yönetir.")
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
        if karaokeMode == .classic && lyricTrackingMode == .karaoke {
            return .clean
        }
        guard karaokeMode == .kinetic, lyricTrackingMode == .karaoke else { return nil }
        if kineticStyle == .automatic &&
            kineticIntensity == .balanced &&
            kineticLetterStyle == .automatic &&
            kineticOverlayStyle == .automatic {
            return .automatic
        }
        if kineticStyle == .cinematic &&
            kineticIntensity == .subtle &&
            kineticLetterStyle == .clean &&
            kineticOverlayStyle == .cinematicBand {
            return .cinematic
        }
        if kineticStyle == .impact &&
            kineticIntensity == .energetic &&
            kineticLetterStyle == .rhythm &&
            kineticOverlayStyle == .spotlight {
            return .energetic
        }
        if kineticStyle == .cinematic &&
            kineticIntensity == .subtle &&
            kineticLetterStyle == .clean &&
            kineticOverlayStyle == .underShadow {
            return .shadow
        }
        return nil
    }

    private func apply(_ preset: StudioPreset) {
        lyricTrackingMode = .karaoke
        switch preset {
        case .automatic:
            karaokeMode = .kinetic
            kineticStyle = .automatic
            kineticIntensity = .balanced
            kineticLetterStyle = .automatic
            kineticOverlayStyle = .automatic
        case .clean:
            karaokeMode = .classic
            kineticLetterStyle = .clean
            kineticOverlayStyle = .none
        case .cinematic:
            karaokeMode = .kinetic
            kineticStyle = .cinematic
            kineticIntensity = .subtle
            kineticLetterStyle = .clean
            kineticOverlayStyle = .cinematicBand
        case .energetic:
            karaokeMode = .kinetic
            kineticStyle = .impact
            kineticIntensity = .energetic
            kineticLetterStyle = .rhythm
            kineticOverlayStyle = .spotlight
        case .shadow:
            karaokeMode = .kinetic
            kineticStyle = .cinematic
            kineticIntensity = .subtle
            kineticLetterStyle = .clean
            kineticOverlayStyle = .underShadow
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
            return "Tam cümle sabit kalır; aktif kelime Regular kopyanın yerini alır, Bold ve %4 büyük olarak seçilen renkte görünür."
        case .centeredReveal:
            return "Harfler tek tek gelir; büyüyen cümle sürekli ortada kalır."
        case .centeredWordReveal:
            return "Kelimeler birer parça halinde gelir; cümle sürekli ortada kalır."
        }
    }

    private var availableOverlays: [KineticOverlayStyle] {
        KineticOverlayStyle.allCases.filter {
            !$0.requiresKaraokeTracking || lyricTrackingMode == .karaoke
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
}

struct CompactFontPicker: View {
    let fonts: [FontOption]
    @Binding var selection: String
    let karaokeMode: KaraokeMode
    let kineticStyle: KineticStyle

    @State private var showsLibrary = false

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
                HStack(spacing: 12) {
                    Text("AaŞ")
                        .font(.custom(selectedFont.psName, size: 28))
                        .foregroundColor(Theme.yellow)
                        .frame(width: 56)
                        .frame(minHeight: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedFont.display)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(selectedFont.category.title)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Text("Değiştir")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.yellow)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 58)
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
                HStack(spacing: 8) {
                    Text("Önerilen")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    ForEach(recommendedFonts.prefix(3)) { font in
                        Button {
                            Theme.haptic()
                            selection = font.psName
                        } label: {
                            Text(font.display)
                                .font(.caption2.weight(.semibold))
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
        .sheet(isPresented: $showsLibrary) {
            FontLibrarySheet(fonts: fonts, selection: $selection)
        }
    }

    private var selectedFont: FontOption {
        fonts.first(where: { $0.psName == selection })
            ?? fonts.first
            ?? FontOption(
                psName: "Helvetica-Bold",
                display: "Helvetica",
                assFamily: "Helvetica",
                kalin: true,
                category: .modern
            )
    }

    private var recommendedFonts: [FontOption] {
        let allowed = Set(fonts.map(\.psName))
        return FontCatalog.onerilen(karaokeMode: karaokeMode, kineticStyle: kineticStyle)
            .filter { allowed.contains($0.psName) }
    }
}

private struct FontLibrarySheet: View {
    let fonts: [FontOption]
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var filter: FontCategory?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        categoryFilters

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
                    .padding(16)
                }
            }
            .navigationTitle("Font Seç")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Font ara")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                        .foregroundColor(Theme.yellow)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: "Tümü", category: nil)
                ForEach(FontCategory.allCases) { category in
                    categoryButton(title: category.title, category: category)
                }
            }
        }
    }

    private func categoryButton(title: String, category: FontCategory?) -> some View {
        let selected = filter == category
        return Button {
            Theme.haptic()
            filter = category
        } label: {
            Text(title)
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

    private func fontCard(_ font: FontOption) -> some View {
        let selected = selection == font.psName
        return Button {
            Theme.haptic()
            selection = font.psName
        } label: {
            VStack(spacing: 7) {
                Text("AaŞğ")
                    .font(.custom(font.psName, size: 28))
                    .foregroundColor(selected ? Theme.yellow : .white)
                Text(font.display)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(selected ? Theme.yellow : .gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
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
    }

    private var filteredFonts: [FontOption] {
        fonts.filter { font in
            let categoryMatches = filter == nil || font.category == filter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatches = query.isEmpty ||
                font.display.localizedCaseInsensitiveContains(query)
            return categoryMatches && searchMatches
        }
    }
}
