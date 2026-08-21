import BonemanTranslation
import SGSimpleSettings
import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import NaturalLanguage
import TelegramCore
import SwiftUI
import Translation
import Combine

// Incuding at least one Objective-C class in a swift file ensures that it doesn't get stripped by the linker
private final class LinkHelperClass: NSObject {
}

public let supportedTranslationLanguages = [
    "af",
    "sq",
    "am",
    "ar",
    "hy",
    "az",
    "eu",
    "be",
    "bn",
    "bs",
    "bg",
    "ca",
    "ceb",
    "zh",
    "co",
    "hr",
    "cs",
    "da",
    "nl",
    "en",
    "eo",
    "et",
    "fi",
    "fr",
    "fy",
    "gl",
    "ka",
    "de",
    "el",
    "gu",
    "ht",
    "ha",
    "haw",
    "he",
    "hi",
    "hmn",
    "hu",
    "is",
    "ig",
    "id",
    "ga",
    "it",
    "ja",
    "jv",
    "kn",
    "kk",
    "km",
    "rw",
    "ko",
    "ku",
    "ky",
    "lo",
    "lv",
    "lt",
    "lb",
    "mk",
    "mg",
    "ms",
    "ml",
    "mt",
    "mi",
    "mr",
    "mn",
    "my",
    "ne",
    "no",
    "ny",
    "or",
    "ps",
    "fa",
    "pl",
    "pt",
    "pt-BR",
    "pa",
    "ro",
    "ru",
    "sm",
    "gd",
    "sr",
    "st",
    "sn",
    "sd",
    "si",
    "sk",
    "sl",
    "so",
    "es",
    "su",
    "sw",
    "sv",
    "tl",
    "tg",
    "ta",
    "tt",
    "te",
    "th",
    "tr",
    "tk",
    "uk",
    "ur",
    "ug",
    "uz",
    "vi",
    "cy",
    "xh",
    "yi",
    "yo",
    "zu"
]

public let popularTranslationLanguages = [
    "en",
    "ar",
    "zh",
    "fr",
    "de",
    "it",
    "ja",
    "ko",
    "pt-BR",
    "ru",
    "es",
    "uk"
]

@available(iOS 12.0, *)
private let languageRecognizer = NLLanguageRecognizer()

public func effectiveIgnoredTranslationLanguages(context: AccountContext, ignoredLanguages: [String]?) -> Set<String> {
    var baseLang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let rawSuffix = "-raw"
    if baseLang.hasSuffix(rawSuffix) {
        baseLang = String(baseLang.dropLast(rawSuffix.count))
    }
    
    var dontTranslateLanguages = Set<String>()
    if let ignoredLanguages = ignoredLanguages {
        dontTranslateLanguages = Set(ignoredLanguages.map(normalizeTranslationLanguage))
    } else {
        dontTranslateLanguages.insert(normalizeTranslationLanguage(baseLang))
        for language in systemLanguageCodes() {
            dontTranslateLanguages.insert(language)
        }
    }
    return dontTranslateLanguages
}

public func normalizeTranslationLanguage(_ code: String) -> String {
    return BonemanTranslationPolicy.canonicalLanguageIdentifier(code)
}

private func detectedAppleTranslationLanguage(for text: String) -> String? {
    guard #available(iOS 12.0, *) else {
        return nil
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(256)))
    let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
    return hypotheses
        .filter { $0.key != .undetermined }
        .sorted(by: { $0.value > $1.value })
        .first
        .map { normalizeTranslationLanguage($0.key.rawValue) }
}

private func resolvedAppleTranslationLanguage(for text: String, preferredLanguage: String?) -> String? {
    let detectedLanguage = detectedAppleTranslationLanguage(for: text)
    return BonemanTranslationPolicy.resolvedSourceLanguage(
        text: text,
        detectedLanguage: detectedLanguage,
        preferredLanguage: preferredLanguage
    )
}

public func shouldScheduleAppleTranslation(text: String, toLanguage: String) -> Bool {
    let sourceLanguage = detectedAppleTranslationLanguage(for: text)
    return BonemanTranslationPolicy.shouldTranslate(
        text: text,
        fromLanguage: sourceLanguage,
        toLanguage: normalizeTranslationLanguage(toLanguage)
    )
}

