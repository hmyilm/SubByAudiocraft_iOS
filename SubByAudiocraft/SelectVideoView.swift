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
    let fonts: [FontOption]

    var body: some View {
        VStack(spacing: 16) {
            if player == nil {
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
            } else {
                // Video seçili: canlı ön izleme + video değiştirme
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "play.rectangle.fill", title: "Canlı Ön İzleme")

                    SubtitlePreviewPlayer(
                        player: player,
                        fontName: fontName,
                        fontSize: fontSize,
                        marginV: marginV,
                        sampleText: "Altyazı Ön İzleme",
                        height: 260
                    )

                    PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                        Label("Videoyu Değiştir", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.yellow)
                    }
                }
                .card()

                // Stil paneli
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(icon: "paintbrush.fill", title: "Altyazı Tasarımı")
                    FontChipPicker(fonts: fonts, selection: $fontName)
                    LabeledSlider(icon: "textformat.size", title: "Yazı Büyüklüğü", value: $fontSize, range: 30...150, step: 1)
                    LabeledSlider(icon: "arrow.up.and.down", title: "Dikey Konum", value: $marginV, range: 30...950, step: 5)
                }
                .card()
            }
        }
    }
}
