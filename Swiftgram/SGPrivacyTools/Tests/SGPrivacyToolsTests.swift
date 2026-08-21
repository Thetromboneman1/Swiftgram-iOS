import XCTest
@testable import SGPrivacyTools

final class SGPrivacyToolsTests: XCTestCase {
    func testGhostModeHonorsAccountScopedPeerException() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SGPrivacySettings(defaults: defaults)
        settings.hideTyping = true
        XCTAssertTrue(settings.shouldSuppress(accountPeerId: 1, peerId: 2, activity: .typing))
        settings.setPeerException(accountPeerId: 1, peerId: 2, value: true)
        XCTAssertFalse(settings.shouldSuppress(accountPeerId: 1, peerId: 2, activity: .typing))
        XCTAssertTrue(settings.shouldSuppress(accountPeerId: 3, peerId: 2, activity: .typing))
    }

    func testEditHistoryIsBoundedAndDeduplicated() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SGPrivacySettings.shared
        let previousValue = settings.retainEditHistory
        settings.retainEditHistory = true
        defer { settings.retainEditHistory = previousValue }
        var timestamp: Int32 = 100
        let store = SGEditHistoryStore(defaults: defaults, maxMessages: 2, maxRevisions: 2, maxAge: 1000, now: { timestamp })
        let key = SGEditHistoryMessageKey(accountPeerId: 1, peerId: 2, namespace: 0, id: 3)
        store.recordPreviousText("one", for: key, updatedText: "two")
        timestamp += 1
        store.recordPreviousText("one", for: key, updatedText: "two")
        timestamp += 1
        store.recordPreviousText("two", for: key, updatedText: "three")
        timestamp += 1
        store.recordPreviousText("three", for: key, updatedText: "four")
        XCTAssertEqual(store.revisions(for: key).map(\.text), ["two", "three"])
    }

    func testEditHistoryExpiresOldRecords() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var timestamp: Int32 = 100
        let store = SGEditHistoryStore(defaults: defaults, maxAge: 10, now: { timestamp })
        let key = SGEditHistoryMessageKey(accountPeerId: 1, peerId: 2, namespace: 0, id: 3)
        store.recordPreviousText("old", for: key, updatedText: "new")
        timestamp = 111
        XCTAssertTrue(store.revisions(for: key).isEmpty)
    }
}