public func isAppleTranslationSelected(context: AccountContext) -> Bool {
    switch SGSimpleSettings.shared.translationBackendEnum {
    case .system:
        return true
    case .gtranslate:
        return false
    case .default:
        let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
        switch (translationConfiguration.manual, translationConfiguration.auto) {
        case (.system, _), (_, .system):
            return true
        default:
            return false
        }
    }
}

public func canUseAppleTranslation(context: AccountContext) -> Bool {
    guard isAppleTranslationSelected(context: context) else {
        return false
    }
    // The Boneman privacy contract uses TranslationSession only, which requires iOS 18 or later.
    if #available(iOS 18.0, *) {
        return true
    } else {
        return false
    }
}

public func canUseAppleChatTranslation(context: AccountContext) -> Bool {
    guard isAppleTranslationSelected(context: context) else {
        return false
    }
    if #available(iOS 18.0, *) {
        return true
    } else {
        return false
    }
}

public func canTranslateChats(context: AccountContext) -> Bool {
    if isAppleTranslationSelected(context: context) {
        return canUseAppleChatTranslation(context: context)
    }
    return true
}

public func canTranslateText(context: AccountContext, text: String, showTranslate: Bool, showTranslateIfTopical: Bool = false, ignoredLanguages: [String]?) -> (canTranslate: Bool, language: String?) {
    let shouldOfferAppleTranslation = isAppleTranslationSelected(context: context)
    guard showTranslate || showTranslateIfTopical || shouldOfferAppleTranslation,
          BonemanTranslationPolicy.shouldTranslate(text: text, fromLanguage: nil, toLanguage: "und") else {
        return (false, nil)
    }

    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var translateButtonAvailable = false
    switch translationConfiguration.manual {
    case .enabled, .alternative:
        translateButtonAvailable = true
    case .system:
        translateButtonAvailable = canUseAppleTranslation(context: context)
    default:
        break
    }
    if isAppleTranslationSelected(context: context) {
        translateButtonAvailable = canUseAppleTranslation(context: context)
    } else {
        translateButtonAvailable = true
    }
    let showTranslate = showTranslate && translateButtonAvailable
        
    if #available(iOS 12.0, *) {
        if context.sharedContext.immediateExperimentalUISettings.disableLanguageRecognition {
            return (true, nil)
        }
                
        let dontTranslateLanguages = effectiveIgnoredTranslationLanguages(context: context, ignoredLanguages: ignoredLanguages)
        
        let text = String(text.prefix(64))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        
        var supportedTranslationLanguages = supportedTranslationLanguages
        if !showTranslate && showTranslateIfTopical {
            supportedTranslationLanguages = ["uk", "ru"]
        }
                
        let filteredLanguages = hypotheses.filter {
            if isAppleTranslationSelected(context: context) {
                return $0.key != .undetermined
            } else {
                return supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue))
            }
        }.sorted(by: { $0.value > $1.value })
        if let language = filteredLanguages.first {
            let languageCode = normalizeTranslationLanguage(language.key.rawValue)
            return (!dontTranslateLanguages.contains(languageCode), languageCode)
        } else {
            return (false, nil)
        }
    } else {
        return (false, nil)
    }
}

public func systemLanguageCodes() -> [String] {
    var languages: [String] = []
    for language in Locale.preferredLanguages.prefix(2) {
        languages.append(normalizeTranslationLanguage(language))
    }
    if languages.count == 2 && languages != ["en", "ru"] {
        languages = Array(languages.prefix(1))
    }
    return languages
}

@available(iOS 13.0, *)
class ExternalTranslationTrigger: ObservableObject {
    @Published var generation: Int = 0
}

@available(iOS 18.0, *)
private struct TranslationViewImpl: View {
    @State private var configuration: TranslationSession.Configuration?
    @ObservedObject var externalCondition: ExternalTranslationTrigger
    private let workQueue: BonemanTranslationWorkQueue
    
    init(externalCondition: ExternalTranslationTrigger, workQueue: BonemanTranslationWorkQueue) {
        self.externalCondition = externalCondition
        self.workQueue = workQueue
    }

