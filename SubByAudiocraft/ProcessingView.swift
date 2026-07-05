import SwiftUI

// İşlem aşamaları: ekranda hangi adımın aktif olduğunu göstermek için kullanılır
enum ProcessingStage: Int, CaseIterable {
    case extractingAudio
    case transcribing
    case burning
    case saving

    var title: String {
        switch self {
        case .extractingAudio: return "Ses videodan çıkarılıyor"
        case .transcribing: return "Yapay zeka sözleri çözümlüyor"
        case .burning: return "Altyazılar videoya gömülüyor"
        case .saving: return "Galeriye kaydediliyor"
        }
    }
}

// Adım 3: Markalı işlem ekranı — nabız animasyonu + aşama listesi
struct ProcessingView: View {
    let stage: ProcessingStage
    let message: String
    var downloadProgress: Double? = nil

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Theme.yellow.opacity(0.25), lineWidth: 3)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.18 : 0.95)
                    .opacity(pulse ? 0.3 : 1.0)
                Circle()
                    .fill(Theme.yellow.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "waveform")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.yellow)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(ProcessingStage.allCases, id: \.rawValue) { item in
                    HStack(spacing: 10) {
                        if item.rawValue < stage.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if item == stage {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.yellow))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(Color(white: 0.3))
                        }
                        Text(item.title)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(item == stage ? .semibold : .regular)
                            .foregroundColor(item == stage ? .white : (item.rawValue < stage.rawValue ? .gray : Color(white: 0.4)))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 8)

            // Model ilk kez indirilirken ilerleme çubuğu gösterilir
            if let progress = downloadProgress, progress < 1.0 {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .tint(Theme.yellow)
                    Text("Yapay zeka modeli indiriliyor: %\(Int(progress * 100))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
            }

            Text(message)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .card()
    }
}
