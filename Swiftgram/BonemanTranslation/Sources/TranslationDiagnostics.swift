import Foundation

public struct BonemanTranslationDiagnosticsSnapshot: Equatable {
    public let backend: String
    public let languagePair: String
    public let modelStatus: String
    public let batchState: String
    public let queueDepth: Int
    public let translatedCount: Int
    public let skippedCount: Int
    public let failedMessageIds: [String]

    public var redactedReport: String {
        return [
            "Translation backend: \(self.backend)",
            "Language pair: \(self.languagePair)",
            "Apple model status: \(self.modelStatus)",
            "Batch state: \(self.batchState)",
            "Queue depth: \(self.queueDepth)",
            "Translated: \(self.translatedCount)",
            "Skipped: \(self.skippedCount)",
            "Failed message IDs: \(self.failedMessageIds.isEmpty ? "none" : self.failedMessageIds.joined(separator: ", "))",
        ].joined(separator: "\n")
    }
}

/// Process-memory-only operational state. It never accepts or stores message text.
public final class BonemanTranslationDiagnostics {
    public static let shared = BonemanTranslationDiagnostics()

    private let lock = NSLock()
    private var languagePair = "none"
    private var modelStatus = "unknown"
    private var batchState = "idle"
    private var queueDepth = 0
    private var translatedCount = 0
    private var skippedCount = 0
    private var failedMessageIds: [String] = []

    public init() {}

    public func recordBatch(sourceLanguage: String?, targetLanguage: String, pendingCount: Int) {
        self.lock.lock()
        self.languagePair = "\(sourceLanguage ?? "auto")->\(targetLanguage)"
        self.batchState = pendingCount == 0 ? "idle" : "processing"
        self.queueDepth = max(0, pendingCount)
        self.lock.unlock()
    }

    public func recordModelStatus(_ status: String, sourceLanguage: String?, targetLanguage: String) {
        self.lock.lock()
        self.languagePair = "\(sourceLanguage ?? "auto")->\(targetLanguage)"
        self.modelStatus = status
        self.lock.unlock()
    }

    public func recordResult(_ result: BonemanTranslationWorkResult, failedOpaqueIds: [String] = [], remainingCount: Int) {
        self.lock.lock()
        switch result {
        case .translated:
            self.translatedCount += 1
        case .skipped:
            self.skippedCount += 1
        case .failed:
            self.failedMessageIds.append(contentsOf: failedOpaqueIds)
            self.failedMessageIds = Array(self.failedMessageIds.suffix(50))
        }
        self.queueDepth = max(0, remainingCount)
        self.batchState = remainingCount == 0 ? "idle" : "processing"
        self.lock.unlock()
    }

    public func recordCancelled() {
        self.lock.lock()
        self.batchState = "cancelled"
        self.queueDepth = 0
        self.lock.unlock()
    }

    public func snapshot() -> BonemanTranslationDiagnosticsSnapshot {
        self.lock.lock()
        defer { self.lock.unlock() }
        return BonemanTranslationDiagnosticsSnapshot(
            backend: "Apple TranslationSession (on-device)",
            languagePair: self.languagePair,
            modelStatus: self.modelStatus,
            batchState: self.batchState,
            queueDepth: self.queueDepth,
            translatedCount: self.translatedCount,
            skippedCount: self.skippedCount,
            failedMessageIds: self.failedMessageIds
        )
    }

    public func clear() {
        self.lock.lock()
        self.languagePair = "none"
        self.modelStatus = "unknown"
        self.batchState = "idle"
        self.queueDepth = 0
        self.translatedCount = 0
        self.skippedCount = 0
        self.failedMessageIds.removeAll(keepingCapacity: false)
        self.lock.unlock()
    }

    /// Produces a non-reversible, process-local identifier suitable for a redacted report.
    public static func opaqueMessageId(_ value: AnyHashable) -> String {
        var hasher = Hasher()
        hasher.combine(value)
        return String(format: "%08llx", UInt64(bitPattern: Int64(hasher.finalize())))
    }
}
