import SwiftUI
import AVKit
import UIKit

// MARK: - 3 Adımlı İlerleme Göstergesi (Video → Düzenle → Kaydet)
struct StepIndicator: View {
    let currentIndex: Int
    private let steps = ["Video", "Satırlar", "Zaman", "Kaydet"]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                stepCircle(index)
                if index < 3 {
                    Rectangle()
                        .fill(index < currentIndex ? Theme.yellow : Color(white: 0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 15)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func stepCircle(_ index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if index == currentIndex {
                    Circle()
                        .stroke(Theme.yellow, lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
                Circle()
                    .fill(index < currentIndex ? Theme.yellow : Color(white: 0.16))
                    .frame(width: 26, height: 26)
                if index < currentIndex {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.black)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(index == currentIndex ? Theme.yellow : .gray)
                }
            }
            .frame(width: 32, height: 32)
            Text(steps[index])
                .font(.caption2)
                .foregroundColor(index == currentIndex ? Theme.yellow : .gray)
        }
        .frame(width: 52)
    }
}

// MARK: - Durum Banner'ı (başarı / hata / bilgi)
// Hata durumunda ham teknik log doğrudan gösterilmez; "Teknik Detay" altında gizlenir.
struct StatusBanner: View {
    let message: String

    @State private var showDetails = false

    private enum Kind { case error, success, info }

    private var kind: Kind {
        if message.hasPrefix("Hata:") { return .error }
        if message.contains("🎉") || message.contains("başarıyla") { return .success }
        return .info
    }

    private var summary: String {
        if kind == .error && message.count > 140 {
            return String(message.prefix(140)) + "…"
        }
        return message
    }

    private var logFileURL: URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hata_kaydi.txt")
        try? message.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundColor(color)
                Text(summary)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if kind == .error {
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView {
                            Text(message)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 140)

                        HStack(spacing: 16) {
                            Button {
                                UIPasteboard.general.string = message
                            } label: {
                                Label("Kopyala", systemImage: "doc.on.doc")
                            }
                            if let url = logFileURL {
                                ShareLink(item: url) {
                                    Label("Paylaş", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.yellow)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Teknik Detay")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch kind {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .error: return .red
        case .success: return .green
        case .info: return .gray
        }
    }
}

// MARK: - Yatay Kaydırmalı Font Seçici Çipleri
struct FontChipPicker: View {
    let fonts: [FontOption]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(fonts) { font in
                    let isSelected = font.psName == selection
                    Button {
                        Theme.haptic()
                        selection = font.psName
                    } label: {
                        VStack(spacing: 4) {
                            Text("Abc")
                                .font(.custom(font.psName, size: 22))
                                .foregroundColor(isSelected ? Theme.yellow : .white)
                            Text(font.display)
                                .font(.caption2)
                                .foregroundColor(isSelected ? Theme.yellow : .gray)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 74)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(white: isSelected ? 0.16 : 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Theme.yellow : Theme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - İkonlu Slider Satırı
struct LabeledSlider: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(Theme.yellow)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                ValueBadge(text: "\(Int(value))")
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.yellow)
        }
    }
}

// MARK: - Canlı Altyazı Ön İzlemeli Video Oynatıcı
struct SubtitlePreviewPlayer: View {
    let player: AVPlayer?
    let fontName: String
    let fontSize: Double
    let marginV: Double
    let sampleText: String
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.isMuted = true
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                }

                // 1080p referans yüksekliğine göre ölçeklenmiş canlı altyazı bindirmesi
                if !sampleText.isEmpty {
                    Text(sampleText)
                        .font(.custom(fontName, size: CGFloat(fontSize) * (geo.size.height / 1080.0)))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .padding(.bottom, CGFloat(marginV) * (geo.size.height / 1080.0))
                }
            }
        }
        .frame(height: height)
        .background(Color.black)
        .cornerRadius(14)
        .clipped()
    }
}
