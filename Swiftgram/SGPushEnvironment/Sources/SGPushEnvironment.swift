import Foundation

public enum SGPushEnvironment {
    public static let infoPlistKey = "TelegramAPSEnvironment"

    public static func isSandbox(apsEnvironment: String?, fallbackIsDebug: Bool) -> Bool {
        switch apsEnvironment?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "development", "sandbox":
            return true
        case "production":
            return false
        default:
            return fallbackIsDebug
        }
    }

    public static var isSandboxForCurrentApp: Bool {
        #if DEBUG
        let fallbackIsDebug = true
        #else
        let fallbackIsDebug = false
        #endif

        return isSandbox(
            apsEnvironment: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
            fallbackIsDebug: fallbackIsDebug
        )
    }
}
