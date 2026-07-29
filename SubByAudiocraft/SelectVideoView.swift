import SwiftUI
import PhotosUI
import AVKit

// İlk ekran yalnızca videoyu ve analiz tercihini toplar. Görsel tasarım,
// gerçek sözler oluşmadan anlamlı olmadığı için Tasarım adımında yapılır.
struct SelectVideoView: View {
    @Binding var selectedItem: PhotosPickerItem?
    let player: AVPlayer?
    @Binding var analysisQuality: AnalysisQuality
    let isLoadingVideo: Bool

    @State private var showsAnalysisOptions = false

    var body: some View {
        VStack(spacing: 16) {
            if player == nil {
                videoImportCard
            } else {
                selectedVideoCard
                analysisCard
            }
        }
    }

    @ViewBuilder
    private var videoImportCard: some View {
        if isLoadingVideo {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Theme.yellow)
                    .scaleEffect(1.2)

                Text("Video hazırlanıyor")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)

                Text("Büyük videoların hazırlanması birkaç saniye sürebilir.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .importCard()
        } else {
            PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.yellow.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 30))
                            .foregroundColor(Theme.yellow)
                    }

                    Text("Galeriden Video Seç")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)

                    Text("Videodaki sözleri cihazında çözümler,\nsonra birlikte kontrol edip tasarlarsın.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .importCard()
            }
            .accessibilityHint("Altyazı oluşturmak istediğin videoyu galeriden seçer.")
        }
    }

    private var selectedVideoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "play.rectangle.fill", title: "Seçilen Video")

            VideoPlayer(player: player)
                .frame(height: 250)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Label("Video hazır", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)

                Spacer()

                PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                    Label("Değiştir", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.yellow)
                        .frame(minHeight: 44)
                }
            }
        }
        .card()
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Theme.haptic()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsAnalysisOptions.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .foregroundColor(Theme.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Söz Analizi")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("\(analysisQuality.title) seçili")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text(analysisQuality == .balanced ? "Önerilen" : analysisQuality.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Theme.yellow)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.yellow.opacity(0.12)))
                    Image(systemName: showsAnalysisOptions ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Söz analizi, \(analysisQuality.title)")
            .accessibilityHint(showsAnalysisOptions ? "Analiz seçeneklerini kapatır." : "Analiz seçeneklerini açar.")

            if showsAnalysisOptions {
                Divider()
                    .overlay(Theme.cardStroke)

                Picker("Analiz Kalitesi", selection: $analysisQuality) {
                    ForEach(AnalysisQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                Text(analysisQuality.detail)
                    .font(.caption)
                    .foregroundColor(analysisQuality == .best ? .orange : .gray)
                    .fixedSize(horizontal: false, vertical: true)

                if let qwenModelID = analysisQuality.qwenModelID() {
                    Label(
                        qwenModelID.contains("5bit")
                            ? "Şarkı modeli ilk kullanımda yaklaşık 1 GB indirilir."
                            : "Şarkı modeli ilk kullanımda yaklaşık 680 MB indirilir.",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption2)
                    .foregroundColor(.green)
                }

                if analysisQuality == .best {
                    Label(
                        analysisQuality.usesMemorySafeFallback
                            ? "iPhone belleğini korumak için modeller sırayla çalıştırılır."
                            : "Daha büyük zamanlama modeli nedeniyle analiz daha uzun sürebilir.",
                        systemImage: analysisQuality.usesMemorySafeFallback
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundColor(analysisQuality.usesMemorySafeFallback ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}

private extension View {
    func importCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                .foregroundColor(Theme.yellow.opacity(0.5))
        )
    }
}
