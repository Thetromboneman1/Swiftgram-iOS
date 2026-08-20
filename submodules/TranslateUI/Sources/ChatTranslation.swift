import TextFormat
import Foundation
import NaturalLanguage
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramUIPreferences
import AlertUI
import Display
import PresentationDataUtils

public struct ChatTranslationState: Codable {
    enum CodingKeys: String, CodingKey {
        case baseLang
        case fromLang
        case timestamp
        case toLang
        case isEnabled
    }
    
    public let baseLang: String
    public let fromLang: String
    public let timestamp: Int32?
    public let toLang: String?
    public let isEnabled: Bool
    
    public init(
        baseLang: String,
        fromLang: String,
        timestamp: Int32?,
        toLang: String?,
        isEnabled: Bool
    ) {
        self.baseLang = baseLang
        self.fromLang = fromLang
        self.timestamp = timestamp
        self.toLang = toLang
        self.isEnabled = isEnabled
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.baseLang = try container.decode(String.self, forKey: .baseLang)
        self.fromLang = try container.decode(String.self, forKey: .fromLang)
        self.timestamp = try container.decodeIfPresent(Int32.self, forKey: .timestamp)
        self.toLang = try container.decodeIfPresent(String.self, forKey: .toLang)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.baseLang, forKey: .baseLang)
        try container.encode(self.fromLang, forKey: .fromLang)
        try container.encodeIfPresent(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.toLang, forKey: .toLang)
        try container.encode(self.isEnabled, forKey: .isEnabled)
    }

    public func withFromLang(_ fromLang: String) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: fromLang,
            timestamp: self.timestamp,
            toLang: self.toLang,
            isEnabled: self.isEnabled
        )
    }
    public func withToLang(_ toLang: String?) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: self.fromLang,
            timestamp: self.timestamp,
            toLang: toLang,
            isEnabled: self.isEnabled
        )
    }
    
    public func withIsEnabled(_ isEnabled: Bool) -> ChatTranslationState {
        return ChatTranslationState(
            baseLang: self.baseLang,
            fromLang: self.fromLang,
            timestamp: self.timestamp,
            toLang: self.toLang,
            isEnabled: isEnabled
        )
    }
}

private func cachedChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?) -> Signal<ChatTranslationState?, NoError> {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    
    return engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
}

private func updateChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?, state: ChatTranslationState?) -> Signal<Never, NoError> {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    
    if let state {
        return engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key, item: state)
    } else {
        return engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key)
    }
}

public func updateChatTranslationStateInteractively(engine: TelegramEngine, peerId: EnginePeer.Id, threadId: Int64?, _ f: @escaping (ChatTranslationState?) -> ChatTranslationState?) -> Signal<Never, NoError> {
    let key: EngineDataBuffer
    if let threadId {
        key = EngineDataBuffer(length: 16)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
        key.setInt64(8, value: threadId)
    } else {
        key = EngineDataBuffer(length: 8)
        key.setInt64(0, value: peerId.id._internalGetInt64Value())
    }
    
    return engine.data.get(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
    |> mapToSignal { current -> Signal<Never, NoError> in
        if let current {
            return updateChatTranslationState(engine: engine, peerId: peerId, threadId: threadId, state: f(current))
        } else {
            return .never()
        }
    }
}


@available(iOS 12.0, *)
private let languageRecognizer = NLLanguageRecognizer()

private struct AppleTranslationFailureAlertState {
    let timestamp: Double
    let shouldPresent: Bool
}

private let appleTranslationFailureAlertState = Atomic<AppleTranslationFailureAlertState>(
    value: AppleTranslationFailureAlertState(timestamp: 0.0, shouldPresent: false)
)

private func presentAppleTranslationFailure(context: AccountContext) {
    let currentTimestamp = CFAbsoluteTimeGetCurrent()
    let alertState = appleTranslationFailureAlertState.modify { previousState in
        if currentTimestamp - previousState.timestamp < 30.0 {
            return AppleTranslationFailureAlertState(timestamp: previousState.timestamp, shouldPresent: false)
        } else {
            return AppleTranslationFailureAlertState(timestamp: currentTimestamp, shouldPresent: true)
        }
    }
    guard alertState.shouldPresent else {
        return
    }

    Queue.mainQueue().async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = textAlertController(
            context: context,
            title: "Apple Translation",
            text: "Apple Translation could not translate one or more messages. Unsupported or ambiguous messages will stay original while supported messages continue translating on device.",
            actions: [
                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
            ]
        )
        context.sharedContext.presentGlobalController(controller, nil)
    }
}

