import SwiftUI

// Geçmiş: kaydedilmiş projelerin listesi. Bir projeye dokununca düzenleyicide yeniden
// açılır; sözler, satır düzeni ve stil ayarları kaldığı yerden devam eder.
struct HistoryView: View {
    @ObservedObject var store: ProjectStore
    let onOpen: (SavedProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var silinecek: SavedProject? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                if store.projeler.isEmpty {
                    bosDurum
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.projeler) { proje in
                                projeSatiri(proje)
                            }

                            Text("Projeler videolarıyla birlikte uygulama içinde saklanır. Yer açmak için kullanmadıklarını silebilirsin.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Geçmiş")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundColor(Theme.yellow)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Proje silinsin mi?", isPresented: Binding(
            get: { silinecek != nil },
            set: { acik in if !acik { silinecek = nil } }
        )) {
            Button("Sil", role: .destructive) {
                if let proje = silinecek { store.sil(proje) }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        } message: {
            Text("Projenin videosu ve tüm düzenlemeleri kalıcı olarak silinir. Galerine kaydettiğin videolar etkilenmez.")
        }
    }

    private var bosDurum: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.yellow.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.yellow)
            }
            Text("Henüz kayıtlı proje yok")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
            Text("Bir video analiz ettiğinde projen otomatik olarak\nburaya kaydedilir; sonradan açıp yeniden\ndüzenleyebilir ve tekrar dışa aktarabilirsin.")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func projeSatiri(_ proje: SavedProject) -> some View {
        HStack(spacing: 12) {
            kapak(proje)

            VStack(alignment: .leading, spacing: 4) {
                Text(proje.baslik)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(proje.guncelleme.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)

                HStack(spacing: 6) {
                    Text("\(proje.kelimeler.count) kelime")
                    if proje.disaAktarimSayisi > 0 {
                        Text("•")
                        Text("\(proje.disaAktarimSayisi) kez dışa aktarıldı")
                    }
                }
                .font(.caption2)
                .foregroundColor(Theme.yellow.opacity(0.85))
            }

            Spacer(minLength: 0)

            Button {
                silinecek = proje
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundColor(.red.opacity(0.8))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            Theme.haptic()
            onOpen(proje)
        }
    }

    private func kapak(_ proje: SavedProject) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.14))
            if let img = UIImage(contentsOfFile: store.kapakURL(proje).path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
