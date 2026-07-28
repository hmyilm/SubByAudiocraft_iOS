import SwiftUI
import AVKit

// Adım 2: Ön izleme + kelime düzenleme listesi
struct EditWordsView: View {
    @Binding var words: [VideoProcessor.WordTimestamp]
    @Binding var breaks: Set<UUID>
    let player: AVPlayer?
    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var marginV: Double
    @Binding var karaokeMode: KaraokeMode
    @Binding var lyricTrackingMode: LyricTrackingMode
    @Binding var kineticStyle: KineticStyle
    @Binding var kineticAccent: KineticAccent
    @Binding var kineticCustomColorHex: String
    @Binding var kineticIntensity: KineticIntensity
    @Binding var kineticLetterStyle: KineticLetterStyle
    @Binding var kineticOverlayStyle: KineticOverlayStyle
    @Binding var kineticEmphasisWordIDs: Set<UUID>

    @State private var expandedWordID: UUID? = nil
    @State private var previewLine: String = ""
    @State private var previewWords: [VideoProcessor.WordTimestamp] = []
    @State private var previewLineIndex: Int = 0
    @State private var playbackTime: Double = 0

    private var lines: [[VideoProcessor.WordTimestamp]] {
        var groups: [[VideoProcessor.WordTimestamp]] = []
        var current: [VideoProcessor.WordTimestamp] = []
        for word in words {
            current.append(word)
            if breaks.contains(word.id) {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    var body: some View {
        VStack(spacing: 16) {
            if player != nil {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "play.rectangle.fill", title: "Canlı Ön İzleme")

                    // Video oynarken o an söylenen satır gerçek zamanlı gösterilir
                    SubtitlePreviewPlayer(
                        player: player,
                        fontName: fontName,
                        fontSize: fontSize,
                        marginV: marginV,
                        sampleText: previewLine,
                        height: 200,
                        karaokeWords: previewWords,
                        playbackTime: playbackTime,
                        isMuted: false,
                        karaokeMode: karaokeMode,
                        lyricTrackingMode: lyricTrackingMode,
                        kineticStyle: kineticStyle,
                        kineticAccent: kineticAccent,
                        kineticCustomColorHex: kineticCustomColorHex,
                        kineticIntensity: kineticIntensity,
                        kineticLetterStyle: kineticLetterStyle,
                        kineticOverlayStyle: kineticOverlayStyle,
                        kineticLineIndex: previewLineIndex,
                        kineticRepeatCount: previewPlan?.repeatCount ?? 1,
                        kineticScenePlan: previewPlan
                    )

                    if karaokeMode == .kinetic,
                       lyricTrackingMode != .centeredReveal,
                       let plan = previewPlan {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(
                                "\(kineticStyle.title) yönetmen · \(plan.creativeDirection.title)",
                                systemImage: kineticStyle.icon
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.yellow)

                            Text(
                                "\(plan.sectionRole.title) · \(plan.composition.title) · " +
                                plan.creativeDirection.detail
                            )
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Label(previewTrackingHint, systemImage: lyricTrackingMode.icon)
                    .font(.caption2)
                    .foregroundColor(.gray)

                    KaraokeModePicker(
                        selection: $karaokeMode,
                        lyricTrackingMode: $lyricTrackingMode,
                        kineticStyle: $kineticStyle,
                        kineticAccent: $kineticAccent,
                        kineticCustomColorHex: $kineticCustomColorHex,
                        kineticIntensity: $kineticIntensity,
                        kineticLetterStyle: $kineticLetterStyle,
                        kineticOverlayStyle: $kineticOverlayStyle
                    )

                    // Font burada da değiştirilebilir: Geçmiş'ten açılan projelerde
                    // 1. adıma (video seçme) dönüş yoktur, stilin tamamı bu ekrandan yönetilir.
                    FontChipPicker(
                        fonts: FontCatalog.hepsi,
                        selection: $fontName,
                        karaokeMode: karaokeMode,
                        kineticStyle: kineticStyle
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            LabeledSlider(icon: "textformat.size", title: "Boyut", value: $fontSize, range: 30...150, step: 1)
                            LabeledSlider(icon: "arrow.up.and.down", title: "Konum", value: $marginV, range: 30...950, step: 5)
                        }
                        VStack(spacing: 12) {
                            LabeledSlider(icon: "textformat.size", title: "Boyut", value: $fontSize, range: 30...150, step: 1)
                            LabeledSlider(icon: "arrow.up.and.down", title: "Konum", value: $marginV, range: 30...950, step: 5)
                        }
                    }
                }
                .card()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.yellow)
                    Text("Sözleri Düzenle")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(words.count) kelime")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                if karaokeMode == .kinetic,
                   lyricTrackingMode != .centeredReveal {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label("Vurgu Yönetmeni", systemImage: "star.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                            if !kineticEmphasisWordIDs.isEmpty {
                                Button {
                                    Theme.haptic()
                                    kineticEmphasisWordIDs.removeAll()
                                } label: {
                                    Text("Tümünü Otomatik Yap")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(Theme.yellow)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Bir kelimenin yıldızına dokunursan o satırın tipografik odağı olur. Seçim yapmazsan yönetmen anlam ve süreye göre otomatik karar verir.")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.yellow.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.yellow.opacity(0.22), lineWidth: 1)
                    )
                }

                Button {
                    Theme.haptic()
                    let newWord = VideoProcessor.WordTimestamp(
                        text: "Yeni",
                        start: words.last?.end ?? 0.0,
                        end: (words.last?.end ?? 0.0) + 1.0
                    )
                    words.append(newWord)
                    expandedWordID = newWord.id
                } label: {
                    Label("Kelime Ekle", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.yellow))
                }
                .buttonStyle(.plain)

                ScrollView {
                    VStack(spacing: 8) {
                        // Kimlik (id) tabanlı ForEach: silme sırasında çökmeyi önler
                        ForEach($words) { $word in
                            WordRow(
                                word: $word,
                                isExpanded: expandedWordID == word.id,
                                showsEmphasis: karaokeMode == .kinetic
                                    && lyricTrackingMode != .centeredReveal,
                                isEmphasis: kineticEmphasisWordIDs.contains(word.id),
                                onToggleEmphasis: {
                                    toggleEmphasis(word.id)
                                },
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedWordID = (expandedWordID == word.id) ? nil : word.id
                                    }
                                    player?.seek(
                                        to: CMTime(seconds: max(0, word.start), preferredTimescale: 600),
                                        toleranceBefore: .zero,
                                        toleranceAfter: .zero
                                    )
                                },
                                onDelete: {
                                    deleteWord(word.id)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .card()
        }
        // Oynatma konumuna göre aktif satırı bulup ön izlemeye yansıt
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updatePreviewLine()
        }
        .onAppear {
            normalizeEmphasisSelection()
        }
        .onChange(of: breaks) { _ in
            normalizeEmphasisSelection()
        }
    }

    private var previewPlan: KineticTypographyPlan? {
        guard lines.indices.contains(previewLineIndex) else { return nil }
        let plans = VideoProcessor.shared.kineticScenePlans(
            for: lines,
            style: kineticStyle,
            emphasisWordIDs: kineticEmphasisWordIDs
        )
        return plans[previewLineIndex]
    }

    private var previewTrackingHint: String {
        switch lyricTrackingMode {
        case .off:
            return "Söz takibi kapalı; satır zamanlamasını sesi dinleyerek kontrol edebilirsin."
        case .karaoke:
            return "Vurgulanan kelime o anda söylenen bölümü gösterir."
        case .centeredReveal:
            return "Yeni harf vokalle gelir; büyüyen cümle merkezde kalırken önceki harfler sola kayar."
        }
    }

    private func updatePreviewLine() {
        guard let player = player else {
            previewLine = ""
            previewWords = []
            playbackTime = 0
            return
        }
        let t = player.currentTime().seconds
        guard t.isFinite else {
            previewLine = ""
            previewWords = []
            playbackTime = 0
            return
        }
        playbackTime = t
        if let match = lines.enumerated().first(where: { item in
            let group = item.element
            guard let first = group.first, let last = group.last else { return false }
            return t >= first.start - 0.2 && t <= last.end + 0.2
        }) {
            let index = match.offset
            let line = match.element
            previewLine = line.map { $0.text }.joined(separator: " ")
            previewWords = line
            previewLineIndex = index
        } else {
            previewLine = ""
            previewWords = []
            previewLineIndex = 0
        }
    }

    private func deleteWord(_ id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        kineticEmphasisWordIDs.remove(id)
        let endedLine = breaks.remove(id) != nil
        if endedLine, index > 0 {
            breaks.insert(words[index - 1].id)
        }
        words.remove(at: index)
        if expandedWordID == id { expandedWordID = nil }
    }

    private func toggleEmphasis(_ id: UUID) {
        guard let line = lines.first(where: { group in group.contains(where: { $0.id == id }) }) else {
            return
        }
        let wasSelected = kineticEmphasisWordIDs.contains(id)
        kineticEmphasisWordIDs.subtract(Set(line.map(\.id)))
        if !wasSelected {
            kineticEmphasisWordIDs.insert(id)
        }
        Theme.haptic()
        if let word = line.first(where: { $0.id == id }) {
            player?.seek(
                to: CMTime(seconds: max(0, word.start), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    private func normalizeEmphasisSelection() {
        let validIDs = Set(words.map(\.id))
        var normalized = Set<UUID>()
        for line in lines {
            if let selected = line.first(where: {
                validIDs.contains($0.id) && kineticEmphasisWordIDs.contains($0.id)
            }) {
                normalized.insert(selected.id)
            }
        }
        if normalized != kineticEmphasisWordIDs {
            kineticEmphasisWordIDs = normalized
        }
    }
}

// Tek kelime satırı: varsayılan sade görünüm; zaman çipine dokununca +/- kontrolleri açılır
struct WordRow: View {
    @Binding var word: VideoProcessor.WordTimestamp
    let isExpanded: Bool
    let showsEmphasis: Bool
    let isEmphasis: Bool
    let onToggleEmphasis: () -> Void
    let onToggleExpand: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Kelime", text: $word.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.field)
                    )

                if showsEmphasis {
                    Button(action: onToggleEmphasis) {
                        Image(systemName: isEmphasis ? "star.fill" : "star")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isEmphasis ? .black : Theme.yellow)
                            .padding(7)
                            .background(
                                Circle()
                                    .fill(isEmphasis ? Theme.yellow : Theme.field)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isEmphasis ? "Manuel vurguyu kaldır" : "Bu kelimeyi vurgula"
                    )
                }

                Button(action: onToggleExpand) {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f–%.1fs", word.start, word.end))
                            .font(.system(.caption2, design: .monospaced))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(Theme.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.field))
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                HStack(spacing: 16) {
                    // Başlangıç her zaman bitişten önce kalacak şekilde kelepçelenir
                    timeControl(
                        label: "Başlangıç",
                        value: word.start,
                        minus: { word.start = max(0, word.start - 0.1) },
                        plus: { if word.start + 0.1 <= word.end - 0.1 { word.start += 0.1 } }
                    )
                    timeControl(
                        label: "Bitiş",
                        value: word.end,
                        minus: { word.end = max(word.end - 0.1, word.start + 0.1) },
                        plus: { word.end += 0.1 }
                    )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEmphasis ? Theme.yellow.opacity(0.65) : Color.clear, lineWidth: 1)
        )
    }

    private func timeControl(label: String, value: Double, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            HStack(spacing: 10) {
                Button(action: minus) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                Text(String(format: "%.1fs", value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 44)
                Button(action: plus) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