public func translateMessageIds(context: AccountContext, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, viaText: Bool = false, forQuickTranslate: Bool = false) -> Signal<Never, NoError> {
    return context.account.postbox.transaction { transaction -> Signal<Never, NoError> in
        var messageDictToTranslate: [EngineMessage.Id: String] = [:]
        var messageIdsToTranslate: [EngineMessage.Id] = []
        var messageIdsSet = Set<EngineMessage.Id>()
        for messageId in messageIds {
            if let message = transaction.getMessage(messageId) {
                if let replyAttribute = message.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute, let replyMessage = message.associatedMessages[replyAttribute.messageId] {
                    if !replyMessage.text.isEmpty {
                        if replyMessage.attributes.contains(where: { attribute in
                            guard let translation = attribute as? TranslationMessageAttribute else {
                                return false
                            }
                            return translation.toLang == toLang && translation.hasRenderableContent
                        }) {
                        } else {
                            if !messageIdsSet.contains(replyMessage.id) {
                                messageIdsToTranslate.append(replyMessage.id)
                                messageIdsSet.insert(replyMessage.id)
                                messageDictToTranslate[replyMessage.id] = replyMessage.text
                            }
                        }
                    }
                }
                // MARK: Swiftgram
                guard forQuickTranslate || message.author?.id != context.account.peerId else {
                    continue
                }
                if message.attributes.contains(where: { attribute in
                    guard let translation = attribute as? TranslationMessageAttribute else {
                        return false
                    }
                    return translation.toLang == toLang && translation.hasRenderableContent
                }) {
                    continue
                }
                
                if !message.text.isEmpty {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                        messageDictToTranslate[messageId] = message.text
                    }
                } else if let _ = message.richText {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                        messageDictToTranslate[messageId] = message.text
                    }
                } else if let _ = message.richText {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                        messageDictToTranslate[messageId] = message.text
                    }
                // TODO(swiftgram): Translate polls
                } else if let _ = message.media.first(where: { $0 is TelegramMediaPoll }), !viaText {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                } else if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
                    if !messageIdsSet.contains(messageId) {
                        messageIdsToTranslate.append(messageId)
                        messageIdsSet.insert(messageId)
                    }
                }
            } else {
                if !messageIdsSet.contains(messageId) {
                    messageIdsToTranslate.append(messageId)
                    messageIdsSet.insert(messageId)
                }
            }
        }
        
        if isAppleTranslationSelected(context: context) {
            let appleMessageIds = messageIdsToTranslate.filter { messageId in
                guard let message = transaction.getMessage(messageId),
                      message.richText == nil,
                      !message.media.contains(where: { $0 is TelegramMediaPoll }),
                      !message.attributes.contains(where: { $0 is AudioTranscriptionMessageAttribute }) else {
                    return false
                }
                return shouldScheduleAppleTranslation(text: message.text, toLanguage: toLang)
            }
            guard canUseAppleChatTranslation(context: context), !appleMessageIds.isEmpty else {
                return .complete()
            }
            return context.engine.messages.translateMessages(
                messageIds: appleMessageIds,
                fromLang: nil,
                toLang: toLang,
                enableLocalIfPossible: false,
                localOnly: true
            )
            |> `catch` { _ -> Signal<Never, NoError> in
                // A local failure may mean an unsupported pair or a language pack that the user
                // declined to download. Completing here is deliberate: never fall back to cloud.
                presentAppleTranslationFailure(context: context)
                return .complete()
            }
        }

        let enableLocalIfPossible = false
        if viaText {
        return context.engine.messages.translateMessagesViaText(messagesDict: messageDictToTranslate, fromLang: fromLang, toLang: toLang, generateEntitiesFunction: { text in
            generateTextEntities(text, enabledTypes: .all)
        }, enableLocalIfPossible: enableLocalIfPossible) //context.sharedContext.immediateExperimentalUISettings.enableLocalTranslation)
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }
        } else {
        if forQuickTranslate && messageIdsToTranslate.isEmpty { return .complete() } // Otherwise Telegram's API will return .never()
        return context.engine.messages.translateMessages(messageIds: messageIdsToTranslate, fromLang: fromLang, toLang: toLang, enableLocalIfPossible: enableLocalIfPossible)
        |> `catch` { _ -> Signal<Never, NoError> in
            return translateMessageIds(context: context, messageIds: messageIdsToTranslate, fromLang: fromLang, toLang: toLang, viaText: true, forQuickTranslate: forQuickTranslate)
        }
        }
    } |> switchToLatest
}

