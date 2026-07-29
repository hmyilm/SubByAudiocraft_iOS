import SwiftUI

// Adım 2: Satır (kıta) düzenleme — sistemin önerdiği satırları kullanıcı kontrol edip onaylar.
// Her zaman cümlesi ekranda birlikte görünecek kelime grubudur. Ok menüsü yeni zaman
// cümlesi veya aynı cümle içinde ikinci görsel satır seçer; kelimeye dokununca metin
// düzenlenir, basılı tutunca silinebilir.
struct LineEditView: View {
    @Binding var words: [VideoProcessor.WordTimestamp]
    @Binding var breaks: Set<UUID>
    @Binding var inlineBreaks: Set<UUID>

    @State private var editingWordID: UUID? = nil
    @State private var editText: String = ""
    @State private var showEditAlert = false
    @State private var previousBreaks: Set<UUID>? = nil
    @State private var previousInlineBreaks: Set<UUID>? = nil

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
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "text.alignleft", title: "Sözleri Satırlara Böl")

                Text("Kelimeye dokunarak yazımı düzelt. Yanındaki ok menüsünden yeni cümle başlatabilir veya aynı anda görünen cümleyi iki satıra bölebilirsin.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        breakLegend(
                            title: "Yeni cümle",
                            icon: "return.circle.fill",
                            color: Theme.yellow
                        )
                        breakLegend(
                            title: "Aynı anda alt satır",
                            icon: "arrow.turn.down.right.circle.fill",
                            color: .cyan
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        breakLegend(
                            title: "Yeni cümle",
                            icon: "return.circle.fill",
                            color: Theme.yellow
                        )
                        breakLegend(
                            title: "Aynı anda alt satır",
                            icon: "arrow.turn.down.right.circle.fill",
                            color: .cyan
                        )
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Hazır düzen")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)
                        ForEach([2, 3, 4, 5], id: \.self) { n in
                            Button {
                                Theme.haptic()
                                rememberBreakState()
                                splitEvery(n)
                            } label: {
                                Text("\(n)'li")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(Theme.yellow))
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            Theme.haptic()
                            rememberBreakState()
                            breaks = VideoProcessor.shared.autoLineBreaks(for: words)
                            inlineBreaks.removeAll()
                        } label: {
                            Text("Otomatik")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Theme.yellow)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(Capsule().stroke(Theme.yellow, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Label("Silme işlemi için kelimeye basılı tutabilirsin.", systemImage: "hand.tap")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    if previousBreaks != nil || previousInlineBreaks != nil {
                        Button {
                            Theme.haptic()
                            undoLastBreakChange()
                        } label: {
                            Label("Geri Al", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Theme.yellow)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(icon: "music.note.list", title: "Cümle Yerleşimi")
                    Text("\(lines.count) cümle")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 20, alignment: .trailing)
                            .padding(.top, 9)

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(visualRows(for: line).enumerated()), id: \.offset) { row in
                                FlowLayout(spacing: 6) {
                                    ForEach(row.element) { word in
                                        wordChip(word)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.12))
                    )
                }
            }
            .card()
        }
        .alert("Kelimeyi Düzenle", isPresented: $showEditAlert) {
            TextField("Kelime", text: $editText)
            Button("Kaydet") {
                if let id = editingWordID, let idx = words.firstIndex(where: { $0.id == id }) {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { words[idx].text = trimmed }
                }
            }
            Button("İptal", role: .cancel) {}
        }
        .onAppear {
            normalizeInlineBreaks()
        }
    }

    private func wordChip(_ word: VideoProcessor.WordTimestamp) -> some View {
        let endsLine = breaks.contains(word.id) && word.id != words.last?.id
        let endsVisualRow = inlineBreaks.contains(word.id) && word.id != words.last?.id
        return HStack(spacing: 0) {
            Button {
                Theme.haptic()
                beginEditing(word)
            } label: {
                Text(word.text)
                    .font(.callout)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(word.text), düzenle")

            if word.id != words.last?.id {
                Menu {
                    Button {
                        Theme.haptic()
                        toggleInlineBreak(after: word)
                    } label: {
                        Label(
                            endsVisualRow
                                ? "Alt satır ayırmasını kaldır"
                                : "Aynı cümlede alt satıra geçir",
                            systemImage: endsVisualRow
                                ? "arrow.uturn.left"
                                : "arrow.turn.down.right"
                        )
                    }

                    Button {
                        Theme.haptic()
                        toggleBreak(after: word)
                    } label: {
                        Label(
                            endsLine ? "Cümle sonunu kaldır" : "Yeni cümle başlat",
                            systemImage: endsLine ? "text.append" : "return"
                        )
                    }
                } label: {
                    Image(
                        systemName: endsLine
                            ? "return.circle.fill"
                            : (
                                endsVisualRow
                                    ? "arrow.turn.down.right.circle.fill"
                                    : "arrow.turn.down.right.circle"
                            )
                    )
                        .font(.body)
                        .foregroundColor(
                            endsLine
                                ? Theme.yellow
                                : (endsVisualRow ? .cyan : .gray)
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    endsLine
                        ? "Yeni cümle başlangıcı"
                        : (endsVisualRow ? "Aynı cümlede alt satır" : "Satır seçenekleri")
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    endsLine
                        ? Theme.yellow.opacity(0.7)
                        : (endsVisualRow ? Color.cyan.opacity(0.7) : Color.clear),
                    lineWidth: 1
                )
        )
        .contextMenu {
            Button(role: .destructive) {
                deleteWord(word.id)
            } label: {
                Label("Kelimeyi Sil", systemImage: "trash")
            }
        }
    }

    private func beginEditing(_ word: VideoProcessor.WordTimestamp) {
        editingWordID = word.id
        editText = word.text
        showEditAlert = true
    }

    private func toggleBreak(after word: VideoProcessor.WordTimestamp) {
        guard word.id != words.last?.id else { return }
        rememberBreakState()
        if breaks.contains(word.id) {
            breaks.remove(word.id)
        } else {
            breaks.insert(word.id)
            inlineBreaks.remove(word.id)
        }
        normalizeInlineBreaks()
    }

    private func breakLegend(title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
    }

    private func toggleInlineBreak(after word: VideoProcessor.WordTimestamp) {
        guard word.id != words.last?.id else { return }
        rememberBreakState()
        if inlineBreaks.contains(word.id) {
            inlineBreaks.remove(word.id)
            return
        }

        // Aynı noktada zaman cümlesi ve görsel alt satır birlikte bulunamaz.
        // Kullanıcı alt satırı seçtiğinde sonraki kelime aynı zaman cümlesine katılır.
        breaks.remove(word.id)
        if let group = lines.first(where: { $0.contains(where: { $0.id == word.id }) }) {
            inlineBreaks.subtract(Set(group.map(\.id)))
        }
        inlineBreaks.insert(word.id)
        normalizeInlineBreaks()
    }

    private func splitEvery(_ n: Int) {
        var newBreaks = Set<UUID>()
        for (index, word) in words.enumerated() where (index + 1) % n == 0 {
            newBreaks.insert(word.id)
        }
        breaks = newBreaks
        inlineBreaks.removeAll()
    }

    private func undoLastBreakChange() {
        if let previousBreaks {
            breaks = previousBreaks
        }
        if let previousInlineBreaks {
            inlineBreaks = previousInlineBreaks
        }
        self.previousBreaks = nil
        self.previousInlineBreaks = nil
    }

    private func deleteWord(_ id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        rememberBreakState()
        let endedLine = breaks.remove(id) != nil
        if endedLine, index > 0 {
            // Satırın son kelimesi silinince satır düzenini korumak için sonu bir
            // önceki kelimeye taşı; aksi halde iki satır fark edilmeden birleşir.
            breaks.insert(words[index - 1].id)
        }
        let endedVisualRow = inlineBreaks.remove(id) != nil
        if endedVisualRow, index > 0, !breaks.contains(words[index - 1].id) {
            inlineBreaks.insert(words[index - 1].id)
        }
        words.remove(at: index)
        normalizeInlineBreaks()
    }

    private func rememberBreakState() {
        previousBreaks = breaks
        previousInlineBreaks = inlineBreaks
    }

    private func visualRows(
        for line: [VideoProcessor.WordTimestamp]
    ) -> [[VideoProcessor.WordTimestamp]] {
        var rows: [[VideoProcessor.WordTimestamp]] = []
        var current: [VideoProcessor.WordTimestamp] = []
        for word in line {
            current.append(word)
            if inlineBreaks.contains(word.id), word.id != line.last?.id {
                rows.append(current)
                current = []
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func normalizeInlineBreaks() {
        let validIDs = Set(words.map(\.id))
        inlineBreaks.formIntersection(validIDs)
        inlineBreaks.subtract(breaks)

        var normalized = Set<UUID>()
        for line in lines {
            guard line.count > 1 else { continue }
            if let selected = line.dropLast().first(where: {
                inlineBreaks.contains($0.id)
            }) {
                normalized.insert(selected.id)
            }
        }
        inlineBreaks = normalized
    }
}

// iOS 16 Layout protokolü ile basit satır kaydırmalı (flow) yerleşim
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let width = maxWidth == .infinity ? max(0, x - spacing) : maxWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
