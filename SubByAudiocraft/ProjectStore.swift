import Foundation
import AVFoundation
import UIKit

// Kaydedilmiş proje: kaynak video + sözler + satır düzeni + stil ayarları.
// Geçmiş ekranından yeniden açılıp düzenlenebilir ve tekrar dışa aktarılabilir;
// böylece dışa aktarılan video beğenilmezse analiz baştan yapılmak zorunda kalmaz.
struct SavedProject: Identifiable, Codable {
    var id: UUID
    var olusturma: Date
    var guncelleme: Date
    var baslik: String
    var kelimeler: [VideoProcessor.WordTimestamp]
    var satirSonlari: [UUID]
    var fontAdi: String
    var fontBoyu: Double
    var dikeyKonum: Double
    var videoDosyasi: String
    var disaAktarimSayisi: Int
}

// Projeleri Documents/Projeler/<uuid>/ klasörlerinde saklar:
// proje.json (sözler + ayarlar), video.<uzantı> (kaynak video), kapak.jpg (liste görseli).
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published private(set) var projeler: [SavedProject] = []

    private let kokKlasor: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        kokKlasor = docs.appendingPathComponent("Projeler", isDirectory: true)
        try? FileManager.default.createDirectory(at: kokKlasor, withIntermediateDirectories: true)
        yukle()
    }

    private func klasor(_ id: UUID) -> URL {
        kokKlasor.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func videoURL(_ proje: SavedProject) -> URL {
        klasor(proje.id).appendingPathComponent(proje.videoDosyasi)
    }

    func kapakURL(_ proje: SavedProject) -> URL {
        klasor(proje.id).appendingPathComponent("kapak.jpg")
    }

    // Bir dosyanın proje klasörüne ait olup olmadığı: proje videoları geçici dosya
    // temizliklerinde SİLİNMEMELİDİR (yalnız Geçmiş'ten silinirler).
    func projeDosyasiMi(_ url: URL) -> Bool {
        url.path.hasPrefix(kokKlasor.path)
    }

    private func yukle() {
        let fm = FileManager.default
        let klasorler = (try? fm.contentsOfDirectory(at: kokKlasor, includingPropertiesForKeys: nil)) ?? []
        var liste: [SavedProject] = []
        for dir in klasorler {
            let json = dir.appendingPathComponent("proje.json")
            if let data = try? Data(contentsOf: json),
               let proje = try? JSONDecoder().decode(SavedProject.self, from: data) {
                liste.append(proje)
            }
        }
        projeler = liste.sorted { $0.guncelleme > $1.guncelleme }
    }

    private func yaz(_ proje: SavedProject) {
        guard let data = try? JSONEncoder().encode(proje) else { return }
        try? data.write(to: klasor(proje.id).appendingPathComponent("proje.json"), options: .atomic)
    }

    private static func baslikUret(_ kelimeler: [VideoProcessor.WordTimestamp]) -> String {
        let baslik = kelimeler.prefix(5).map { $0.text }.joined(separator: " ")
        return baslik.isEmpty ? "Adsız proje" : baslik
    }

    // Yeni proje oluşturur; kaynak videoyu geçici klasörden kalıcı proje klasörüne TAŞIR.
    // Başarılıysa çağıran taraf videoURL(_:) adresini kullanmalıdır (eski geçici yol artık yoktur).
    func olustur(videoURL kaynak: URL,
                 kelimeler: [VideoProcessor.WordTimestamp],
                 satirSonlari: Set<UUID>,
                 fontAdi: String,
                 fontBoyu: Double,
                 dikeyKonum: Double) -> SavedProject? {
        let id = UUID()
        let fm = FileManager.default
        let hedefKlasor = klasor(id)
        do {
            try fm.createDirectory(at: hedefKlasor, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let uzanti = kaynak.pathExtension.isEmpty ? "mp4" : kaynak.pathExtension
        let dosyaAdi = "video." + uzanti
        let hedef = hedefKlasor.appendingPathComponent(dosyaAdi)
        do {
            try fm.moveItem(at: kaynak, to: hedef)
        } catch {
            do {
                try fm.copyItem(at: kaynak, to: hedef)
            } catch {
                try? fm.removeItem(at: hedefKlasor)
                return nil
            }
        }

        let proje = SavedProject(
            id: id,
            olusturma: Date(),
            guncelleme: Date(),
            baslik: Self.baslikUret(kelimeler),
            kelimeler: kelimeler,
            satirSonlari: Array(satirSonlari),
            fontAdi: fontAdi,
            fontBoyu: fontBoyu,
            dikeyKonum: dikeyKonum,
            videoDosyasi: dosyaAdi,
            disaAktarimSayisi: 0
        )
        yaz(proje)
        projeler.insert(proje, at: 0)
        kapakOlustur(proje)
        return proje
    }

    // Düzenlemeleri kaydeder; disaAktarildi=true ise dışa aktarım sayacını artırır.
    func guncelle(id: UUID,
                  kelimeler: [VideoProcessor.WordTimestamp],
                  satirSonlari: Set<UUID>,
                  fontAdi: String,
                  fontBoyu: Double,
                  dikeyKonum: Double,
                  disaAktarildi: Bool) {
        guard let idx = projeler.firstIndex(where: { $0.id == id }) else { return }
        var proje = projeler[idx]
        proje.kelimeler = kelimeler
        proje.satirSonlari = Array(satirSonlari)
        proje.fontAdi = fontAdi
        proje.fontBoyu = fontBoyu
        proje.dikeyKonum = dikeyKonum
        proje.baslik = Self.baslikUret(kelimeler)
        proje.guncelleme = Date()
        if disaAktarildi { proje.disaAktarimSayisi += 1 }
        projeler.remove(at: idx)
        projeler.insert(proje, at: 0)
        yaz(proje)
    }

    func sil(_ proje: SavedProject) {
        try? FileManager.default.removeItem(at: klasor(proje.id))
        projeler.removeAll { $0.id == proje.id }
    }

    // Liste için küçük kapak görseli (videonun ilk yarım saniyesinden bir kare)
    private func kapakOlustur(_ proje: SavedProject) {
        let asset = AVAsset(url: videoURL(proje))
        let uretici = AVAssetImageGenerator(asset: asset)
        uretici.appliesPreferredTrackTransform = true
        uretici.maximumSize = CGSize(width: 320, height: 320)
        let hedef = kapakURL(proje)
        DispatchQueue.global(qos: .utility).async {
            let zaman = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cg = try? uretici.copyCGImage(at: zaman, actualTime: nil),
               let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) {
                try? data.write(to: hedef)
            }
        }
    }
}
