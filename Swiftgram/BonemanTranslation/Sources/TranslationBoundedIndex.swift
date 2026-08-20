import Foundation

/// A small ordered set used to bound persisted Apple-translation ownership metadata.
///
/// Values are ordered from least to most recently touched. Touching an existing value moves it to
/// the end, and inserting beyond `capacity` returns the exact values that must be evicted.
public struct BonemanTranslationBoundedIndex<Element: Hashable> {
    public private(set) var values: [Element]

    private let capacity: Int

    public init(values: [Element] = [], capacity: Int) {
        self.capacity = max(1, capacity)

        var uniqueValues: [Element] = []
        var seen = Set<Element>()
        for value in values.reversed() {
            if seen.insert(value).inserted {
                uniqueValues.append(value)
            }
        }
        uniqueValues.reverse()
        self.values = Array(uniqueValues.suffix(self.capacity))
    }

    @discardableResult
    public mutating func touch(_ value: Element) -> [Element] {
        self.values.removeAll(where: { $0 == value })
        self.values.append(value)

        guard self.values.count > self.capacity else {
            return []
        }
        let overflowCount = self.values.count - self.capacity
        let evicted = Array(self.values.prefix(overflowCount))
        self.values.removeFirst(overflowCount)
        return evicted
    }

    public mutating func remove(_ values: Set<Element>) {
        guard !values.isEmpty else {
            return
        }
        self.values.removeAll(where: { values.contains($0) })
    }
}
