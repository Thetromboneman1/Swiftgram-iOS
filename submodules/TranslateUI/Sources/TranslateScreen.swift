import BonemanTranslation
import SGSimpleSettings
import Foundation
import UIKit
import Display
import TelegramCore
import SwiftSignalKit
import AccountContext
import SwiftUI
import Translation

public func presentTranslateScreen(
    context: AccountContext,
    text: String,
    entities: [MessageTextEntity] = [],
    canCopy: Bool,
    fromLanguage: String?,
    toLanguage: String? = nil,
    isExpanded: Bool = false,
    ignoredLanguages: [String]? = nil,
    replaceText: ((String, [MessageTextEntity]) -> Void)? = nil,
    translateChat: ((String, String) -> Void)? = nil,
    pushController: @escaping (ViewController) -> Void = { _ in },
    presentController: @escaping (ViewController) -> Void = { _ in },
    wasDismissed: (() -> Void)? = nil,
    display: (ViewController) -> Void
) {
    guard isAppleTranslationSelected(context: context) else {
        return
    }
    guard #available(iOS 18.0, *) else {
        presentAppleTranslationUnavailableAlert(context: context)
        return
    }
    guard let rootViewController = context.sharedContext.mainWindow?.viewController?.view.window?.rootViewController else {
        return
    }

    var presenter = rootViewController
    while let presentedViewController = presenter.presentedViewController, !presentedViewController.isBeingDismissed {
        presenter = presentedViewController
    }

    let preferredTargetLanguage = normalizeTranslationLanguage(SGSimpleSettings.shared.preferredTranslationLanguage)
    var defaultTargetLanguage = toLanguage
        ?? (preferredTargetLanguage.isEmpty ? nil : preferredTargetLanguage)
        ?? context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    if defaultTargetLanguage.hasSuffix("-raw") {
        defaultTargetLanguage.removeLast(4)
    }
    defaultTargetLanguage = normalizeTranslationLanguage(defaultTargetLanguage)
    if defaultTargetLanguage.isEmpty {
        defaultTargetLanguage = "en"
    }

    let coordinator = AppleTranslationSheetCoordinator(wasDismissed: wasDismissed)
    let view = AppleTranslationPreviewView(
        originalText: text,
        sourceLanguage: fromLanguage,
        initialTargetLanguage: defaultTargetLanguage,
        canCopy: canCopy,
        replaceText: replaceText,
        translateChat: translateChat,
        dismiss: {
            coordinator.dismiss()
        }
    )
    let hostingController = UIHostingController(rootView: view)
    coordinator.hostingController = hostingController
    hostingController.modalPresentationStyle = .pageSheet
    if let sheet = hostingController.sheetPresentationController {
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
    }
    presenter.present(hostingController, animated: true)
}

