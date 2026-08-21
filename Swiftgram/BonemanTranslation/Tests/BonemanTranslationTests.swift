import XCTest
@testable import BonemanTranslation

final class BonemanTranslationPolicyTests: XCTestCase {
    func testSystemBackendBecomesEffectiveDefaultOnlyWhenAvailable() {
        XCTAssertEqual(BonemanTranslationPolicy.effectiveBackend(rawValue: "default", appleSystemAvailable: true), "system")
        XCTAssertEqual(BonemanTranslationPolicy.effectiveBackend(rawValue: "default", appleSystemAvailable: false), "default")
        XCTAssertEqual(BonemanTranslationPolicy.effectiveBackend(rawValue: "gtranslate", appleSystemAvailable: true), "gtranslate")
    }

    func testSkipsEmptyEmojiAndURLOnlyText() {
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "", fromLanguage: nil, toLanguage: "es"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "  \n", fromLanguage: nil, toLanguage: "es"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "Hello", fromLanguage: nil, toLanguage: ""))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "👋🏽 🎉", fromLanguage: nil, toLanguage: "es"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "https://example.com/a", fromLanguage: nil, toLanguage: "es"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "www.example.com", fromLanguage: nil, toLanguage: "es"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "example.com/path", fromLanguage: nil, toLanguage: "es"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "hello@example.com", fromLanguage: nil, toLanguage: "es"))
    }

    func testAllowsNaturalLanguageIncludingMultilineAndEmoji() {
        XCTAssertTrue(BonemanTranslationPolicy.shouldTranslate(text: "Hello", fromLanguage: "en", toLanguage: "es"))
        XCTAssertTrue(BonemanTranslationPolicy.shouldTranslate(text: "Hello 👋🏽\nHow are you?", fromLanguage: nil, toLanguage: "es"))
        XCTAssertTrue(BonemanTranslationPolicy.shouldTranslate(text: String(repeating: "Long message. ", count: 100), fromLanguage: "en", toLanguage: "es"))
    }

    func testSkipsSameLanguageButPreservesDistinctScriptVariants() {
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "Hello", fromLanguage: "en-US", toLanguage: "en"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "Hello", fromLanguage: "en-US", toLanguage: "en-GB"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "Hola", fromLanguage: "es", toLanguage: "es-MX"))
        XCTAssertFalse(BonemanTranslationPolicy.shouldTranslate(text: "Ola", fromLanguage: "pt-BR", toLanguage: "pt-PT"))
        XCTAssertTrue(BonemanTranslationPolicy.shouldTranslate(text: "中文", fromLanguage: "zh-Hans", toLanguage: "zh-Hant"))
        XCTAssertTrue(BonemanTranslationPolicy.shouldTranslate(text: "Zdravo", fromLanguage: "sr-Latn", toLanguage: "sr-Cyrl"))
    }

    func testCanonicalLanguageIdentifiersPreserveScriptAndRegion() {
        XCTAssertEqual(BonemanTranslationPolicy.canonicalLanguageIdentifier("ZH_hans_cn"), "zh-Hans-CN")
        XCTAssertEqual(BonemanTranslationPolicy.canonicalLanguageIdentifier("zh-Hant"), "zh-Hant")
        XCTAssertEqual(BonemanTranslationPolicy.canonicalLanguageIdentifier("pt_br"), "pt-BR")
        XCTAssertEqual(BonemanTranslationPolicy.canonicalLanguageIdentifier("nb-NO"), "no-NO")
    }

    func testCyrillicChatSourceOverridesIncompatiblePerMessageDetection() {
        XCTAssertEqual(
            BonemanTranslationPolicy.resolvedSourceLanguage(
                text: "Привет",
                detectedLanguage: "fi",
                preferredLanguage: "ru"
            ),
            "ru"
        )
    }

    func testChatSourceDoesNotOverrideAnotherScript() {
        XCTAssertEqual(
            BonemanTranslationPolicy.resolvedSourceLanguage(
                text: "Hyvää päivää",
                detectedLanguage: "fi",
                preferredLanguage: "ru"
            ),
            "fi"
        )
    }

    func testMixedChatPrefersForeignLanguageOverDominantIgnoredLanguage() {
        XCTAssertEqual(
            BonemanTranslationPolicy.resolvedChatSourceLanguage(
                languageWeights: ["en": 500, "ar": 80],
                ignoredLanguages: ["en"]
            ),
            "ar"
        )
    }

    func testMixedChatFallsBackToDominantLanguageWhenAllAreIgnored() {
        XCTAssertEqual(
            BonemanTranslationPolicy.resolvedChatSourceLanguage(
                languageWeights: ["en-US": 500, "es": 80],
                ignoredLanguages: ["en-US", "es"]
            ),
            "en-US"
        )
    }
}