    private func updateConfigurationForActiveWork() {
        guard let work = self.workQueue.activeWork else {
            return
        }
        let sourceLanguage = work.key.sourceLanguage
        let targetLanguage = work.key.targetLanguage
        let requestedSource = sourceLanguage.map { Locale.Language(identifier: $0) }
        let requestedTarget = Locale.Language(identifier: targetLanguage)
        if self.configuration != nil,
           self.configuration?.source == requestedSource,
           self.configuration?.target == requestedTarget {
            // This is reached only after the previous translationTask action returned. Invalidating
            // while that action is active can make Apple fatal-error the process.
            self.configuration?.invalidate()
        } else {
            self.configuration = .init(
                source: requestedSource,
                target: requestedTarget
            )
        }
    }

    private func complete(work: BonemanTranslationWork, result: BonemanTranslationWorkResult) {
        guard self.workQueue.completeActive(workId: work.id, result: result) else {
            return
        }
        // Defer the next configuration mutation until this translationTask action has returned.
        Queue.mainQueue().async {
            if self.workQueue.beginNextIfIdle() != nil {
                self.externalCondition.generation &+= 1
            }
        }
    }
    
    var body: some View {
        Text("ABC")
        .onAppear {
            self.updateConfigurationForActiveWork()
        }
        .onChange(of: self.externalCondition.generation) { _, _ in
            self.updateConfigurationForActiveWork()
        }
        .translationTask(self.configuration, action: { session in
            guard let work = self.workQueue.activeWork else {
                return
            }

            do {
                let targetLanguage = Locale.Language(identifier: work.key.targetLanguage)
                let languageAvailability = LanguageAvailability()
                let status: LanguageAvailability.Status
                if let sourceLanguage = work.key.sourceLanguage {
                    status = await languageAvailability.status(
                        from: Locale.Language(identifier: sourceLanguage),
                        to: targetLanguage
                    )
                } else {
                    status = try await languageAvailability.status(for: work.key.text, to: targetLanguage)
                }
                switch status {
                case .unsupported:
                    BonemanTranslationDiagnostics.shared.recordModelStatus("unsupported", sourceLanguage: work.key.sourceLanguage, targetLanguage: work.key.targetLanguage)
                    print("[BonemanTranslation] unavailable pair=\(work.key.sourceLanguage ?? "auto")->\(work.key.targetLanguage)")
                    // Unsupported pairs must be visible to the caller. Treating this as a skipped
                    // message stores an empty terminal translation and makes the chat appear
                    // translated even though Apple produced no result.
                    self.complete(work: work, result: .failed)
                    return
                case .supported:
                    BonemanTranslationDiagnostics.shared.recordModelStatus("supported, download may be required", sourceLanguage: work.key.sourceLanguage, targetLanguage: work.key.targetLanguage)
                    // Apple owns the language-resource consent and download UI. Message content
                    // remains in TranslationSession and is not sent to a translation service.
                    // prepareTranslation requires an explicit source language. A nil-source
                    // session must proceed through translate(), where Apple performs detection
                    // and owns any language-resource prompt.
                    if work.key.sourceLanguage != nil {
                        try await session.prepareTranslation()
                    }
                case .installed:
                    BonemanTranslationDiagnostics.shared.recordModelStatus("installed", sourceLanguage: work.key.sourceLanguage, targetLanguage: work.key.targetLanguage)
                    break
                @unknown default:
                    BonemanTranslationDiagnostics.shared.recordModelStatus("unknown", sourceLanguage: work.key.sourceLanguage, targetLanguage: work.key.targetLanguage)
                    print("[BonemanTranslation] unknown availability pair=\(work.key.sourceLanguage ?? "auto")->\(work.key.targetLanguage)")
                    self.complete(work: work, result: .failed)
                    return
                }

                // Exactly one source text enters each task. This keeps mixed-language chats safe and
                // lets a nil-source session auto-detect each visible message independently.
                let response = try await session.translate(work.key.text)
                let translatedText = response.targetText
                if translatedText.isEmpty || translatedText == work.key.text {
                    self.complete(work: work, result: .skipped)
                } else {
                    self.complete(work: work, result: .translated(translatedText))
                }
            } catch {
                if Translation.TranslationError.unsupportedSourceLanguage ~= error
                    || Translation.TranslationError.unsupportedTargetLanguage ~= error
                    || Translation.TranslationError.unsupportedLanguagePairing ~= error {
                    print("[BonemanTranslation] unsupported pair=\(work.key.sourceLanguage ?? "auto")->\(work.key.targetLanguage)")
                    self.complete(work: work, result: .failed)
                } else if Translation.TranslationError.unableToIdentifyLanguage ~= error
                    || Translation.TranslationError.nothingToTranslate ~= error {
                    self.complete(work: work, result: .skipped)
                } else {
                    print("[BonemanTranslation] failed pair=\(work.key.sourceLanguage ?? "auto")->\(work.key.targetLanguage) category=\(String(reflecting: type(of: error)))")
                    self.complete(work: work, result: .failed)
                }
            }
        })
    }
}

