import SwiftUI
import AVKit

// Adım 2: Ön izleme + kelime düzenleme listesi
struct EditWordsView: View {
    @Binding var words: [VideoProcessor.WordTimestamp]
    let player: AVPlayer?
    let fontName: String
    @Binding var fontSize: Double
    @Binding var marginV: Double

    @State private var expandedWordID: UUID? = nil

    var body: some View {
        VStack(spacing: 16) {
            if player != nil {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "play.rectangle.fill", title: "Ön İzleme")

                    SubtitlePreviewPlayer(
                        player: player,
                        fontName: fontName,
                        fontSize: fontSize,
                        marginV: marginV,
                        sampleText: words.isEmpty ? "Altyazı Ön İzleme" : words.prefix(3).map { $0.text }.joined(separator: " "),
                        height: 200
                    )

                    HStack(spacing: 12) {
                        LabeledSlider(icon: "textformat.size", title: "Boyut", value: $fontSize, range: 30...150, step: 1)
                        LabeledSlider(icon: "arrow.up.and.down", title: "Konum", value: $marginV, range: 30...950, step: 5)
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
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedWordID = (expandedWordID == word.id) ? nil : word.id
                                    }
                                },
                                onDelete: {
                                    words.removeAll { $0.id == word.id }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .card()
        }
    }
}

// Tek kelime satırı: varsayılan sade görünüm; zaman çipine dokununca +/- kontrolleri açılır
struct WordRow: View {
    @Binding var word: VideoProcessor.WordTimestamp
    let isExpanded: Bool
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
