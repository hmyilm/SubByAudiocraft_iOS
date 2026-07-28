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

    private func makeWords(_ texts: [String]) -> [VideoProcessor.WordTimestamp] {
        texts.enumerated().map { index, text in
            let start = Double(index) * 0.4
            return VideoProcessor.WordTimestamp(text: text, start: start, end: start + 0.3)
        }
    }
}
