import Foundation

/// `{"record": ..., "details": ...}`
struct RecordEnvelope<Record: Decodable, Details: Decodable>: Decodable {
    var record: Record
    var details: Details?
}

/// `{"records": [...], "count": n}`
struct RecordsEnvelope<Record: Decodable>: Decodable {
    var records: [Record]
    var count: Int?
}

/// Placeholder for envelopes whose details are not surfaced.
struct NoDetails: Decodable {}

/// `record` of a create response.
struct CreateRecord: Decodable {
    var receipt: Receipt
    var secret: Secret
    var shareDomain: String?

    enum CodingKeys: String, CodingKey {
        case receipt
        case secret
        case shareDomain = "share_domain"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        receipt = try c.decode(Receipt.self, forKey: .receipt)
        secret = try c.decode(Secret.self, forKey: .secret)
        shareDomain = try c.lenientString(.shareDomain).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// `details` of a status response.
struct StatusDetails: Decodable {
    var currentExpiration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case currentExpiration = "current_expiration"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentExpiration = try c.lenientDouble(.currentExpiration)
    }
}

/// `record` of a status response: either `{"state": "unknown"}` or a secret.
enum StatusRecord: Decodable {
    case unknown
    case secret(Secret)

    enum CodingKeys: String, CodingKey {
        case state
        case identifier
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let state = try c.decodeIfPresent(String.self, forKey: .state)
        if state == SecretState.unknown.rawValue || !c.contains(.identifier) {
            self = .unknown
        } else {
            self = try .secret(Secret(from: decoder))
        }
    }
}

/// Error body shape. The API has two generations of it; accept both.
struct APIErrorBody: Decodable {
    var error: String?
    var errorType: String?
    var message: String?
    var field: String?
    var requestID: String?
    var errorID: String?
    var code: String?
    var retryAfter: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case error
        case errorType = "error_type"
        case message
        case field
        case requestID = "request_id"
        case errorID = "error_id"
        case code
        case retryAfter = "retry_after"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.lenientString(.error)
        errorType = try c.lenientString(.errorType)
        message = try c.lenientString(.message)
        field = try c.lenientString(.field)
        requestID = try c.lenientString(.requestID)
        errorID = try c.lenientString(.errorID)
        code = try c.lenientString(.code)
        retryAfter = try c.lenientDouble(.retryAfter)
    }
}
