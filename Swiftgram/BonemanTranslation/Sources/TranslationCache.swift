import Foundation

public struct BonemanTranslationCacheKey: Hashable {
    public let text: String
    public let sourceLanguage: String?
    public let targetLanguage: String

    public init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage.map(BonemanTranslationPolicy.canonicalLanguageIdentifier)
        self.targetLanguage = BonemanTranslationPolicy.canonicalLanguageIdentifier(targetLanguage)
    }
}

/// A bounded, process-memory-only LRU cache. It never writes message text to disk or preferences.
public final class BonemanTranslationCache {
    private let capacity: Int
    private let lock = NSLock()
    private var values: [BonemanTranslationCacheKey: String] = [:]
    private var recency: [BonemanTranslationCacheKey] = []

    public init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    public var count: Int {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.values.count
    }

    public func value(for key: BonemanTranslationCacheKey) -> String? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let value = self.values[key] else {
            return nil
        }
        self.markMostRecent(key)
        return value
    }

    public func insert(_ value: String, for key: BonemanTranslationCacheKey) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }

        self.values[key] = value
        self.markMostRecent(key)
        while self.values.count > self.capacity, let oldestKey = self.recency.first {
            self.recency.removeFirst()
            self.values.removeValue(forKey: oldestKey)
        }
    }

    public func removeAll() {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        self.values.removeAll(keepingCapacity: false)
        self.recency.removeAll(keepingCapacity: false)
    }

    private func markMostRecent(_ key: BonemanTranslationCacheKey) {
        if let index = self.recency.firstIndex(of: key) {
            self.recency.remove(at: index)
        }
        self.recency.append(key)
    }
}
