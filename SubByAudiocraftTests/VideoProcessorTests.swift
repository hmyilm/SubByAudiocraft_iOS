import XCTest
@testable import SubByAudiocraft

final class VideoProcessorTests: XCTestCase {
    func testAutomaticGroupingLimitsLineToFourWords() {
        let words = makeWords(["bir", "iki", "üç", "dört", "beş"])

        let groups = VideoProcessor.shared.autoLineGroups(for: words)

        XCTAssertEqual(groups.map(\.count), [4, 1])
        XCTAssertEqual(groups.flatMap { $0 }.map(\.text), words.map(\.text))
    }

    func testAutomaticGroupingStartsNewLineAfterLongPause() {
        var words = makeWords(["merhaba", "dünya", "yeniden"])
        words[2].start = words[1].end + 0.81
        words[2].end = words[2].start + 0.3

        let groups = VideoProcessor.shared.autoLineGroups(for: words)

        XCTAssertEqual(groups.map(\.count), [2, 1])
    }

    func testAutomaticBreaksContainEveryGroupEnd() {
        let words = makeWords(["a", "b", "c", "d", "e", "f"])

        let groups = VideoProcessor.shared.autoLineGroups(for: words)
        let breaks = VideoProcessor.shared.autoLineBreaks(for: words)

        XCTAssertEqual(breaks, Set(groups.compactMap { $0.last?.id }))
    }

    func testRenderSpaceRequirementUsesSafeMinimumAndScalesWithInput() {
        let megabyte = Int64(1_024 * 1_024)

        XCTAssertEqual(
            VideoProcessor.shared.renderSpaceRequirement(forInputBytes: 1 * megabyte),
            350 * megabyte
        )
        XCTAssertEqual(
            VideoProcessor.shared.renderSpaceRequirement(forInputBytes: 500 * megabyte),
            1_000 * megabyte
        )
    }

    func testBestQualityUsesMemorySafeModelsOnLowerMemoryDevices() {
        let belowThreshold = AnalysisQuality.largeModelMinimumPhysicalMemory - 1

        XCTAssertEqual(
            AnalysisQuality.best.modelCandidates(physicalMemory: belowThreshold),
            ["openai_whisper-small", "openai_whisper-base"]
        )
    }

    func testBestQualityKeepsLargeModelOnCapableDevices() {
        let candidates = AnalysisQuality.best.modelCandidates(
            physicalMemory: AnalysisQuality.largeModelMinimumPhysicalMemory
        )

        XCTAssertEqual(candidates.first, "openai_whisper-large-v3-v20240930_626MB")
        XCTAssertTrue(candidates.contains("openai_whisper-small"))
    }

    func testRecognitionNormalizationMergesOnlyOverlappingDuplicates() {
        let duplicateA = VideoProcessor.WordTimestamp(text: "Sevda", start: 0.0, end: 0.5)
        let duplicateB = VideoProcessor.WordTimestamp(text: "sevda", start: 0.05, end: 0.55)
        let intentionalRepeat = VideoProcessor.WordTimestamp(text: "sevda", start: 0.7, end: 1.0)

        let normalized = VideoProcessor.shared.normalizeRecognizedWords([
            duplicateA,
            duplicateB,
            intentionalRepeat
        ])

        XCTAssertEqual(normalized.map(\.text), ["Sevda", "sevda"])
        XCTAssertEqual(normalized[0].end, 0.55, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].start, 0.7, accuracy: 0.0001)
    }

    func testRecognizedTextCleanupNormalizesWhitespaceAndPunctuation() {
        XCTAssertEqual(
            VideoProcessor.shared.cleanRecognizedText("  Kara\u{00A0}   Sevda!!!  "),
            "Kara Sevda"
        )
    }

    func testRecognitionNormalizationRemovesMusicMarkersAndRepairsOverlap() {
        let words = [
            VideoProcessor.WordTimestamp(text: "[MÜZİK]", start: 0.0, end: 0.4),
            VideoProcessor.WordTimestamp(text: "kara", start: 0.2, end: 1.0),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.6, end: 0.9)
        ]

        let normalized = VideoProcessor.shared.normalizeRecognizedWords(words)

        XCTAssertEqual(normalized.map(\.text), ["kara", "sevda"])
        XCTAssertEqual(normalized[0].end, normalized[1].start, accuracy: 0.0001)
        XCTAssertGreaterThan(normalized[0].end, normalized[0].start)
        XCTAssertGreaterThan(normalized[1].end, normalized[1].start)
    }

    func testRenderPreparationRepairsInvalidTimesAndClampsToVideo() {
        let firstID = UUID()
        let words = [
            VideoProcessor.WordTimestamp(id: firstID, text: "  kara  ", start: .nan, end: .infinity),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.02, end: 2.0),
            VideoProcessor.WordTimestamp(text: "fazla", start: 5.0, end: 6.0)
        ]

        let prepared = VideoProcessor.shared.prepareWordsForRendering(words, maximumTime: 1.0)

        XCTAssertEqual(prepared.count, 2)
        XCTAssertEqual(prepared[0].id, firstID)
        XCTAssertEqual(prepared[0].text, "kara")
        XCTAssertEqual(prepared[0].end, prepared[1].start, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(prepared[1].end, 1.0)
    }

    func testRenderPreparationLeavesValidWordsUnchanged() {
        let words = makeWords(["kara", "sevda"])

        let prepared = VideoProcessor.shared.prepareWordsForRendering(words, maximumTime: 10)

        XCTAssertEqual(prepared, words)
    }

    func testFittedFontSizeOnlyShrinksOverflowingLines() {
        XCTAssertEqual(
            VideoProcessor.shared.fittedFontSize(
                requested: 70,
                measuredWidth: 400,
                maximumWidth: 500
            ),
            70
        )
        XCTAssertEqual(
            VideoProcessor.shared.fittedFontSize(
                requested: 70,
                measuredWidth: 700,
                maximumWidth: 500
            ),
            50
        )
    }

    private func makeWords(_ texts: [String]) -> [VideoProcessor.WordTimestamp] {
        texts.enumerated().map { index, text in
            let start = Double(index) * 0.4
            return VideoProcessor.WordTimestamp(text: text, start: start, end: start + 0.3)
        }
    }
}
