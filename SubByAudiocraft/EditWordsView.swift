import SwiftUI
import AVKit

private enum EditorPanel: String, CaseIterable, Identifiable {
    case design
    case words

    var id: String { rawValue }

    var title: String {
        switch self {
        case .design: return "Tasarım"
        case .words: return "Kelime ve Zaman"
        }
    }
}

// Adım 2: Ön izleme + kelime düzenleme listesi
struct EditWordsView: View {
    @Binding var words: [VideoProcessor.WordTimestamp]
    @Binding var breaks: Set<UUID>
    @Binding var inlineBreaks: Set<UUID>
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
    @State private var selectedPanel: EditorPanel = .design
    @State private var showsAddWordAlert = false
    @State private var newWordText = ""
    @State private var pendingWordStart: Double?
    @State private var wordSortWorkItem: DispatchWorkItem?

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
                        inlineLineBreaks: inlineBreaks,
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
                       !lyricTrackingMode.isProgressiveReveal,
                       lyricTrackingMode != .boldWord,
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
                }
                .card()

                Picker("Düzenleme Bölümü", selection: $selectedPanel) {
                    ForEach(EditorPanel.allCases) { panel in
                        Text(panel.title).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Tasarım ayarlarıyla kelime zamanlaması arasında geçiş yapar.")

                if selectedPanel == .design {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(icon: "paintbrush.fill", title: "Tasarım Ayarları")

                        StudioTypographyControls(
                            fontName: fontName,
                            karaokeMode: $karaokeMode,
                            lyricTrackingMode: $lyricTrackingMode,
                            kineticStyle: $kineticStyle,
                            kineticAccent: $kineticAccent,
                            kineticCustomColorHex: $kineticCustomColorHex,
                            kineticIntensity: $kineticIntensity,
                            kineticLetterStyle: $kineticLetterStyle,
                            kineticOverlayStyle: $kineticOverlayStyle
                        )

                        // Geçmişten açılan projelerde de stilin tamamı burada yönetilir.
                        CompactFontPicker(
                            fonts: FontCatalog.hepsi,
                            selection: $fontName,
                            karaokeMode: karaokeMode,
                            kineticStyle: kineticStyle
                        )

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                LabeledSlider(icon: "textformat.size", title: "Yazı Boyutu", value: $fontSize, range: 30...150, step: 1)
                                LabeledSlider(
                                    icon: "arrow.up.and.down",
                                    title: "Dikey Konum",
                                    value: $marginV,
                                    range: 30...950,
                                    step: 5,
                                    valueText: positionTitle
                                )
                            }
                            VStack(spacing: 12) {
                                LabeledSlider(icon: "textformat.size", title: "Yazı Boyutu", value: $fontSize, range: 30...150, step: 1)
                                LabeledSlider(
                                    icon: "arrow.up.and.down",
                                    title: "Dikey Konum",
                                    value: $marginV,
                                    range: 30...950,
                                    step: 5,
                                    valueText: positionTitle
                                )
                            }
                        }
                    }
                    .card()
                }
            }

            if selectedPanel == .words {
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

                Text("Kelimeyi doğrudan düzenleyebilir, zaman etiketine dokunarak saniyelerini ayarlayabilirsin.")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)

                if karaokeMode == .kinetic,
                   !lyricTrackingMode.isProgressiveReveal,
                   lyricTrackingMode != .boldWord {
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
                    pendingWordStart = currentInsertionTime()
                    newWordText = ""
                    player?.pause()
                    showsAddWordAlert = true
                } label: {
                    Label("Kelime Ekle", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.yellow))
                }
                .buttonStyle(.plain)

                LazyVStack(spacing: 8) {
                    // Kimlik (id) tabanlı ForEach: silme sırasında çökmeyi önler
                    ForEach($words) { $word in
                        WordRow(
                            word: $word,
                            isExpanded: expandedWordID == word.id,
                            showsEmphasis: karaokeMode == .kinetic
                                && !lyricTrackingMode.isProgressiveReveal
                                && lyricTrackingMode != .boldWord,
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
                            },
                            onTimingChanged: {
                                scheduleChronologicalSort()
                            }
                        )
                    }
                }
                }
                .card()
            }
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
        .onChange(of: inlineBreaks) { _ in
            updatePreviewLine()
        }
        .alert("Kelime Ekle", isPresented: $showsAddWordAlert) {
            TextField("Kelime", text: $newWordText)
            Button("İptal", role: .cancel) {
                pendingWordStart = nil
            }
            Button("Ekle") {
                addWordAtPendingTime()
            }
            .disabled(newWordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(
                "Kelime \(String(format: "%.1f", pendingWordStart ?? 0)) saniyeye eklenecek."
            )
        }
        .onDisappear {
            wordSortWorkItem?.cancel()
            wordSortWorkItem = nil
        }
    }

    private var previewPlan: KineticTypographyPlan? {
        guard !lyricTrackingMode.isProgressiveReveal,
              lyricTrackingMode != .boldWord,
              lines.indices.contains(previewLineIndex) else { return nil }
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
            return "Harfler vokal ilerledikçe soldan sağa takip edilir."
        case .boldWord:
            return "O anda söylenen kelime kalın görünür; satır konumu ve diğer kelimeler sabit kalır."
        case .centeredReveal:
            return "Yeni harf vokalle gelir; büyüyen cümle merkezde kalırken önceki harfler sola kayar."
        case .centeredWordReveal:
            return "Yeni kelime tek parça halinde gelir; cümle merkezde kalırken önceki kelimeler sola kayar."
        }
    }

    private func positionTitle(_ value: Double) -> String {
        if value < 260 { return "Alt" }
        if value < 650 { return "Orta" }
        return "Üst"
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
            previewLine = VideoProcessor.shared.visualLineGroups(
                for: line,
                inlineLineBreaks: inlineBreaks
            )
            .map { $0.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
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
        let endedVisualRow = inlineBreaks.remove(id) != nil
        if endedVisualRow, index > 0, !breaks.contains(words[index - 1].id) {
            inlineBreaks.insert(words[index - 1].id)
        }
        words.remove(at: index)
        if expandedWordID == id { expandedWordID = nil }
    }

    private func currentInsertionTime() -> Double {
        if let currentTime = player?.currentTime().seconds,
           currentTime.isFinite,
           currentTime >= 0 {
            return currentTime
        }
        if let expandedWordID,
           let expandedWord = words.first(where: { $0.id == expandedWordID }) {
            return max(0, expandedWord.end)
        }
        let lastEnd = VideoProcessor.shared.chronologicallySortedWords(words).last?.end ?? 0
        return max(0, lastEnd)
    }

    private func addWordAtPendingTime() {
        let text = newWordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            pendingWordStart = nil
            return
        }

        wordSortWorkItem?.cancel()
        wordSortWorkItem = nil

        let sortedBefore = VideoProcessor.shared.chronologicallySortedWords(words)
        let start = max(0, pendingWordStart ?? currentInsertionTime())
        let nextStart = sortedBefore.first(where: { $0.start > start + 0.02 })?.start
        var end = start + 0.6
        if let nextStart, nextStart - start >= 0.12 {
            end = min(end, nextStart - 0.02)
        }
        end = max(start + 0.1, end)

        let newWord = VideoProcessor.WordTimestamp(text: text, start: start, end: end)
        if let previousLast = sortedBefore.last,
           start >= previousLast.start,
           breaks.remove(previousLast.id) != nil {
            breaks.insert(newWord.id)
        }

        words.append(newWord)
        words = VideoProcessor.shared.chronologicallySortedWords(words)
        expandedWordID = newWord.id
        pendingWordStart = nil
        player?.seek(
            to: CMTime(seconds: start, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func scheduleChronologicalSort() {
        wordSortWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            let sorted = VideoProcessor.shared.chronologicallySortedWords(words)
            if sorted.map(\.id) != words.map(\.id) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    words = sorted
                }
            }
        }
        wordSortWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
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
    let onTimingChanged: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Kelime", text: $word.text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
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
                            .frame(width: 44, height: 44)
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
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Theme.field))
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(spacing: 8) {
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

                    shiftControl

                    Text("Düğmeye basılı tuttukça ayar hızlanır. Kaydır, kelimenin süresini korur.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
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
                AcceleratingStepButton(systemImage: "minus.circle.fill") {
                    minus()
                    onTimingChanged()
                }
                Text(String(format: "%.1fs", value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 44)
                AcceleratingStepButton(systemImage: "plus.circle.fill") {
                    plus()
                    onTimingChanged()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shiftControl: some View {
        HStack(spacing: 10) {
            Text("Kelimeyi kaydır")
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer(minLength: 4)
            AcceleratingStepButton(systemImage: "backward.end.fill") {
                let shift = min(0.1, word.start)
                guard shift > 0 else { return }
                word.start -= shift
                word.end -= shift
                onTimingChanged()
            }
            Text(String(format: "%.1f–%.1fs", word.start, word.end))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 82)
            AcceleratingStepButton(systemImage: "forward.end.fill") {
                word.start += 0.1
                word.end += 0.1
                onTimingChanged()
            }
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.field.opacity(0.7))
        )
    }
}

private struct AcceleratingStepButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .foregroundColor(.gray)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        beginPress()
                    }
                    .onEnded { _ in
                        endPress()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
            .onDisappear {
                endPress()
            }
    }

    private func beginPress() {
        guard repeatTask == nil else { return }
        isPressed = true
        action()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            var repeatCount = 0
            while !Task.isCancelled {
                action()
                repeatCount += 1
                let interval: UInt64
                if repeatCount < 6 {
                    interval = 140_000_000
                } else if repeatCount < 18 {
                    interval = 80_000_000
                } else {
                    interval = 45_000_000
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func endPress() {
        repeatTask?.cancel()
        repeatTask = nil
        isPressed = false
    }
}
