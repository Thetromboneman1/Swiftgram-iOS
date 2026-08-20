import Postbox

public class TranslationMessageAttribute: MessageAttribute, Equatable {
    public enum Provenance: Int32 {
        /// Telegram, Swiftgram, and legacy attributes that predate explicit provenance.
        case upstream = 0
        /// Content produced locally by Boneman's Apple TranslationSession integration.
        case bonemanApple = 1
    }

    public struct Additional : PostboxCoding, Equatable {
        public let text: String
        public let entities: [MessageTextEntity]
        
        public init(text: String, entities: [MessageTextEntity]) {
            self.text = text
            self.entities = entities
        }
        
        public init(decoder: PostboxDecoder) {
            self.text = decoder.decodeStringForKey("text", orElse: "")
            self.entities = decoder.decodeObjectArrayWithDecoderForKey("entities")
        }
        
        public func encode(_ encoder: PostboxEncoder) {
            encoder.encodeString(self.text, forKey: "text")
            encoder.encodeObjectArray(self.entities, forKey: "entities")
        } 
    }
    
    public let text: String
    public let entities: [MessageTextEntity]
    public let toLang: String
    public let provenance: Provenance

    public let additional: [Additional]
    public let pollSolution: Additional?
    /// The translated rich content, for messages carrying a `RichTextMessageAttribute` (translated via
    /// `messages.translateRichMessage`). `text`/`entities` stay empty for those.
    public let instantPage: InstantPage?

    /// Empty plain-text attributes can be left behind by an interrupted or failed local
    /// translation. They must not suppress a later retry. Rich translations remain renderable
    /// when their text is empty if they carry an instant page, additional fields, or poll data.
    public var hasRenderableContent: Bool {
        return !self.text.isEmpty || self.instantPage != nil || !self.additional.isEmpty || self.pollSolution != nil
    }

    public var associatedPeerIds: [PeerId] {
        return []
    }

    public init(
        text: String,
        entities: [MessageTextEntity],
        additional:[Additional] = [],
        pollSolution: Additional? = nil,
        toLang: String,
        instantPage: InstantPage? = nil,
        provenance: Provenance = .upstream
    ) {
        self.text = text
        self.entities = entities
        self.toLang = toLang
        self.provenance = provenance
        self.additional = additional
        self.pollSolution = pollSolution
        self.instantPage = instantPage
    }

    required public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("text", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("entities")
        self.additional = decoder.decodeObjectArrayWithDecoderForKey("additional")
        self.toLang = decoder.decodeStringForKey("toLang", orElse: "")
        self.provenance = Provenance(rawValue: decoder.decodeInt32ForKey("bonemanProvenance", orElse: 0)) ?? .upstream
        self.pollSolution = decoder.decodeObjectForKey("pollSolution") as? Additional
        self.instantPage = decoder.decodeObjectForKey("ipage", decoder: { InstantPage(decoder: $0) }) as? InstantPage
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "text")
        encoder.encodeObjectArray(self.entities, forKey: "entities")
        encoder.encodeString(self.toLang, forKey: "toLang")
        encoder.encodeInt32(self.provenance.rawValue, forKey: "bonemanProvenance")
        encoder.encodeObjectArray(self.additional, forKey: "additional")

        if let pollSolution {
            encoder.encodeObject(pollSolution, forKey: "pollSolution")
        } else {
            encoder.encodeNil(forKey: "pollSolution")
        }
        if let instantPage {
            encoder.encodeObject(instantPage, forKey: "ipage")
        } else {
            encoder.encodeNil(forKey: "ipage")
        }
    }

    public static func ==(lhs: TranslationMessageAttribute, rhs: TranslationMessageAttribute) -> Bool {
        if lhs.text != rhs.text {
            return false
        }
        if lhs.entities != rhs.entities {
            return false
        }
        if lhs.toLang != rhs.toLang {
            return false
        }
        if lhs.provenance != rhs.provenance {
            return false
        }
        if lhs.additional != rhs.additional {
            return false
        }
        if lhs.pollSolution != rhs.pollSolution {
            return false
        }
        if lhs.instantPage != rhs.instantPage {
            return false
        }
        return true
    }
}







// MARK: Swiftgram
public class QuickTranslationMessageAttribute: MessageAttribute, Equatable {
    public let originalText: String
    public let originalEntities: [MessageTextEntity]

    public var associatedPeerIds: [PeerId] {
        return []
    }
    
    public init(
        text: String,
        entities: [MessageTextEntity]
    ) {
        self.originalText = text
        self.originalEntities = entities
    }
    
    required public init(decoder: PostboxDecoder) {
        self.originalText = decoder.decodeStringForKey("originalText", orElse: "")
        self.originalEntities = decoder.decodeObjectArrayWithDecoderForKey("originalEntities")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.originalText, forKey: "originalText")
        encoder.encodeObjectArray(self.originalEntities, forKey: "originalEntities")
    }
    
    public static func ==(lhs: QuickTranslationMessageAttribute, rhs: QuickTranslationMessageAttribute) -> Bool {
        if lhs.originalText != rhs.originalText {
            return false
        }
        if lhs.originalEntities != rhs.originalEntities {
            return false
        }
        return true
    }
}
