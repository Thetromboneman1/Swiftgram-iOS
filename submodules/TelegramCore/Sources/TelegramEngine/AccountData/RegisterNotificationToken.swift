import Foundation
import SwiftSignalKit
import Postbox
import TelegramApi
import MtProtoKit


public enum NotificationTokenType {
    case aps(encrypt: Bool)
    case voip
}

func _internal_unregisterNotificationToken(account: Account, token: Data, type: NotificationTokenType, otherAccountUserIds: [PeerId.Id]) -> Signal<Never, NoError> {
    let mappedType: Int32
    switch type {
        case .aps:
            mappedType = 1
        case .voip:
            mappedType = 9
    }
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: mappedType, token: hexString(token), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> retryRequest
    |> ignoreValues
}

func _internal_registerNotificationToken(account: Account, token: Data, type: NotificationTokenType, sandbox: Bool, otherAccountUserIds: [PeerId.Id], excludeMutedChats: Bool) -> Signal<Bool, NoError> {
    let networkReady = account.networkState
    |> filter { state in
        switch state {
        case .online, .updating:
            return true
        default:
            return false
        }
    }
    |> take(1)
    |> map { _ -> Void in
        Logger.shared.log("Push Registration", "Telegram network ready")
        return Void()
    }

    return combineLatest(
        masterNotificationsKey(account: account, ignoreDisabled: false),
        networkReady
    )
    |> mapToSignal { masterKey, _ -> Signal<Bool, NoError> in
        let mappedType: Int32
        var keyData = Data()
        switch type {
            case let .aps(encrypt):
                mappedType = 1
                if encrypt {
                    keyData = masterKey.data
                }
            case .voip:
                mappedType = 9
                keyData = masterKey.data
        }
        var flags: Int32 = 0
        if excludeMutedChats {
            flags |= 1 << 0
        }
        return account.network.request(Api.functions.account.registerDevice(flags: flags, tokenType: mappedType, token: hexString(token), appSandbox: sandbox ? .boolTrue : .boolFalse, secret: Buffer(data: keyData), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
        |> timeout(15.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(MTRpcError(errorCode: -1000, errorDescription: "PUSH_REGISTRATION_TIMEOUT")))
        |> retry(retryOnError: { error in
            if error.errorDescription == "TOKEN_WAS_INVALIDATED" {
                return false
            }
            return error.errorCode <= 0 || error.errorCode >= 500
        }, delayIncrement: 1.0, maxDelay: 30.0, maxRetries: nil, onQueue: Queue.concurrentDefaultQueue())
        |> map { _ -> Bool in
            return true
        }
        |> `catch` { _ -> Signal<Bool, NoError> in
            // Never report a failed Telegram registration as successful. A false
            // result asks the app delegate to refresh the APNs token once, while
            // transport failures continue with a capped backoff above.
            return .single(false)
        }
    }
}
