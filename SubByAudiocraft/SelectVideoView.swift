import SwiftUI
import PhotosUI
import AVKit

// Adım 1: Video seçimi ve altyazı stil ayarları
struct SelectVideoView: View {
    @Binding var selectedItem: PhotosPickerItem?
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
    @Binding var analysisQuality: AnalysisQuality
    let isLoadingVideo: Bool
    let fonts: [FontOption]

    var body: some View {
        VStack(spacing: 16) {
            if player == nil {
                if isLoadingVideo {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(Theme.yellow)
                            .scaleEffect(1.2)
                        Text("Video hazırlanıyor")
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.white)
                        Text("Büyük videoların kopyalanması birkaç saniye sürebilir.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .fill(Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                            .foregroundColor(Theme.yellow.opacity(0.5))
                    )
                } else {
                    // Boş durum: kesikli konturlu büyük yükleme kartı
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
                            Text("Videondaki konuşma veya şarkı sözleri\notomatik olarak altyazıya dönüştürülür.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                        .background(
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
            } else {
                // Video seçili: canlı ön izleme + video değiştirme
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "play.rectangle.fill", title: "Canlı Ön İzleme")

                    SubtitlePreviewPlayer(
                        player: player,
                        fontName: fontName,
                        fontSize: fontSize,
                        marginV: marginV,
                        sampleText: karaokeMode == .kinetic ? "Söz Ritme Dönüşür" : "Altyazı Ön İzleme",
                        height: 260,
                        karaokeMode: karaokeMode,
                        lyricTrackingMode: lyricTrackingMode,
                        kineticStyle: kineticStyle,
                        kineticAccent: kineticAccent,
                        kineticCustomColorHex: kineticCustomColorHex,
                        kineticIntensity: kineticIntensity,
                        kineticLetterStyle: kineticLetterStyle,
                        kineticOverlayStyle: kineticOverlayStyle
                    )

                    PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                        Label("Videoyu Değiştir", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.yellow)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "cpu.fill", title: "Analiz Kalitesi")

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
                                ? "Ücretsiz ve cihaz içinde çalışan Qwen3 şarkı modeli ilk kullanımda yaklaşık 1 GB indirilir. Analiz sırasında uygulamayı açık tut."
                                : "Ücretsiz ve cihaz içinde çalışan Qwen3 şarkı modeli ilk kullanımda yaklaşık 680 MB indirilir. Analiz sırasında uygulamayı açık tut.",
                            systemImage: "music.note.list"
                        )
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if analysisQuality == .best {
                        Label(
                            analysisQuality.usesMemorySafeFallback
                                ? "Bu cihazın belleğine uygun modeller sırayla çalıştırılır; aynı anda belleğe yüklenmez."
                                : "Büyük zamanlama modeli daha uzun sürebilir; analiz sırasında uygulamayı açık tut.",
                            systemImage: analysisQuality.usesMemorySafeFallback
                                ? "checkmark.shield.fill"
                                : "exclamationmark.triangle.fill"
                        )
                            .font(.caption2)
                            .foregroundColor(analysisQuality.usesMemorySafeFallback ? .green : .orange)
                    }
                }
                .card()

                // Stil paneli
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(icon: "paintbrush.fill", title: "Altyazı Tasarımı")
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
                    Divider()
                        .overlay(Theme.cardStroke)
                    FontChipPicker(
                        fonts: fonts,
                        selection: $fontName,
                        karaokeMode: karaokeMode,
                        kineticStyle: kineticStyle
                    )
                    LabeledSlider(icon: "textformat.size", title: "Yazı Büyüklüğü", value: $fontSize, range: 30...150, step: 1)
                    LabeledSlider(icon: "arrow.up.and.down", title: "Dikey Konum", value: $marginV, range: 30...950, step: 5)
                }
                .card()
            }
        }
    }
}
