import XCTest
@testable import SubByAudiocraft

final class ProjectHistoryCompatibilityTests: XCTestCase {
    func testExistingProjectSurvivesUpgradeSaveAndBackupRecovery() throws {
        // Gerçek kullanıcı klasörüne dokunmadan önceki sürümün dosya düzeni.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID()
        let firstID = UUID()
        let lastID = UUID()
        let directory = root.appendingPathComponent(projectID.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("video.mov")
        let videoData = Data("unchanged source video".utf8)
        try videoData.write(to: video)
        let json = """
        {
          "id":"\(projectID)","olusturma":100,"guncelleme":200,
          "baslik":"Çok uğraştım",
          "kelimeler":[
            {"id":"\(firstID)","text":"Çok","start":1.25,"end":1.75},
            {"id":"\(lastID)","text":"uğraştım","start":1.8,"end":2.95}
          ],
          "satirSonlari":["\(lastID)"],"icSatirSonlari":["\(firstID)"],
          "fontAdi":"Courgette-Regular","fontBoyu":83,"dikeyKonum":345,
          "yaziRengi":"#BADA55","karaokeModu":"classic","sozTakibi":"boldWord",
          "kinetikStil":"editorial","kinetikVurgu":"custom","kinetikOzelRenk":"#12ABEF",
          "kinetikYogunluk":"subtle","kinetikVurgular":["\(lastID)"],
          "kinetikHarfStili":"clean","kinetikOverlay":"underShadow","stilSurumu":2,
          "videoDosyasi":"video.mov","disaAktarimSayisi":7
        }
        """
        let originalData = Data(json.utf8)
        let metadata = directory.appendingPathComponent("proje.json")
        try originalData.write(to: metadata)

        let store = ProjectStore(rootDirectory: root)
        let existing = try XCTUnwrap(store.projeler.first)
        XCTAssertEqual(store.projeler.count, 1)
        XCTAssertEqual(try Data(contentsOf: metadata), originalData, "Loading must not migrate or overwrite the user's file.")
        XCTAssertEqual(existing.kelimeler.map(\.id), [firstID, lastID])
        XCTAssertEqual(existing.kelimeler.map(\.start), [1.25, 1.8])
        XCTAssertEqual(existing.kelimeler.map(\.end), [1.75, 2.95])
        XCTAssertTrue(existing.kelimeler.allSatisfy { $0.subtitleMarginV == nil })
        XCTAssertEqual(existing.dikeyKonum, 345)
        XCTAssertEqual(existing.fontBoyu, 83)
        XCTAssertEqual(existing.kineticOverlayStyle, .underShadow)
        XCTAssertTrue(store.projeDosyasiMi(video))

        let positioned = VideoProcessor.shared.applyingSubtitleMarginV(
            580, to: existing.kelimeler, in: existing.kelimeler
        )
        store.guncelle(
            id: existing.id, kelimeler: positioned,
            satirSonlari: Set(existing.satirSonlari), icSatirSonlari: existing.inlineLineBreakIDs,
            fontAdi: existing.fontAdi, fontBoyu: existing.fontBoyu, dikeyKonum: existing.dikeyKonum,
            yaziRengi: existing.subtitleTextColorHex, karaokeModu: existing.karaokeMode,
            sozTakibi: existing.lyricTrackingMode, kinetikStil: existing.kineticStyle,
            kinetikVurgu: existing.kineticAccent, kinetikOzelRenk: existing.kineticCustomColorHex,
            kinetikYogunluk: existing.kineticIntensity, kinetikVurgular: existing.kineticEmphasisWordIDs,
            kinetikHarfStili: existing.kineticLetterStyle, kinetikOverlay: existing.kineticOverlayStyle,
            disaAktarildi: false
        )
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("proje.yedek.json")), originalData)
        let reopened = try XCTUnwrap(ProjectStore(rootDirectory: root).projeler.first)
        XCTAssertEqual(reopened.kelimeler, positioned)
        XCTAssertEqual(reopened.fontAdi, existing.fontAdi)
        XCTAssertEqual(reopened.fontBoyu, existing.fontBoyu)
        XCTAssertEqual(reopened.dikeyKonum, existing.dikeyKonum)
        XCTAssertEqual(reopened.satirSonlari, existing.satirSonlari)
        XCTAssertEqual(reopened.icSatirSonlari, existing.icSatirSonlari)
        XCTAssertEqual(reopened.yaziRengi, existing.yaziRengi)
        XCTAssertEqual(reopened.sozTakibi, existing.sozTakibi)
        XCTAssertEqual(reopened.kinetikStil, existing.kinetikStil)
        XCTAssertEqual(reopened.kinetikOzelRenk, existing.kinetikOzelRenk)
        XCTAssertEqual(reopened.kinetikVurgular, existing.kinetikVurgular)
        XCTAssertEqual(reopened.kinetikOverlay, existing.kinetikOverlay)
        XCTAssertEqual(reopened.disaAktarimSayisi, 7)
        XCTAssertEqual(reopened.olusturma, existing.olusturma)
        XCTAssertEqual(reopened.videoDosyasi, existing.videoDosyasi)
        XCTAssertEqual(try Data(contentsOf: video), videoData)

        // Yarım/bozuk kayıt geçmişten kaybolmaya veya kaynak videonun silinmesine yol açmaz.
        try Data("{".utf8).write(to: metadata)
        let recovered = try XCTUnwrap(ProjectStore(rootDirectory: root).projeler.first)
        XCTAssertEqual(recovered.kelimeler, existing.kelimeler)
        XCTAssertEqual(recovered.dikeyKonum, existing.dikeyKonum)
        XCTAssertEqual(try Data(contentsOf: video), videoData)
        XCTAssertEqual(try Data(contentsOf: metadata), Data("{".utf8))
    }
}
