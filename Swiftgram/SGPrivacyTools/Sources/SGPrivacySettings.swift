import Foundation

public enum SGPrivateActivityKind: String, CaseIterable {
    case typing
    case recording
    case uploading
    case emojiInteraction
}

/// Native privacy controls shared by the typed Telegram request and Swiftgram UI layers.
public final class SGPrivacySettings {
    public static let shared = SGPrivacySettings()

    private enum Key {
        static let hideTyping = "privacy.hideTyping"
        static let hideRecording = "privacy.hideRecording"
        static let hideUploading = "privacy.hideUploading"
        static let hideEmojiInteractions = "privacy.hideEmojiInteractions"
        static let hideOnlineStatus = "privacy.hideOnlineStatus"
        static let hideSponsoredMessages = "privacy.hideSponsoredMessages"
        static let retainEditHistory = "privacy.retainEditHistory"
        static let peerExceptions = "privacy.peerExceptions"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.hideTyping: false,
            Key.hideRecording: false,
            Key.hideUploading: false,
            Key.hideEmojiInteractions: false,
            Key.hideOnlineStatus: false,
            Key.hideSponsoredMessages: true,
            Key.retainEditHistory: true,
            Key.peerExceptions: [String](),
        ])
    }

    public var hideTyping: Bool {
        get { self.defaults.bool(forKey: Key.hideTyping) }
        set { self.defaults.set(newValue, forKey: Key.hideTyping) }
    }

    public var hideRecording: Bool {
        get { self.defaults.bool(forKey: Key.hideRecording) }
        set { self.defaults.set(newValue, forKey: Key.hideRecording) }
    }

    public var hideUploading: Bool {
        get { self.defaults.bool(forKey: Key.hideUploading) }
        set { self.defaults.set(newValue, forKey: Key.hideUploading) }
    }

    public var hideEmojiInteractions: Bool {
        get { self.defaults.bool(forKey: Key.hideEmojiInteractions) }
        set { self.defaults.set(newValue, forKey: Key.hideEmojiInteractions) }
    }

    public var hideOnlineStatus: Bool {
        get { self.defaults.bool(forKey: Key.hideOnlineStatus) }
        set { self.defaults.set(newValue, forKey: Key.hideOnlineStatus) }
    }

    public var hideSponsoredMessages: Bool {
        get { self.defaults.bool(forKey: Key.hideSponsoredMessages) }
        set { self.defaults.set(newValue, forKey: Key.hideSponsoredMessages) }
    }

    public var retainEditHistory: Bool {
        get { self.defaults.bool(forKey: Key.retainEditHistory) }
        set { self.defaults.set(newValue, forKey: Key.retainEditHistory) }
    }

    public var hasAnyGhostModeEnabled: Bool {
        return self.hideTyping || self.hideRecording || self.hideUploading || self.hideEmojiInteractions || self.hideOnlineStatus
    }

    public func shouldSuppress(accountPeerId: Int64, peerId: Int64, activity: SGPrivateActivityKind) -> Bool {
        if self.isPeerException(accountPeerId: accountPeerId, peerId: peerId) {
            return false
        }
        switch activity {
        case .typing:
            return self.hideTyping
        case .recording:
            return self.hideRecording
        case .uploading:
            return self.hideUploading
        case .emojiInteraction:
            return self.hideEmojiInteractions
        }
    }

    public func isPeerException(accountPeerId: Int64, peerId: Int64) -> Bool {
        let key = Self.peerExceptionKey(accountPeerId: accountPeerId, peerId: peerId)
        self.lock.lock()
        defer { self.lock.unlock() }
        return Set(self.defaults.stringArray(forKey: Key.peerExceptions) ?? []).contains(key)
    }

    public func setPeerException(accountPeerId: Int64, peerId: Int64, value: Bool) {
        let key = Self.peerExceptionKey(accountPeerId: accountPeerId, peerId: peerId)
        self.lock.lock()
        defer { self.lock.unlock() }
        var values = self.defaults.stringArray(forKey: Key.peerExceptions) ?? []
        values.removeAll(where: { $0 == key })
        if value {
            values.append(key)
        }
        // Bound stale account/chat entries while preserving most recently changed exceptions.
        self.defaults.set(Array(values.suffix(512)), forKey: Key.peerExceptions)
    }

    private static func peerExceptionKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "\(accountPeerId):\(peerId)"
    }
}
