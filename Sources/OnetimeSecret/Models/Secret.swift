public import Foundation

/// A secret as the recipient sees it.
///
/// The ``value`` is only present on the result of a reveal. Every other
/// operation returns metadata only.
public struct Secret: Sendable, Hashable, Identifiable {
    /// Full identifier; the last path component of the share link.
    public var identifier: String

    /// Short, human-friendly prefix of the identifier.
    public var shortID: String

    /// Lifecycle state.
    public var state: SecretState

    /// Whether a passphrase is required to reveal the value.
    public var hasPassphrase: Bool

    /// Whether the recipient must confirm before the value is shown.
    public var requiresVerification: Bool

    /// How the value should be rendered.
    public var displayType: DisplayType

    /// When the secret was created.
    public var createdAt: Date?

    /// When the secret was last modified.
    public var updatedAt: Date?

    /// Time to live that was requested at creation, in seconds.
    public var lifespan: TimeInterval?

    /// Remaining time to live when the record was read, in seconds, when
    /// the API reports it.
    public var timeToLive: TimeInterval?

    public var isPreviewed: Bool
    public var isRevealed: Bool
    public var isViewed: Bool
    public var isReceived: Bool

    /// The plaintext. Only set by ``OnetimeSecretClient/Secrets/reveal(_:passphrase:)``.
    public var value: String?

    public var id: String { identifier }

    /// Whether the value can still be revealed.
    public var isAvailable: Bool {
        state == .new || state == .previewed
    }

    public init(
        identifier: String,
        shortID: String,
        state: SecretState,
        hasPassphrase: Bool = false,
        requiresVerification: Bool = false,
        displayType: DisplayType = .text,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        lifespan: TimeInterval? = nil,
        timeToLive: TimeInterval? = nil,
        isPreviewed: Bool = false,
        isRevealed: Bool = false,
        isViewed: Bool = false,
        isReceived: Bool = false,
        value: String? = nil
    ) {
        self.identifier = identifier
        self.shortID = shortID
        self.state = state
        self.hasPassphrase = hasPassphrase
        self.requiresVerification = requiresVerification
        self.displayType = displayType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lifespan = lifespan
        self.timeToLive = timeToLive
        self.isPreviewed = isPreviewed
        self.isRevealed = isRevealed
        self.isViewed = isViewed
        self.isReceived = isReceived
        self.value = value
    }
}

extension Secret: Decodable {
    enum CodingKeys: String, CodingKey {
        case identifier
        case shortid
        case state
        case hasPassphrase = "has_passphrase"
        case verification
        case displayType = "display_type"
        case created
        case updated
        case lifespan
        case secretTTL = "secret_ttl"
        case isPreviewed = "is_previewed"
        case isRevealed = "is_revealed"
        case isViewed = "is_viewed"
        case isReceived = "is_received"
        case secretValue = "secret_value"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        shortID = try c.lenientString(.shortid) ?? String(identifier.prefix(8))
        state = try c.decode(SecretState.self, forKey: .state)
        hasPassphrase = try c.lenientBool(.hasPassphrase) ?? false
        requiresVerification = try c.lenientBool(.verification) ?? false
        displayType = try c.decodeIfPresent(DisplayType.self, forKey: .displayType) ?? .text
        createdAt = try c.timestamp(.created)
        updatedAt = try c.timestamp(.updated)
        lifespan = try c.lenientDouble(.lifespan)
        timeToLive = try c.lenientDouble(.secretTTL)
        isPreviewed = try c.lenientBool(.isPreviewed) ?? false
        isRevealed = try c.lenientBool(.isRevealed) ?? false
        isViewed = try c.lenientBool(.isViewed) ?? false
        isReceived = try c.lenientBool(.isReceived) ?? false
        value = try c.decodeIfPresent(String.self, forKey: .secretValue)
    }
}

extension Secret: CustomStringConvertible {
    /// Never includes the value.
    public var description: String {
        "Secret(\(shortID), state: \(state), hasPassphrase: \(hasPassphrase))"
    }
}