public func chatTranslationState(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, forcePredict: Bool = false) -> Signal<ChatTranslationState?, NoError> {
    if peerId.id == EnginePeer.Id.Id._internalFromInt64Value(777000) {
        return .single(nil)
    }
    
    guard canTranslateChats(context: context) else {
        return .single(nil)
    }
    
    let loggingEnabled = context.sharedContext.immediateExperimentalUISettings.logLanguageRecognition
    
    if #available(iOS 12.0, *) {
        var baseLang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let rawSuffix = "-raw"
        if baseLang.hasSuffix(rawSuffix) {
            baseLang = String(baseLang.dropLast(rawSuffix.count))
        }

        return combineLatest(
            context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.translationSettings])
            |> map { sharedData -> TranslationSettings in
                return sharedData.entries[ApplicationSpecificSharedDataKeys.translationSettings]?.get(TranslationSettings.self) ?? TranslationSettings.defaultSettings
            },
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AutoTranslateEnabled(id: peerId))
        )
        |> mapToSignal { settings, autoTranslateEnabled in
            if !settings.translateChats && !autoTranslateEnabled && !forcePredict {
                return .single(nil)
            }
            
            var dontTranslateLanguages = Set<String>()
            if let ignoredLanguages = settings.ignoredLanguages {
                dontTranslateLanguages = Set(ignoredLanguages)
            } else {
                dontTranslateLanguages.insert(baseLang)
                for language in systemLanguageCodes() {
                    dontTranslateLanguages.insert(language)
                }
            }
            
            return cachedChatTranslationState(engine: context.engine, peerId: peerId, threadId: threadId)
            |> mapToSignal { cached in
                let currentTime = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                if let cached, let timestamp = cached.timestamp, cached.baseLang == baseLang && currentTime - timestamp < 60 * 60 {
                    if !dontTranslateLanguages.contains(cached.fromLang) || forcePredict {
                        return .single(cached)
                    } else {
                        return .single(nil)
                    }
                } else {
                    return .single(nil)
                    |> then(
                        context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .upperBound, anchorIndex: .upperBound, count: 32, fixedCombinedReadStates: nil)
                        |> filter { messageHistoryView -> Bool in
                            return messageHistoryView.0.entries.count > 1
                        }
                        |> take(1)
                        |> map { messageHistoryView, _, _ -> ChatTranslationState? in
                            let messages = messageHistoryView.entries.map(\.message)
                            
                            if loggingEnabled {
                                Logger.shared.log("ChatTranslation", "Start language recognizing for \(peerId)")
                            }
                            var fromLangs: [String: Int] = [:]
                            var count = 0
                            for message in messages {
                                if message.effectivelyIncoming(context.account.peerId), message.text.count >= 10 {
                                    if let summaryAttribute = message.attributes.first(where: { $0 is SummarizationMessageAttribute }) as? SummarizationMessageAttribute, !summaryAttribute.fromLang.isEmpty {
                                        let fromLang = normalizeTranslationLanguage(summaryAttribute.fromLang)
                                        if supportedTranslationLanguages.contains(fromLang) {
                                            fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + message.text.count
                                            count += 1
                                        }
                                    } else {
                                        var text = String(message.text.prefix(256))
                                        if var entities = message.textEntitiesAttribute?.entities.filter({ entity in
                                            switch entity.type {
                                            case .Pre, .Code, .Url, .Email, .Mention, .Hashtag, .BotCommand:
                                                return true
                                            default:
                                                return false
                                            }
                                        }) {
                                            entities = entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound })
                                            var ranges: [Range<String.Index>] = []
                                            for entity in entities {
                                                if entity.range.lowerBound > text.count || entity.range.upperBound > text.count {
                                                    continue
                                                }
                                                ranges.append(text.index(text.startIndex, offsetBy: entity.range.lowerBound) ..< text.index(text.startIndex, offsetBy: entity.range.upperBound))
                                            }
                                            for range in ranges {
                                                if range.upperBound < text.endIndex {
                                                    text.removeSubrange(range)
                                                }
                                            }
                                        }
                                        
                                        if message.text.count < 10 {
                                            continue
                                        }
                                        
                                        languageRecognizer.processString(text)
                                        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 4)
                                        languageRecognizer.reset()
                                        
                                        let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
                                        if let language = filteredLanguages.first {
                                            let fromLang = normalizeTranslationLanguage(language.key.rawValue)
                                            if loggingEnabled && !["en", "ru"].contains(fromLang) && !dontTranslateLanguages.contains(fromLang) {
                                                Logger.shared.log("ChatTranslation", "\(text)")
                                                Logger.shared.log("ChatTranslation", "Recognized as: \(fromLang), other hypotheses: \(hypotheses.map { $0.key.rawValue }.joined(separator: ",")) ")
                                            }
                                            fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + message.text.count
                                            count += 1
                                        }
                                    }
                                }
                                if count >= 16 {
                                    break
                                }
                            }
                                                        
                            var mostFrequent: (String, Int)?
                            for (lang, count) in fromLangs {
                                if let current = mostFrequent {
                                    if count > current.1 {
                                        mostFrequent = (lang, count)
                                    }
                                } else {
                                    mostFrequent = (lang, count)
                                }
                            }
                            let fromLang = mostFrequent?.0 ?? ""
                            if loggingEnabled {
                                Logger.shared.log("ChatTranslation", "Ended with: \(fromLang)")
                            }
                            
                            let isEnabled: Bool
                            if let currentIsEnabled = cached?.isEnabled {
                                isEnabled = currentIsEnabled
                            } else if autoTranslateEnabled {
                                isEnabled = true
                            } else {
                                isEnabled = false
                            }
                            
                            let state = ChatTranslationState(
                                baseLang: baseLang,
                                fromLang: fromLang,
                                timestamp: currentTime,
                                toLang: cached?.toLang,
                                isEnabled: isEnabled
                            )
                            let _ = updateChatTranslationState(engine: context.engine, peerId: peerId, threadId: threadId, state: state).start()
                            if !dontTranslateLanguages.contains(fromLang) || forcePredict {
                                return state
                            } else {
                                return nil
                            }
                        }
                    )
                }
            }
        }
    } else {
        return .single(nil)
    }
}
