public import Foundation

/// Options shared by conceal and generate.
public protocol SecretCreationOptions: Sendable {
    /// Lifetime in seconds. The service rounds to the plan's allowed values
    /// and applies its default when `nil`.
    var timeToLive: TimeInterval? { get set }

    /// Passphrase the recipient must enter. Hashed by the service; the SDK
    /// never stores it.
    var passphrase: String? { get set }

    /// Email address to send the link to. Requires an account.
    var recipient: String? { get set }

    /// Domain for the share link; overrides ``Configuration/shareDomain``.
    var shareDomain: String? { get set }
}

/// Options for ``OnetimeSecretClient/Secrets/conceal(_:_:)``.
public struct ConcealOptions: SecretCreationOptions, Hashable {
    public var timeToLive: TimeInterval?
    public var passphrase: String?
    public var recipient: String?
    public var shareDomain: String?

    /// How the recipient's UI renders the value. Defaults to plain text.
    public var displayType: DisplayType?

    public init(
        timeToLive: TimeInterval? = nil,
        passphrase: String? = nil,
        recipient: String? = nil,
        shareDomain: String? = nil,
        displayType: DisplayType? = nil
    ) {
        self.timeToLive = timeToLive
        self.passphrase = passphrase
        self.recipient = recipient
        self.shareDomain = shareDomain
        self.displayType = displayType
    }
}

extension ConcealOptions: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never includes the passphrase.
    public var description: String {
        let fields: [(String, String?)] = [
            ("timeToLive", timeToLive.map { String($0) }),
            ("passphrase", passphrase == nil ? nil : "<redacted>"),
            ("recipient", recipient),
            ("shareDomain", shareDomain),
            ("displayType", displayType?.rawValue),
        ]
        return "ConcealOptions(" + describe(fields) + ")"
    }

    public var debugDescription: String { description }
}

/// Which characters a generated secret may contain.
public struct CharacterSets: Sendable, Hashable, Encodable {
    public var uppercase: Bool?
    public var lowercase: Bool?
    public var numbers: Bool?
    public var symbols: Bool?

    /// Drop characters that are easy to confuse, such as `l`, `1`, `O`, `0`.
    public var excludeAmbiguous: Bool?

    public init(
        uppercase: Bool? = nil,
        lowercase: Bool? = nil,
        numbers: Bool? = nil,
        symbols: Bool? = nil,
        excludeAmbiguous: Bool? = nil
    ) {
        self.uppercase = uppercase
        self.lowercase = lowercase
        self.numbers = numbers
        self.symbols = symbols
        self.excludeAmbiguous = excludeAmbiguous
    }

    enum CodingKeys: String, CodingKey {
        case uppercase
        case lowercase
        case numbers
        case symbols
        case excludeAmbiguous = "exclude_ambiguous"
    }
}

/// Options for ``OnetimeSecretClient/Secrets/generate(_:)``.
public struct GenerateOptions: SecretCreationOptions, Hashable {
    /// Shortest value the service will generate.
    public static let minimumLength = 4
    /// Longest value the service will generate.
    public static let maximumLength = 128

    public var timeToLive: TimeInterval?
    public var passphrase: String?
    public var recipient: String?
    public var shareDomain: String?

    /// Length of the generated value, between ``minimumLength`` and
    /// ``maximumLength``. The service picks a default when `nil`.
    public var length: Int?

    /// Character classes to draw from.
    public var characterSets: CharacterSets?

    /// Fetch the generated value from the receipt right after creation.
    ///
    /// The API discloses a generated value to its creator once, on the first
    /// receipt fetch within a short window. When `true` (the default) the SDK
    /// performs that fetch and returns the value in
    /// ``GeneratedSecret/value``. Set to `false` if your app will fetch the
    /// receipt itself and read ``Receipt/generatedValue``.
    public var claimValue: Bool

    public init(
        length: Int? = nil,
        characterSets: CharacterSets? = nil,
        timeToLive: TimeInterval? = nil,
        passphrase: String? = nil,
        recipient: String? = nil,
        shareDomain: String? = nil,
        claimValue: Bool = true
    ) {
        self.length = length
        self.characterSets = characterSets
        self.timeToLive = timeToLive
        self.passphrase = passphrase
        self.recipient = recipient
        self.shareDomain = shareDomain
        self.claimValue = claimValue
    }
}

extension GenerateOptions: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never includes the passphrase.
    public var description: String {
        let fields: [(String, String?)] = [
            ("length", length.map { String($0) }),
            ("timeToLive", timeToLive.map { String($0) }),
            ("passphrase", passphrase == nil ? nil : "<redacted>"),
            ("recipient", recipient),
            ("shareDomain", shareDomain),
            ("claimValue", String(claimValue)),
        ]
        return "GenerateOptions(" + describe(fields) + ")"
    }

    public var debugDescription: String { description }
}

/// `name: value` pairs, `nil` spelled out, joined for a description.
func describe(_ fields: [(String, String?)]) -> String {
    fields.map { "\($0.0): \($0.1 ?? "nil")" }.joined(separator: ", ")
}

/// Wire form of the `secret` object in create requests.
struct CreateSecretPayload: Encodable {
    var kind: String
    var shareDomain: String
    var secret: String?
    var ttl: Int?
    var passphrase: String?
    var recipient: String?
    var displayType: String?
    var length: Int?
    var characterSets: CharacterSets?

    enum CodingKeys: String, CodingKey {
        case kind
        case shareDomain = "share_domain"
        case secret
        case ttl
        case passphrase
        case recipient
        case displayType = "display_type"
        case length
        case characterSets = "character_sets"
    }
}

/// Envelope for create requests: `{"secret": {...}}`.
struct CreateSecretRequest: Encodable {
    var secret: CreateSecretPayload
}

/// Body for reveal: `continue` confirms consumption. The schema types it as
/// a string.
struct RevealRequest: Encodable {
    var passphrase: String?
    var `continue` = "true"
}

/// Body for burn: `continue` confirms destruction.
struct BurnRequest: Encodable {
    var passphrase: String?
    var `continue` = "true"
}

/// Body for receipt updates.
struct UpdateReceiptRequest: Encodable {
    var memo: String
}

/// Body for bulk status checks. The server parses `identifiers` as a
/// comma-separated string (the published schema says array; both are
/// accepted, the string is what the server code reads).
struct ListStatusRequest: Encodable {
    var identifiers: String

    init(identifiers: [String]) {
        self.identifiers = identifiers.joined(separator: ",")
    }
}
