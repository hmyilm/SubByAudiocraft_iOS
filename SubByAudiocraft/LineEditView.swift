import SwiftUI

// Adım 2: Satır (kıta) düzenleme — sistemin önerdiği satırları kullanıcı kontrol edip onaylar.
// Her satır ekranda birlikte görünecek kelime grubudur. Kelimeye dokununca satır orada
// bölünür/birleşir; basılı tutunca kelime düzenlenir veya silinir.
struct LineEditView: View {
    @Binding var words: [VideoProcessor.WordTimestamp]
    @Binding var breaks: Set<UUID>

    @State private var editingWordID: UUID? = nil
    @State private var editText: String = ""
    @State private var showEditAlert = false
    @State private var previousBreaks: Set<UUID>? = nil

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

                Text("Kelimeye dokunarak yazımı düzelt. Yanındaki dönüş düğmesiyle cümlenin nerede biteceğini belirle.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Hazır düzen")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)
                        ForEach([2, 3, 4, 5], id: \.self) { n in
                            Button {
                                Theme.haptic()
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
                            previousBreaks = breaks
                            breaks = VideoProcessor.shared.autoLineBreaks(for: words)
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
                    if previousBreaks != nil {
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
                    SectionHeader(icon: "music.note.list", title: "Kıtalar")
                    Text("\(lines.count) satır")
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

                        FlowLayout(spacing: 6) {
                            ForEach(line) { word in
                                wordChip(word)
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
    }

    private func wordChip(_ word: VideoProcessor.WordTimestamp) -> some View {
        let endsLine = breaks.contains(word.id) && word.id != words.last?.id
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
                Button {
                    Theme.haptic()
                    toggleBreak(after: word)
                } label: {
                    Image(systemName: endsLine ? "return.circle.fill" : "return.circle")
                        .font(.body)
                        .foregroundColor(endsLine ? Theme.yellow : .gray)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(endsLine ? "Satır sonunu kaldır" : "Buraya satır sonu ekle")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(endsLine ? Theme.yellow.opacity(0.7) : Color.clear, lineWidth: 1)
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
        previousBreaks = breaks
        if breaks.contains(word.id) {
            breaks.remove(word.id)
        } else {
            breaks.insert(word.id)
        }
    }

    private func splitEvery(_ n: Int) {
        previousBreaks = breaks
        var newBreaks = Set<UUID>()
        for (index, word) in words.enumerated() where (index + 1) % n == 0 {
            newBreaks.insert(word.id)
        }
        breaks = newBreaks
    }

    private func undoLastBreakChange() {
        guard let previousBreaks else { return }
        breaks = previousBreaks
        self.previousBreaks = nil
    }

    private func deleteWord(_ id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        let endedLine = breaks.remove(id) != nil
        if endedLine, index > 0 {
            // Satırın son kelimesi silinince satır düzenini korumak için sonu bir
            // önceki kelimeye taşı; aksi halde iki satır fark edilmeden birleşir.
            breaks.insert(words[index - 1].id)
        }
        words.remove(at: index)
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
