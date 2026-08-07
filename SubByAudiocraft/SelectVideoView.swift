import SwiftUI
import PhotosUI
import AVKit

// İlk ekran yalnızca videoyu ve analiz tercihini toplar. Görsel tasarım,
// gerçek sözler oluşmadan anlamlı olmadığı için Tasarım adımında yapılır.
struct SelectVideoView: View {
    @Binding var selectedItem: PhotosPickerItem?
    let player: AVPlayer?
    @Binding var analysisQuality: AnalysisQuality
    @Binding var vocalIsolationMode: VocalIsolationMode
    @Binding var groqAPIKey: String
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
                    Text(analysisBadge)
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
                    .foregroundColor(
                        analysisQuality == .best
                            ? .orange
                            : (analysisQuality == .cloud ? Theme.yellow : .gray)
                    )
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(Theme.cardStroke)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Vokal Temizleme", systemImage: "music.note.list")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("Final ses korunur")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.green)
                    }

                    Picker("Vokal Temizleme", selection: $vocalIsolationMode) {
                        ForEach(VocalIsolationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(vocalIsolationMode.detail)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)

                    if vocalIsolationMode.usesVocalIsolation {
                        Label(
                            "İlk kullanımda yalnız vokal modeli yaklaşık \(VocalIsolationService.approximateDownloadMegabytes) MB indirilir.",
                            systemImage: "arrow.down.circle"
                        )
                        .font(.caption2)
                        .foregroundColor(.green)
                    }
                }

                if analysisQuality == .cloud {
                    cloudAPIKeyEditor
                }

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

    private var analysisBadge: String {
        switch analysisQuality {
        case .balanced: return "Yerel öneri"
        case .cloud: return "En güçlü"
        default: return analysisQuality.title
        }
    }

    private var cloudAPIKeyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Theme.cardStroke)

            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundColor(Theme.yellow)
                SecureField("gsk_… Groq API anahtarı", text: $groqAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white)

                if !groqAPIKey.isEmpty {
                    Button {
                        Theme.haptic()
                        groqAPIKey = ""
                        SecureAPIKeyStore.deleteGroqAPIKey()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Groq anahtarını sil")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        GroqSpeechClient.isPlausibleAPIKey(groqAPIKey)
                            ? Color.green.opacity(0.6)
                            : Theme.cardStroke,
                        lineWidth: 1
                    )
            )
            .onChange(of: groqAPIKey) {
                SecureAPIKeyStore.saveGroqAPIKey(groqAPIKey)
            }

            if GroqSpeechClient.isPlausibleAPIKey(groqAPIKey) {
                Label("Anahtar iPhone Keychain'de güvenli saklanıyor.", systemImage: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Text("Ücretsiz Groq anahtarını girince Bulut Hassas kullanılabilir.")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            Link(
                destination: URL(string: "https://console.groq.com/keys")!
            ) {
                Label("Ücretsiz Groq anahtarı oluştur", systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.yellow)
            }

            Text(
                "Bu modda yalnız analiz edilen ses Groq'ya gönderilir. "
                + "Diğer modlar tamamen cihazda çalışır. Bulut hatasında yerel analiz otomatik başlar."
            )
            .font(.caption2)
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
        }
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
