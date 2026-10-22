public import Foundation

/// The result of concealing a secret: the recipient's secret, the creator's
/// receipt, and the links to hand out.
public struct ConcealedSecret: Sendable, Hashable {
    /// The secret as the recipient will see it (metadata only).
    public var secret: Secret

    /// The creator's receipt.
    public var receipt: Receipt

    /// Custom share domain the API applied, if any.
    public var shareDomain: String?

    /// Link to give to the recipient. Opening it does not consume the
    /// secret; the recipient confirms on that page.
    public var shareURL: URL

    /// Link to the receipt in the web UI.
    public var receiptURL: URL

    /// Link that burns the secret in the web UI.
    public var burnURL: URL

    public init(
        secret: Secret,
        receipt: Receipt,
        shareDomain: String?,
        shareURL: URL,
        receiptURL: URL,
        burnURL: URL
    ) {
        self.secret = secret
        self.receipt = receipt
        self.shareDomain = shareDomain
        self.shareURL = shareURL
        self.receiptURL = receiptURL
        self.burnURL = burnURL
    }
}

/// The result of generating a secret. Identical to ``ConcealedSecret`` plus
/// the generated ``value``.
public struct GeneratedSecret: Sendable, Hashable {
    public var secret: Secret
    public var receipt: Receipt
    public var shareDomain: String?
    public var shareURL: URL
    public var receiptURL: URL
    public var burnURL: URL

    /// The generated value.
    ///
    /// `nil` when ``GenerateOptions/claimValue`` was `false`, when the
    /// service declined to disclose it (for example, the disclosure window
    /// had passed by the time the receipt was fetched), or when the fetch
    /// failed; see ``claimFailure``.
    public var value: String?

    /// Why the value could not be claimed, when the receipt fetch after
    /// creation failed. The secret itself was created and is live.
    public var claimFailure: ClaimFailure?

    public init(
        secret: Secret,
        receipt: Receipt,
        shareDomain: String?,
        shareURL: URL,
        receiptURL: URL,
        burnURL: URL,
        value: String?,
        claimFailure: ClaimFailure? = nil
    ) {
        self.secret = secret
        self.receipt = receipt
        self.shareDomain = shareDomain
        self.shareURL = shareURL
        self.receiptURL = receiptURL
        self.burnURL = burnURL
        self.value = value
        self.claimFailure = claimFailure
    }
}

extension GeneratedSecret: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never includes the value.
    public var description: String {
        "GeneratedSecret(\(secret.shortID), value: \(value == nil ? "nil" : "<redacted>"), shareURL: \(shareURL))"
    }

    public var debugDescription: String { description }
}

/// The result of a non-destructive status check.
public enum SecretStatus: Sendable, Hashable {
    /// The service has no record of the identifier: it expired, was consumed
    /// and purged, or never existed.
    case unknown

    /// The secret exists. `expiresIn` is the remaining lifetime in seconds,
    /// when the service reports it.
    case known(Secret, expiresIn: TimeInterval?)

    /// The secret, when known.
    public var secret: Secret? {
        if case let .known(secret, _) = self { return secret }
        return nil
    }

    /// Whether the value can still be revealed.
    public var isAvailable: Bool {
        secret?.isAvailable ?? false
    }
}

/// A revealed secret. Creating this value consumed the secret.
public struct RevealedSecret: Sendable, Hashable {
    /// The plaintext.
    public var value: String

    /// Metadata, with ``Secret/value`` also set.
    public var secret: Secret

    public init(value: String, secret: Secret) {
        self.value = value
        self.secret = secret
    }
}

extension RevealedSecret: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never includes the value.
    public var description: String {
        "RevealedSecret(\(secret.shortID), value: <redacted>)"
    }

    public var debugDescription: String { description }
}

/// Health of the service.
public struct SystemStatus: Sendable, Hashable, Decodable {
    /// Status string, `"nominal"` when all is well.
    public var status: String

    /// Locale the service responded in.
    public var locale: String?

    /// Whether the service reports itself healthy.
    public var isNominal: Bool { status == "nominal" }
}

/// Version of the service.
public struct SystemVersion: Sendable, Hashable {
    /// Version components as reported, joined with `.`.
    public var version: String

    public init(version: String) {
        self.version = version
    }
}

extension SystemVersion: Decodable {
    enum CodingKeys: String, CodingKey {
        case version
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? c.decode(String.self, forKey: .version) {
            version = string
            return
        }
        var parts = try c.nestedUnkeyedContainer(forKey: .version)
        var components: [String] = []
        while !parts.isAtEnd {
            if let int = try? parts.decode(Int.self) {
                components.append(String(int))
            } else if let double = try? parts.decode(Double.self) {
                components.append(String(double))
            } else {
                try components.append(parts.decode(String.self))
            }
        }
        version = components.joined(separator: ".")
    }
}

/// Locales the web UI and emails are available in.
public struct SupportedLocales: Sendable, Hashable, Decodable {
    public var locales: [String]
    public var defaultLocale: String
    public var locale: String?

    enum CodingKeys: String, CodingKey {
        case locales
        case defaultLocale = "default_locale"
        case locale
    }
}