@available(iOS 18.0, *)
public final class ExperimentalInternalTranslationServiceImpl: ExperimentalInternalTranslationService {
    private final class TranslationBatch {
        let subscriberId: Int
        private let inputKeysByCacheKey: [BonemanTranslationCacheKey: [AnyHashable]]
        private var remainingKeys: Set<BonemanTranslationCacheKey>
        private var results: [AnyHashable: String]
        private var failed = false
        private var cancelled = false
        private var completion: (([AnyHashable: String]?) -> Void)?

        init(
            subscriberId: Int,
            inputKeysByCacheKey: [BonemanTranslationCacheKey: [AnyHashable]],
            cachedResults: [AnyHashable: String],
            completion: @escaping ([AnyHashable: String]?) -> Void
        ) {
            self.subscriberId = subscriberId
            self.inputKeysByCacheKey = inputKeysByCacheKey
            self.remainingKeys = Set(inputKeysByCacheKey.keys)
            self.results = cachedResults
            self.completion = completion
        }

        func resolve(key: BonemanTranslationCacheKey, result: BonemanTranslationWorkResult) {
            guard !self.cancelled, self.remainingKeys.remove(key) != nil else {
                return
            }
            switch result {
            case let .translated(text):
                for inputKey in self.inputKeysByCacheKey[key] ?? [] {
                    self.results[inputKey] = text
                }
            case .skipped:
                // Empty text is an internal terminal marker. TelegramCore stores an empty local
                // translation attribute so unsupported/no-op visible messages are not rescheduled.
                for inputKey in self.inputKeysByCacheKey[key] ?? [] {
                    self.results[inputKey] = ""
                }
            case .failed:
                self.failed = true
            }

            if self.remainingKeys.isEmpty {
                let completion = self.completion
                self.completion = nil
                completion?(self.failed && self.results.isEmpty ? nil : self.results)
            }
        }

        func cancel() -> Bool {
            let wasPending = self.completion != nil
            self.cancelled = true
            self.completion = nil
            return wasPending
        }
    }
    
    private final class Impl: NSObject {
        private let hostingController: UIViewController
        private let cache = BonemanTranslationCache(capacity: 256)
        private let workQueue = BonemanTranslationWorkQueue(capacity: 128)
        private let taskTrigger = ExternalTranslationTrigger()
        private var nextSubscriberId: Int = 0
        
