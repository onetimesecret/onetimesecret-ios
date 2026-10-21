public import Foundation

/// The creator's record of a secret: when it was shared, viewed, revealed or
/// burned, plus the links to manage it. A receipt never contains the secret
/// value, with one exception: see ``generatedValue``.
public struct Receipt: Sendable, Hashable, Identifiable {
    /// Full identifier; the last path component of the receipt link.
    public var identifier: String

    /// Short, human-friendly prefix of the identifier.
    public var shortID: String

    /// Lifecycle state.
    public var state: ReceiptState

    /// Identifier of the secret. Removed by the API once the secret is gone.
    public var secretIdentifier: String?

    /// Short identifier of the secret.
    public var secretShortID: String?

    /// State of the secret as last known to the receipt, when reported.
    public var secretState: SecretState?

    /// Identifier of the account that created the secret, if any.
    public var customerID: String?

    /// Identifier of the owning account, if any.
    public var ownerID: String?

    /// How the secret was created.
    public var kind: SecretKind?

    /// Where the receipt came from.
    public var source: ReceiptSource?

    /// Requested lifetime of the secret, in seconds.
    public var lifespan: TimeInterval?

    /// Remaining lifetime of the secret when read, in seconds.
    public var secretTimeToLive: TimeInterval?

    /// Remaining lifetime of the receipt itself, in seconds.
    public var receiptTimeToLive: TimeInterval?

    /// Custom domain the share link uses, if any.
    public var shareDomain: String?

    /// Email recipients the link was sent to.
    public var recipients: [String]

    /// Display name for the recipient, if set.
    public var recipientName: String?

    /// Free-text note set by the creator. See
    /// ``OnetimeSecretClient/Receipts/updateMemo(_:memo:)``.
    public var memo: String?

    /// Whether the secret needs a passphrase to reveal.
    public var hasPassphrase: Bool

    public var createdAt: Date?
    public var updatedAt: Date?
    public var sharedAt: Date?
    public var previewedAt: Date?
    public var viewedAt: Date?
    public var receivedAt: Date?
    public var revealedAt: Date?
    public var burnedAt: Date?

    /// When the secret expires on its own.
    public var expiresAt: Date?

    /// Human-readable description of the lifetime, for example `"5 minutes"`.
    public var naturalExpiration: String?

    public var isPreviewed: Bool
    public var isViewed: Bool
    public var isReceived: Bool
    public var isRevealed: Bool
    public var isBurned: Bool
    public var isExpired: Bool
    public var isOrphaned: Bool

    /// Whether the secret can no longer be revealed, for whatever reason.
    public var isDestroyed: Bool

    /// Link the recipient opens. `nil` once the secret is gone.
    public var shareURL: URL?

    /// Link to this receipt in the web UI.
    public var receiptURL: URL?

    /// Link that burns the secret in the web UI.
    public var burnURL: URL?

    // MARK: Telemetry, present when a single receipt is fetched

    /// How many times the recipient-side page has been loaded.
    public var viewCount: Int?

    public var firstAccessedAt: Date?
    public var lastAccessedAt: Date?

    /// The generated value, for a secret created with
    /// ``OnetimeSecretClient/Secrets/generate(options:)``.
    ///
    /// The API discloses it to the creator exactly once, on the first fetch of
    /// the receipt within a short window after creation. After that it is
    /// `nil` for good. ``OnetimeSecretClient/Secrets/generate(options:)`` claims
    /// that single disclosure for you unless told not to.
    public var generatedValue: String?

    public var id: String { identifier }

    /// Whether the secret can still be revealed, as far as the receipt knows.
    public var isSecretAvailable: Bool {
        !isDestroyed && !isBurned && !isRevealed && !isExpired && !isOrphaned
    }
}

