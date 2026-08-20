import Foundation

public enum BonemanTranslationWorkResult: Equatable {
    case translated(String)
    case skipped
    case failed
}

public struct BonemanTranslationWork: Equatable {
    public let id: Int
    public let key: BonemanTranslationCacheKey

    fileprivate init(id: Int, key: BonemanTranslationCacheKey) {
        self.id = id
        self.key = key
    }
}

/// A bounded, thread-safe, single-flight queue for Apple Translation work.
///
/// Identical cache keys share one work item, but each subscriber keeps an independent cancellation
/// handle. `cancelAll()` invalidates the current work without pretending that an already-running
/// Apple session stopped; the next item cannot start until the active item reports completion.
public final class BonemanTranslationWorkQueue {
    public typealias Completion = (BonemanTranslationWorkResult) -> Void

    private final class Entry {
        let work: BonemanTranslationWork
        var completions: [Int: Completion]

        init(work: BonemanTranslationWork, subscriberId: Int, completion: @escaping Completion) {
            self.work = work
            self.completions = [subscriberId: completion]
        }
    }

    private let capacity: Int
    private let lock = NSLock()
    private var nextWorkId: Int = 0
    private var entriesById: [Int: Entry] = [:]
    private var workIdByKey: [BonemanTranslationCacheKey: Int] = [:]
    private var pendingWorkIds: [Int] = []
    private var activeWorkId: Int?

    public init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
    }

    public var count: Int {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.entriesById.count
    }

    @discardableResult
    public func enqueue(
        key: BonemanTranslationCacheKey,
        subscriberId: Int,
        completion: @escaping Completion
    ) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }

        if let workId = self.workIdByKey[key], let entry = self.entriesById[workId] {
            entry.completions[subscriberId] = completion
            return true
        }
        guard self.entriesById.count < self.capacity else {
            return false
        }

        let workId = self.nextWorkId
        self.nextWorkId &+= 1
        let work = BonemanTranslationWork(id: workId, key: key)
        self.entriesById[workId] = Entry(work: work, subscriberId: subscriberId, completion: completion)
        self.workIdByKey[key] = workId
        self.pendingWorkIds.append(workId)
        return true
    }

    /// Returns a work item only when no other item is active.
    public func beginNextIfIdle() -> BonemanTranslationWork? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard self.activeWorkId == nil else {
            return nil
        }

        while !self.pendingWorkIds.isEmpty {
            let workId = self.pendingWorkIds.removeFirst()
            guard let entry = self.entriesById[workId], !entry.completions.isEmpty else {
                self.removeEntryLocked(workId: workId)
                continue
            }
            self.activeWorkId = workId
            return entry.work
        }
        return nil
    }

    public var activeWork: BonemanTranslationWork? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let activeWorkId = self.activeWorkId else {
            return nil
        }
        return self.entriesById[activeWorkId]?.work
    }

    @discardableResult
    public func completeActive(workId: Int, result: BonemanTranslationWorkResult) -> Bool {
        let completions: [Completion]
        self.lock.lock()
        guard self.activeWorkId == workId, let entry = self.entriesById[workId] else {
            self.lock.unlock()
            return false
        }
        completions = Array(entry.completions.values)
        self.activeWorkId = nil
        self.removeEntryLocked(workId: workId)
        self.lock.unlock()

        for completion in completions {
            completion(result)
        }
        return true
    }

    public func cancel(subscriberId: Int) {
        self.lock.lock()
        var emptyPendingWorkIds: [Int] = []
        for (workId, entry) in self.entriesById {
            entry.completions.removeValue(forKey: subscriberId)
            if entry.completions.isEmpty, workId != self.activeWorkId {
                emptyPendingWorkIds.append(workId)
            }
        }
        for workId in emptyPendingWorkIds {
            self.removeEntryLocked(workId: workId)
        }
        if !emptyPendingWorkIds.isEmpty {
            let removedIds = Set(emptyPendingWorkIds)
            self.pendingWorkIds.removeAll(where: { removedIds.contains($0) })
        }
        self.lock.unlock()
    }

    public func cancelAll() {
        self.lock.lock()
        let activeWorkId = self.activeWorkId
        let pendingWorkIds = self.pendingWorkIds
        self.pendingWorkIds.removeAll(keepingCapacity: false)
        for workId in pendingWorkIds {
            self.removeEntryLocked(workId: workId)
        }
        if let activeWorkId, let activeEntry = self.entriesById[activeWorkId] {
            activeEntry.completions.removeAll(keepingCapacity: false)
            if self.workIdByKey[activeEntry.work.key] == activeWorkId {
                self.workIdByKey.removeValue(forKey: activeEntry.work.key)
            }
        }
        self.lock.unlock()
    }

    private func removeEntryLocked(workId: Int) {
        guard let entry = self.entriesById.removeValue(forKey: workId) else {
            return
        }
        if self.workIdByKey[entry.work.key] == workId {
            self.workIdByKey.removeValue(forKey: entry.work.key)
        }
    }
}
