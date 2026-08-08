import Foundation
import SwiftUI
import AVKit
import UIKit

// MARK: - Ana üretim akışı
struct StepIndicator: View {
    let currentIndex: Int
    private let steps = ["Video", "Sözler", "Tasarım", "Kaydet"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                stepCircle(index)
                if index < 3 {
                    Rectangle()
                        .fill(index < currentIndex ? Theme.yellow : Color(white: 0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 15)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func stepCircle(_ index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if index == currentIndex {
                    Circle()
                        .stroke(Theme.yellow, lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
                Circle()
                    .fill(index < currentIndex ? Theme.yellow : Color(white: 0.16))
                    .frame(width: 26, height: 26)
                if index < currentIndex {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.black)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(index == currentIndex ? Theme.yellow : .gray)
                }
            }
            .frame(width: 32, height: 32)
            Text(steps[index])
                .font(.caption2)
                .foregroundColor(index == currentIndex ? Theme.yellow : .gray)
        }
        .frame(width: 52)
    }
}

// MARK: - Durum Banner'ı (başarı / hata / bilgi)
// Hata durumunda ham teknik log doğrudan gösterilmez; "Teknik Detay" altında gizlenir.
struct StatusBanner: View {
    let message: String

    @State private var showDetails = false

    private enum Kind { case error, success, info }

    private var kind: Kind {
        if message.hasPrefix("Hata:") { return .error }
        if message.contains("🎉") || message.contains("başarıyla") { return .success }
        return .info
    }

    private var summary: String {
        if kind == .error && message.count > 140 {
            return String(message.prefix(140)) + "…"
        }
        return message
    }

    private var logFileURL: URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hata_kaydi.txt")
        try? message.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundColor(color)
                Text(summary)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if kind == .error {
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView {
                            Text(message)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 140)

                        HStack(spacing: 16) {
                            Button {
                                UIPasteboard.general.string = message
                            } label: {
                                Label("Kopyala", systemImage: "doc.on.doc")
                            }
                            if let url = logFileURL {
                                ShareLink(item: url) {
                                    Label("Paylaş", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.yellow)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Teknik Detay")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch kind {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .error: return .red
        case .success: return .green
        case .info: return .gray
        }
    }
}

private enum FontPickerFilter: String, CaseIterable, Identifiable {
    case recommended
    case modern
    case poster
    case serif
    case handwriting
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Önerilen"
        case .modern: return FontCategory.modern.title
        case .poster: return FontCategory.poster.title
        case .serif: return FontCategory.serif.title
        case .handwriting: return FontCategory.handwriting.title
        case .all: return "Tümü"
        }
    }
}

// MARK: - Küratörlü Font Seçici
struct FontChipPicker: View {
    let fonts: [FontOption]
    @Binding var selection: String
    let karaokeMode: KaraokeMode
    let kineticStyle: KineticStyle

    @State private var filter: FontPickerFilter = .recommended

    init(
        fonts: [FontOption],
        selection: Binding<String>,
        karaokeMode: KaraokeMode,
        kineticStyle: KineticStyle
    ) {
        self.fonts = fonts
        self._selection = selection
        self.karaokeMode = karaokeMode
        self.kineticStyle = kineticStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "textformat")
                    .font(.caption)
                    .foregroundColor(Theme.yellow)
                Text("Font Kütüphanesi")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(fonts.count) Türkçe uyumlu font")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(FontPickerFilter.allCases) { item in
                        let isSelected = item == filter
                        Button {
                            Theme.haptic()
                            filter = item
                        } label: {
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(isSelected ? .black : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Theme.yellow : Color(white: 0.13))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.clear : Theme.cardStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let best = recommendedFonts.first {
                HStack(spacing: 9) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundColor(Theme.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendationTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                        Text(best.display)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button {
                        Theme.haptic()
                        selection = best.psName
                        filter = .recommended
                    } label: {
                        Text(selection == best.psName ? "Uygulandı" : "Uygula")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(selection == best.psName ? .green : Theme.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selection == best.psName)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.yellow.opacity(0.07))
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visibleFonts) { font in
                        fontButton(font)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var recommendedFonts: [FontOption] {
        let allowed = Set(fonts.map(\.psName))
        return FontCatalog.onerilen(
            karaokeMode: karaokeMode,
            kineticStyle: kineticStyle
        )
        .filter { allowed.contains($0.psName) }
    }

    private var visibleFonts: [FontOption] {
        let filtered: [FontOption]
        switch filter {
        case .recommended:
            filtered = recommendedFonts
        case .modern:
            filtered = fonts.filter { $0.category == .modern }
        case .poster:
            filtered = fonts.filter { $0.category == .poster }
        case .serif:
            filtered = fonts.filter { $0.category == .serif }
        case .handwriting:
            filtered = fonts.filter { $0.category == .handwriting }
        case .all:
            filtered = fonts
        }

        guard
            let selected = fonts.first(where: { $0.psName == selection }),
            !filtered.contains(where: { $0.psName == selected.psName })
        else {
            return filtered
        }

        return [selected] + filtered
    }

    private var recommendationTitle: String {
        if karaokeMode == .classic {
            return "Klasik karaoke için güvenli başlangıç"
        }
        return "\(kineticStyle.title) yönetmen için ana font"
    }

    private func fontButton(_ font: FontOption) -> some View {
        let isSelected = font.psName == selection
        let isRecommended = recommendedFonts.contains { $0.psName == font.psName }

        return Button {
            Theme.haptic()
            selection = font.psName
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Text("AaŞ")
                        .font(.custom(font.psName, size: 22))
                        .foregroundColor(isSelected ? Theme.yellow : .white)
                    if isRecommended {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.yellow)
                    }
                }
                Text(font.display)
                    .font(.caption2)
                    .foregroundColor(isSelected ? Theme.yellow : .gray)
                    .lineLimit(1)
            }
            .frame(minWidth: 84)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: isSelected ? 0.16 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Theme.yellow : Theme.cardStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Karaoke / Kinetik Tipografi Modu
struct KaraokeModePicker: View {
    @Binding var selection: KaraokeMode
    @Binding var lyricTrackingMode: LyricTrackingMode
    @Binding var kineticStyle: KineticStyle
    @Binding var kineticAccent: KineticAccent
    @Binding var kineticCustomColorHex: String
    @Binding var kineticIntensity: KineticIntensity
    @Binding var kineticLetterStyle: KineticLetterStyle
    @Binding var kineticOverlayStyle: KineticOverlayStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "textformat.alt")
                    .font(.caption)
                    .foregroundColor(Theme.yellow)
                Text("Yazı Hareketi")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            Picker("Yazı Hareketi", selection: $selection) {
                ForEach(KaraokeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selection.detail)
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                Text("Söz Takibi")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 7),
                        GridItem(.flexible(), spacing: 7)
                    ],
                    spacing: 7
                ) {
                    ForEach(LyricTrackingMode.allCases) { mode in
                        let isSelected = mode == lyricTrackingMode
                        Button {
                            Theme.haptic()
                            lyricTrackingMode = mode
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.caption.weight(.semibold))
                                Text(mode.title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .foregroundColor(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? Theme.yellow
                                            : Color.white.opacity(0.08)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(lyricTrackingMode.detail)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)

                if lyricTrackingMode.isProgressiveReveal {
                    Label(
                        "\(lyricTrackingMode.title) seçiliyken karaoke vurgusu kapanır; seçilen font ve vurgu rengi korunur.",
                        systemImage: "arrow.left.and.right.text.vertical"
                    )
                    .font(.caption2)
                    .foregroundColor(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )

            if selection == .kinetic {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kinetik Yönetmen")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)

                    if lyricTrackingMode.isProgressiveReveal {
                        Label(
                            "Merkez akışında sahne, yoğunluk, harf tasarımı ve overlay yerine temiz cümle hareketi kullanılır. Font ve vurgu rengi etkin kalır.",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption2)
                        .foregroundColor(Theme.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                    } else if lyricTrackingMode == .boldWord {
                        Label(
                            "Cümle + Kalın seçiliyken tam cümle sabit kalır. Kinetik sahne düzeni kapanır; fontun Bold davranışı ve seçilen vurgu rengi etkin kalır.",
                            systemImage: "bold"
                        )
                        .font(.caption2)
                        .foregroundColor(Theme.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Group {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(KineticStyle.allCases) { style in
                                    let isSelected = style == kineticStyle
                                    Button {
                                        Theme.haptic()
                                        kineticStyle = style
                                    } label: {
                                        Label(style.title, systemImage: style.icon)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(isSelected ? .black : .white)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? Theme.yellow : Color.white.opacity(0.08))
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(
                                                        isSelected ? Theme.yellow : Theme.cardStroke,
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Text(kineticStyle.detail)
                            .font(.caption2)
                            .foregroundColor(Theme.yellow.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Hareket Yoğunluğu")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)

                            Picker("Hareket Yoğunluğu", selection: $kineticIntensity) {
                                ForEach(KineticIntensity.allCases) { intensity in
                                    Text(intensity.title).tag(intensity)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(kineticIntensity.detail)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Harf Tasarımı")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(KineticLetterStyle.allCases) { letterStyle in
                                        let isSelected = letterStyle == kineticLetterStyle
                                        Button {
                                            Theme.haptic()
                                            kineticLetterStyle = letterStyle
                                        } label: {
                                            Label(letterStyle.title, systemImage: letterStyle.icon)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(isSelected ? .black : .white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(
                                                    Capsule()
                                                        .fill(
                                                            isSelected
                                                                ? Theme.yellow
                                                                : Color.white.opacity(0.08)
                                                        )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Text(kineticLetterStyle.detail)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Arka Katman / Overlay")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(KineticOverlayStyle.allCases) { overlayStyle in
                                        let isSelected = overlayStyle == kineticOverlayStyle
                                        let isAvailable = !overlayStyle.requiresKaraokeTracking
                                            || lyricTrackingMode == .karaoke
                                        Button {
                                            Theme.haptic()
                                            kineticOverlayStyle = overlayStyle
                                        } label: {
                                            Label(overlayStyle.title, systemImage: overlayStyle.icon)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(isSelected ? .black : .white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(
                                                    Capsule()
                                                        .fill(
                                                            isSelected
                                                                ? Theme.yellow
                                                                : Color.white.opacity(0.08)
                                                        )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!isAvailable)
                                        .opacity(isAvailable ? 1 : 0.38)
                                    }
                                }
                            }

                            Text(kineticOverlayStyle.detail)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)

                            if lyricTrackingMode != .karaoke {
                                Text("Spot ve Alt Gölge katmanları aktif kelimeyi izlediği için yalnız Karaoke söz takibinde kullanılabilir.")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .disabled(
                        lyricTrackingMode.isProgressiveReveal
                            || lyricTrackingMode == .boldWord
                    )
                    .opacity(
                        lyricTrackingMode.isProgressiveReveal
                            || lyricTrackingMode == .boldWord
                            ? 0.42
                            : 1
                    )

                    accentControls

                    Label(
                        lyricTrackingMode.isProgressiveReveal
                            ? "Akış modu seçilen fontu ve rengi kullanır; uygulanmayan seçenekler yukarıda pasif gösterilir."
                            : (
                                lyricTrackingMode == .boldWord
                                    ? "Normal cümle Regular çizilir. Aktif kelime varsa gerçek Bold kesitiyle, tek kesitli fontlarda kontrollü kalınlıkla ve seçilen renkle gösterilir."
                                    : "Overlay, vurgu rengi, harf tasarımı ve geçişler aynı sahne planından beslenir; rastgele üst üste bindirilmez."
                            ),
                        systemImage: lyricTrackingMode.isProgressiveReveal
                            || lyricTrackingMode == .boldWord
                            ? "checkmark.shield"
                            : "scope"
                    )
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else if lyricTrackingMode.isProgressiveReveal
                        || lyricTrackingMode == .boldWord {
                accentControls
                    .padding(.top, 2)
            }
        }
        .onChange(of: lyricTrackingMode) {
            if lyricTrackingMode != .karaoke, kineticOverlayStyle.requiresKaraokeTracking {
                kineticOverlayStyle = .none
            }
        }
    }

    @ViewBuilder
    private var accentControls: some View {
        VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Vurgu Rengi")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(
                                kineticAccent == .custom
                                    ? kineticAccent.title + " " + resolvedAccent.hex
                                    : kineticAccent.title
                            )
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(resolvedAccent.previewColor)
                        }

                        HStack(spacing: 10) {
                            ForEach(KineticAccent.presetCases) { accent in
                                let isSelected = accent == kineticAccent
                                Button {
                                    Theme.haptic()
                                    kineticAccent = accent
                                } label: {
                                    Circle()
                                        .fill(accent.previewColor(customHex: nil))
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    isSelected ? Color.white : Color.white.opacity(0.2),
                                                    lineWidth: isSelected ? 2.5 : 1
                                                )
                                        )
                                        .overlay {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .black))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                        .accessibilityLabel(accent.title)
                                }
                                .buttonStyle(.plain)
                            }

                            ColorPicker(
                                "Özel vurgu rengi",
                                selection: customColorBinding,
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(
                                        kineticAccent == .custom
                                            ? Color.white
                                            : Color.white.opacity(0.2),
                                        lineWidth: kineticAccent == .custom ? 2.5 : 1
                                    )
                                    .allowsHitTesting(false)
                            )
                            .accessibilityLabel("Özel vurgu rengi")
                        }

                        Text("Özel renk seçildiğinde aktif yazı rengi kontrasta göre otomatik siyah veya beyaz olur.")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resolvedAccent: KineticResolvedColor {
        kineticAccent.resolvedColor(customHex: kineticCustomColorHex)
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { KineticResolvedColor(hex: kineticCustomColorHex).previewColor },
            set: { color in
                let uiColor = UIColor(color)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard uiColor.getRed(
                    &red,
                    green: &green,
                    blue: &blue,
                    alpha: &alpha
                ) else {
                    return
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

// MARK: - İkonlu Slider Satırı
struct LabeledSlider: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var valueText: ((Double) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(Theme.yellow)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                ValueBadge(text: valueText?(value) ?? "\(Int(value))")
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.yellow)
                .accessibilityLabel(title)
                .accessibilityValue(valueText?(value) ?? "\(Int(value))")
        }
    }
}

// MARK: - Canlı Altyazı Ön İzlemeli Video Oynatıcı
struct SubtitlePreviewPlayer: View {
    let player: AVPlayer?
    let fontName: String
    let fontSize: Double
    let marginV: Double
    let sampleText: String
    let height: CGFloat
    let karaokeWords: [VideoProcessor.WordTimestamp]
    let inlineLineBreaks: Set<UUID>
    let playbackTime: Double
    let isMuted: Bool
    let karaokeMode: KaraokeMode
    let lyricTrackingMode: LyricTrackingMode
    let kineticStyle: KineticStyle
    let kineticAccent: KineticAccent
    let kineticCustomColorHex: String
    let kineticIntensity: KineticIntensity
    let kineticLetterStyle: KineticLetterStyle
    let kineticOverlayStyle: KineticOverlayStyle
    let kineticLineIndex: Int
    let kineticRepeatCount: Int
    let kineticScenePlan: KineticTypographyPlan?

    init(
        player: AVPlayer?,
        fontName: String,
        fontSize: Double,
        marginV: Double,
        sampleText: String,
        height: CGFloat,
        karaokeWords: [VideoProcessor.WordTimestamp] = [],
        inlineLineBreaks: Set<UUID> = [],
        playbackTime: Double = 0,
        isMuted: Bool = true,
        karaokeMode: KaraokeMode = .classic,
        lyricTrackingMode: LyricTrackingMode = .karaoke,
        kineticStyle: KineticStyle = .automatic,
        kineticAccent: KineticAccent = .gold,
        kineticCustomColorHex: String = KineticAccent.defaultCustomHex,
        kineticIntensity: KineticIntensity = .balanced,
        kineticLetterStyle: KineticLetterStyle = .clean,
        kineticOverlayStyle: KineticOverlayStyle = .none,
        kineticLineIndex: Int = 0,
        kineticRepeatCount: Int = 1,
        kineticScenePlan: KineticTypographyPlan? = nil
    ) {
        self.player = player
        self.fontName = fontName
        self.fontSize = fontSize
        self.marginV = marginV
        self.sampleText = sampleText
        self.height = height
        self.karaokeWords = karaokeWords
        self.inlineLineBreaks = inlineLineBreaks
        self.playbackTime = playbackTime
        self.isMuted = isMuted
        self.karaokeMode = karaokeMode
        self.lyricTrackingMode = lyricTrackingMode
        self.kineticStyle = kineticStyle
        self.kineticAccent = kineticAccent
        self.kineticCustomColorHex = kineticCustomColorHex
        self.kineticIntensity = kineticIntensity
        self.kineticLetterStyle = kineticLetterStyle
        self.kineticOverlayStyle = kineticOverlayStyle
        self.kineticLineIndex = kineticLineIndex
        self.kineticRepeatCount = kineticRepeatCount
        self.kineticScenePlan = kineticScenePlan
    }

    var body: some View {
        GeometryReader { geo in
            let viewport = VideoProcessor.shared.aspectFitRect(
                contentSize: player?.currentItem?.presentationSize ?? .zero,
                in: geo.size
            )
            let previewScale = viewport.height / 1080.0

            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.isMuted = isMuted
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                }

                // 1080p referans yüksekliğine göre ölçeklenmiş canlı altyazı bindirmesi
                if !karaokeWords.isEmpty || !sampleText.isEmpty {
                    Group {
                        if lyricTrackingMode.isProgressiveReveal {
                            let previewWords = karaokeWords.isEmpty ? sampleTimingWords : karaokeWords
                            let revealPlaybackTime = karaokeWords.isEmpty
                                ? samplePlaybackTime(
                                    words: previewWords,
                                    plan: VideoProcessor.shared.kineticTypographyPlan(
                                        for: previewWords,
                                        lineIndex: kineticLineIndex,
                                        style: kineticStyle,
                                        repeatCount: kineticRepeatCount
                                    )
                                )
                                : playbackTime
                            let revealAccent = kineticAccent.resolvedColor(
                                customHex: kineticCustomColorHex
                            ).previewColor
                            if lyricTrackingMode == .centeredWordReveal {
                                CenteredWordRevealPreview(
                                    words: previewWords,
                                    inlineLineBreaks: inlineLineBreaks,
                                    playbackTime: revealPlaybackTime,
                                    accent: revealAccent,
                                    fontName: fontName,
                                    fontSize: CGFloat(fontSize) * previewScale
                                )
                            } else {
                                CenteredRevealPreview(
                                    words: previewWords,
                                    inlineLineBreaks: inlineLineBreaks,
                                    playbackTime: revealPlaybackTime,
                                    accent: revealAccent
                                )
                            }
                        } else if karaokeMode == .kinetic
                                    && lyricTrackingMode != .boldWord {
                            let previewWords = karaokeWords.isEmpty ? sampleTimingWords : karaokeWords
                            let plan = kineticScenePlan
                                ?? VideoProcessor.shared.kineticTypographyPlan(
                                    for: previewWords,
                                    lineIndex: kineticLineIndex,
                                    style: kineticStyle,
                                    repeatCount: kineticRepeatCount
                                )
                            KineticPreviewLockup(
                                words: previewWords,
                                plan: plan,
                                fontName: fontName,
                                fontSize: fontSize,
                                playbackTime: karaokeWords.isEmpty
                                    ? samplePlaybackTime(words: previewWords, plan: plan)
                                    : playbackTime,
                                previewHeight: viewport.height,
                                accent: kineticAccent,
                                customColorHex: kineticCustomColorHex,
                                intensity: kineticIntensity,
                                letterStyle: kineticLetterStyle,
                                overlayStyle: kineticOverlayStyle,
                                trackingMode: lyricTrackingMode,
                                manualRows: manualKineticRows(for: previewWords)
                            )
                        } else if karaokeWords.isEmpty {
                            Text(sampleText)
                                .foregroundColor(.white)
                        } else {
                            VStack(spacing: max(1, viewport.height / 120)) {
                                ForEach(
                                    Array(classicPreviewRows.enumerated()),
                                    id: \.offset
                                ) { row in
                                    HStack(spacing: max(2, CGFloat(fontSize) * 0.28 * previewScale)) {
                                        ForEach(row.element) { word in
                                            if lyricTrackingMode == .karaoke {
                                                ClassicCharacterTrackingWord(
                                                    text: word.text,
                                                    start: word.start,
                                                    end: word.end,
                                                    playbackTime: playbackTime
                                                )
                                            } else {
                                                let isBoldActive = lyricTrackingMode == .boldWord
                                                    && playbackTime >= word.start
                                                    && playbackTime < word.end
                                                if lyricTrackingMode == .boldWord {
                                                    // Thin metnin ölçüsüne kurulan overlay, Georgia-Bold
                                                    // daha geniş olduğunda yazıyı sıkıştırıyordu. İki yüz
                                                    // aynı ZStack'te ölçülür; kutu büyük olan yüze göre sabit
                                                    // kalır ve yalnız görünürlük değişir.
                                                    ZStack {
                                                        Text(word.text)
                                                            .font(
                                                                .custom(
                                                                    thinPreviewFontName,
                                                                    size: CGFloat(fontSize) * previewScale
                                                                )
                                                            )
                                                            .fontWeight(
                                                                hasRealThinPreviewFace ? nil : .regular
                                                            )
                                                            .foregroundColor(.white)
                                                            .opacity(isBoldActive ? 0 : 1)

                                                        Text(word.text)
                                                            .font(
                                                                .custom(
                                                                    boldPreviewFontName,
                                                                    size: CGFloat(fontSize) * previewScale
                                                                )
                                                            )
                                                            .fontWeight(
                                                                hasRealBoldPreviewFace ? nil : .bold
                                                            )
                                                            .foregroundColor(resolvedPreviewAccent)
                                                            .opacity(isBoldActive ? 1 : 0)
                                                    }
                                                } else {
                                                    Text(word.text)
                                                        .font(
                                                            .custom(
                                                                fontName,
                                                                size: CGFloat(fontSize) * previewScale
                                                            )
                                                        )
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    }
                        .font(
                            .custom(
                                lyricTrackingMode == .boldWord
                                    ? thinPreviewFontName
                                    : fontName,
                                size: CGFloat(fontSize) * previewScale
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, max(1, 20 * previewScale))
                        .padding(.vertical, max(0.5, 5 * previewScale))
                        .background(
                            karaokeWords.isEmpty && karaokeMode == .classic
                                ? Color.black.opacity(0.6)
                                : Color.clear
                        )
                        .cornerRadius(max(1, 6 * previewScale))
                        .padding(.bottom, CGFloat(marginV) * previewScale)
                        .frame(
                            width: viewport.width,
                            height: viewport.height,
                            alignment: .bottom
                        )
                        .clipped()
                        .position(x: viewport.midX, y: viewport.midY)
                }
            }
        }
        .frame(height: height)
        .background(Color.black)
        .cornerRadius(14)
        .clipped()
    }

    private var classicPreviewRows: [[VideoProcessor.WordTimestamp]] {
        VideoProcessor.shared.visualLineGroups(
            for: karaokeWords,
            inlineLineBreaks: inlineLineBreaks
        )
    }

    private var regularPreviewFontName: String {
        FontCatalog.regularPSName(for: fontName)
    }

    private var boldPreviewFontName: String {
        FontCatalog.boldPSName(for: fontName) ?? regularPreviewFontName
    }

    private var thinPreviewFontName: String {
        FontCatalog.faceName(for: fontName, weight: .thin)
    }

    private var hasRealBoldPreviewFace: Bool {
        FontCatalog.boldPSName(for: fontName) != nil
    }

    private var hasRealThinPreviewFace: Bool {
        FontCatalog.thinPSName(for: fontName) != nil
    }

    private var resolvedPreviewAccent: Color {
        kineticAccent.resolvedColor(
            customHex: kineticCustomColorHex
        ).previewColor
    }

    private func manualKineticRows(
        for words: [VideoProcessor.WordTimestamp]
    ) -> [[Int]]? {
        let rows = VideoProcessor.shared.visualLineGroups(
            for: words,
            inlineLineBreaks: inlineLineBreaks
        )
        guard rows.count > 1 else { return nil }
        let indexByID = Dictionary(
            uniqueKeysWithValues: words.enumerated().map { ($0.element.id, $0.offset) }
        )
        return rows.map { row in
            row.compactMap { indexByID[$0.id] }
        }
    }

    private var sampleTimingWords: [VideoProcessor.WordTimestamp] {
        sampleText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .enumerated()
            .map { index, text in
                VideoProcessor.WordTimestamp(
                    text: text,
                    start: Double(index) * 0.35,
                    end: (Double(index) * 0.35) + 0.3
                )
            }
    }

    private func samplePlaybackTime(
        words: [VideoProcessor.WordTimestamp],
        plan: KineticTypographyPlan
    ) -> Double {
        guard words.indices.contains(plan.emphasisIndex) else { return words.first?.start ?? 0 }
        return words[plan.emphasisIndex].start + 0.05
    }
}

// Klasik harf takibinin canlı ön izlemesi. Söylenmemiş bölüm tam beyaz kalır;
// vokal ilerledikçe soldan sağa doğru dışa aktarımdaki gibi soluklaşır.
private struct ClassicCharacterTrackingWord: View {
    let text: String
    let start: Double
    let end: Double
    let playbackTime: Double

    private var progress: CGFloat {
        guard end > start else { return playbackTime >= end ? 1 : 0 }
        return CGFloat(min(1, max(0, (playbackTime - start) / (end - start))))
    }

    var body: some View {
        Text(text)
            .foregroundColor(.white.opacity(0.35))
            .overlay(alignment: .trailing) {
                Text(text)
                    .foregroundColor(.white)
                    .mask(alignment: .trailing) {
                        GeometryReader { geometry in
                            Rectangle()
                                .frame(
                                    width: geometry.size.width * max(0, 1 - progress)
                                )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
            }
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct CenteredRevealPreview: View {
    let words: [VideoProcessor.WordTimestamp]
    let inlineLineBreaks: Set<UUID>
    let playbackTime: Double
    let accent: Color

    var body: some View {
        (
            Text(reveal.leading)
                .foregroundColor(.white)
            +
            Text(reveal.latest)
                .foregroundColor(accent)
        )
            .lineLimit(2)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.09), value: reveal.full)
    }

    private var reveal: (leading: String, latest: String, full: String) {
        var text = ""
        var previousWordEndedVisualRow = false

        for word in words {
            let clean = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            guard playbackTime >= word.start else { break }

            if !text.isEmpty {
                text += previousWordEndedVisualRow ? "\n" : " "
            }

            let characters = Array(clean)
            let count: Int
            if playbackTime >= word.end {
                count = characters.count
            } else {
                let duration = max(0.05, word.end - word.start)
                let progress = min(1, max(0, (playbackTime - word.start) / duration))
                count = min(
                    characters.count,
                    max(1, Int(progress * Double(characters.count)) + 1)
                )
            }
            text += String(characters.prefix(count))

            if count < characters.count {
                break
            }
            previousWordEndedVisualRow = inlineLineBreaks.contains(word.id)
        }

        guard let latest = text.last else {
            return ("", "", "")
        }
        return (
            String(text.dropLast()),
            String(latest),
            text
        )
    }
}

// Kelime Akışı: sözcük harf harf yazılmaz; başlangıç zamanında bütünüyle gelir.
// HStack her eklemede yeniden merkezlendiği için önceki sözcükler doğal biçimde
// sola kayarken cümlenin görsel merkezi sabit kalır.
private struct CenteredWordRevealPreview: View {
    private struct RevealedWord: Identifiable {
        let id: UUID
        let text: String
    }

    let words: [VideoProcessor.WordTimestamp]
    let inlineLineBreaks: Set<UUID>
    let playbackTime: Double
    let accent: Color
    let fontName: String
    let fontSize: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(revealedRows.enumerated()), id: \.offset) { row in
                // Tek tek Text görünümleri dar alanda bağımsız küçülüyordu. Georgia
                // Bold, Regular'dan geniş olduğu için yalnız okunan kelime daha küçük
                // görünüyordu. Birleştirilmiş Text bütün satırı tek oranda ölçekler.
                revealedRowText(row.element)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.interpolate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(
            .spring(response: 0.24, dampingFraction: 0.82),
            value: revealedWords.count
        )
    }

    private var revealedWords: [RevealedWord] {
        words.compactMap { word in
            let clean = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, playbackTime >= word.start else { return nil }
            return RevealedWord(id: word.id, text: clean)
        }
    }

    private var revealedRows: [[RevealedWord]] {
        var rows: [[RevealedWord]] = []
        var current: [RevealedWord] = []
        for word in revealedWords {
            current.append(word)
            if inlineLineBreaks.contains(word.id), word.id != revealedWords.last?.id {
                rows.append(current)
                current = []
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private var thinFaceName: String {
        FontCatalog.faceName(for: fontName, weight: .thin)
    }

    private var boldFaceName: String {
        FontCatalog.faceName(for: fontName, weight: .bold)
    }

    private func revealedRowText(_ row: [RevealedWord]) -> Text {
        row.enumerated().reduce(Text("")) { result, item in
            let word = item.element
            let isLatest = word.id == revealedWords.last?.id
            let separator = item.offset == 0
                ? Text("")
                : Text("\u{00A0}")
                    .font(.custom(thinFaceName, size: fontSize))
                    .fontWeight(fallbackWeight(isLatest: false))
            let run = Text(word.text)
                .font(.custom(isLatest ? boldFaceName : thinFaceName, size: fontSize))
                .fontWeight(fallbackWeight(isLatest: isLatest))
                .foregroundColor(isLatest ? accent : .white)
            return result + separator + run
        }
    }

    private func fallbackWeight(isLatest: Bool) -> Font.Weight? {
        if isLatest {
            return FontCatalog.boldPSName(for: fontName) == nil ? .bold : nil
        }
        return FontCatalog.thinPSName(for: fontName) == nil ? .regular : nil
    }
}

private struct KineticPreviewLockup: View {
    let words: [VideoProcessor.WordTimestamp]
    let plan: KineticTypographyPlan
    let fontName: String
    let fontSize: Double
    let playbackTime: Double
    let previewHeight: CGFloat
    let accent: KineticAccent
    let customColorHex: String
    let intensity: KineticIntensity
    let letterStyle: KineticLetterStyle
    let overlayStyle: KineticOverlayStyle
    let trackingMode: LyricTrackingMode
    let manualRows: [[Int]]?

    private var playbackIndex: Int? {
        words.firstIndex { playbackTime >= $0.start && playbackTime < $0.end }
    }

    private var focusedIndex: Int {
        if let playbackIndex { return playbackIndex }
        if let past = words.lastIndex(where: { $0.start <= playbackTime }) { return past }
        return words.indices.contains(plan.emphasisIndex) ? plan.emphasisIndex : 0
    }

    private var visibleRows: [[Int]] {
        if let manualRows {
            return manualRows
        }
        if plan.scene == .focusCut || plan.scene == .impactSequence {
            return [[focusedIndex]]
        }
        if plan.scene == .captionWindow {
            let page = plan.pages.first(where: { $0.contains(focusedIndex) })
                ?? plan.pages.first
                ?? []
            return page.isEmpty ? [] : [page]
        }
        return plan.rows
    }

    var body: some View {
        VStack(spacing: max(3, previewHeight / 100)) {
            ForEach(Array(visibleRows.enumerated()), id: \.offset) { rowItem in
                HStack(spacing: max(2, previewHeight / 110)) {
                    ForEach(rowItem.element, id: \.self) { index in
                        if words.indices.contains(index) {
                            let word = words[index]
                            let isActive = trackingMode == .karaoke
                                && playbackTime >= word.start
                                && playbackTime < word.end
                            let isPast = trackingMode == .karaoke
                                && playbackTime >= word.end
                            let isBoldActive = trackingMode == .boldWord
                                && playbackTime >= word.start
                                && playbackTime < word.end
                            let glyphDesign = VideoProcessor.shared.kineticGlyphDesign(
                                text: word.text,
                                wordIndex: index,
                                plan: plan,
                                letterStyle: FontCatalog.secenek(fontName)?.bitisik == true
                                    ? .clean
                                    : letterStyle
                            )
                            let previewFontSize = scaledFontSize(
                                wordIndex: index,
                                rowIndex: rowItem.offset,
                                row: rowItem.element,
                                treatment: glyphDesign.treatment
                            )
                            KineticPreviewWordRun(
                                design: glyphDesign,
                                fontName: fontName,
                                baseFontSize: previewFontSize
                            )
                                .foregroundColor(
                                    isBoldActive
                                        ? .clear
                                        : (
                                            isActive
                                                ? (
                                                    plan.highlight == .pill
                                                        ? resolvedAccent.foregroundPreviewColor
                                                        : resolvedAccent.previewColor
                                                )
                                                : (isPast ? .white.opacity(0.35) : .white)
                                        )
                                )
                                .overlay {
                                    if isBoldActive {
                                        KineticPreviewWordRun(
                                            design: glyphDesign,
                                            fontName: fontName,
                                            baseFontSize: previewFontSize,
                                            fontWeight: .bold
                                        )
                                        .foregroundColor(resolvedAccent.previewColor)
                                    }
                                }
                                .padding(
                                    .horizontal,
                                    plan.highlight == .pill
                                        || resolvedOverlay.requiresKaraokeTracking ? 6 : 0
                                )
                                .padding(
                                    .vertical,
                                    plan.highlight == .pill
                                        || resolvedOverlay.requiresKaraokeTracking ? 3 : 0
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(
                                            activeWordBackground(isActive: isActive)
                                        )
                                )
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(
                                            isActive && plan.highlight == .underline
                                                ? resolvedAccent.previewColor
                                                : Color.clear
                                        )
                                        .frame(height: max(2, previewHeight / 135))
                                        .offset(y: max(2, previewHeight / 180))
                                }
                                .scaleEffect(isActive ? previewActiveScale : 1)
                                .shadow(
                                    color: isActive
                                        && plan.highlight == .glow
                                        && resolvedOverlay != .none
                                        ? resolvedAccent.previewColor.opacity(0.55)
                                        : (
                                            isActive && resolvedOverlay == .underShadow
                                                ? .black.opacity(0.8)
                                                : .clear
                                        ),
                                    radius: isActive
                                        && (
                                            (
                                                plan.highlight == .glow
                                                    && resolvedOverlay != .none
                                            )
                                                || resolvedOverlay == .underShadow
                                        )
                                        ? 4
                                        : 0,
                                    y: isActive && resolvedOverlay == .underShadow
                                        ? 4
                                        : 0
                                )
                                .transition(.asymmetric(
                                    insertion: .scale(scale: previewEntranceScale).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                }
                .frame(
                    maxWidth: usesSplitPreviewLayout || resolvedOverlay == .cinematicBand
                        ? .infinity
                        : nil,
                    alignment: previewRowAlignment(
                        rowIndex: rowItem.offset,
                        row: rowItem.element
                    )
                )
            }
        }
        .padding(.horizontal, groupOverlayHorizontalPadding)
        .padding(.vertical, groupOverlayVerticalPadding)
        .frame(
            maxWidth: resolvedOverlay == .cinematicBand ? .infinity : nil,
            alignment: .center
        )
        .background { groupOverlayBackground }
        .frame(maxWidth: .infinity, alignment: previewGroupAlignment)
        .animation(.easeOut(duration: previewAnimationDuration), value: focusedIndex)
    }

    private var resolvedAccent: KineticResolvedColor {
        accent.resolvedColor(customHex: customColorHex)
    }

    private var resolvedOverlay: KineticOverlayStyle {
        VideoProcessor.shared.resolvedKineticOverlayStyle(
            requested: overlayStyle,
            plan: plan,
            trackingMode: trackingMode
        )
    }

    private var groupOverlayHorizontalPadding: CGFloat {
        switch resolvedOverlay {
        case .glass: return max(10, previewHeight / 42)
        case .cinematicBand: return max(12, previewHeight / 36)
        case .accentPanel: return max(14, previewHeight / 34)
        case .automatic, .none, .spotlight, .underShadow: return 0
        }
    }

    private var groupOverlayVerticalPadding: CGFloat {
        switch resolvedOverlay {
        case .glass: return max(7, previewHeight / 64)
        case .cinematicBand: return max(10, previewHeight / 52)
        case .accentPanel: return max(9, previewHeight / 55)
        case .automatic, .none, .spotlight, .underShadow: return 0
        }
    }

    private func activeWordBackground(isActive: Bool) -> Color {
        guard isActive else { return .clear }
        if plan.highlight == .pill {
            return resolvedAccent.previewColor
        }
        if resolvedOverlay == .spotlight {
            let opacity: Double
            switch intensity {
            case .subtle: opacity = 0.34
            case .balanced: opacity = 0.46
            case .energetic: opacity = 0.56
            }
            return resolvedAccent.previewColor.opacity(opacity)
        }
        if resolvedOverlay == .underShadow {
            let opacity: Double
            switch intensity {
            case .subtle: opacity = 0.25
            case .balanced: opacity = 0.34
            case .energetic: opacity = 0.42
            }
            return Color.black.opacity(opacity)
        }
        return .clear
    }

    @ViewBuilder
    private var groupOverlayBackground: some View {
        switch resolvedOverlay {
        case .glass:
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 7, y: 4)
                Capsule()
                    .fill(resolvedAccent.previewColor.opacity(0.9))
                    .frame(width: max(28, previewHeight / 3.8), height: 2)
                    .padding(.leading, 12)
            }
        case .cinematicBand:
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.66))
                Rectangle()
                    .fill(resolvedAccent.previewColor.opacity(0.55))
                    .frame(height: 1)
            }
        case .accentPanel:
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                Capsule()
                    .fill(resolvedAccent.previewColor)
                    .frame(width: 3)
                    .padding(.vertical, 9)
            }
        case .automatic, .none, .spotlight, .underShadow:
            Color.clear
        }
    }

    private var previewActiveScale: CGFloat {
        let base: CGFloat
        switch intensity {
        case .subtle: base = 1.025
        case .balanced: base = 1.06
        case .energetic: base = 1.10
        }
        return min(1.14, 1 + ((base - 1) * CGFloat(plan.motionGain)))
    }

    private var previewEntranceScale: CGFloat {
        let base: CGFloat
        switch intensity {
        case .subtle: base = 0.88
        case .balanced: base = 0.72
        case .energetic: base = 0.64
        }
        return max(0.58, 1 - ((1 - base) * CGFloat(plan.motionGain)))
    }

    private var previewAnimationDuration: Double {
        let base: Double
        switch intensity {
        case .subtle: base = 0.26
        case .balanced: base = 0.18
        case .energetic: base = 0.12
        }
        return max(0.09, base / max(0.82, plan.motionGain))
    }

    private var usesSplitPreviewLayout: Bool {
        plan.composition == .splitLeading || plan.composition == .splitTrailing
    }

    private var previewGroupAlignment: Alignment {
        switch plan.composition {
        case .leading, .splitLeading:
            return .leading
        case .trailing, .splitTrailing:
            return .trailing
        case .staircase:
            switch focusedIndex % 3 {
            case 0: return .leading
            case 2: return .trailing
            default: return .center
            }
        case .centered:
            return .center
        }
    }

    private func previewRowAlignment(rowIndex: Int, row: [Int]) -> Alignment {
        let emphasizedRow = row.contains(plan.emphasisIndex)
        switch plan.composition {
        case .splitLeading:
            return emphasizedRow ? .leading : .trailing
        case .splitTrailing:
            return emphasizedRow ? .trailing : .leading
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .staircase:
            switch rowIndex % 3 {
            case 0: return .leading
            case 2: return .trailing
            default: return .center
            }
        case .centered:
            return .center
        }
    }

    private func scaledFontSize(
        wordIndex: Int,
        rowIndex: Int,
        row: [Int],
        treatment: KineticGlyphTreatment
    ) -> CGFloat {
        let scale: Double
        switch plan.scene {
        case .phraseBuild:
            scale = (manualRows ?? plan.rows).count > 1 ? 0.88 : 1
        case .captionWindow:
            scale = 1.04
        case .focusCut:
            scale = 1.32
        case .impactSequence:
            scale = 1.20
        case .editorialStack:
            scale = row.contains(plan.emphasisIndex) ? 1.28 : 0.72
        case .chorusLockup:
            scale = plan.rows.count > 1
                ? (rowIndex == plan.rows.count - 1 ? 1.04 : 0.82)
                : 1.08
        }
        let emphasisScale: Double
        if wordIndex == plan.emphasisIndex
            && treatment != .poster
            && treatment != .rhythm
            && treatment != .signature {
            switch plan.scene {
            case .phraseBuild: emphasisScale = 1.10
            case .captionWindow: emphasisScale = 1.08
            case .chorusLockup: emphasisScale = 1.12
            case .focusCut, .editorialStack, .impactSequence: emphasisScale = 1
            }
        } else {
            emphasisScale = 1
        }
        return CGFloat(fontSize * scale * emphasisScale) * (previewHeight / 1080.0)
    }
}

private struct KineticGlyphRun: View {
    let design: KineticGlyphDesign
    let fontName: String
    let baseFontSize: CGFloat
    let fontWeight: Font.Weight?

    init(
        design: KineticGlyphDesign,
        fontName: String,
        baseFontSize: CGFloat,
        fontWeight: Font.Weight? = nil
    ) {
        self.design = design
        self.fontName = fontName
        self.baseFontSize = baseFontSize
        self.fontWeight = fontWeight
    }

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: max(0, baseFontSize * CGFloat(design.trackingFactor))
        ) {
            ForEach(Array(design.characters.enumerated()), id: \.offset) { item in
                let scale = design.scaleFactors.indices.contains(item.offset)
                    ? design.scaleFactors[item.offset]
                    : 1
                Text(String(item.element))
                    .font(.custom(fontName, size: baseFontSize * CGFloat(scale)))
                    .fontWeight(fontWeight)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct KineticPreviewWordRun: View {
    let design: KineticGlyphDesign
    let fontName: String
    let baseFontSize: CGFloat
    let fontWeight: Font.Weight?

    init(
        design: KineticGlyphDesign,
        fontName: String,
        baseFontSize: CGFloat,
        fontWeight: Font.Weight? = nil
    ) {
        self.design = design
        self.fontName = fontName
        self.baseFontSize = baseFontSize
        self.fontWeight = fontWeight
    }

    private var resolvedFontName: String {
        guard fontWeight != nil else { return fontName }
        return FontCatalog.boldPSName(for: fontName)
            ?? FontCatalog.regularPSName(for: fontName)
    }

    private var resolvedFontWeight: Font.Weight? {
        guard fontWeight != nil else { return nil }
        return FontCatalog.boldPSName(for: fontName) == nil ? fontWeight : nil
    }

    @ViewBuilder
    var body: some View {
        if FontCatalog.secenek(fontName)?.bitisik == true {
            Text(String(design.characters))
                .font(.custom(resolvedFontName, size: baseFontSize))
                .fontWeight(resolvedFontWeight)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        } else {
            KineticGlyphRun(
                design: design,
                fontName: resolvedFontName,
                baseFontSize: baseFontSize,
                fontWeight: resolvedFontWeight
            )
        }
    }
}

private extension KineticAccent {
    var previewColor: Color {
        previewColor(customHex: nil)
    }

    func previewColor(customHex: String?) -> Color {
        resolvedColor(customHex: customHex).previewColor
    }
}

private extension KineticResolvedColor {
    var previewColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    var foregroundPreviewColor: Color {
        usesDarkForeground ? .black : .white
    }
}
