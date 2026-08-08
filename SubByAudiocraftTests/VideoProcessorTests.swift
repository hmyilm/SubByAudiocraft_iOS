import XCTest
@testable import SubByAudiocraft

final class VideoProcessorTests: XCTestCase {
    func testPortraitPreviewUsesOnlyTheAspectFitVideoViewport() {
        let rect = VideoProcessor.shared.aspectFitRect(
            contentSize: CGSize(width: 1080, height: 1920),
            in: CGSize(width: 360, height: 200)
        )

        XCTAssertEqual(rect.width, 112.5, accuracy: 0.001)
        XCTAssertEqual(rect.height, 200, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 123.75, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
    }

    func testLandscapePreviewUsesTheCenteredAspectFitVideoViewport() {
        let rect = VideoProcessor.shared.aspectFitRect(
            contentSize: CGSize(width: 1920, height: 1080),
            in: CGSize(width: 360, height: 240)
        )

        XCTAssertEqual(rect.width, 360, accuracy: 0.001)
        XCTAssertEqual(rect.height, 202.5, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 18.75, accuracy: 0.001)
    }

    func testInvalidPresentationSizeFallsBackToTheWholePreview() {
        let rect = VideoProcessor.shared.aspectFitRect(
            contentSize: .zero,
            in: CGSize(width: 360, height: 200)
        )

        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 360, height: 200))
    }

    func testSelectedModesResolveToDedicatedExportPaths() {
        let processor = VideoProcessor.shared

        XCTAssertEqual(
            processor.subtitleRenderPath(
                karaokeMode: .kinetic,
                lyricTrackingMode: .karaoke,
                usesConnectedFont: false
            ),
            .kinetic
        )
        XCTAssertEqual(
            processor.subtitleRenderPath(
                karaokeMode: .kinetic,
                lyricTrackingMode: .karaoke,
                usesConnectedFont: true
            ),
            .connectedKinetic
        )
        XCTAssertEqual(
            processor.subtitleRenderPath(
                karaokeMode: .classic,
                lyricTrackingMode: .boldWord,
                usesConnectedFont: false
            ),
            .boldWord
        )
        XCTAssertEqual(
            processor.subtitleRenderPath(
                karaokeMode: .kinetic,
                lyricTrackingMode: .boldWord,
                usesConnectedFont: true
            ),
            .boldWord
        )
        XCTAssertEqual(
            processor.subtitleRenderPath(
                karaokeMode: .kinetic,
                lyricTrackingMode: .centeredWordReveal,
                usesConnectedFont: true
            ),
            .centeredWordReveal
        )
        XCTAssertEqual(
            processor.subtitleRenderPath(
                karaokeMode: .classic,
                lyricTrackingMode: .karaoke,
                usesConnectedFont: false
            ),
            .classicKaraoke
        )
    }

    func testEveryModeCombinationResolvesToOneStableExportPath() {
        for karaokeMode in KaraokeMode.allCases {
            for trackingMode in LyricTrackingMode.allCases {
                for connected in [false, true] {
                    var expected: SubtitleRenderPath
                    switch trackingMode {
                    case .boldWord:
                        expected = .boldWord
                    case .centeredReveal:
                        expected = .centeredCharacterReveal
                    case .centeredWordReveal:
                        expected = .centeredWordReveal
                    case .off:
                        expected = karaokeMode == .kinetic ? .kinetic : .staticLine
                        if connected && karaokeMode == .kinetic {
                            expected = .connectedKinetic
                        }
                    case .karaoke:
                        expected = karaokeMode == .kinetic ? .kinetic : .classicKaraoke
                        if connected && karaokeMode == .kinetic {
                            expected = .connectedKinetic
                        }
                    }

                    XCTAssertEqual(
                        VideoProcessor.shared.subtitleRenderPath(
                            karaokeMode: karaokeMode,
                            lyricTrackingMode: trackingMode,
                            usesConnectedFont: connected
                        ),
                        expected,
                        "\(karaokeMode.rawValue)/\(trackingMode.rawValue)/\(connected)"
                    )
                }
            }
        }
    }

    func testDefaultASSStyleIsFlatWithoutImplicitOutlineOrShadow() {
        let style = VideoProcessor.shared.makeDefaultASSStyleLine(
            familyName: "Montserrat",
            fontSize: 70,
            isBold: false,
            marginV: 120
        )
        let fields = style.split(separator: ",", omittingEmptySubsequences: false)

        XCTAssertEqual(fields.count, 23)
        XCTAssertEqual(fields[16], "0", "Outline varsayılan olarak kapalı olmalı")
        XCTAssertEqual(fields[17], "0", "Shadow varsayılan olarak kapalı olmalı")
        XCTAssertEqual(fields[3], "&H00FFFFFF")
    }

    func testChronologicalWordSortPlacesNewWordAtItsTimestamp() {
        var words = makeWords(["bir", "iki", "üç"])
        let inserted = VideoProcessor.WordTimestamp(
            text: "yeni",
            start: 0.2,
            end: 0.35
        )
        words.append(inserted)

        let sorted = VideoProcessor.shared.chronologicallySortedWords(words)

        XCTAssertEqual(sorted.map(\.text), ["bir", "yeni", "iki", "üç"])
        XCTAssertEqual(sorted[1].id, inserted.id)
    }

    func testChronologicalWordSortKeepsEqualTimedWordsStable() {
        let first = VideoProcessor.WordTimestamp(text: "ilk", start: 1, end: 1.4)
        let second = VideoProcessor.WordTimestamp(text: "ikinci", start: 1, end: 1.4)

        let sorted = VideoProcessor.shared.chronologicallySortedWords([first, second])

        XCTAssertEqual(sorted.map(\.id), [first.id, second.id])
    }

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

    func testAutomaticGroupingHonorsNaturalPhrasePunctuation() {
        let words = makeWords(["seni", "bekledim,", "ama", "gelmedin"])

        let groups = VideoProcessor.shared.autoLineGroups(for: words)

        XCTAssertEqual(groups.map { $0.map(\.text) }, [
            ["seni", "bekledim,"],
            ["ama", "gelmedin"]
        ])
    }

    func testAutomaticBreaksContainEveryGroupEnd() {
        let words = makeWords(["a", "b", "c", "d", "e", "f"])

        let groups = VideoProcessor.shared.autoLineGroups(for: words)
        let breaks = VideoProcessor.shared.autoLineBreaks(for: words)

        XCTAssertEqual(breaks, Set(groups.compactMap { $0.last?.id }))
    }

    func testInlineBreakKeepsOneTimedPhraseButCreatesTwoVisualRows() {
        let words = makeWords(["hep", "birlikte", "burada", "kalalım"])
        let inlineBreaks = Set([words[1].id])

        let rows = VideoProcessor.shared.visualLineGroups(
            for: words,
            inlineLineBreaks: inlineBreaks
        )

        XCTAssertEqual(rows.map { $0.map(\.text) }, [
            ["hep", "birlikte"],
            ["burada", "kalalım"]
        ])

        let bold = VideoProcessor.shared.makeBoldWordDialogues(
            group: words,
            segStart: 0,
            segEnd: 2,
            fontName: "Anton-Regular",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            inlineLineBreaks: inlineBreaks
        )
        XCTAssertFalse(bold.contains("hep birlikte\\Nburada kalalım"))
        XCTAssertTrue(bold.contains("}hep"))
        XCTAssertTrue(bold.contains("}birlikte"))
        XCTAssertTrue(bold.contains("}burada"))
        XCTAssertTrue(bold.contains("}kalalım"))
        XCTAssertTrue(bold.contains("\\pos("))
        XCTAssertTrue(bold.contains(",890)"))
        XCTAssertTrue(bold.contains(",960)"))

        let connected = VideoProcessor.shared.makeConnectedKaraokeRowsDialogues(
            group: words,
            inlineLineBreaks: inlineBreaks,
            segStart: 0,
            segEnd: 2,
            fontName: "PetitFormalScript-Regular",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080
        )
        let connectedDialogues = connected.components(separatedBy: "\n").filter {
            $0.hasPrefix("Dialogue:")
        }
        XCTAssertEqual(connectedDialogues.count, 4)
        XCTAssertTrue(connectedDialogues.contains { $0.hasSuffix("}hep birlikte") })
        XCTAssertTrue(connectedDialogues.contains { $0.hasSuffix("}burada kalalım") })

        let reveal = VideoProcessor.shared.makeCenteredWordRevealDialogues(
            group: words,
            segStart: 0,
            segEnd: 2,
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            inlineLineBreaks: inlineBreaks
        )
        XCTAssertTrue(reveal.contains("\\N"))

        let characterReveal = VideoProcessor.shared.makeCenteredRevealDialogues(
            group: words,
            segStart: 0,
            segEnd: 2,
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            inlineLineBreaks: inlineBreaks
        )
        XCTAssertTrue(characterReveal.contains("\\N"))

        let kinetic = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 2,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            style: .impact,
            inlineLineBreaks: inlineBreaks
        )
        let kineticTextDialogues = kinetic.components(separatedBy: "\n").filter {
            $0.hasPrefix("Dialogue: 2,") || $0.hasPrefix("Dialogue: 3,")
        }
        XCTAssertEqual(kineticTextDialogues.count, words.count)
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

    func testBalancedQualityUsesFiveBitSongModelOnIPhone14ClassMemory() {
        XCTAssertEqual(
            AnalysisQuality.balanced.qwenModelID(
                physicalMemory: AnalysisQuality.qwenFiveBitMinimumPhysicalMemory
            ),
            "aufklarer/Qwen3-ASR-0.6B-MLX-5bit"
        )
        XCTAssertNil(AnalysisQuality.fast.qwenModelID(physicalMemory: UInt64.max))
    }

    func testSongModelFallsBackToFourBitOnLowerMemoryDevices() {
        XCTAssertEqual(
            AnalysisQuality.best.qwenModelID(
                physicalMemory: AnalysisQuality.qwenFiveBitMinimumPhysicalMemory - 1
            ),
            "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        )
    }

    func testCloudQualityUsesBalancedLocalFallback() {
        XCTAssertTrue(AnalysisQuality.cloud.usesCloudTranscription)
        XCTAssertEqual(AnalysisQuality.cloud.localFallbackQuality, .balanced)
        XCTAssertEqual(
            AnalysisQuality.cloud.modelCandidates(physicalMemory: UInt64.max),
            AnalysisQuality.balanced.modelCandidates(physicalMemory: UInt64.max)
        )
        XCTAssertNil(AnalysisQuality.cloud.qwenModelID(physicalMemory: UInt64.max))
    }

    func testVocalIsolationDefaultsToAutomaticAndCanBeDisabled() {
        XCTAssertEqual(VocalIsolationMode.resolved(nil), .automatic)
        XCTAssertTrue(VocalIsolationMode.automatic.usesVocalIsolation)
        XCTAssertFalse(VocalIsolationMode.off.usesVocalIsolation)
    }

    func testVocalIsolationChunkPlanCoversEverySampleExactlyOnce() {
        let chunks = VocalIsolationService.chunkPlan(
            totalSamples: 1_000,
            coreSamples: 300,
            contextSamples: 40
        )

        XCTAssertEqual(chunks.map(\.outputRange), [
            0..<300,
            300..<600,
            600..<900,
            900..<1_000
        ])
        XCTAssertEqual(chunks.first?.inputRange, 0..<340)
        XCTAssertEqual(chunks[1].inputRange, 260..<640)
        XCTAssertEqual(chunks.last?.inputRange, 860..<1_000)
        XCTAssertEqual(
            chunks.flatMap { Array($0.outputRange) },
            Array(0..<1_000)
        )
        XCTAssertTrue(chunks.allSatisfy {
            $0.localOutputRange.count == $0.outputRange.count
                && $0.localOutputRange.lowerBound >= 0
                && $0.localOutputRange.upperBound <= $0.inputRange.count
        })
    }

    func testVocalIsolationDownmixKeepsLengthAndCentersStereo() {
        let mono = VocalIsolationService.downmixToMono(
            left: [1, 0.5, -1],
            right: [-1, 0.5, 1]
        )

        XCTAssertEqual(mono, [0, 0.5, 0])
    }

    func testUnderShadowOverlayFollowsOnlyActiveKaraokeWord() {
        XCTAssertTrue(KineticOverlayStyle.underShadow.requiresKaraokeTracking)
        XCTAssertTrue(KineticOverlayStyle.spotlight.requiresKaraokeTracking)
        XCTAssertFalse(KineticOverlayStyle.glass.requiresKaraokeTracking)
    }

    func testGroqAPIKeyValidationDoesNotAcceptGoogleOrIncompleteKeys() {
        XCTAssertTrue(
            GroqSpeechClient.isPlausibleAPIKey(
                "  gsk_123456789012345678901234  "
            )
        )
        XCTAssertFalse(
            GroqSpeechClient.isPlausibleAPIKey(
                "AIzaSyExampleGoogleKey"
            )
        )
        XCTAssertFalse(GroqSpeechClient.isPlausibleAPIKey("gsk_short"))
    }

    func testGroqResponseDecodesWordLevelTimestamps() throws {
        let data = Data(
            """
            {
              "text": "Kara sevda",
              "words": [
                {"word": " Kara", "start": 0.12, "end": 0.48},
                {"word": "sevda", "start": 0.52, "end": 1.04}
              ]
            }
            """.utf8
        )

        let words = try GroqSpeechClient.shared.decodeWordTimestamps(from: data)

        XCTAssertEqual(words.map(\.text), ["Kara", "sevda"])
        XCTAssertEqual(words[0].start, 0.12, accuracy: 0.0001)
        XCTAssertEqual(words[1].end, 1.04, accuracy: 0.0001)
    }

    func testGroqResponseWithoutWordTimestampsIsRejected() {
        let data = Data(#"{"text":"Kara sevda"}"#.utf8)

        XCTAssertThrowsError(
            try GroqSpeechClient.shared.decodeWordTimestamps(from: data)
        ) { error in
            guard let clientError = error as? GroqSpeechClient.ClientError,
                  case .missingWordTimestamps = clientError else {
                return XCTFail("Beklenmeyen hata: \(error)")
            }
        }
    }

    func testGroqRestoresFullTranscriptPunctuationToTimedWords() throws {
        let data = Data(
            #"{"text":"Merhaba, nasılsın? İyiyim!","words":[{"word":"Merhaba","start":0.1,"end":0.5},{"word":"nasılsın","start":0.6,"end":1.0},{"word":"İyiyim","start":1.1,"end":1.5}]}"#.utf8
        )

        let words = try GroqSpeechClient.shared.decodeWordTimestamps(from: data)

        XCTAssertEqual(words.map(\.text), ["Merhaba,", "nasılsın?", "İyiyim!"])
    }

    func testRecognitionNormalizationMergesOnlyOverlappingDuplicates() {
        let duplicateA = VideoProcessor.WordTimestamp(text: "Sevda", start: 0.0, end: 0.5)
        let duplicateB = VideoProcessor.WordTimestamp(text: "sevda,", start: 0.05, end: 0.55)
        let intentionalRepeat = VideoProcessor.WordTimestamp(text: "sevda", start: 0.7, end: 1.0)

        let normalized = VideoProcessor.shared.normalizeRecognizedWords([
            duplicateA,
            duplicateB,
            intentionalRepeat
        ])

        XCTAssertEqual(normalized.map(\.text), ["Sevda,", "sevda"])
        XCTAssertEqual(normalized[0].end, 0.55, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].start, 0.7, accuracy: 0.0001)
    }

    func testRecognizedTextCleanupNormalizesWhitespaceAndPunctuation() {
        XCTAssertEqual(
            VideoProcessor.shared.cleanRecognizedText("  Kara\u{00A0}   Sevda !!!  "),
            "Kara Sevda!!!"
        )
    }

    func testLyricTokenizationKeepsTurkishPunctuationAndDropsMarkers() {
        XCTAssertEqual(
            VideoProcessor.shared.lyricWords(
                from: #"[MÜZİK] “Merhaba,” nasılsın? İyiyim! ♪"#
            ),
            ["Merhaba,", "nasılsın?", "İyiyim!"]
        )
    }

    func testTurkishQuestionWordsAddQuestionMarkToPhraseEnding() {
        let words = [
            VideoProcessor.WordTimestamp(text: "merhaba", start: 0.0, end: 0.35),
            VideoProcessor.WordTimestamp(text: "nasılsın", start: 0.42, end: 0.85)
        ]

        let normalized = VideoProcessor.shared.normalizeRecognizedWords(words)

        XCTAssertEqual(normalized.map(\.text), ["merhaba", "nasılsın?"])
    }

    func testQuestionMarkMovesToLastWordAndRespectsPauseBoundary() {
        let words = [
            VideoProcessor.WordTimestamp(text: "neden", start: 0.0, end: 0.25),
            VideoProcessor.WordTimestamp(text: "böyle", start: 0.30, end: 0.60),
            VideoProcessor.WordTimestamp(text: "yaptın", start: 0.66, end: 1.0),
            VideoProcessor.WordTimestamp(text: "hava", start: 1.80, end: 2.05),
            VideoProcessor.WordTimestamp(text: "güzel", start: 2.10, end: 2.42)
        ]

        let normalized = VideoProcessor.shared.normalizeRecognizedWords(words)

        XCTAssertEqual(
            normalized.map(\.text),
            ["neden", "böyle", "yaptın?", "hava", "güzel"]
        )
    }

    func testExistingQuestionPunctuationIsNotDuplicated() {
        let words = [
            VideoProcessor.WordTimestamp(text: "nasılsın?", start: 0.0, end: 0.5)
        ]

        XCTAssertEqual(
            VideoProcessor.shared.normalizeRecognizedWords(words).map(\.text),
            ["nasılsın?"]
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

    func testSecondTimingPassPreservesOnsetsAndOnlyExtendsNearbyWords() {
        let primary = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "sevda", start: 1.5, end: 2.0)
        ]
        let secondary = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.2, end: 1.6),
            VideoProcessor.WordTimestamp(text: "sevda", start: 1.7, end: 2.2)
        ]

        let merged = VideoProcessor.shared.mergeTimingPasses(
            primary: primary,
            secondary: secondary
        )

        XCTAssertEqual(merged.map(\.text), ["kara", "sevda"])
        XCTAssertEqual(merged[0].start, 1.0, accuracy: 0.0001)
        XCTAssertEqual(merged[1].start, 1.5, accuracy: 0.0001)
        XCTAssertEqual(merged[0].end, 1.45, accuracy: 0.0001)
        XCTAssertEqual(merged[1].end, 2.05, accuracy: 0.0001)
        XCTAssertTrue(zip(merged, merged.dropFirst()).allSatisfy { pair in
            pair.0.end <= pair.1.start
        })
    }

    func testSecondTimingPassRejectsLargeTimingShift() {
        let primary = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "sevda", start: 1.5, end: 2.0)
        ]
        let shifted = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.8, end: 2.2),
            VideoProcessor.WordTimestamp(text: "sevda", start: 2.3, end: 2.8)
        ]

        let merged = VideoProcessor.shared.mergeTimingPasses(
            primary: primary,
            secondary: shifted
        )

        XCTAssertEqual(merged.map(\.start), primary.map(\.start))
        XCTAssertEqual(merged.map(\.end), primary.map(\.end))
    }

    func testQwenTranscriptCorrectsWordsWithoutLosingWhisperTiming() throws {
        let timed = [
            VideoProcessor.WordTimestamp(text: "kara", start: 2.0, end: 2.4),
            VideoProcessor.WordTimestamp(text: "sefta", start: 2.5, end: 2.9),
            VideoProcessor.WordTimestamp(text: "yandı", start: 3.0, end: 3.6)
        ]

        let aligned = try XCTUnwrap(
            VideoProcessor.shared.alignEnhancedTranscriptWords(
                ["kara", "sevda", "yandı"],
                to: timed
            )
        )

        XCTAssertEqual(aligned.map(\.text), ["kara", "sevda", "yandı"])
        XCTAssertEqual(aligned.map(\.start), timed.map(\.start))
        XCTAssertGreaterThan(aligned[2].end, aligned[2].start)
    }

    func testQwenTranscriptUsesTwoStrongNeighborsForCompleteWordCorrection() throws {
        let timed = [
            VideoProcessor.WordTimestamp(text: "kara", start: 2.0, end: 2.4),
            VideoProcessor.WordTimestamp(text: "bilmem", start: 2.5, end: 2.9),
            VideoProcessor.WordTimestamp(text: "sevda", start: 3.0, end: 3.6)
        ]

        let aligned = try XCTUnwrap(
            VideoProcessor.shared.alignEnhancedTranscriptWords(
                ["kara", "yaktın", "sevda"],
                to: timed
            )
        )

        XCTAssertEqual(aligned.map(\.text), ["kara", "yaktın", "sevda"])
        XCTAssertEqual(aligned.map(\.start), timed.map(\.start))
        XCTAssertEqual(aligned.map(\.end), timed.map(\.end))
    }

    func testQwenTranscriptInterpolatesAnInsertedWordMonotonically() throws {
        let timed = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "sevda", start: 2.0, end: 2.5)
        ]

        let aligned = try XCTUnwrap(
            VideoProcessor.shared.alignEnhancedTranscriptWords(
                ["kara", "bir", "sevda"],
                to: timed
            )
        )

        XCTAssertEqual(aligned.map(\.text), ["kara", "bir", "sevda"])
        XCTAssertEqual(aligned[0].start, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThan(aligned[1].start, aligned[0].start)
        XCTAssertLessThan(aligned[1].start, aligned[2].start)
        XCTAssertEqual(aligned[2].start, 2.0, accuracy: 0.0001)
    }

    func testQwenTranscriptDoesNotInventWordInsideTightTimingGap() throws {
        let timed = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.48),
            VideoProcessor.WordTimestamp(text: "sevda", start: 1.5, end: 2.0)
        ]

        let aligned = try XCTUnwrap(
            VideoProcessor.shared.alignEnhancedTranscriptWords(
                ["kara", "bir", "sevda"],
                to: timed
            )
        )

        XCTAssertEqual(aligned.map(\.text), ["kara", "sevda"])
        XCTAssertEqual(aligned.map(\.start), timed.map(\.start))
    }

    func testQwenTranscriptDropsSungVowelInsteadOfMakingCaptionWord() throws {
        let timed = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "sevda", start: 2.0, end: 2.5)
        ]

        let aligned = try XCTUnwrap(
            VideoProcessor.shared.alignEnhancedTranscriptWords(
                ["kara", "aaaa", "sevda"],
                to: timed
            )
        )

        XCTAssertEqual(aligned.map(\.text), ["kara", "sevda"])
        XCTAssertEqual(aligned.map(\.start), timed.map(\.start))
    }

    func testQwenTranscriptRejectsUnrelatedWindow() {
        let timed = [
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "sevda", start: 1.5, end: 2.0),
            VideoProcessor.WordTimestamp(text: "yandı", start: 2.1, end: 2.6)
        ]

        XCTAssertNil(
            VideoProcessor.shared.alignEnhancedTranscriptWords(
                ["gece", "çok", "uzun"],
                to: timed
            )
        )
    }

    func testRecognitionNormalizationMergesMelismaIntoPreviousWordDuration() {
        let words = [
            VideoProcessor.WordTimestamp(text: "sevda", start: 1.0, end: 1.5),
            VideoProcessor.WordTimestamp(text: "aaaa", start: 1.54, end: 2.2),
            VideoProcessor.WordTimestamp(text: "yakıyor", start: 2.4, end: 2.9)
        ]

        let normalized = VideoProcessor.shared.normalizeRecognizedWords(words)

        XCTAssertEqual(normalized.map(\.text), ["sevda", "yakıyor"])
        XCTAssertEqual(normalized[0].end, 2.2, accuracy: 0.0001)
        XCTAssertEqual(normalized[1].start, 2.4, accuracy: 0.0001)
    }

    func testRecognitionNormalizationKeepsLegitimateSingleLetterWord() {
        let words = [
            VideoProcessor.WordTimestamp(text: "işte", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "o", start: 1.45, end: 1.8)
        ]

        let normalized = VideoProcessor.shared.normalizeRecognizedWords(words)

        XCTAssertEqual(normalized.map(\.text), ["işte", "o"])
    }

    func testRecognitionNormalizationDropsUnanchoredSungVowels() {
        let words = [
            VideoProcessor.WordTimestamp(text: "aaaa", start: 0.2, end: 0.8),
            VideoProcessor.WordTimestamp(text: "kara", start: 1.0, end: 1.4),
            VideoProcessor.WordTimestamp(text: "ü", start: 2.0, end: 2.3)
        ]

        let normalized = VideoProcessor.shared.normalizeRecognizedWords(words)

        XCTAssertEqual(normalized.map(\.text), ["kara"])
    }

    func testLyricRecognitionWindowsCoverEveryWordWithinMemorySafeDuration() {
        let words = (0..<90).map { index in
            let start = Double(index) * 0.55
            return VideoProcessor.WordTimestamp(
                text: "söz\(index)",
                start: start,
                end: start + 0.32
            )
        }

        let windows = VideoProcessor.shared.lyricRecognitionWindows(
            for: words,
            maximumTime: 55
        )

        XCTAssertEqual(windows.flatMap { Array($0.wordRange) }, Array(words.indices))
        XCTAssertTrue(windows.allSatisfy { $0.end > $0.start })
        XCTAssertTrue(windows.allSatisfy { $0.end - $0.start <= 14.5001 })
    }

    func testAudioFrameRangeReadsOnlyRequestedWindow() throws {
        let range = try XCTUnwrap(
            VideoProcessor.shared.audioFrameRange(
                start: 12.25,
                end: 26.75,
                sampleRate: 16_000,
                totalFrameCount: 16_000 * 60
            )
        )

        XCTAssertEqual(range.lowerBound, 196_000)
        XCTAssertEqual(range.upperBound, 428_000)
        XCTAssertEqual(range.count, 232_000)
        XCTAssertLessThan(range.count, 16_000 * 15)
    }

    func testAudioFrameRangeClampsToFileAndRejectsInvalidWindows() throws {
        let clamped = try XCTUnwrap(
            VideoProcessor.shared.audioFrameRange(
                start: -2,
                end: 80,
                sampleRate: 16_000,
                totalFrameCount: 16_000 * 60
            )
        )

        XCTAssertEqual(clamped.lowerBound, 0)
        XCTAssertEqual(clamped.upperBound, 16_000 * 60)
        XCTAssertNil(
            VideoProcessor.shared.audioFrameRange(
                start: 5,
                end: 5,
                sampleRate: 16_000,
                totalFrameCount: 16_000 * 60
            )
        )
        XCTAssertNil(
            VideoProcessor.shared.audioFrameRange(
                start: .nan,
                end: 5,
                sampleRate: 16_000,
                totalFrameCount: 16_000 * 60
            )
        )
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

    func testKineticPlanSelectsMeaningfulWordInsteadOfTurkishStopWord() {
        let words = [
            VideoProcessor.WordTimestamp(text: "ve", start: 0.0, end: 0.4),
            VideoProcessor.WordTimestamp(text: "kara", start: 0.4, end: 0.8),
            VideoProcessor.WordTimestamp(text: "sevdanın", start: 0.8, end: 1.3)
        ]

        let plan = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 0)

        XCTAssertEqual(plan.emphasisIndex, 2)
        XCTAssertEqual(plan.rows.flatMap { $0 }.sorted(), Array(words.indices))
    }

    func testKineticPlanUsesFocusCutForShortPhrase() {
        let words = makeWords(["kara", "sevda"])

        let plan = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 4)

        XCTAssertEqual(plan.scene, .focusCut)
        XCTAssertEqual(plan.rows, [[0, 1]])
    }

    func testKineticPlanRespondsToFastVocalCadence() {
        let words = [
            VideoProcessor.WordTimestamp(text: "bir", start: 0.00, end: 0.16),
            VideoProcessor.WordTimestamp(text: "anda", start: 0.17, end: 0.32),
            VideoProcessor.WordTimestamp(text: "yandım", start: 0.33, end: 0.49),
            VideoProcessor.WordTimestamp(text: "sana", start: 0.50, end: 0.68)
        ]

        let plan = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 1)

        XCTAssertEqual(plan.scene, .impactSequence)
    }

    func testKineticPlanKeepsSustainedVocalCalmAndReadable() {
        let words = [
            VideoProcessor.WordTimestamp(text: "gece", start: 0.0, end: 0.3),
            VideoProcessor.WordTimestamp(text: "bana", start: 0.4, end: 0.7),
            VideoProcessor.WordTimestamp(text: "kal", start: 0.8, end: 1.7)
        ]

        let plan = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 2)

        XCTAssertEqual(plan.scene, .phraseBuild)
        XCTAssertEqual(plan.energy, .calm)
        XCTAssertEqual(plan.motion, .softLift)
    }

    func testKineticPlanIsDeterministicAndNeverLosesAWord() {
        let words = makeWords(["gecenin", "içinde", "seni", "aradım"])

        let first = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 7)
        let second = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 7)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.pages.flatMap { $0 }.sorted(), Array(words.indices))
        XCTAssertEqual(Set(first.pages.flatMap { $0 }).count, words.count)
    }

    func testCaptionWindowBuildsStableShortPagesWithoutDroppingWords() {
        let words = makeWords(["bu", "gece", "yine", "seni", "sessizce", "aradım", "durmadan"])

        let plan = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 3)

        XCTAssertEqual(plan.scene, .captionWindow)
        XCTAssertEqual(plan.highlight, .pill)
        XCTAssertEqual(plan.motion, .pagePop)
        XCTAssertTrue(plan.pages.allSatisfy { (1...4).contains($0.count) })
        XCTAssertEqual(plan.pages.flatMap { $0 }, Array(words.indices))
    }

    func testRepeatedLyricsReceiveTheSameChorusLockup() {
        let first = makeWords(["sensiz", "geceler", "bitmiyor", "yine"])
        let second = first.enumerated().map { index, word in
            VideoProcessor.WordTimestamp(
                text: index == 3 ? "yine!" : word.text,
                start: word.start + 8,
                end: word.end + 8
            )
        }

        let plans = VideoProcessor.shared.kineticScenePlans(for: [first, second])

        XCTAssertEqual(plans.map(\.scene), [.chorusLockup, .chorusLockup])
        XCTAssertEqual(plans.map(\.repeatCount), [2, 2])
        XCTAssertEqual(plans[0].rows, plans[1].rows)
        XCTAssertEqual(plans.map(\.composition), [.centered, .centered])
        XCTAssertEqual(plans.map(\.sectionRole), [.chorus, .chorus])
    }

    func testAutomaticDirectorUsesRealSectionGapInsteadOfLineNumberRandomness() {
        let first = makeWords(["gece", "yine", "üstüme", "çöktü"])
        let second = shiftedWords(makeWords(["seni", "sessizce", "aradım"]), by: 1.6)
        let newSection = shiftedWords(makeWords(["dön", "artık", "bana"]), by: 4.0)

        let plans = VideoProcessor.shared.kineticScenePlans(
            for: [first, second, newSection]
        )

        XCTAssertEqual(plans[0].scene, .editorialStack)
        XCTAssertEqual(plans[1].scene, .captionWindow)
        XCTAssertEqual(plans[2].scene, .editorialStack)
    }

    func testAutomaticDirectorNeverUsesPunchCutOnAdjacentLines() {
        let first = makeRapidWords(["kal", "gitme", "yanımda", "bugece"], offset: 0)
        let second = makeRapidWords(["ses", "ver", "duy", "beni"], offset: 0.95)
        let third = makeRapidWords(["dön", "bana", "son", "kez"], offset: 1.90)

        let plans = VideoProcessor.shared.kineticScenePlans(for: [first, second, third])

        XCTAssertEqual(plans.map(\.motion), [.punchCut, .pagePop, .punchCut])
        for pair in zip(plans, plans.dropFirst()) {
            XCTAssertFalse(pair.0.motion == .punchCut && pair.1.motion == .punchCut)
        }
    }

    func testAutomaticDirectorAddsBreathingSceneAfterLongFlowRun() {
        let groups = [
            shiftedWords(makeWords(["gece", "yine", "seni", "aradım"]), by: 0),
            shiftedWords(makeWords(["sessiz", "sokak", "bana", "kaldı"]), by: 1.7),
            shiftedWords(makeWords(["gözlerin", "uzakta", "yanar", "hâlâ"]), by: 3.4),
            shiftedWords(makeWords(["kalbim", "adını", "söyler", "durur"]), by: 5.1)
        ]

        let plans = VideoProcessor.shared.kineticScenePlans(for: groups)

        XCTAssertEqual(
            plans.map(\.scene),
            [.editorialStack, .captionWindow, .captionWindow, .phraseBuild]
        )
    }

    func testAutomaticDirectorBuildsOneIdentityFromWholeSong() {
        let slow = [
            [
                VideoProcessor.WordTimestamp(text: "gece", start: 0.0, end: 0.8),
                VideoProcessor.WordTimestamp(text: "sessiz", start: 0.9, end: 1.8),
                VideoProcessor.WordTimestamp(text: "kalır", start: 1.9, end: 2.8)
            ],
            [
                VideoProcessor.WordTimestamp(text: "içimde", start: 3.4, end: 4.2),
                VideoProcessor.WordTimestamp(text: "izin", start: 4.3, end: 5.1),
                VideoProcessor.WordTimestamp(text: "kalır", start: 5.2, end: 6.2)
            ]
        ]
        let fast = [
            makeRapidWords(["dön", "bana", "şimdi", "hemen"], offset: 0),
            makeRapidWords(["kal", "burada", "sakın", "gitme"], offset: 1.0),
            makeRapidWords(["ses", "ver", "duy", "beni"], offset: 2.0)
        ]
        let chorus = makeWords(["sensiz", "geceler", "bitmiyor", "yine"])
        let repeated = [
            chorus,
            shiftedWords(chorus, by: 8),
            makeRapidWords(["kal", "benimle", "bu", "gece"], offset: 10)
        ]

        XCTAssertEqual(
            VideoProcessor.shared.kineticCreativeDirection(for: slow),
            .cinematicFlow
        )
        XCTAssertEqual(
            VideoProcessor.shared.kineticCreativeDirection(for: fast),
            .rhythmicPulse
        )
        XCTAssertEqual(
            VideoProcessor.shared.kineticCreativeDirection(for: repeated),
            .anthemLift
        )

        let slowPlans = VideoProcessor.shared.kineticScenePlans(for: slow)
        XCTAssertFalse(slowPlans.contains { $0.scene == .impactSequence })
        XCTAssertTrue(
            slowPlans.allSatisfy {
                let overlay = KineticOverlayStyle.automatic.resolved(for: $0)
                return overlay == .glass || overlay == .accentPanel
            }
        )
    }

    func testAutomaticPlansShareIdentityAndOnlyUseItsCompatibleSceneFamily() {
        let groups = [
            makeRapidWords(["dön", "bana", "şimdi", "hemen"], offset: 0),
            makeRapidWords(["kal", "burada", "sakın", "gitme"], offset: 1.0),
            shiftedWords(makeWords(["biraz", "nefes", "al"]), by: 2.2),
            makeRapidWords(["ses", "ver", "duy", "beni"], offset: 4.0)
        ]

        let first = VideoProcessor.shared.kineticScenePlans(for: groups)
        let second = VideoProcessor.shared.kineticScenePlans(for: groups)
        let allowedScenes: [KineticScene] = [
            .impactSequence,
            .captionWindow,
            .phraseBuild,
            .focusCut,
            .chorusLockup
        ]

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.allSatisfy { $0.creativeDirection == .rhythmicPulse })
        XCTAssertTrue(first.allSatisfy { allowedScenes.contains($0.scene) })
        XCTAssertFalse(first.contains { $0.scene == .editorialStack })
    }

    func testAutomaticOverlayUsesSongIdentityNotOnlyLocalScene() {
        let words = makeWords(["kal", "benimle"])
        let cinematic = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            creativeDirection: .cinematicFlow
        )
        let rhythmic = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            creativeDirection: .rhythmicPulse
        )

        XCTAssertEqual(cinematic.scene, .focusCut)
        XCTAssertEqual(rhythmic.scene, .focusCut)
        XCTAssertEqual(
            KineticOverlayStyle.automatic.resolved(for: cinematic),
            .glass
        )
        XCTAssertEqual(
            KineticOverlayStyle.automatic.resolved(for: rhythmic),
            .spotlight
        )
    }

    func testManualKineticStylesProduceCoherentSceneFamilies() {
        let words = makeWords(["gecenin", "içinde", "seni", "aradım"])

        let cinematic = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .cinematic
        )
        let editorial = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .editorial
        )
        let impact = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .impact
        )

        XCTAssertEqual(cinematic.scene, .phraseBuild)
        XCTAssertEqual(cinematic.highlight, .color)
        XCTAssertEqual(editorial.scene, .editorialStack)
        XCTAssertEqual(editorial.highlight, .underline)
        XCTAssertEqual(impact.scene, .impactSequence)
        XCTAssertEqual(impact.highlight, .glow)
    }

    func testManualEmphasisOverridesSemanticChoiceWithoutChangingScene() {
        let words = makeWords(["gecenin", "içinde", "seni", "aradım"])
        let automatic = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .editorial
        )
        let selected = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .editorial,
            emphasisWordID: words[1].id
        )

        XCTAssertEqual(selected.scene, automatic.scene)
        XCTAssertEqual(selected.motion, automatic.motion)
        XCTAssertEqual(selected.highlight, automatic.highlight)
        XCTAssertEqual(selected.emphasisIndex, 1)
        XCTAssertEqual(selected.rows, [[0], [1], [2, 3]])
    }

    func testPosterLetterDesignUsesTurkishUppercaseAndOneAnchorGlyph() {
        let words = makeWords(["bu", "içimde", "yanar"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            emphasisWordID: words[1].id
        )

        let design = VideoProcessor.shared.kineticGlyphDesign(
            text: words[1].text,
            wordIndex: 1,
            plan: plan,
            letterStyle: .poster
        )

        XCTAssertEqual(String(design.characters), "İÇİMDE")
        XCTAssertEqual(design.treatment, .poster)
        XCTAssertEqual(design.scaleFactors.filter { $0 == 1.32 }.count, 1)
        XCTAssertEqual(design.maximumScale, 1.32)
        XCTAssertTrue(design.scaleFactors.contains(0.90))
    }

    func testRhythmLetterDesignFollowsVowelsButLeavesOtherWordsClean() {
        let words = makeWords(["kara", "sevda", "içimde"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            emphasisWordID: words[1].id
        )

        let emphasized = VideoProcessor.shared.kineticGlyphDesign(
            text: words[1].text,
            wordIndex: 1,
            plan: plan,
            letterStyle: .rhythm
        )
        let supporting = VideoProcessor.shared.kineticGlyphDesign(
            text: words[0].text,
            wordIndex: 0,
            plan: plan,
            letterStyle: .rhythm
        )

        XCTAssertEqual(String(emphasized.characters), "SEVDA")
        XCTAssertEqual(emphasized.treatment, .rhythm)
        XCTAssertEqual(emphasized.scaleFactors.filter { $0 > 1 }.count, 3)
        XCTAssertEqual(supporting.treatment, .standard)
        XCTAssertTrue(supporting.scaleFactors.allSatisfy { $0 == 1 })
    }

    func testAutomaticLetterDesignTracksSceneFamilyInsteadOfLineNumber() {
        let words = makeWords(["sessizce", "sana", "dönerim"])
        let cinematic = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .cinematic
        )
        let editorial = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 99,
            style: .editorial
        )

        let cinematicDesign = VideoProcessor.shared.kineticGlyphDesign(
            text: words[cinematic.emphasisIndex].text,
            wordIndex: cinematic.emphasisIndex,
            plan: cinematic,
            letterStyle: .automatic
        )
        let editorialDesign = VideoProcessor.shared.kineticGlyphDesign(
            text: words[editorial.emphasisIndex].text,
            wordIndex: editorial.emphasisIndex,
            plan: editorial,
            letterStyle: .automatic
        )

        XCTAssertEqual(cinematicDesign.treatment, .wide)
        XCTAssertEqual(editorialDesign.treatment, .poster)
        XCTAssertGreaterThan(cinematicDesign.trackingFactor, 0)
    }

    func testSceneDirectorAppliesAtMostOnePersistedEmphasisPerLine() {
        let first = makeWords(["gece", "yine", "seni", "aradım"])
        let second = shiftedWords(makeWords(["dön", "artık", "bana"]), by: 1.7)
        let selections: Set<UUID> = [first[1].id, first[3].id, second[2].id]

        let plans = VideoProcessor.shared.kineticScenePlans(
            for: [first, second],
            emphasisWordIDs: selections
        )

        XCTAssertEqual(plans[0].emphasisIndex, 1)
        XCTAssertEqual(plans[1].emphasisIndex, 2)
    }

    func testSemanticDirectorPrefersEmotionalTurkishRootOverLongNeutralWord() {
        let words = [
            VideoProcessor.WordTimestamp(text: "uzaklarda", start: 0.0, end: 0.3),
            VideoProcessor.WordTimestamp(text: "sevdam", start: 0.4, end: 0.7),
            VideoProcessor.WordTimestamp(text: "duruyor", start: 0.8, end: 1.1)
        ]

        let plan = VideoProcessor.shared.kineticTypographyPlan(for: words, lineIndex: 0)

        XCTAssertEqual(plan.emphasisIndex, 1)
    }

    func testEachManualModeUsesAConsistentButVariedSceneFamily() {
        let calm = [
            VideoProcessor.WordTimestamp(text: "gece", start: 0.0, end: 0.8),
            VideoProcessor.WordTimestamp(text: "sessiz", start: 0.9, end: 1.7),
            VideoProcessor.WordTimestamp(text: "kalır", start: 1.8, end: 2.7)
        ]
        let rapid = makeRapidWords(["dön", "bana", "şimdi", "hemen"], offset: 3.0)
        let chorus = shiftedWords(makeWords(["sensiz", "geceler", "bitmiyor", "yine"]), by: 5.0)
        let chorusRepeat = shiftedWords(chorus, by: 5.0)
        let groups = [calm, rapid, chorus, chorusRepeat]

        let cinematic = VideoProcessor.shared.kineticScenePlans(for: groups, style: .cinematic)
        let editorial = VideoProcessor.shared.kineticScenePlans(for: groups, style: .editorial)
        let impact = VideoProcessor.shared.kineticScenePlans(for: groups, style: .impact)

        XCTAssertEqual(cinematic.map(\.scene), [
            .phraseBuild, .captionWindow, .chorusLockup, .chorusLockup
        ])
        XCTAssertEqual(editorial.map(\.scene), [
            .editorialStack, .captionWindow, .chorusLockup, .chorusLockup
        ])
        XCTAssertEqual(impact.map(\.scene), [
            .captionWindow, .impactSequence, .chorusLockup, .chorusLockup
        ])
        XCTAssertTrue(cinematic.allSatisfy { $0.creativeDirection == .cinematicFlow })
        XCTAssertTrue(editorial.allSatisfy { $0.creativeDirection == .editorialStory })
        XCTAssertTrue(impact.allSatisfy { $0.creativeDirection == .rhythmicPulse })
    }

    func testCompositionLanguageMatchesModeInsteadOfLineNumberRandomness() {
        let words = makeWords(["gecenin", "içinde", "seni", "aradım"])
        let cinematic = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 2,
            style: .cinematic
        )
        let editorial = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 92,
            style: .editorial
        )
        let impact = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 17,
            style: .impact
        )

        XCTAssertEqual(cinematic.composition, .centered)
        XCTAssertTrue([.splitLeading, .splitTrailing].contains(editorial.composition))
        XCTAssertEqual(impact.composition, .staircase)
        XCTAssertEqual(
            editorial.composition,
            VideoProcessor.shared.kineticTypographyPlan(
                for: words,
                lineIndex: 999,
                style: .editorial
            ).composition
        )
    }

    func testSectionEnergyShapesMotionWithoutChangingUserIntensity() {
        let calm = [
            VideoProcessor.WordTimestamp(text: "sessiz", start: 0.0, end: 0.9),
            VideoProcessor.WordTimestamp(text: "gece", start: 1.0, end: 1.9),
            VideoProcessor.WordTimestamp(text: "kalır", start: 2.0, end: 3.0)
        ]
        let rapid = makeRapidWords(["dön", "bana", "şimdi", "hemen"], offset: 3.2)

        let plans = VideoProcessor.shared.kineticScenePlans(for: [calm, rapid])

        XCTAssertEqual(plans[0].sectionRole, .opening)
        XCTAssertEqual(plans[1].sectionRole, .lift)
        XCTAssertGreaterThan(plans[1].motionGain, plans[0].motionGain)
    }

    func testSignatureLetterDesignCreatesControlledThreeLevelContrast() {
        let words = makeWords(["bu", "sevdam", "benim"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            emphasisWordID: words[1].id
        )
        let design = VideoProcessor.shared.kineticGlyphDesign(
            text: words[1].text,
            wordIndex: 1,
            plan: plan,
            letterStyle: .signature
        )

        XCTAssertEqual(String(design.characters), "SEVDAM")
        XCTAssertEqual(design.treatment, .signature)
        XCTAssertGreaterThanOrEqual(Set(design.scaleFactors).count, 4)
        XCTAssertGreaterThanOrEqual(design.maximumScale, 1.36)
        XCTAssertTrue(design.scaleFactors.contains(where: { $0 < 0.9 }))
    }

    func testKineticASSCreatesTimedLayerForEveryWord() {
        let words = [
            VideoProcessor.WordTimestamp(text: "kara", start: 0.2, end: 0.55),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.6, end: 1.0),
            VideoProcessor.WordTimestamp(text: "yakıyor", start: 1.05, end: 1.65)
        ]

        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.9,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080
        )

        let regularWords = ass.components(separatedBy: "Dialogue: 2,").count - 1
        let emphasizedWords = ass.components(separatedBy: "Dialogue: 3,").count - 1
        XCTAssertEqual(regularWords + emphasizedWords, words.count)
        XCTAssertEqual(ass.components(separatedBy: "Dialogue: 0,").count - 1, words.count)
        XCTAssertTrue(ass.contains("\\an5\\move("))
        XCTAssertTrue(ass.contains("\\p1"))
        XCTAssertTrue(ass.contains("\\c&H000000&"))
        XCTAssertTrue(ass.contains("\\t("))
        XCTAssertFalse(ass.contains("\\frz"))
        XCTAssertEqual(ass.filter { $0 == "{" }.count, ass.filter { $0 == "}" }.count)
    }

    func testKineticTwoRowExportKeepsTheLastRowOnThePreviewBaseline() {
        let words = [
            VideoProcessor.WordTimestamp(text: "kara", start: 0.2, end: 0.55),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.6, end: 1.0)
        ]
        let plan = KineticTypographyPlan(
            scene: .phraseBuild,
            motion: .lockedReveal,
            highlight: .color,
            energy: .steady,
            creativeDirection: .cinematicFlow,
            emphasisIndex: 0,
            rows: [[0], [1]],
            pages: [[0, 1]],
            repeatCount: 1
        )

        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.2,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            lyricTrackingMode: .off,
            inlineLineBreaks: [words[0].id],
            scenePlan: plan
        )
        let wordDialogues = ass.split(separator: "\n").filter {
            $0.hasPrefix("Dialogue: 2,") || $0.hasPrefix("Dialogue: 3,")
        }

        XCTAssertEqual(wordDialogues.count, 2)
        XCTAssertTrue(wordDialogues[0].contains(",868)"))
        XCTAssertTrue(wordDialogues[1].contains(",933)"))
    }

    func testKineticTrackingCanBeDisabledWithoutDisablingTypographyMotion() {
        let words = makeWords(["kara", "sevda", "içimde"])

        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .editorial,
            lyricTrackingMode: .off
        )

        let regularWords = ass.components(separatedBy: "Dialogue: 2,").count - 1
        let emphasizedWords = ass.components(separatedBy: "Dialogue: 3,").count - 1
        XCTAssertEqual(regularWords + emphasizedWords, words.count)
        XCTAssertFalse(ass.contains("\\alpha&HA0&"))
        XCTAssertFalse(ass.contains("\\c&H2FCCFE&"))
        XCTAssertTrue(ass.contains("\\move("))
    }

    func testConnectedFontKeepsSelectedKineticModeDuringExport() {
        let words = makeWords(["kara", "sevda", "içimde"])
        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "PetitFormalScript-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .cinematic,
            lyricTrackingMode: .karaoke,
            preserveConnectedGlyphs: true
        )

        XCTAssertTrue(ass.contains("\\move("))
        XCTAssertTrue(ass.contains("\\alpha&HA6&"))
        XCTAssertTrue(ass.contains("}kara"))
        XCTAssertTrue(ass.contains("}sevda"))
        XCTAssertFalse(ass.contains("}k{\\fs"))
    }

    func testCenteredRevealGrowsPrefixAndKeepsEveryEventAtSameCenter() {
        let words = [
            VideoProcessor.WordTimestamp(text: "AB", start: 0, end: 0.8),
            VideoProcessor.WordTimestamp(text: "C", start: 1.0, end: 1.4)
        ]

        let ass = VideoProcessor.shared.makeCenteredRevealDialogues(
            group: words,
            segStart: 0,
            segEnd: 1.6,
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080
        )
        let dialogues = ass
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(dialogues.count, 3)
        XCTAssertTrue(dialogues.allSatisfy { $0.contains("\\an5\\pos(304,925)") })
        XCTAssertTrue(dialogues[0].hasSuffix("}A"))
        XCTAssertTrue(dialogues[1].contains("A{\\c&H"))
        XCTAssertTrue(dialogues[1].hasSuffix("}B"))
        XCTAssertTrue(dialogues[2].contains("AB {\\c&H"))
        XCTAssertTrue(dialogues[2].hasSuffix("}C"))
        XCTAssertTrue(dialogues.allSatisfy { $0.contains("\\bord0\\shad0") })
        XCTAssertFalse(ass.contains("\\bord3"))
    }

    func testCenteredWordRevealAddsWholeWordsAndRecentersEveryEvent() {
        let words = [
            VideoProcessor.WordTimestamp(text: "Kara", start: 0.2, end: 0.7),
            VideoProcessor.WordTimestamp(text: "Sevda", start: 0.9, end: 1.5),
            VideoProcessor.WordTimestamp(text: "İçimde", start: 1.7, end: 2.3)
        ]

        let ass = VideoProcessor.shared.makeCenteredWordRevealDialogues(
            group: words,
            segStart: 0.1,
            segEnd: 2.6,
            fontName: "Poppins-Bold",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            accent: .coral
        )
        let dialogues = ass
            .split(separator: "\n")
            .map(String.init)

        XCTAssertEqual(dialogues.count, words.count)
        XCTAssertTrue(dialogues.allSatisfy { $0.contains("\\an5\\pos(304,925)") })
        XCTAssertTrue(dialogues[0].hasSuffix("}Kara"))
        XCTAssertTrue(dialogues[1].contains("Kara\\h{\\fnPoppins\\fs70\\fscx100\\fscy100\\b700\\c&H"))
        XCTAssertTrue(dialogues[1].hasSuffix("}Sevda"))
        XCTAssertTrue(dialogues[2].contains("Kara\\hSevda\\h{\\fnPoppins\\fs70\\fscx100\\fscy100\\b700\\c&H"))
        XCTAssertTrue(dialogues[2].hasSuffix("}İçimde"))
        XCTAssertFalse(dialogues.contains { $0.hasSuffix("}K") || $0.hasSuffix("}Ka") })
        XCTAssertTrue(dialogues.allSatisfy { $0.contains("\\bord0\\shad0") })
        XCTAssertTrue(dialogues.allSatisfy { $0.contains("\\fnPoppins\\b100") })
        XCTAssertTrue(dialogues.allSatisfy {
            $0.contains("\\fnPoppins\\fs70\\fscx100\\fscy100\\b700")
        })
        XCTAssertTrue(dialogues.allSatisfy { $0.contains("\\fs70\\fscx100\\fscy100") })
        XCTAssertFalse(ass.contains("\\shad1.5"))
    }

    func testCenteredWordRevealKeepsGeorgiaFamilyAndUniformActiveSize() {
        let words = [
            VideoProcessor.WordTimestamp(text: "Nasılsın?", start: 0.2, end: 0.8),
            VideoProcessor.WordTimestamp(text: "İyiyim", start: 0.9, end: 1.5)
        ]

        let ass = VideoProcessor.shared.makeCenteredWordRevealDialogues(
            group: words,
            segStart: 0.1,
            segEnd: 1.8,
            fontName: "Georgia",
            fontSize: 72,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080
        )

        XCTAssertTrue(ass.contains("\\fnGeorgia\\b400"))
        XCTAssertTrue(
            ass.contains("\\fnGeorgia\\fs72\\fscx100\\fscy100\\b700")
        )
        XCTAssertFalse(ass.contains("Times New Roman"))
        XCTAssertFalse(ass.contains("Helvetica"))
    }

    func testEveryTrackingModeHasAFunctionalRenderingPath() {
        let words = [
            VideoProcessor.WordTimestamp(text: "kara", start: 0.1, end: 0.55),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.65, end: 1.15),
            VideoProcessor.WordTimestamp(text: "içimde", start: 1.25, end: 1.85)
        ]

        for mode in LyricTrackingMode.allCases {
            let output: String
            switch mode {
            case .centeredReveal:
                output = VideoProcessor.shared.makeCenteredRevealDialogues(
                    group: words,
                    segStart: 0,
                    segEnd: 2,
                    fontSize: 70,
                    marginV: 120,
                    virtualWidth: 608,
                    virtualHeight: 1080
                )
            case .centeredWordReveal:
                output = VideoProcessor.shared.makeCenteredWordRevealDialogues(
                    group: words,
                    segStart: 0,
                    segEnd: 2,
                    fontSize: 70,
                    marginV: 120,
                    virtualWidth: 608,
                    virtualHeight: 1080
                )
            case .off, .karaoke, .boldWord:
                output = VideoProcessor.shared.makeKineticDialogues(
                    group: words,
                    lineIndex: 0,
                    segStart: 0,
                    segEnd: 2,
                    fontName: "Anton-Regular",
                    requestedFontSize: 70,
                    marginV: 120,
                    virtualWidth: 608,
                    virtualHeight: 1080,
                    lyricTrackingMode: mode
                )
            }

            XCTAssertFalse(output.isEmpty, "\(mode.title) çıktı üretmedi")
            XCTAssertTrue(output.contains("Dialogue:"), "\(mode.title) ASS diyaloğu üretmedi")
            XCTAssertFalse(output.lowercased().contains("nan"))
        }
    }

    func testEveryKineticOptionCombinationProducesValidASS() {
        let words = [
            VideoProcessor.WordTimestamp(text: "kara", start: 0.1, end: 0.55),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.65, end: 1.15),
            VideoProcessor.WordTimestamp(text: "içimde", start: 1.25, end: 1.85)
        ]

        for style in KineticStyle.allCases {
            for intensity in KineticIntensity.allCases {
                for letterStyle in KineticLetterStyle.allCases {
                    for overlayStyle in KineticOverlayStyle.allCases {
                        for trackingMode in [LyricTrackingMode.off, .karaoke, .boldWord] {
                            let ass = VideoProcessor.shared.makeKineticDialogues(
                                group: words,
                                lineIndex: 0,
                                segStart: 0,
                                segEnd: 2,
                                fontName: "Anton-Regular",
                                requestedFontSize: 70,
                                marginV: 120,
                                virtualWidth: 608,
                                virtualHeight: 1080,
                                style: style,
                                accent: .gold,
                                intensity: intensity,
                                letterStyle: letterStyle,
                                overlayStyle: overlayStyle,
                                lyricTrackingMode: trackingMode
                            )

                            XCTAssertFalse(
                                ass.isEmpty,
                                "\(style.title)/\(intensity.title)/\(letterStyle.title)/\(overlayStyle.title)/\(trackingMode.title)"
                            )
                            XCTAssertTrue(ass.contains("Dialogue:"))
                            XCTAssertFalse(ass.lowercased().contains("nan"))
                            XCTAssertFalse(ass.lowercased().contains("infinity"))
                        }
                    }
                }
            }
        }

        for accent in KineticAccent.allCases {
            let ass = VideoProcessor.shared.makeKineticDialogues(
                group: words,
                lineIndex: 0,
                segStart: 0,
                segEnd: 2,
                fontName: "Anton-Regular",
                requestedFontSize: 70,
                marginV: 120,
                virtualWidth: 608,
                virtualHeight: 1080,
                style: .automatic,
                accent: accent,
                customColorHex: "#31A7FF",
                intensity: .balanced,
                letterStyle: .automatic,
                overlayStyle: .automatic,
                lyricTrackingMode: .karaoke
            )
            XCTAssertFalse(ass.isEmpty, "\(accent.title) vurgu rengi çıktı üretmedi")
        }
    }

    func testBoldWordTrackingOnlyRaisesTheActiveWordsWeight() {
        let words = [
            VideoProcessor.WordTimestamp(text: "kara", start: 0.10, end: 0.55),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.65, end: 1.15),
            VideoProcessor.WordTimestamp(text: "içimde", start: 1.25, end: 1.85)
        ]

        let classic = VideoProcessor.shared.makeBoldWordDialogues(
            group: words,
            segStart: 0,
            segEnd: 2,
            fontName: "Anton-Regular",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            accent: .coral
        )
        let classicDialogues = classic.components(separatedBy: "\n").filter {
            $0.hasPrefix("Dialogue:")
        }

        XCTAssertEqual(classicDialogues.count, 9)
        XCTAssertEqual(classicDialogues.filter { $0.hasPrefix("Dialogue: 1,") }.count, 6)
        XCTAssertEqual(classicDialogues.filter { $0.hasPrefix("Dialogue: 2,") }.count, 3)
        XCTAssertTrue(classic.contains("\\fs70\\b400"))
        XCTAssertTrue(classic.contains("\\fs70\\b700"))
        XCTAssertTrue(classicDialogues.contains { $0.hasSuffix("}kara") })
        XCTAssertFalse(classic.contains("kara sevda içimde"))
        XCTAssertTrue(
            classic.contains("Dialogue: 1,0:00:00.00,0:00:00.10")
        )
        XCTAssertTrue(
            classic.contains("Dialogue: 2,0:00:00.10,0:00:00.55")
        )
        XCTAssertTrue(classic.contains("\\c&H7A5CFF&"))
        XCTAssertTrue(classic.contains("\\bord0\\shad0"))
        XCTAssertFalse(classic.contains("\\fscx104"))
        XCTAssertFalse(classic.contains("\\bord0.8"))
        XCTAssertFalse(classic.contains("\\alpha&"))

        let boldFaceClassic = VideoProcessor.shared.makeBoldWordDialogues(
            group: words,
            segStart: 0,
            segEnd: 2,
            fontName: "Montserrat-ExtraBold",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            accent: .violet
        )
        XCTAssertTrue(boldFaceClassic.contains("\\b700\\c&HFA8BA7&"))
        XCTAssertTrue(boldFaceClassic.contains("\\fnMontserrat\\fs70\\b100"))
        XCTAssertTrue(boldFaceClassic.contains("\\fnMontserrat\\fs70\\b700"))
        XCTAssertFalse(boldFaceClassic.contains("\\bord0.8"))

        let georgiaScalePercent = Int(
            (FontCatalog.boldHorizontalScale(
                for: "sevda",
                selection: "Georgia"
            ) * 100).rounded()
        )
        let georgia = VideoProcessor.shared.makeBoldWordDialogues(
            group: words,
            segStart: 0,
            segEnd: 2,
            fontName: "Georgia",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080
        )
        XCTAssertTrue(georgia.contains("\\fscx\(georgiaScalePercent)\\fscy100"))
        XCTAssertFalse(georgia.contains("\\fscy99"))

        let kinetic = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 2,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 608,
            virtualHeight: 1080,
            lyricTrackingMode: .boldWord
        )

        XCTAssertTrue(kinetic.contains("\\b0\\bord0\\shad0"))
        XCTAssertTrue(
            kinetic.contains(
                "\\b1\\c&H2FCCFE&\\bord0\\shad0\\fscx104\\fscy104\\alpha&HFF&"
            )
        )
        XCTAssertFalse(kinetic.contains("\\alpha&HA0&"))
        XCTAssertFalse(kinetic.contains("3A2610"))
    }

    func testBoldWordReplacementRemainsCleanForEveryFontOption() {
        let words = [
            VideoProcessor.WordTimestamp(text: "kara", start: 0.10, end: 0.55),
            VideoProcessor.WordTimestamp(text: "sevda", start: 0.65, end: 1.15)
        ]

        for font in FontCatalog.hepsi {
            let ass = VideoProcessor.shared.makeBoldWordDialogues(
                group: words,
                segStart: 0,
                segEnd: 1.4,
                fontName: FontCatalog.regularPSName(for: font.psName),
                fontSize: 70,
                marginV: 120,
                virtualWidth: 608,
                virtualHeight: 1080,
                accent: .mint
            )
            let dialogues = ass.split(separator: "\n")

            XCTAssertEqual(dialogues.count, 6, font.display)
            let expectedThinTag = font.hasRealThinFace ? "\\b100" : "\\b400"
            XCTAssertTrue(ass.contains("\(expectedThinTag)\\c&HFFFFFF&"), font.display)
            XCTAssertTrue(ass.contains("\\b700\\c&HA5E654&"), font.display)
            XCTAssertFalse(ass.contains("\\fscx104"), font.display)
            XCTAssertFalse(ass.contains("\\bord0.8"), font.display)
            XCTAssertFalse(ass.contains("kara sevda"), font.display)
        }
    }

    func testEditorialASSUsesAnimatedUnderlineInsteadOfRandomScaling() {
        let words = makeWords(["gecenin", "içinde", "seni", "aradım"])

        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.8,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .editorial
        )

        XCTAssertTrue(ass.contains("\\p1"))
        XCTAssertTrue(ass.contains("\\fscx0"))
        XCTAssertTrue(ass.contains("\\c&H2FCCFE&"))
        XCTAssertFalse(ass.contains("\\frz"))
    }

    func testCinematicASSKeepsCleanTextWithoutDecorationShapes() {
        let words = makeWords(["sessizce", "sana", "dönerim"])

        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .cinematic
        )

        XCTAssertFalse(ass.contains("\\p1"))
        XCTAssertTrue(ass.contains("\\move("))
        XCTAssertTrue(ass.contains("\\c&H2FCCFE&"))
        XCTAssertFalse(ass.contains("\\shad2.4"))
        XCTAssertFalse(ass.contains("3A2610"))
    }

    func testKineticAccentChangesASSWithoutChangingAnimationPlan() {
        let words = makeWords(["kara", "sevda", "içimde"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .editorial
        )

        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .editorial,
            accent: .coral,
            scenePlan: plan
        )

        XCTAssertTrue(ass.contains("\\c&H7A5CFF&"))
        XCTAssertFalse(ass.contains("\\c&H2FCCFE&"))
        XCTAssertEqual(plan.highlight, .underline)
    }

    func testKineticIntensityChangesMotionStrengthAndActivePulse() {
        let words = makeWords(["bu", "gece", "seni", "aradım"])
        let subtle = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.7,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            intensity: .subtle
        )
        let energetic = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.7,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            intensity: .energetic
        )

        XCTAssertNotEqual(subtle, energetic)
        XCTAssertTrue(subtle.contains("\\fscx102\\fscy102"))
        XCTAssertTrue(energetic.contains("\\fscx109\\fscy109"))
        XCTAssertFalse(subtle.contains("\\frz"))
        XCTAssertFalse(energetic.contains("\\frz"))
    }

    func testManualEmphasisUsesReservedTypographyScaleWithoutDroppingWords() {
        let words = makeWords(["bu", "gece", "seni", "aradım"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            emphasisWordID: words[1].id
        )
        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.7,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            scenePlan: plan
        )

        let regularWords = ass.components(separatedBy: "Dialogue: 2,").count - 1
        let emphasizedWords = ass.components(separatedBy: "Dialogue: 3,").count - 1
        XCTAssertEqual(regularWords + emphasizedWords, words.count)
        XCTAssertEqual(emphasizedWords, 1)
        XCTAssertTrue(ass.contains("\\fs79"))
        XCTAssertFalse(ass.contains("\\frz"))
    }

    func testPosterLetterASSReservesGlyphSizesAndTracking() {
        let words = makeWords(["kara", "sevda", "içimde"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .editorial,
            emphasisWordID: words[1].id
        )
        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .editorial,
            letterStyle: .poster,
            scenePlan: plan
        )

        XCTAssertTrue(ass.contains("\\fsp2"))
        XCTAssertTrue(ass.contains("\\fs119"))
        XCTAssertTrue(ass.contains("}S"))
        XCTAssertTrue(ass.contains("}E"))
        XCTAssertFalse(ass.contains("\\frz"))
    }

    func testCustomAccentNormalizesHexASSOrderAndForegroundContrast() {
        XCTAssertEqual(KineticResolvedColor.normalizedHex(" #1a3bc4 "), "#1A3BC4")
        XCTAssertEqual(KineticResolvedColor.normalizedHex("#f80"), "#FF8800")
        XCTAssertNil(KineticResolvedColor.normalizedHex("turuncu"))

        let dark = KineticAccent.custom.resolvedColor(customHex: "#123ABC")
        let light = KineticAccent.custom.resolvedColor(customHex: "#F4E55A")
        XCTAssertEqual(dark.hex, "#123ABC")
        XCTAssertEqual(dark.assColor, "BC3A12")
        XCTAssertFalse(dark.usesDarkForeground)
        XCTAssertEqual(dark.foregroundASSColor, "FFFFFF")
        XCTAssertTrue(light.usesDarkForeground)
        XCTAssertEqual(light.foregroundASSColor, "000000")
    }

    func testAutomaticOverlayResolvesBySceneFamilyAndLegacyStaysOff() {
        XCTAssertEqual(
            KineticOverlayStyle.automatic.resolved(for: .phraseBuild),
            .glass
        )
        XCTAssertEqual(
            KineticOverlayStyle.automatic.resolved(for: .editorialStack),
            .accentPanel
        )
        XCTAssertEqual(
            KineticOverlayStyle.automatic.resolved(for: .impactSequence),
            .spotlight
        )
        XCTAssertEqual(KineticOverlayStyle.resolved(nil), .none)
        XCTAssertEqual(KineticOverlayStyle.resolved("bilinmeyen"), .none)
    }

    func testOverlayResolverKeepsEffectsOffUnlessTheModeCanUseThem() {
        let words = makeWords(["kara", "sevda", "içimde"])
        let plan = VideoProcessor.shared.kineticTypographyPlan(
            for: words,
            lineIndex: 0,
            style: .automatic
        )

        for trackingMode in LyricTrackingMode.allCases {
            XCTAssertEqual(
                VideoProcessor.shared.resolvedKineticOverlayStyle(
                    requested: .none,
                    plan: plan,
                    trackingMode: trackingMode
                ),
                .none
            )

            let underShadow = VideoProcessor.shared.resolvedKineticOverlayStyle(
                requested: .underShadow,
                plan: plan,
                trackingMode: trackingMode
            )
            XCTAssertEqual(
                underShadow,
                trackingMode == .karaoke || trackingMode == .boldWord
                    ? .underShadow
                    : .none
            )
        }
    }

    func testGlassOverlayAndCustomAccentAreWrittenToASSBelowWords() {
        let words = makeWords(["gece", "sana", "dönerim"])
        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .cinematic,
            accent: .custom,
            customColorHex: "#123ABC",
            overlayStyle: .glass
        )

        XCTAssertTrue(ass.contains("\\p1\\bord0\\shad0\\c&H0D0D10&"))
        XCTAssertTrue(ass.contains("\\c&HBC3A12&"))
        XCTAssertTrue(ass.contains("\\3c&HFFFFFF&"))
        XCTAssertTrue(ass.contains("Dialogue: 0,"))
        XCTAssertTrue(ass.contains("Dialogue: 2,") || ass.contains("Dialogue: 3,"))
        XCTAssertFalse(ass.contains("\\frz"))
    }

    func testSpotlightOverlayCreatesOneTimedPlatePerWord() {
        let words = makeWords(["kal", "benimle", "bu", "gece"])
        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.7,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .impact,
            overlayStyle: .spotlight
        )

        XCTAssertEqual(
            ass.components(separatedBy: "\\alpha&H72&").count - 1,
            words.count
        )
        XCTAssertTrue(ass.contains("\\3a&H38&"))
    }

    func testUnderShadowOverlayCreatesSubtleDarkPlateForEveryReadWord() {
        let words = makeWords(["gölgen", "kalır", "altta"])
        let ass = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .cinematic,
            intensity: .balanced,
            overlayStyle: .underShadow,
            lyricTrackingMode: .karaoke
        )

        XCTAssertEqual(
            ass.components(separatedBy: "\\alpha&H88&").count - 1,
            words.count
        )
        XCTAssertTrue(ass.contains("\\c&H000000&"))
        XCTAssertTrue(ass.contains("\\blur5.5"))

        let boldWord = VideoProcessor.shared.makeBoldWordDialogues(
            group: words,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Georgia",
            fontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            inlineLineBreaks: Set([words[0].id]),
            overlayStyle: .underShadow,
            intensity: .balanced
        )
        XCTAssertEqual(
            boldWord.components(separatedBy: "\\alpha&HD9&").count - 1,
            1
        )
        XCTAssertTrue(boldWord.contains("Dialogue: 0,"))
        XCTAssertTrue(boldWord.contains("\\blur5"))

        let trackingOff = VideoProcessor.shared.makeKineticDialogues(
            group: words,
            lineIndex: 0,
            segStart: 0,
            segEnd: 1.4,
            fontName: "Anton-Regular",
            requestedFontSize: 70,
            marginV: 120,
            virtualWidth: 607,
            virtualHeight: 1080,
            style: .cinematic,
            overlayStyle: .underShadow,
            lyricTrackingMode: .off
        )
        XCTAssertFalse(trackingOff.contains("\\blur5.5"))
    }

    func testUnknownAndLegacyKaraokeModesResolveToClassic() {
        XCTAssertEqual(KaraokeMode.resolved(nil), .classic)
        XCTAssertEqual(KaraokeMode.resolved("bilinmeyen"), .classic)
        XCTAssertEqual(KaraokeMode.resolved("kinetic"), .kinetic)
        XCTAssertEqual(KineticStyle.resolved(nil), .automatic)
        XCTAssertEqual(KineticStyle.resolved("bilinmeyen"), .automatic)
        XCTAssertEqual(KineticStyle.resolved("editorial"), .editorial)
        XCTAssertEqual(KineticAccent.resolved(nil), .gold)
        XCTAssertEqual(KineticAccent.resolved("bilinmeyen"), .gold)
        XCTAssertEqual(KineticAccent.resolved("mint"), .mint)
        XCTAssertEqual(KineticIntensity.resolved(nil), .balanced)
        XCTAssertEqual(KineticIntensity.resolved("bilinmeyen"), .balanced)
        XCTAssertEqual(KineticIntensity.resolved("energetic"), .energetic)
        XCTAssertEqual(KineticLetterStyle.resolved(nil), .clean)
        XCTAssertEqual(KineticLetterStyle.resolved("bilinmeyen"), .clean)
        XCTAssertEqual(KineticLetterStyle.resolved("poster"), .poster)
        XCTAssertEqual(KineticLetterStyle.resolved("signature"), .signature)
        XCTAssertEqual(KineticOverlayStyle.resolved("glass"), .glass)
        XCTAssertEqual(
            LyricTrackingMode.resolved("centeredWordReveal"),
            .centeredWordReveal
        )
        XCTAssertEqual(LyricTrackingMode.resolved("boldWord"), .boldWord)
        XCTAssertTrue(LyricTrackingMode.centeredReveal.isProgressiveReveal)
        XCTAssertTrue(LyricTrackingMode.centeredWordReveal.isProgressiveReveal)
        XCTAssertFalse(LyricTrackingMode.karaoke.isProgressiveReveal)
        XCTAssertFalse(LyricTrackingMode.boldWord.isProgressiveReveal)
    }

    func testLegacyProjectWithoutKaraokeModeDecodesAsClassic() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "olusturma": 0,
          "guncelleme": 0,
          "baslik": "Eski Proje",
          "kelimeler": [],
          "satirSonlari": [],
          "fontAdi": "Anton-Regular",
          "fontBoyu": 70,
          "dikeyKonum": 120,
          "videoDosyasi": "video.mp4",
          "disaAktarimSayisi": 0
        }
        """

        let project = try JSONDecoder().decode(SavedProject.self, from: Data(json.utf8))

        XCTAssertNil(project.karaokeModu)
        XCTAssertNil(project.sozTakibi)
        XCTAssertNil(project.kinetikStil)
        XCTAssertNil(project.kinetikVurgu)
        XCTAssertNil(project.kinetikOzelRenk)
        XCTAssertNil(project.kinetikYogunluk)
        XCTAssertNil(project.kinetikVurgular)
        XCTAssertNil(project.kinetikHarfStili)
        XCTAssertNil(project.kinetikOverlay)
        XCTAssertNil(project.stilSurumu)
        XCTAssertNil(project.icSatirSonlari)
        XCTAssertEqual(project.karaokeMode, .classic)
        XCTAssertEqual(project.lyricTrackingMode, .karaoke)
        XCTAssertEqual(project.kineticStyle, .automatic)
        XCTAssertEqual(project.kineticAccent, .gold)
        XCTAssertEqual(project.kineticCustomColorHex, KineticAccent.defaultCustomHex)
        XCTAssertEqual(project.kineticIntensity, .balanced)
        XCTAssertTrue(project.kineticEmphasisWordIDs.isEmpty)
        XCTAssertTrue(project.inlineLineBreakIDs.isEmpty)
        XCTAssertEqual(project.kineticLetterStyle, .clean)
        XCTAssertEqual(project.kineticOverlayStyle, .none)
    }

    func testLegacyAutomaticOverlayMigratesToCleanWhileNewExplicitChoiceIsKept() throws {
        let base = """
        {
          "id": "\(UUID().uuidString)",
          "olusturma": 0,
          "guncelleme": 0,
          "baslik": "Overlay Projesi",
          "kelimeler": [],
          "satirSonlari": [],
          "fontAdi": "Anton-Regular",
          "fontBoyu": 70,
          "dikeyKonum": 120,
          "kinetikOverlay": "automatic",
          "videoDosyasi": "video.mp4",
          "disaAktarimSayisi": 0
        }
        """
        let legacy = try JSONDecoder().decode(SavedProject.self, from: Data(base.utf8))
        XCTAssertNil(legacy.stilSurumu)
        XCTAssertEqual(legacy.kineticOverlayStyle, .none)

        let currentJSON = base.replacingOccurrences(
            of: "\"kinetikOverlay\": \"automatic\",",
            with: "\"kinetikOverlay\": \"automatic\", \"stilSurumu\": 2,"
        )
        let current = try JSONDecoder().decode(
            SavedProject.self,
            from: Data(currentJSON.utf8)
        )
        XCTAssertEqual(current.stilSurumu, SavedProject.currentStyleVersion)
        XCTAssertEqual(current.kineticOverlayStyle, .automatic)
    }

    private func makeWords(_ texts: [String]) -> [VideoProcessor.WordTimestamp] {
        texts.enumerated().map { index, text in
            let start = Double(index) * 0.4
            return VideoProcessor.WordTimestamp(text: text, start: start, end: start + 0.3)
        }
    }

    private func shiftedWords(
        _ words: [VideoProcessor.WordTimestamp],
        by offset: Double
    ) -> [VideoProcessor.WordTimestamp] {
        words.map {
            VideoProcessor.WordTimestamp(
                text: $0.text,
                start: $0.start + offset,
                end: $0.end + offset
            )
        }
    }

    private func makeRapidWords(
        _ texts: [String],
        offset: Double
    ) -> [VideoProcessor.WordTimestamp] {
        texts.enumerated().map { index, text in
            let start = offset + (Double(index) * 0.2)
            return VideoProcessor.WordTimestamp(text: text, start: start, end: start + 0.16)
        }
    }
}

final class FontCatalogTests: XCTestCase {
    func testEveryFontProvidesThinRegularAndBoldWithinItsOwnFamily() {
        for font in FontCatalog.hepsi {
            for weight in SubtitleFontWeight.allCases {
                XCTAssertFalse(font.faceName(for: weight).isEmpty, "\(font.display) / \(weight.title)")
            }
            XCTAssertEqual(font.faceName(for: .regular), font.regularFaceName)
            XCTAssertEqual(
                FontCatalog.faceName(for: font.psName, weight: .thin),
                font.thinPSName ?? font.regularFaceName
            )
            XCTAssertEqual(
                FontCatalog.faceName(for: font.psName, weight: .bold),
                font.boldPSName ?? font.regularFaceName
            )
        }
        XCTAssertEqual(SubtitleFontWeight.thin.assTag, "\\b100")
        XCTAssertEqual(SubtitleFontWeight.regular.assTag, "\\b400")
        XCTAssertEqual(SubtitleFontWeight.bold.assTag, "\\b700")
    }

    func testGeorgiaKeepsItsOwnFamilyForAllWeights() {
        let georgia = try! XCTUnwrap(FontCatalog.secenek("Georgia"))

        XCTAssertEqual(georgia.faceName(for: .thin), "Georgia")
        XCTAssertFalse(georgia.hasRealFace(for: .thin))
        XCTAssertEqual(georgia.faceName(for: .regular), "Georgia")
        XCTAssertEqual(georgia.faceName(for: .bold), "Georgia-Bold")
        XCTAssertTrue(georgia.hasRealFace(for: .bold))
        XCTAssertEqual(georgia.assTag(for: .thin), "\\b400")
        XCTAssertEqual(georgia.availableWeights, [.regular, .bold])
        XCTAssertEqual(georgia.assTag(for: .regular), "\\b400")
        XCTAssertEqual(georgia.assTag(for: .bold), "\\b700")
        XCTAssertEqual(FontCatalog.assFamilyName(for: georgia.psName), "Georgia")
        XCTAssertNotEqual(
            FontCatalog.assFamilyName(for: georgia.psName),
            georgia.boldPSName
        )
        XCTAssertEqual(
            FontCatalog.renderPSNames(for: georgia.psName),
            ["Georgia", "Georgia-Bold"]
        )
        let horizontalScale = FontCatalog.boldHorizontalScale(
            for: "yaşar",
            selection: georgia.psName
        )
        XCTAssertGreaterThan(horizontalScale, 0.85)
        XCTAssertLessThan(horizontalScale, 0.95)
    }

    func testCatalogUsesUniquePostScriptNamesAndExcludesUnsafeLegacyFonts() {
        let names = FontCatalog.hepsi.map(\.psName)

        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(FontCatalog.gomulu.count, 28)
        XCTAssertEqual(
            FontCatalog.secenek("PetitFormalScript-Regular"),
            FontOption(
                psName: "PetitFormalScript-Regular",
                display: "Petit Formal Script",
                assFamily: "Petit Formal Script",
                kalin: false,
                category: .handwriting,
                bitisik: true
            )
        )
        XCTAssertNil(FontCatalog.secenek("Creepster-Regular"))
        XCTAssertNil(FontCatalog.secenek("PermanentMarker-Regular"))
    }

    func testEveryFontSupportsDynamicRegularAndBoldRendering() {
        for font in FontCatalog.hepsi {
            XCTAssertFalse(font.regularFaceName.isEmpty, font.display)
            XCTAssertEqual(
                FontCatalog.regularPSName(for: font.psName),
                font.regularFaceName,
                font.display
            )

            let renderNames = FontCatalog.renderPSNames(for: font.psName)
            XCTAssertEqual(renderNames.first, font.regularFaceName, font.display)
            if let boldPSName = font.boldPSName {
                XCTAssertTrue(renderNames.contains(boldPSName), font.display)
                XCTAssertEqual(
                    FontCatalog.boldPSName(for: font.regularFaceName),
                    boldPSName,
                    font.display
                )
            } else {
                // Tek kesit yayımlayan aileler aynı Cümle + Kalın yolunda kontrollü
                // sentetik ağırlık kullanır; hayali bir font dosyasına yönelmez.
                XCTAssertNil(FontCatalog.boldPSName(for: font.psName), font.display)
                XCTAssertEqual(renderNames, [font.regularFaceName], font.display)
            }
        }
    }

    func testBundledFamiliesWithPublishedWeightsUseRealFontFaces() {
        let expectedFaces: [String: (regular: String, bold: String, thin: String?)] = [
            "Montserrat-ExtraBold": ("Montserrat-Regular", "Montserrat-Bold", "Montserrat-Light"),
            "Poppins-Bold": ("Poppins-Regular", "Poppins-Bold", "Poppins-Light"),
            "Lato-Bold": ("Lato-Regular", "Lato-Bold", "Lato-Light"),
            "SpaceMono-Bold": ("SpaceMono-Regular", "SpaceMono-Bold", nil),
            "LeagueSpartan-Bold": ("LeagueSpartan-Regular", "LeagueSpartan-Bold", nil),
            "Oswald-Bold": ("Oswald-Regular", "Oswald-Bold", nil),
            "PlayfairDisplayRoman-Black": (
                "PlayfairDisplayRoman-Regular",
                "PlayfairDisplayRoman-Bold",
                nil
            ),
            "CaveatRoman-Bold": ("CaveatRoman-Regular", "CaveatRoman-Bold", nil)
        ]

        for (selection, faces) in expectedFaces {
            XCTAssertEqual(FontCatalog.regularPSName(for: selection), faces.regular)
            XCTAssertEqual(FontCatalog.boldPSName(for: selection), faces.bold)
            XCTAssertEqual(FontCatalog.thinPSName(for: selection), faces.thin)
            let renderNames = FontCatalog.renderPSNames(for: selection)
            XCTAssertEqual(renderNames.first, faces.regular)
            XCTAssertTrue(renderNames.contains(selection))
            XCTAssertTrue(renderNames.contains(faces.bold))
            if let thin = faces.thin {
                XCTAssertTrue(renderNames.contains(thin))
            }
        }
    }

    func testEveryModeHasNonConnectedCuratedRecommendations() {
        for mode in KaraokeMode.allCases {
            for style in KineticStyle.allCases {
                let recommendations = FontCatalog.onerilen(
                    karaokeMode: mode,
                    kineticStyle: style
                )

                XCTAssertFalse(recommendations.isEmpty, "\(mode.rawValue)/\(style.rawValue)")
                XCTAssertTrue(recommendations.allSatisfy { !$0.bitisik })
                XCTAssertTrue(
                    recommendations.allSatisfy { FontCatalog.secenek($0.psName) != nil }
                )
            }
        }
    }

    func testKineticDirectorsStartWithAFontMatchingTheirVisualIdentity() {
        XCTAssertEqual(
            FontCatalog.onerilen(karaokeMode: .kinetic, kineticStyle: .automatic).first?.psName,
            "Montserrat-ExtraBold"
        )
        XCTAssertEqual(
            FontCatalog.onerilen(karaokeMode: .kinetic, kineticStyle: .cinematic).first?.psName,
            "PlayfairDisplayRoman-Black"
        )
        XCTAssertEqual(
            FontCatalog.onerilen(karaokeMode: .kinetic, kineticStyle: .editorial).first?.psName,
            "LeagueSpartan-Bold"
        )
        XCTAssertEqual(
            FontCatalog.onerilen(karaokeMode: .kinetic, kineticStyle: .impact).first?.psName,
            "ArchivoBlack-Regular"
        )
    }
}
