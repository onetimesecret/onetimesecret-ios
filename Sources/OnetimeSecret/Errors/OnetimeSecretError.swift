public import Foundation

/// What the API said when it rejected a request.
public struct APIErrorDetails: Sendable, Hashable {
    /// HTTP status code.
    public var statusCode: Int

    /// Human-readable message from the API, if any.
    public var message: String?

    /// Secondary message, when the API sent both an `error` and a more
    /// specific `message` (for example `[CREDENTIALS_INVALID] Invalid credentials`).
    public var detail: String?

    /// Machine-readable error class, for example `"RecordNotFound"` or `"missing"`.
    public var errorType: String?

    /// Short error code, for example `"api_key_invalid"`.
    public var code: String?

    /// The request field the error refers to, if any.
    public var field: String?

    /// Identifier to quote when contacting support.
    public var requestID: String?

    /// Error tracking identifier, when the API sent one.
    public var errorID: String?

    /// Seconds to wait before retrying, from the `Retry-After` header or the
    /// body, when the service sent one. Mostly on 429 and 503.
    public var retryAfter: TimeInterval?

    /// The raw response body, for diagnostics.
    public var body: Data

    public init(
        statusCode: Int,
        message: String? = nil,
        detail: String? = nil,
        errorType: String? = nil,
        code: String? = nil,
        field: String? = nil,
        requestID: String? = nil,
        errorID: String? = nil,
        retryAfter: TimeInterval? = nil,
        body: Data = Data()
    ) {
        self.statusCode = statusCode
        self.message = message
        self.detail = detail
        self.errorType = errorType
        self.code = code
        self.field = field
        self.requestID = requestID
        self.errorID = errorID
        self.retryAfter = retryAfter
        self.body = body
    }
}

/// Errors thrown by the SDK.
public enum OnetimeSecretError: Error, Sendable {
    /// A parameter failed validation before any request was made.
    case invalidArgument(String)

    /// The operation needs account credentials and the client has none.
    case authenticationRequired

    /// 401: credentials were missing or rejected.
    case unauthorized(APIErrorDetails)

    /// 403: the account is not allowed to perform the operation.
    case forbidden(APIErrorDetails)

    /// 404: no such secret or receipt. Already-consumed secrets also surface
    /// here once their record has been removed.
    case notFound(APIErrorDetails)

    /// 400 or 422: the request was understood but rejected. ``APIErrorDetails/field``
    /// names the offending parameter when the API knows it.
    case validation(APIErrorDetails)

    /// 422 with a passphrase complaint: the secret is passphrase protected and
    /// the passphrase was missing or wrong. The secret is not consumed.
    case passphraseRejected(APIErrorDetails)

    /// 429: slow down. `retryAfter` is the server's hint in seconds, when sent.
    case rateLimited(APIErrorDetails, retryAfter: TimeInterval?)

    /// 5xx: the service failed. Safe to retry with backoff.
    case server(APIErrorDetails)

    /// Any other non-2xx status.
    case unexpectedStatus(APIErrorDetails)

    /// The transport failed below HTTP (offline, DNS, TLS, timeout, cancelled).
    case transport(any Error)

    /// A 2xx response could not be decoded. Usually means the API changed
    /// shape; please report it with the SDK version. `body` has secret
    /// values redacted for responses that can carry them.
    case decoding(any Error, body: Data)

    /// The API details, for the cases that carry them.
    public var details: APIErrorDetails? {
        switch self {
        case let .unauthorized(d), let .forbidden(d), let .notFound(d), let .validation(d),
             let .passphraseRejected(d), let .rateLimited(d, _), let .server(d),
             let .unexpectedStatus(d):
            return d
        case .invalidArgument, .authenticationRequired, .transport, .decoding:
            return nil
        }
    }

    /// HTTP status code, when the error came from a response.
    public var statusCode: Int? { details?.statusCode }

    /// Request identifier to quote to support, when the API sent one.
    public var requestID: String? { details?.requestID }

    /// Seconds to wait before retrying, when the API said.
    public var retryAfter: TimeInterval? { details?.retryAfter }

    /// Whether retrying the same request later could succeed.
    ///
    /// This says nothing about whether retrying is *safe*. Reveal is not
    /// idempotent: a reveal that timed out may have consumed the secret on
    /// the server, and a repeated conceal creates a second secret. After a
    /// retryable failure of `reveal`, call `secrets.status(_:)` first; after
    /// one of `conceal`/`generate`, check `receipts.list()` if you have an
    /// account, or accept the possible duplicate.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .server:
            return true
        case let .transport(error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                     .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    return true
                default:
                    return false
                }
            }
            return false
        default:
            return false
        }
    }
}

extension OnetimeSecretError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidArgument(message):
            return message
        case .authenticationRequired:
            return "This operation requires account credentials."
        case let .unauthorized(d):
            return d.message ?? "Authentication failed."
        case let .forbidden(d):
            return d.message ?? "Permission denied."
        case let .notFound(d):
            return d.message ?? "The secret or receipt does not exist."
        case let .validation(d):
            if let field = d.field, let message = d.message {
                return "\(message) (\(field))"
            }
            return d.message ?? "The request was rejected."
        case let .passphraseRejected(d):
            return d.message ?? "The passphrase was missing or incorrect."
        case let .rateLimited(d, retryAfter):
            if let retryAfter {
                return d.message ?? "Rate limited. Retry after \(Int(retryAfter)) seconds."
            }
            return d.message ?? "Rate limited."
        case let .server(d):
            return d.message ?? "The service returned an error (HTTP \(d.statusCode))."
        case let .unexpectedStatus(d):
            return d.message ?? "Unexpected response (HTTP \(d.statusCode))."
        case let .transport(error):
            return error.localizedDescription
        case let .decoding(error, _):
            return "Could not decode the response: \(error.localizedDescription)"
        }
    }
}
