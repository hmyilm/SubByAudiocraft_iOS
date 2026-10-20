import SwiftUI

// Sahne burada kullanıcının birlikte gösterdiği kelime grubudur.
struct SubtitleScenePositionControls: View {
    @Binding var words: [VideoProcessor.WordTimestamp]
    let lineBreaks: Set<UUID>
    let inlineLineBreaks: Set<UUID>
    let fontSize: Double
    @Binding var defaultMarginV: Double
    @Binding var selectedWordID: UUID?
    let currentWordID: UUID?
    let onSelect: ([VideoProcessor.WordTimestamp]) -> Void

    @State private var editsDefault = false

    private var groups: [[VideoProcessor.WordTimestamp]] {
        VideoProcessor.shared.subtitleGroups(for: words, lineBreaks: lineBreaks)
    }

    private var selectedIndex: Int {
        guard let id = selectedWordID ?? currentWordID else { return 0 }
        return groups.firstIndex { $0.contains { $0.id == id } } ?? 0
    }

    private var selectedGroup: [VideoProcessor.WordTimestamp] {
        groups.indices.contains(selectedIndex) ? groups[selectedIndex] : []
    }

    private var positionRange: ClosedRange<Double> {
        let rows = VideoProcessor.shared.visualLineGroups(
            for: selectedGroup, inlineLineBreaks: inlineLineBreaks
        ).count
        let maximum = SubtitlePosition.visibleMargin(
            SubtitlePosition.range.upperBound, fontSize: fontSize, rowCount: rows
        )
        return SubtitlePosition.range.lowerBound...maximum
    }

    private var position: Binding<Double> {
        Binding(
            get: {
                let value = editsDefault
                    ? SubtitlePosition.clamped(defaultMarginV)
                    : VideoProcessor.shared.subtitleMarginV(
                        for: selectedGroup, defaultMarginV: defaultMarginV
                    )
                return min(positionRange.upperBound, value)
            },
            set: { value in
                if editsDefault {
                    defaultMarginV = SubtitlePosition.clamped(value)
                } else {
                    let group = selectedGroup
                    selectedWordID = group.first?.id
                    words = VideoProcessor.shared.applyingSubtitleMarginV(value, to: group, in: words)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "arrow.up.and.down", title: "Sahne Konumu")

            Picker("Konumun uygulanacağı yer", selection: $editsDefault) {
                Text("Bu Grup").tag(false)
                Text("Genel Konum").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button { selectGroup(selectedIndex - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(selectedIndex == 0 || groups.isEmpty)
                .accessibilityLabel("Önceki kelime grubu")

                Menu {
                    ForEach(Array(groups.enumerated()), id: \.element.first?.id) { item in
                        Button("\(item.offset + 1). \(item.element.map(\.text).joined(separator: " "))") {
                            selectGroup(item.offset)
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text("Grup \(groups.isEmpty ? 0 : selectedIndex + 1) / \(groups.count)")
                            .font(.caption.weight(.semibold))
                        Text(selectedGroup.map(\.text).joined(separator: " "))
                            .font(.caption2)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Konumu ayarlanacak kelime grubunu seç")

                Button { selectGroup(selectedIndex + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(selectedIndex + 1 >= groups.count)
                .accessibilityLabel("Sonraki kelime grubu")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.yellow)

            HStack {
                Text("Yükseklik").font(.subheadline.weight(.semibold))
                Spacer()
                Text("%\(Int((position.wrappedValue / 10.8).rounded()))")
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .foregroundStyle(Theme.yellow)
            }

            // Tek, tam genişlikli slider: değer değişince ViewThatFits yeniden
            // bir kontrol seçmez; ön izleme de ayar sırasında aynı sahnede kalır.
            Slider(value: position, in: positionRange, step: 1) { editing in
                if editing { beginEditing() }
            }
            .tint(Theme.yellow)
            .frame(minHeight: 44)
            .accessibilityLabel(editsDefault ? "Genel altyazı yüksekliği" : "Bu grubun yüksekliği")
            .accessibilityValue("Yüzde \(Int((position.wrappedValue / 10.8).rounded()))")

            HStack {
                Button { adjust(by: -5) } label: {
                    Label("Aşağı", systemImage: "arrow.down").frame(minHeight: 44)
                }
                .disabled(position.wrappedValue <= SubtitlePosition.range.lowerBound)
                Spacer()
                Button { adjust(by: 5) } label: {
                    Label("Yukarı", systemImage: "arrow.up").frame(minHeight: 44)
                }
                .disabled(position.wrappedValue >= positionRange.upperBound)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.yellow)

            if !editsDefault && selectedGroup.first?.subtitleMarginV != nil {
                Button("Bu grubu genel konuma döndür") {
                    beginEditing()
                    words = VideoProcessor.shared.applyingSubtitleMarginV(nil, to: selectedGroup, in: words)
                }
                .font(.caption)
                .frame(minHeight: 44)
                .foregroundStyle(Theme.yellow)
            }

            Text(editsDefault
                 ? "Özel konumu olmayan gruplara uygulanır. Sahneye özel ayarlar korunur."
                 : "Yalnız seçili kelime grubunu taşır. Ayarlarken video durur; diğer grupların konumu korunur.")
                .font(.caption2)
                .foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(groups.isEmpty)
    }

    private func selectGroup(_ index: Int) {
        guard groups.indices.contains(index) else { return }
        let group = groups[index]
        selectedWordID = group.first?.id
        onSelect(group)
    }

    private func beginEditing() {
        selectedWordID = selectedGroup.first?.id
        onSelect(selectedGroup)
    }

    private func adjust(by amount: Double) {
        beginEditing()
        position.wrappedValue = min(positionRange.upperBound, SubtitlePosition.clamped(position.wrappedValue + amount))
    }
}
