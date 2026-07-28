import Foundation
import SwiftUI
import AVKit
import UIKit

// MARK: - 3 Adımlı İlerleme Göstergesi (Video → Düzenle → Kaydet)
struct StepIndicator: View {
    let currentIndex: Int
    private let steps = ["Video", "Satırlar", "Zaman", "Kaydet"]

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

// MARK: - Yatay Kaydırmalı Font Seçici Çipleri
struct FontChipPicker: View {
    let fonts: [FontOption]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(fonts) { font in
                    let isSelected = font.psName == selection
                    Button {
                        Theme.haptic()
                        selection = font.psName
                    } label: {
                        VStack(spacing: 4) {
                            Text("Abc")
                                .font(.custom(font.psName, size: 22))
                                .foregroundColor(isSelected ? Theme.yellow : .white)
                            Text(font.display)
                                .font(.caption2)
                                .foregroundColor(isSelected ? Theme.yellow : .gray)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 74)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(white: isSelected ? 0.16 : 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Theme.yellow : Theme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Karaoke / Kinetik Tipografi Modu
struct KaraokeModePicker: View {
    @Binding var selection: KaraokeMode
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

            if selection == .kinetic {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kinetik Yönetmen")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)

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
                                }
                            }
                        }

                        Text(kineticOverlayStyle.detail)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }

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

                    Label(
                        "Overlay, vurgu rengi, harf tasarımı ve geçişler aynı sahne planından beslenir; rastgele üst üste bindirilmez.",
                        systemImage: "scope"
                    )
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
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
                ValueBadge(text: "\(Int(value))")
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.yellow)
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
    let playbackTime: Double
    let isMuted: Bool
    let karaokeMode: KaraokeMode
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
        playbackTime: Double = 0,
        isMuted: Bool = true,
        karaokeMode: KaraokeMode = .classic,
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
        self.playbackTime = playbackTime
        self.isMuted = isMuted
        self.karaokeMode = karaokeMode
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
            ZStack(alignment: .bottom) {
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
                        if karaokeMode == .kinetic {
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
                                previewHeight: geo.size.height,
                                accent: kineticAccent,
                                customColorHex: kineticCustomColorHex,
                                intensity: kineticIntensity,
                                letterStyle: kineticLetterStyle,
                                overlayStyle: kineticOverlayStyle
                            )
                        } else if karaokeWords.isEmpty {
                            Text(sampleText)
                                .foregroundColor(.white)
                        } else {
                            HStack(spacing: max(2, geo.size.height / 100)) {
                                ForEach(Array(karaokeWords.enumerated()), id: \.element.id) { item in
                                    let word = item.element
                                    let isActive = playbackTime >= word.start && playbackTime < word.end
                                    let isPast = playbackTime >= word.end
                                    Text(word.text)
                                        .foregroundColor(
                                            isActive
                                                ? Theme.yellow
                                                : (isPast ? .white.opacity(0.35) : .white)
                                        )
                                        .scaleEffect(isActive ? 1.08 : 1)
                                        .shadow(
                                            color: isActive ? Theme.yellow.opacity(0.45) : .clear,
                                            radius: isActive ? 4 : 0
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                        .font(.custom(fontName, size: CGFloat(fontSize) * (geo.size.height / 1080.0)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            karaokeWords.isEmpty && karaokeMode == .classic
                                ? Color.black.opacity(0.6)
                                : Color.clear
                        )
                        .shadow(color: karaokeWords.isEmpty ? .clear : .black.opacity(0.9), radius: 2)
                        .cornerRadius(6)
                        .padding(.bottom, CGFloat(marginV) * (geo.size.height / 1080.0))
                }
            }
        }
        .frame(height: height)
        .background(Color.black)
        .cornerRadius(14)
        .clipped()
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

    private var activeIndex: Int? {
        words.firstIndex { playbackTime >= $0.start && playbackTime < $0.end }
    }

    private var focusedIndex: Int {
        if let activeIndex { return activeIndex }
        if let past = words.lastIndex(where: { $0.start <= playbackTime }) { return past }
        return words.indices.contains(plan.emphasisIndex) ? plan.emphasisIndex : 0
    }

    private var visibleRows: [[Int]] {
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
                            let isActive = playbackTime >= word.start && playbackTime < word.end
                            let isPast = playbackTime >= word.end
                            let glyphDesign = VideoProcessor.shared.kineticGlyphDesign(
                                text: word.text,
                                wordIndex: index,
                                plan: plan,
                                letterStyle: letterStyle
                            )
                            KineticGlyphRun(
                                design: glyphDesign,
                                fontName: fontName,
                                baseFontSize: scaledFontSize(
                                    wordIndex: index,
                                    rowIndex: rowItem.offset,
                                    row: rowItem.element,
                                    treatment: glyphDesign.treatment
                                )
                            )
                                .foregroundColor(
                                    isActive
                                        ? (
                                            plan.highlight == .pill
                                                ? resolvedAccent.foregroundPreviewColor
                                                : resolvedAccent.previewColor
                                        )
                                        : (isPast ? .white.opacity(0.35) : .white)
                                )
                                .padding(
                                    .horizontal,
                                    plan.highlight == .pill || resolvedOverlay == .spotlight ? 6 : 0
                                )
                                .padding(
                                    .vertical,
                                    plan.highlight == .pill || resolvedOverlay == .spotlight ? 3 : 0
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
                                    color: isActive && plan.highlight == .glow
                                        ? resolvedAccent.previewColor.opacity(0.55)
                                        : .black.opacity(0.8),
                                    radius: isActive ? 4 : 2
                                )
                                .transition(.asymmetric(
                                    insertion: .scale(scale: previewEntranceScale).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                }
                .frame(
                    maxWidth: resolvedOverlay == .cinematicBand ? .infinity : nil,
                    alignment: .center
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
        .animation(.easeOut(duration: previewAnimationDuration), value: activeIndex)
    }

    private var resolvedAccent: KineticResolvedColor {
        accent.resolvedColor(customHex: customColorHex)
    }

    private var resolvedOverlay: KineticOverlayStyle {
        overlayStyle.resolved(for: plan.scene)
    }

    private var groupOverlayHorizontalPadding: CGFloat {
        switch resolvedOverlay {
        case .glass: return max(10, previewHeight / 42)
        case .cinematicBand: return max(12, previewHeight / 36)
        case .accentPanel: return max(14, previewHeight / 34)
        case .automatic, .none, .spotlight: return 0
        }
    }

    private var groupOverlayVerticalPadding: CGFloat {
        switch resolvedOverlay {
        case .glass: return max(7, previewHeight / 64)
        case .cinematicBand: return max(10, previewHeight / 52)
        case .accentPanel: return max(9, previewHeight / 55)
        case .automatic, .none, .spotlight: return 0
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
        case .automatic, .none, .spotlight:
            Color.clear
        }
    }

    private var previewActiveScale: CGFloat {
        switch intensity {
        case .subtle: return 1.025
        case .balanced: return 1.06
        case .energetic: return 1.10
        }
    }

    private var previewEntranceScale: CGFloat {
        switch intensity {
        case .subtle: return 0.88
        case .balanced: return 0.72
        case .energetic: return 0.64
        }
    }

    private var previewAnimationDuration: Double {
        switch intensity {
        case .subtle: return 0.26
        case .balanced: return 0.18
        case .energetic: return 0.12
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
            scale = plan.rows.count > 1 ? 0.88 : 1
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
            && treatment != .rhythm {
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
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
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