        init(view: UIView, parentViewController: UIViewController?) {
            self.hostingController = UIHostingController(rootView: TranslationViewImpl(
                externalCondition: self.taskTrigger,
                workQueue: self.workQueue
            ))

            super.init()

            self.hostingController.view.frame = .zero
            self.hostingController.view.backgroundColor = .clear
            self.hostingController.view.isUserInteractionEnabled = false
            self.hostingController.view.accessibilityElementsHidden = true
            parentViewController?.addChild(self.hostingController)
            view.addSubview(self.hostingController.view)
            self.hostingController.didMove(toParent: parentViewController)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.clearCacheForMemoryWarning),
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )

        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            self.hostingController.willMove(toParent: nil)
            self.hostingController.view.removeFromSuperview()
            self.hostingController.removeFromParent()
        }

        @objc private func clearCacheForMemoryWarning() {
            self.cache.removeAll()
        }

        func clearCache() {
            self.workQueue.cancelAll()
            self.cache.removeAll()
        }
        
        func translate(texts: [AnyHashable: String], fromLang: String?, toLang: String, onResult: @escaping ([AnyHashable: String]?) -> Void) -> Disposable {
            let requestedSourceLanguage = fromLang.flatMap { value -> String? in
                return value.isEmpty ? nil : normalizeTranslationLanguage(value)
            }
            let targetLanguage = normalizeTranslationLanguage(toLang)
            var cachedResults: [AnyHashable: String] = [:]
            var inputKeysByCacheKey: [BonemanTranslationCacheKey: [AnyHashable]] = [:]
            for (key, text) in texts {
                // Whole-chat translation intentionally arrives without a single source language
                // because a chat can contain several languages. Detect each message locally so
                // TranslationSession receives an explicit pair and can prepare or download the
                // correct Apple language model instead of silently attempting an unprepared
                // auto-detect session.
                let sourceLanguage = resolvedAppleTranslationLanguage(for: text, preferredLanguage: requestedSourceLanguage)
                guard BonemanTranslationPolicy.shouldTranslate(text: text, fromLanguage: sourceLanguage, toLanguage: targetLanguage) else {
                    cachedResults[key] = ""
                    continue
                }
                let cacheKey = BonemanTranslationCacheKey(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
                if let cachedResult = self.cache.value(for: cacheKey) {
                    cachedResults[key] = cachedResult
                } else {
                    inputKeysByCacheKey[cacheKey, default: []].append(key)
                }
            }

            guard !inputKeysByCacheKey.isEmpty else {
                onResult(cachedResults)
                return ActionDisposable {
                }
            }

            let subscriberId = self.nextSubscriberId
            self.nextSubscriberId &+= 1
            let batch = TranslationBatch(
                subscriberId: subscriberId,
                inputKeysByCacheKey: inputKeysByCacheKey,
                cachedResults: cachedResults,
                completion: onResult
            )
            BonemanTranslationDiagnostics.shared.recordBatch(sourceLanguage: requestedSourceLanguage, targetLanguage: targetLanguage, pendingCount: inputKeysByCacheKey.count)
            for cacheKey in inputKeysByCacheKey.keys {
                // The queue must retain the batch until every serial work item resolves. A weak
                // batch here deallocates the coordinator as soon as translate() returns, so Apple
                // produces results that never reach TelegramCore for persistence.
                let accepted = self.workQueue.enqueue(key: cacheKey, subscriberId: subscriberId, completion: { [weak self, batch] result in
                    switch result {
                    case let .translated(text):
                        self?.cache.insert(text, for: cacheKey)
                    case .skipped:
                        self?.cache.insert("", for: cacheKey)
                    case .failed:
                        break
                    }
                    let opaqueIds: [String]
                    if case .failed = result {
                        opaqueIds = (inputKeysByCacheKey[cacheKey] ?? []).map(BonemanTranslationDiagnostics.opaqueMessageId)
                    } else {
                        opaqueIds = []
                    }
                    BonemanTranslationDiagnostics.shared.recordResult(result, failedOpaqueIds: opaqueIds, remainingCount: max(0, self?.workQueue.count ?? 0))
                    batch.resolve(key: cacheKey, result: result)
                })
                if !accepted {
                    let opaqueIds = (inputKeysByCacheKey[cacheKey] ?? []).map(BonemanTranslationDiagnostics.opaqueMessageId)
                    BonemanTranslationDiagnostics.shared.recordResult(.failed, failedOpaqueIds: opaqueIds, remainingCount: self.workQueue.count)
                    batch.resolve(key: cacheKey, result: .failed)
                }
            }
            if self.workQueue.beginNextIfIdle() != nil {
                self.taskTrigger.generation &+= 1
            }

            return ActionDisposable { [weak self, batch] in
                Queue.mainQueue().async {
                    let wasPending = batch.cancel()
                    self?.workQueue.cancel(subscriberId: subscriberId)
                    if wasPending {
                        BonemanTranslationDiagnostics.shared.recordCancelled()
                    }
                }
            }
        }
    }
    
    private let impl: QueueLocalObject<Impl>
    
    public init(view: UIView, parentViewController: UIViewController? = nil) {
        self.impl = QueueLocalObject(queue: .mainQueue(), generate: {
            return Impl(view: view, parentViewController: parentViewController)
        })
    }
    
    public func translate(texts: [AnyHashable: String], fromLang: String?, toLang: String) -> Signal<[AnyHashable: String]?, NoError> {
        return self.impl.signalWith { impl, subscriber in
            return impl.translate(texts: texts, fromLang: fromLang, toLang: toLang, onResult: { result in
                subscriber.putNext(result)
                subscriber.putCompletion()
            })
        }
    }

    public func clearCache() {
        self.impl.with { impl in
            impl.clearCache()
        }
    }
}

