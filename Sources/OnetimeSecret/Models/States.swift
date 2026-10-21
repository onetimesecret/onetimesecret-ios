/// Lifecycle state of a secret.
///
/// Modelled as a struct rather than an enum so that states added by the API
/// decode instead of failing; compare against the static members.
public struct SecretState: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Created and not yet looked at.
    public static let new = SecretState(rawValue: "new")
    /// The confirmation page was loaded but the value was not revealed.
    public static let previewed = SecretState(rawValue: "previewed")
    /// The value was revealed. The secret is gone.
    public static let revealed = SecretState(rawValue: "revealed")
    /// The creator burned it before it was revealed. The secret is gone.
    public static let burned = SecretState(rawValue: "burned")
    /// The service has no record of the secret (expired, consumed and purged,
    /// or never existed). Only returned by status checks.
    public static let unknown = SecretState(rawValue: "unknown")

    public var description: String { rawValue }
}

/// Lifecycle state of a receipt, which outlives the secret it describes.
public struct ReceiptState: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let new = ReceiptState(rawValue: "new")
    public static let shared = ReceiptState(rawValue: "shared")
    public static let previewed = ReceiptState(rawValue: "previewed")
    public static let revealed = ReceiptState(rawValue: "revealed")
    public static let burned = ReceiptState(rawValue: "burned")
    public static let expired = ReceiptState(rawValue: "expired")
    /// The secret disappeared without the receipt recording why.
    public static let orphaned = ReceiptState(rawValue: "orphaned")

    public var description: String { rawValue }
}

/// How a secret was created.
public struct SecretKind: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The caller supplied the value.
    public static let conceal = SecretKind(rawValue: "conceal")
    /// The service generated a random value.
    public static let generate = SecretKind(rawValue: "generate")

    public var description: String { rawValue }
}

/// How a receipt was created.
public struct ReceiptSource: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Created by the account through the API or web UI.
    public static let standard = ReceiptSource(rawValue: "standard")
    /// Submitted to the account through an incoming-secrets form.
    public static let incoming = ReceiptSource(rawValue: "incoming")

    public var description: String { rawValue }
}

/// How the secret value should be rendered to the recipient.
public struct DisplayType: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let text = DisplayType(rawValue: "text")
    public static let markdown = DisplayType(rawValue: "markdown")

    public var description: String { rawValue }
}
