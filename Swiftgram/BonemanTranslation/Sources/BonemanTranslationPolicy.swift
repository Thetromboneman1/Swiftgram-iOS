import Foundation

public enum BonemanTranslationPolicy {
    public static let defaultBackend = "default"
    public static let systemBackend = "system"

    /// Makes Apple translation the effective default without changing an explicit backend choice.
    public static func effectiveBackend(rawValue: String, appleSystemAvailable: Bool) -> String {
        if rawValue == self.defaultBackend && appleSystemAvailable {
            return self.systemBackend
        }
        return rawValue
    }

    /// Returns false for content that Apple Translation cannot usefully translate.
    public static func shouldTranslate(text: String, fromLanguage: String?, toLanguage: String) -> Bool {
        guard !toLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }
        guard !self.isURLOnly(trimmedText) else {
            return false
        }
        guard self.containsLetterOrNumber(trimmedText) else {
            return false
        }
        if let fromLanguage, !fromLanguage.isEmpty, self.languagesAreEquivalent(fromLanguage, toLanguage) {
            return false
        }
        return true
    }

    public static func languagesAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = self.languageComponents(lhs)
        let rhsParts = self.languageComponents(rhs)
        guard let lhsLanguage = lhsParts.first, let rhsLanguage = rhsParts.first, lhsLanguage == rhsLanguage else {
            return false
        }

        let lhsScript = self.scriptComponent(lhsParts)
        let rhsScript = self.scriptComponent(rhsParts)
        if let lhsScript, let rhsScript, lhsScript != rhsScript {
            return false
        }

        // Apple chooses regional behavior within a language model, so en-US/en-GB and similar
        // region-only variants are the same translation language. Explicitly different scripts
        // remain distinct (for example zh-Hans/zh-Hant or sr-Latn/sr-Cyrl).
        return true
    }

    /// Canonicalizes the common BCP-47 casing and separator forms without discarding meaningful
    /// script or region subtags. Apple Translation distinguishes identifiers such as `zh-Hans`
    /// and `zh-Hant`, so reducing every identifier to its primary language is not safe.
    public static func canonicalLanguageIdentifier(_ identifier: String) -> String {
        var components = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else {
            return identifier
        }

        components[0] = components[0].lowercased()
        if components[0] == "nb" {
            components[0] = "no"
        }
        for index in components.indices.dropFirst() {
            let component = components[index]
            if component.count == 4, component.allSatisfy(\.isLetter) {
                components[index] = component.prefix(1).uppercased() + component.dropFirst().lowercased()
            } else if (component.count == 2 && component.allSatisfy(\.isLetter)) || (component.count == 3 && component.allSatisfy(\.isNumber)) {
                components[index] = component.uppercased()
            } else {
                components[index] = component.lowercased()
            }
        }
        return components.joined(separator: "-")
    }

    private static func languageComponents(_ identifier: String) -> [String] {
        return identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .split(separator: "-")
            .map(String.init)
    }

    private static func scriptComponent(_ components: [String]) -> String? {
        return components.dropFirst().first(where: { component in
            component.count == 4 && component.allSatisfy(\.isLetter)
        })
    }

    private static func containsLetterOrNumber(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                return true
            }
        }
        return false
    }

    private static func isURLOnly(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }) else {
            return false
        }

        let lowercasedText = text.lowercased()
        if lowercasedText.hasPrefix("www.") {
            return true
        }
        if lowercasedText.contains("@"), !lowercasedText.hasPrefix("@"), !lowercasedText.hasSuffix("@") {
            return true
        }
        guard let url = URL(string: text), url.scheme != nil else {
            let hostCandidate = lowercasedText.split(whereSeparator: { "/?#".contains($0) }).first.map(String.init) ?? lowercasedText
            let hostParts = hostCandidate.split(separator: ".")
            guard hostParts.count >= 2, let topLevelDomain = hostParts.last else {
                return false
            }
            return topLevelDomain.count >= 2 && topLevelDomain.allSatisfy { $0.isLetter }
        }
        return true
    }
}