public func translateTextWithApple(text: String, fromLanguage: String?, toLanguage: String) -> Signal<String?, NoError> {
    guard #available(iOS 18.0, *), let service = engineExperimentalInternalTranslationService else {
        return .single(nil)
    }
    return service.translate(texts: [AnyHashable(0): text], fromLang: fromLanguage, toLang: toLanguage)
    |> map { result in
        guard let translatedText = result?[AnyHashable(0)], !translatedText.isEmpty else {
            return nil
        }
        return translatedText
    }
}

func alternativeTranslateText(text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TelegramCore.TranslationError> {
    return Signal { subscriber in
        var task: URLSessionTask?
        Queue.concurrentDefaultQueue().async {
            let effectiveFromLang: String
            if let fromLang {
                effectiveFromLang = fromLang
            } else {
                languageRecognizer.processString(text)
                let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 3)
                languageRecognizer.reset()
                
                let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
                if let language = filteredLanguages.first {
                    let languageCode = normalizeTranslationLanguage(language.key.rawValue)
                    effectiveFromLang = languageCode
                } else {
                    effectiveFromLang = "en"
                }
            }
            
            var uri = "https://translate.goo"
            uri += "gleapis.com/transl"
            uri += "ate_a"
            uri += "/singl"
            uri += "e?client=gtx&sl=\(effectiveFromLang.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            uri += "&tl=\(toLang.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            uri += "&dt=t&ie=UTF-8&oe=UTF-8&otf=1&ssel=0&tsel=0&kc=7&dt=at&dt=bd&dt=ex&dt=ld&dt=md&dt=qca&dt=rw&dt=rm&dt=ss&q="
            uri += text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            
            guard let url = URL(string: uri) else {
                subscriber.putError(.generic)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(getRandomUserAgent(), forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Translation failed: \(error.localizedDescription)")
                    subscriber.putError(.generic)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    subscriber.putError(.generic)
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    print("Translation failed with status code: \(httpResponse.statusCode)")
                    let isRateLimit = httpResponse.statusCode == 429
                    subscriber.putError(isRateLimit ? .limitExceeded : .generic)
                    return
                }
                
                guard let data = data else {
                    subscriber.putError(.generic)
                    return
                }
                
                do {
                    guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                        subscriber.putError(.generic)
                        return
                    }
                    
                    guard let translationArray = jsonArray.first as? [Any] else {
                        subscriber.putError(.generic)
                        return
                    }
                    
                    var result = ""
                    for element in translationArray {
                        if let translationBlock = element as? [Any],
                           translationBlock.count > 0,
                           let blockText = translationBlock[0] as? String,
                           blockText != "null" && !blockText.isEmpty {
                            result += blockText
                        }
                    }
                    
                    if text.hasPrefix("\n") {
                        result = "\n" + result
                    }
                    
                    subscriber.putNext((result, []))
                    subscriber.putCompletion()
                } catch {
                    print("JSON parsing error: \(error)")
                    subscriber.putError(.generic)
                }
            }
            task?.resume()
        }
        return ActionDisposable {
            task?.cancel()
        }
    }
}

func getRandomUserAgent() -> String {
    let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"
    ]
    return userAgents.randomElement() ?? userAgents[0]
}
