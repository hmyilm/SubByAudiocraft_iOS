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

    @State private var expandedWordID: UUID? = nil
    @State private var previewLine: String = ""
    @State private var previewWords: [VideoProcessor.WordTimestamp] = []
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
                        isMuted: false
                    )

                    Label(
                        "Sarı kelime o anda söylenen bölümü gösterir; sesi dinleyerek zamanlamayı kontrol edebilirsin.",
                        systemImage: "waveform"
                    )
                    .font(.caption2)
                    .foregroundColor(.gray)

                    // Font burada da değiştirilebilir: Geçmiş'ten açılan projelerde
                    // 1. adıma (video seçme) dönüş yoktur, stilin tamamı bu ekrandan yönetilir.
                    FontChipPicker(fonts: FontCatalog.hepsi, selection: $fontName)

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
        if let line = lines.first(where: { group in
            guard let first = group.first, let last = group.last else { return false }
            return t >= first.start - 0.2 && t <= last.end + 0.2
        }) {
            previewLine = line.map { $0.text }.joined(separator: " ")
            previewWords = line
        } else {
            previewLine = ""
            previewWords = []
        }
    }

    private func deleteWord(_ id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        let endedLine = breaks.remove(id) != nil
        if endedLine, index > 0 {
            breaks.insert(words[index - 1].id)
        }
        words.remove(at: index)
        if expandedWordID == id { expandedWordID = nil }
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
