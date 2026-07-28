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
        XCTAssertEqual(KineticOverlayStyle.resolved("glass"), .glass)
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
        XCTAssertNil(project.kinetikStil)
        XCTAssertNil(project.kinetikVurgu)
        XCTAssertNil(project.kinetikOzelRenk)
        XCTAssertNil(project.kinetikYogunluk)
        XCTAssertNil(project.kinetikVurgular)
        XCTAssertNil(project.kinetikHarfStili)
        XCTAssertNil(project.kinetikOverlay)
        XCTAssertEqual(project.karaokeMode, .classic)
        XCTAssertEqual(project.kineticStyle, .automatic)
        XCTAssertEqual(project.kineticAccent, .gold)
        XCTAssertEqual(project.kineticCustomColorHex, KineticAccent.defaultCustomHex)
        XCTAssertEqual(project.kineticIntensity, .balanced)
        XCTAssertTrue(project.kineticEmphasisWordIDs.isEmpty)
        XCTAssertEqual(project.kineticLetterStyle, .clean)
        XCTAssertEqual(project.kineticOverlayStyle, .none)
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
