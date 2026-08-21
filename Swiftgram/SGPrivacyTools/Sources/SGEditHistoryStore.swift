import Foundation

public struct SGEditHistoryMessageKey: Codable, Hashable {
    public let accountPeerId: Int64
    public let peerId: Int64
    public let namespace: Int32
    public let id: Int32

    public init(accountPeerId: Int64, peerId: Int64, namespace: Int32, id: Int32) {
        self.accountPeerId = accountPeerId
        self.peerId = peerId
        self.namespace = namespace
        self.id = id
    }
}

public struct SGEditHistoryRevision: Codable, Equatable {
    public let text: String
    public let capturedAt: Int32

    public init(text: String, capturedAt: Int32) {
        self.text = text
        self.capturedAt = capturedAt
    }
}

/// Bounded local-only storage for prior edited text. Entries are never synced or logged.
public final class SGEditHistoryStore {
    public static let shared = SGEditHistoryStore()

    private struct Record: Codable {
        var key: SGEditHistoryMessageKey
        var revisions: [SGEditHistoryRevision]
        var lastTouched: Int32
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxMessages: Int
    private let maxRevisions: Int
    private let maxAge: Int32
    private let now: () -> Int32
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "privacy.editHistory.v1",
        maxMessages: Int = 1000,
        maxRevisions: Int = 5,
        maxAge: Int32 = 30 * 24 * 60 * 60,
        now: @escaping () -> Int32 = { Int32(Date().timeIntervalSince1970) }
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maxMessages = max(1, maxMessages)
        self.maxRevisions = max(1, maxRevisions)
        self.maxAge = max(1, maxAge)
        self.now = now
    }

    public func recordPreviousText(_ text: String, for key: SGEditHistoryMessageKey, updatedText: String) {
        guard SGPrivacySettings.shared.retainEditHistory, !text.isEmpty, text != updatedText else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        let timestamp = self.now()
        var records = self.loadPruned(now: timestamp)
        if let index = records.firstIndex(where: { $0.key == key }) {
            if records[index].revisions.last?.text != text {
                records[index].revisions.append(SGEditHistoryRevision(text: text, capturedAt: timestamp))
                records[index].revisions = Array(records[index].revisions.suffix(self.maxRevisions))
            }
            records[index].lastTouched = timestamp
        } else {
            records.append(Record(key: key, revisions: [SGEditHistoryRevision(text: text, capturedAt: timestamp)], lastTouched: timestamp))
        }
        records.sort(by: { $0.lastTouched < $1.lastTouched })
        self.save(Array(records.suffix(self.maxMessages)))
    }

    public func revisions(for key: SGEditHistoryMessageKey) -> [SGEditHistoryRevision] {
        self.lock.lock()
        defer { self.lock.unlock() }
        let records = self.loadPruned(now: self.now())
        self.save(records)
        return records.first(where: { $0.key == key })?.revisions ?? []
    }

    public func removeHistory(for key: SGEditHistoryMessageKey) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var records = self.loadPruned(now: self.now())
        records.removeAll(where: { $0.key == key })
        self.save(records)
    }

    public func removeAll() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.defaults.removeObject(forKey: self.storageKey)
    }

    public var messageCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        let records = self.loadPruned(now: self.now())
        self.save(records)
        return records.count
    }

    private func loadPruned(now: Int32) -> [Record] {
        guard let data = self.defaults.data(forKey: self.storageKey), let records = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        let cutoff = now - self.maxAge
        return records.filter { $0.lastTouched >= cutoff && !$0.revisions.isEmpty }
    }

    private func save(_ records: [Record]) {
        if records.isEmpty {
            self.defaults.removeObject(forKey: self.storageKey)
        } else if let data = try? JSONEncoder().encode(records) {
            self.defaults.set(data, forKey: self.storageKey)
        }
    }
}
