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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
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
        let rootPath = kokKlasor.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func yukle() {
        let fm = FileManager.default
        let klasorler = (try? fm.contentsOfDirectory(at: kokKlasor, includingPropertiesForKeys: nil)) ?? []
        var liste: [SavedProject] = []
        for dir in klasorler {
            let json = dir.appendingPathComponent("proje.json")
            if let data = try? Data(contentsOf: json),
               let proje = try? JSONDecoder().decode(SavedProject.self, from: data),
               fm.fileExists(atPath: videoURL(proje).path) {
                liste.append(proje)
            }
        }
        projeler = liste.sorted { $0.guncelleme > $1.guncelleme }
    }

    @discardableResult
    private func yaz(_ proje: SavedProject) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(proje)
            try data.write(to: klasor(proje.id).appendingPathComponent("proje.json"), options: .atomic)
            return true
        } catch {
            print("Proje kaydedilemedi: \(error.localizedDescription)")
            return false
        }
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
        var kaynakTasindi = false
        do {
            try fm.moveItem(at: kaynak, to: hedef)
            kaynakTasindi = true
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

        guard yaz(proje) else {
            // Taşıma yapıldıysa kullanıcı akışındaki geçici kaynağı geri koymayı dene.
            if kaynakTasindi, !fm.fileExists(atPath: kaynak.path) {
                try? fm.moveItem(at: hedef, to: kaynak)
            }
            try? fm.removeItem(at: hedefKlasor)
            return nil
        }

        // moveItem dosya sağlayıcısı nedeniyle başarısız olup kopyalama kullanıldıysa,
        // kalıcı proje güvenle yazıldıktan sonra artık geçici kopyaya ihtiyaç yoktur.
        if !kaynakTasindi {
            try? fm.removeItem(at: kaynak)
        }
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
        guard yaz(proje) else { return }
        projeler.remove(at: idx)
        projeler.insert(proje, at: 0)
    }

    func sil(_ proje: SavedProject) {
        let folder = klasor(proje.id)
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            projeler.removeAll { $0.id == proje.id }
        } catch {
            print("Proje silinemedi: \(error.localizedDescription)")
        }
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
