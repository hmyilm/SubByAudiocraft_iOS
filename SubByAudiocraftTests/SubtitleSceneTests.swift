import XCTest
@testable import SubByAudiocraft

final class SubtitleSceneTests: XCTestCase {
    private let processor = VideoProcessor.shared

    private func words() -> [VideoProcessor.WordTimestamp] {
        [
            .init(text: "ilk", start: 0.5, end: 0.9),
            .init(text: "sahne", start: 1, end: 1.4),
            .init(text: "yeni", start: 3, end: 3.4),
            .init(text: "sahne", start: 3.5, end: 4)
        ]
    }

    func testPositionOnlyChangesSelectedGroupAndSurvivesSplitAndDeletion() throws {
        let original = words()
        let edited = processor.applyingSubtitleMarginV(600, to: Array(original.suffix(2)), in: original)
        XCTAssertEqual(Array(edited.prefix(2)), Array(original.prefix(2)))
        XCTAssertEqual(edited.suffix(2).map(\.subtitleMarginV), [600, 600])

        let restored = try JSONDecoder().decode(
            [VideoProcessor.WordTimestamp].self, from: JSONEncoder().encode(edited)
        )
        XCTAssertEqual(restored, edited)
        let split = processor.subtitleGroups(for: restored, lineBreaks: Set(restored.map(\.id)))
        XCTAssertEqual(split.map { processor.subtitleMarginV(for: $0, defaultMarginV: 120) }, [120, 120, 600, 600])
        XCTAssertEqual(processor.subtitleMarginV(for: [restored[3]], defaultMarginV: 120), 600)

        let reset = processor.applyingSubtitleMarginV(nil, to: Array(restored.suffix(2)), in: restored)
        XCTAssertTrue(reset.allSatisfy { $0.subtitleMarginV == nil })
        XCTAssertEqual(reset.map(\.id), original.map(\.id))
    }

    func testMergedGroupsUseFirstWordsPositionAndNoBreaksMeansOneGroup() {
        let original = words()
        let edited = processor.applyingSubtitleMarginV(600, to: Array(original.suffix(2)), in: original)
        let groups = processor.subtitleGroups(for: edited, lineBreaks: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(processor.subtitleMarginV(for: groups[0], defaultMarginV: 145), 145)
    }

    func testOldWordRecordsDecodeWithoutPositionAndRenderingKeepsNewPositions() throws {
        let id = UUID()
        let json = """
        {"id":"\(id)","text":"Çığlık","start":1.25,"end":2.5}
        """
        var word = try JSONDecoder().decode(VideoProcessor.WordTimestamp.self, from: Data(json.utf8))
        XCTAssertNil(word.subtitleMarginV)
        XCTAssertEqual(word.id, id)
        word.subtitleMarginV = 580
        let prepared = processor.prepareWordsForRendering([word], maximumTime: 2)
        XCTAssertEqual(prepared.first?.subtitleMarginV, 580)
        XCTAssertEqual(prepared.first?.id, id)
        XCTAssertEqual(prepared.first?.end, 2)
        XCTAssertEqual(processor.normalizeRecognizedWords([word]).first?.subtitleMarginV, 580)
    }

    func testPositionBoundsKeepTwoRowsVisible() {
        XCTAssertEqual(SubtitlePosition.clamped(.nan), 120)
        XCTAssertEqual(SubtitlePosition.clamped(-50), 30)
        XCTAssertEqual(SubtitlePosition.clamped(5000), 950)
        XCTAssertEqual(SubtitlePosition.visibleMargin(950, fontSize: 150, rowCount: 2), 756)
        XCTAssertEqual(SubtitlePosition.visibleMargin(120, fontSize: 70, rowCount: 1), 120)
    }

    func testEveryExportModeMovesOnlyThePositionedScene() {
        let original = words()
        let edited = processor.applyingSubtitleMarginV(580, to: Array(original.suffix(2)), in: original)

        for font in ["Courgette-Regular", "Poppins-Bold"] {
            for karaokeMode in KaraokeMode.allCases {
                for trackingMode in LyricTrackingMode.allCases {
                    for twoRows in [false, true] {
                        func render(_ words: [VideoProcessor.WordTimestamp]) -> [String] {
                            processor.makeASSContent(
                                words: words,
                                lineBreaks: [words[1].id],
                                inlineLineBreaks: twoRows ? [words[0].id, words[2].id] : [],
                                fontName: font, fontSize: 70, marginV: 120,
                                karaokeMode: karaokeMode, lyricTrackingMode: trackingMode,
                                virtualWidth: 608
                            ).components(separatedBy: "\n").filter { $0.hasPrefix("Dialogue:") }
                        }
                        let before = render(original)
                        let after = render(edited)
                        let label = "\(font), \(karaokeMode), \(trackingMode), rows: \(twoRows)"
                        func inFirstScene(_ line: String) -> Bool {
                            let time = line.components(separatedBy: ",")[1]
                            let seconds = Double(time.components(separatedBy: ":").last!)!
                            return seconds < 2
                        }
                        XCTAssertFalse(before.isEmpty, label)
                        XCTAssertEqual(before.filter(inFirstScene), after.filter(inFirstScene), label)
                        XCTAssertNotEqual(before.filter { !inFirstScene($0) }, after.filter { !inFirstScene($0) }, label)
                    }
                }
            }
        }
    }

    func testCourgetteUsesVisibleSameColorStrokeOnlyDuringActiveWord() {
        let ass = processor.makeBoldWordDialogues(
            group: words(), segStart: 0, segEnd: 5,
            fontName: "Courgette-Regular", fontSize: 70, marginV: 120,
            virtualWidth: 608, virtualHeight: 1080, accent: .coral
        )
        let active = ass.components(separatedBy: "\n").filter { $0.hasPrefix("Dialogue: 2,") }
        let inactive = ass.components(separatedBy: "\n").filter { $0.hasPrefix("Dialogue: 1,") }
        XCTAssertEqual(active.count, 4)
        XCTAssertTrue(active.allSatisfy { $0.contains("\\fnCourgette\\fs70\\b400") && $0.contains("\\bord1.540\\3c&H7A5CFF&") })
        XCTAssertTrue(inactive.allSatisfy { $0.contains("\\bord0\\shad0") })
        XCTAssertTrue(ass.contains("Dialogue: 2,0:00:00.50,0:00:00.90"))
        XCTAssertEqual(FontCatalog.syntheticBoldStrokeWidth(for: "Poppins-Bold", fontSize: 70), 0)
    }
}