private func presentAppleTranslationUnavailableAlert(context: AccountContext) {
    guard let rootViewController = context.sharedContext.mainWindow?.viewController?.view.window?.rootViewController else {
        return
    }
    let alert = UIAlertController(
        title: "Apple Translation",
        message: "On-device translation requires iOS 18 or later.",
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    rootViewController.present(alert, animated: true)
}

private final class AppleTranslationSheetCoordinator {
    weak var hostingController: UIViewController?

    private var didDismiss = false
    private let wasDismissed: (() -> Void)?

    init(wasDismissed: (() -> Void)?) {
        self.wasDismissed = wasDismissed
    }

    func dismiss() {
        guard !self.didDismiss else {
            return
        }
        self.didDismiss = true
        self.hostingController?.dismiss(animated: true)
        self.wasDismissed?()
    }
}

@available(iOS 18.0, *)
private struct AppleTranslationPreviewView: View {
    private enum Phase: Equatable {
        case preparing
        case downloading
        case translating
        case translated
        case unavailable(String)
    }

    let originalText: String
    let sourceLanguage: String?
    let canCopy: Bool
    let replaceText: ((String, [MessageTextEntity]) -> Void)?
    let translateChat: ((String, String) -> Void)?
    let dismiss: () -> Void

    @State private var selectedTargetLanguage: String
    @State private var supportedLanguages: [String]
    @State private var configuration: TranslationSession.Configuration?
    @State private var translatedText: String?
    @State private var detectedSourceLanguage: String?
    @State private var phase: Phase = .preparing

    init(
        originalText: String,
        sourceLanguage: String?,
        initialTargetLanguage: String,
        canCopy: Bool,
        replaceText: ((String, [MessageTextEntity]) -> Void)?,
        translateChat: ((String, String) -> Void)?,
        dismiss: @escaping () -> Void
    ) {
        let normalizedSourceLanguage = sourceLanguage.flatMap { value -> String? in
            let normalizedValue = normalizeTranslationLanguage(value)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }
        let normalizedTargetLanguage = normalizeTranslationLanguage(initialTargetLanguage)

        self.originalText = originalText
        self.sourceLanguage = normalizedSourceLanguage
        self.canCopy = canCopy
        self.replaceText = replaceText
        self.translateChat = translateChat
        self.dismiss = dismiss
        self._selectedTargetLanguage = State(initialValue: normalizedTargetLanguage)
        self._supportedLanguages = State(initialValue: [normalizedTargetLanguage])
        self._configuration = State(initialValue: TranslationSession.Configuration(
            source: normalizedSourceLanguage.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: normalizedTargetLanguage)
        ))
    }

    private var sortedSupportedLanguages: [String] {
        return self.supportedLanguages.sorted { lhs, rhs in
            self.displayName(for: lhs).localizedCaseInsensitiveCompare(self.displayName(for: rhs)) == .orderedAscending
        }
    }

    private var statusText: String {
        switch self.phase {
        case .preparing:
            return "Checking language availability…"
        case .downloading:
            return "Waiting for Apple’s language download…"
        case .translating:
            return "Translating on this device…"
        case .translated:
            return "Translated on this device"
        case let .unavailable(message):
            return message
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Original") {
                    Text(self.originalText)
                        .textSelection(.enabled)
                }

                Section {
                    Picker("Translate to", selection: self.$selectedTargetLanguage) {
                        ForEach(self.sortedSupportedLanguages, id: \.self) { language in
                            Text(self.displayName(for: language)).tag(language)
                        }
                    }
                    .onChange(of: self.selectedTargetLanguage) { _, language in
                        self.beginTranslation(to: language)
                    }
                }

                Section("Translation") {
                    if let translatedText = self.translatedText {
                        Text(translatedText)
                            .textSelection(.enabled)
                    } else if case .unavailable = self.phase {
                        Text(self.statusText)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 12.0) {
                            ProgressView()
                            Text(self.statusText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if self.canCopy {
                        Button("Copy") {
                            guard let translatedText = self.translatedText else {
                                return
                            }
                            UIPasteboard.general.string = translatedText
                        }
                        .disabled(self.translatedText == nil)
                    }
                    if let replaceText = self.replaceText {
                        Button("Replace") {
                            guard let translatedText = self.translatedText else {
                                return
                            }
                            replaceText(translatedText, [])
                            self.dismiss()
                        }
                        .disabled(self.translatedText == nil)
                    }
                    if let translateChat = self.translateChat {
                        Button("Translate Chat") {
                            let sourceLanguage = self.detectedSourceLanguage ?? self.sourceLanguage ?? ""
                            translateChat(sourceLanguage, self.selectedTargetLanguage)
                            self.dismiss()
                        }
                        .disabled(self.translatedText == nil)
                    }
                    if case .unavailable = self.phase {
                        Button("Retry") {
                            self.retryTranslation()
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        self.dismiss()
                    }
                } footer: {
                    Text("Boneman translation uses Apple TranslationSession. Message text is processed on device and is not sent to a custom translation service.")
                }
            }
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
            .task {
                let languages = await LanguageAvailability().supportedLanguages
                guard !Task.isCancelled else {
                    return
                }
                var identifiers = Array(Set(languages.map { normalizeTranslationLanguage($0.minimalIdentifier) }))
                if !identifiers.contains(self.selectedTargetLanguage) {
                    identifiers.append(self.selectedTargetLanguage)
                }
                self.supportedLanguages = identifiers
            }
            .translationTask(self.configuration) { session in
                await self.performTranslation(session: session)
            }
            .onDisappear {
                self.dismiss()
            }
        }
    }

    private func displayName(for language: String) -> String {
        return Locale.current.localizedString(forIdentifier: language)
            ?? Locale.current.localizedString(forLanguageCode: language)
            ?? language
    }

    private func beginTranslation(to language: String) {
        let normalizedLanguage = normalizeTranslationLanguage(language)
        guard !normalizedLanguage.isEmpty else {
            return
        }
        SGSimpleSettings.shared.preferredTranslationLanguage = normalizedLanguage
        self.translatedText = nil
        self.detectedSourceLanguage = nil
        self.phase = .preparing
        self.configuration = TranslationSession.Configuration(
            source: self.sourceLanguage.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: normalizedLanguage)
        )
    }

    private func retryTranslation() {
        self.translatedText = nil
        self.detectedSourceLanguage = nil
        self.phase = .preparing
        if var configuration = self.configuration {
            configuration.invalidate()
            self.configuration = configuration
        } else {
            self.beginTranslation(to: self.selectedTargetLanguage)
        }
    }

    private func performTranslation(session: TranslationSession) async {
        let requestedTargetLanguage = self.selectedTargetLanguage
        let targetLanguage = Locale.Language(identifier: requestedTargetLanguage)

        do {
            let availability = LanguageAvailability()
            let status: LanguageAvailability.Status
            if let sourceLanguage = self.sourceLanguage {
                status = await availability.status(
                    from: Locale.Language(identifier: sourceLanguage),
                    to: targetLanguage
                )
            } else {
                status = try await availability.status(for: self.originalText, to: targetLanguage)
            }
            guard !Task.isCancelled, requestedTargetLanguage == self.selectedTargetLanguage else {
                return
            }

            switch status {
            case .unsupported:
                self.phase = .unavailable("This language pair isn’t supported by Apple Translation.")
                return
            case .supported:
                self.phase = .downloading
                // prepareTranslation requires a configured source. With automatic source
                // detection, translate() owns detection and any Apple language-resource prompt.
                if self.sourceLanguage != nil {
                    try await session.prepareTranslation()
                }
            case .installed:
                break
            @unknown default:
                self.phase = .unavailable("This language pair isn’t currently available from Apple Translation.")
                return
            }

            guard !Task.isCancelled, requestedTargetLanguage == self.selectedTargetLanguage else {
                return
            }
            self.phase = .translating
            let response = try await session.translate(self.originalText)
            guard !Task.isCancelled, requestedTargetLanguage == self.selectedTargetLanguage else {
                return
            }

            let targetText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetText.isEmpty, targetText != self.originalText else {
                self.phase = .unavailable("The text is already in the selected language, or there is nothing to translate.")
                return
            }
            self.detectedSourceLanguage = normalizeTranslationLanguage(response.sourceLanguage.minimalIdentifier)
            self.translatedText = response.targetText
            self.phase = .translated
        } catch {
            guard !Task.isCancelled, requestedTargetLanguage == self.selectedTargetLanguage else {
                return
            }
            self.phase = .unavailable("Apple Translation couldn’t complete this request. Install the required language resources and try again.")
        }
    }
}