final class BonemanTranslationCacheTests: XCTestCase {
    func testCacheKeyIncludesTextSourceAndTarget() {
        let cache = BonemanTranslationCache(capacity: 8)
        let key = BonemanTranslationCacheKey(text: "Hello", sourceLanguage: "en", targetLanguage: "es")
        cache.insert("Hola", for: key)

        XCTAssertEqual(cache.value(for: key), "Hola")
        XCTAssertNil(cache.value(for: BonemanTranslationCacheKey(text: "Hello!", sourceLanguage: "en", targetLanguage: "es")))
        XCTAssertNil(cache.value(for: BonemanTranslationCacheKey(text: "Hello", sourceLanguage: nil, targetLanguage: "es")))
        XCTAssertNil(cache.value(for: BonemanTranslationCacheKey(text: "Hello", sourceLanguage: "en", targetLanguage: "fr")))
    }

    func testCacheIsBoundedAndUsesRecentAccessForEviction() {
        let cache = BonemanTranslationCache(capacity: 2)
        let first = BonemanTranslationCacheKey(text: "one", sourceLanguage: "en", targetLanguage: "es")
        let second = BonemanTranslationCacheKey(text: "two", sourceLanguage: "en", targetLanguage: "es")
        let third = BonemanTranslationCacheKey(text: "three", sourceLanguage: "en", targetLanguage: "es")

        cache.insert("uno", for: first)
        cache.insert("dos", for: second)
        XCTAssertEqual(cache.value(for: first), "uno")
        cache.insert("tres", for: third)

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.value(for: second))
        XCTAssertEqual(cache.value(for: first), "uno")
        XCTAssertEqual(cache.value(for: third), "tres")
    }

    func testCacheCanBeCleared() {
        let cache = BonemanTranslationCache()
        cache.insert("Hola", for: BonemanTranslationCacheKey(text: "Hello", sourceLanguage: "en", targetLanguage: "es"))
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
    }

    func testCacheKeyCanonicalizesLanguagesWithoutMergingScripts() {
        let first = BonemanTranslationCacheKey(text: "中文", sourceLanguage: "ZH_hans", targetLanguage: "ZH_hant")
        let equivalent = BonemanTranslationCacheKey(text: "中文", sourceLanguage: "zh-Hans", targetLanguage: "zh-Hant")
        let differentScript = BonemanTranslationCacheKey(text: "中文", sourceLanguage: "zh-Hant", targetLanguage: "zh-Hans")

        XCTAssertEqual(first, equivalent)
        XCTAssertNotEqual(first, differentScript)
    }
}

final class BonemanTranslationBoundedIndexTests: XCTestCase {
    func testTouchIsBoundedAndReturnsExactEviction() {
        var index = BonemanTranslationBoundedIndex(values: [1, 2], capacity: 2)

        XCTAssertEqual(index.touch(3), [1])
        XCTAssertEqual(index.values, [2, 3])
    }

    func testTouchMovesExistingValueWithoutEviction() {
        var index = BonemanTranslationBoundedIndex(values: [1, 2, 3], capacity: 3)

        XCTAssertEqual(index.touch(1), [])
        XCTAssertEqual(index.values, [2, 3, 1])
    }

    func testInitializationDeduplicatesAndTrimsOldestValues() {
        let index = BonemanTranslationBoundedIndex(values: [1, 2, 1, 3, 4], capacity: 3)

        XCTAssertEqual(index.values, [1, 3, 4])
    }

    func testRemoveOnlyDeletesExactValues() {
        var index = BonemanTranslationBoundedIndex(values: [1, 2, 3], capacity: 3)
        index.remove(Set([2, 9]))

        XCTAssertEqual(index.values, [1, 3])
    }
}

final class BonemanTranslationWorkQueueTests: XCTestCase {
    func testSerializesWorkAndDoesNotReplaceTheActiveItem() {
        let queue = BonemanTranslationWorkQueue(capacity: 4)
        let firstKey = BonemanTranslationCacheKey(text: "one", sourceLanguage: nil, targetLanguage: "es")
        let secondKey = BonemanTranslationCacheKey(text: "two", sourceLanguage: nil, targetLanguage: "es")

        XCTAssertTrue(queue.enqueue(key: firstKey, subscriberId: 1, completion: { _ in }))
        let firstWork = queue.beginNextIfIdle()
        XCTAssertEqual(firstWork?.key, firstKey)

        XCTAssertTrue(queue.enqueue(key: secondKey, subscriberId: 2, completion: { _ in }))
        XCTAssertNil(queue.beginNextIfIdle())
        XCTAssertEqual(queue.activeWork?.id, firstWork?.id)

        XCTAssertTrue(queue.completeActive(workId: firstWork!.id, result: .translated("uno")))
        XCTAssertEqual(queue.beginNextIfIdle()?.key, secondKey)
    }