extension Receipt: Decodable {
    enum CodingKeys: String, CodingKey {
        case identifier
        case key
        case shortid
        case state
        case secretIdentifier = "secret_identifier"
        case secretShortID = "secret_shortid"
        case secretState = "secret_state"
        case custid
        case ownerID = "owner_id"
        case kind
        case source
        case lifespan
        case secretTTL = "secret_ttl"
        case receiptTTL = "receipt_ttl"
        case shareDomain = "share_domain"
        case recipients
        case recipientName = "recipient_name"
        case memo
        case hasPassphrase = "has_passphrase"
        case created
        case updated
        case shared
        case previewed
        case viewed
        case received
        case revealed
        case burned
        case expiration
        case naturalExpiration = "natural_expiration"
        case isPreviewed = "is_previewed"
        case isViewed = "is_viewed"
        case isReceived = "is_received"
        case isRevealed = "is_revealed"
        case isBurned = "is_burned"
        case isExpired = "is_expired"
        case isOrphaned = "is_orphaned"
        case isDestroyed = "is_destroyed"
        case shareURL = "share_url"
        case receiptURL = "receipt_url"
        case burnURL = "burn_url"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The list endpoint's schema allows a null identifier; `key` has
        // always carried the same value.
        guard let id = try c.lenientString(.identifier) ?? c.lenientString(.key), !id.isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.identifier,
                .init(codingPath: decoder.codingPath, debugDescription: "Receipt has neither identifier nor key")
            )
        }
        identifier = id
        shortID = try c.lenientString(.shortid) ?? String(identifier.prefix(8))
        state = try c.decode(ReceiptState.self, forKey: .state)
        secretIdentifier = try c.lenientString(.secretIdentifier).flatMap { $0.isEmpty ? nil : $0 }
        secretShortID = try c.lenientString(.secretShortID).flatMap { $0.isEmpty ? nil : $0 }
        secretState = try c.decodeIfPresent(SecretState.self, forKey: .secretState)
        customerID = try c.lenientString(.custid).flatMap { $0.isEmpty ? nil : $0 }
        ownerID = try c.lenientString(.ownerID).flatMap { $0.isEmpty ? nil : $0 }
        kind = try c.lenientString(.kind).flatMap { $0.isEmpty ? nil : SecretKind(rawValue: $0) }
        source = try c.decodeIfPresent(ReceiptSource.self, forKey: .source)
        lifespan = try c.lenientDouble(.lifespan)
        secretTimeToLive = try c.lenientDouble(.secretTTL)
        receiptTimeToLive = try c.lenientDouble(.receiptTTL)
        shareDomain = try c.lenientString(.shareDomain).flatMap { $0.isEmpty ? nil : $0 }
        recipients = try c.stringList(.recipients)
        recipientName = try c.lenientString(.recipientName).flatMap { $0.isEmpty ? nil : $0 }
        memo = try c.lenientString(.memo).flatMap { $0.isEmpty ? nil : $0 }
        hasPassphrase = try c.lenientBool(.hasPassphrase) ?? false
        createdAt = try c.timestamp(.created)
        updatedAt = try c.timestamp(.updated)
        sharedAt = try c.timestamp(.shared)
        previewedAt = try c.timestamp(.previewed)
        viewedAt = try c.timestamp(.viewed)
        receivedAt = try c.timestamp(.received)
        revealedAt = try c.timestamp(.revealed)
        burnedAt = try c.timestamp(.burned)
        expiresAt = try c.timestamp(.expiration)
        naturalExpiration = try c.lenientString(.naturalExpiration)
        isPreviewed = try c.lenientBool(.isPreviewed) ?? false
        isViewed = try c.lenientBool(.isViewed) ?? false
        isReceived = try c.lenientBool(.isReceived) ?? false
        isRevealed = try c.lenientBool(.isRevealed) ?? false
        isBurned = try c.lenientBool(.isBurned) ?? false
        isExpired = try c.lenientBool(.isExpired) ?? false
        isOrphaned = try c.lenientBool(.isOrphaned) ?? false
        isDestroyed = try c.lenientBool(.isDestroyed) ?? false
        receiptURL = try c.lenientURL(.receiptURL)
        burnURL = try c.lenientURL(.burnURL)

        // The API sends a share URL with an empty path once the secret is
        // gone ("https://host/secret/"). Treat that as no link.
        if let url = try c.lenientURL(.shareURL), !url.lastPathComponent.isEmpty, url.lastPathComponent != "secret" {
            shareURL = url
        } else {
            shareURL = nil
        }

        viewCount = nil
        firstAccessedAt = nil
        lastAccessedAt = nil
        generatedValue = nil
    }
}

extension Receipt {
    /// Telemetry the API attaches when one receipt is fetched.
    struct Details: Decodable {
        var viewCount: Int?
        var firstAccessedAt: Date?
        var lastAccessedAt: Date?
        var secretTimeToLive: TimeInterval?
        var secretValue: String?

        enum CodingKeys: String, CodingKey {
            case viewCount = "view_count"
            case firstAccess = "first_access"
            case lastAccess = "last_access"
            case secretRealTTL = "secret_realttl"
            case secretValue = "secret_value"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            viewCount = try c.lenientInt(.viewCount)
            firstAccessedAt = try c.timestamp(.firstAccess)
            lastAccessedAt = try c.timestamp(.lastAccess)
            secretTimeToLive = try c.lenientDouble(.secretRealTTL)
            secretValue = try c.decodeIfPresent(String.self, forKey: .secretValue)
        }
    }

    mutating func apply(_ details: Details) {
        viewCount = details.viewCount
        firstAccessedAt = details.firstAccessedAt
        lastAccessedAt = details.lastAccessedAt
        if let ttl = details.secretTimeToLive {
            secretTimeToLive = ttl
        }
        generatedValue = details.secretValue
    }
}

extension Receipt: CustomStringConvertible {
    /// Never includes a generated value.
    public var description: String {
        "Receipt(\(shortID), state: \(state), secret: \(secretShortID ?? "-"))"
    }
}