    func testCoalescesIdenticalWorkAndFansOutTheResult() {
        let queue = BonemanTranslationWorkQueue(capacity: 4)
        let key = BonemanTranslationCacheKey(text: "hello", sourceLanguage: "en", targetLanguage: "es")
        var results: [BonemanTranslationWorkResult] = []

        XCTAssertTrue(queue.enqueue(key: key, subscriberId: 1, completion: { results.append($0) }))
        XCTAssertTrue(queue.enqueue(key: key, subscriberId: 2, completion: { results.append($0) }))
        XCTAssertEqual(queue.count, 1)

        let work = queue.beginNextIfIdle()!
        XCTAssertTrue(queue.completeActive(workId: work.id, result: .translated("hola")))
        XCTAssertEqual(results, [.translated("hola"), .translated("hola")])
    }

    func testCancellationSuppressesStaleCallbacksButKeepsOtherSubscribers() {
        let queue = BonemanTranslationWorkQueue(capacity: 4)
        let key = BonemanTranslationCacheKey(text: "hello", sourceLanguage: nil, targetLanguage: "es")
        var firstCalled = false
        var secondResult: BonemanTranslationWorkResult?

        XCTAssertTrue(queue.enqueue(key: key, subscriberId: 1, completion: { _ in firstCalled = true }))
        XCTAssertTrue(queue.enqueue(key: key, subscriberId: 2, completion: { secondResult = $0 }))
        let work = queue.beginNextIfIdle()!
        queue.cancel(subscriberId: 1)

        XCTAssertTrue(queue.completeActive(workId: work.id, result: .translated("hola")))
        XCTAssertFalse(firstCalled)
        XCTAssertEqual(secondResult, .translated("hola"))
    }

    func testCancelAllInvalidatesActiveWorkBeforeNewEquivalentWork() {
        let queue = BonemanTranslationWorkQueue(capacity: 4)
        let key = BonemanTranslationCacheKey(text: "hello", sourceLanguage: nil, targetLanguage: "es")
        var staleCalled = false
        var freshResult: BonemanTranslationWorkResult?

        XCTAssertTrue(queue.enqueue(key: key, subscriberId: 1, completion: { _ in staleCalled = true }))
        let staleWork = queue.beginNextIfIdle()!
        queue.cancelAll()
        XCTAssertTrue(queue.enqueue(key: key, subscriberId: 2, completion: { freshResult = $0 }))
        XCTAssertNil(queue.beginNextIfIdle())

        XCTAssertTrue(queue.completeActive(workId: staleWork.id, result: .translated("stale")))
        XCTAssertFalse(staleCalled)
        let freshWork = queue.beginNextIfIdle()!
        XCTAssertNotEqual(freshWork.id, staleWork.id)
        XCTAssertTrue(queue.completeActive(workId: freshWork.id, result: .translated("hola")))
        XCTAssertEqual(freshResult, .translated("hola"))
    }

    func testCapacityBoundsUniqueWorkAndCoalescedSubscribers() {
        let queue = BonemanTranslationWorkQueue(capacity: 2)
        let first = BonemanTranslationCacheKey(text: "one", sourceLanguage: nil, targetLanguage: "es")
        let second = BonemanTranslationCacheKey(text: "two", sourceLanguage: nil, targetLanguage: "es")
        let third = BonemanTranslationCacheKey(text: "three", sourceLanguage: nil, targetLanguage: "es")

        XCTAssertTrue(queue.enqueue(key: first, subscriberId: 1, completion: { _ in }))
        XCTAssertTrue(queue.enqueue(key: second, subscriberId: 2, completion: { _ in }))
        XCTAssertFalse(queue.enqueue(key: first, subscriberId: 3, completion: { _ in }))
        XCTAssertTrue(queue.enqueue(key: first, subscriberId: 1, completion: { _ in }))
        queue.cancel(subscriberId: 2)
        XCTAssertTrue(queue.enqueue(key: first, subscriberId: 3, completion: { _ in }))
        XCTAssertFalse(queue.enqueue(key: third, subscriberId: 4, completion: { _ in }))
        XCTAssertEqual(queue.count, 1)
    }
}

final class BonemanTranslationDiagnosticsTests: XCTestCase {
    func testReportContainsOperationalStateWithoutMessageText() {
        let diagnostics = BonemanTranslationDiagnostics()
        diagnostics.recordBatch(sourceLanguage: "ru", targetLanguage: "en", pendingCount: 2)
        diagnostics.recordModelStatus("installed", sourceLanguage: "ru", targetLanguage: "en")
        diagnostics.recordResult(.failed, failedOpaqueIds: ["abc123"], remainingCount: 1)
        let report = diagnostics.snapshot().redactedReport
        XCTAssertTrue(report.contains("ru->en"))
        XCTAssertTrue(report.contains("abc123"))
        XCTAssertFalse(report.contains("secret message"))
    }
}
