public import Foundation

/// Why ``OnetimeSecretClient/Secrets/generate(options:)`` could not claim the
/// generated value. The secret was created and its links work; only the
/// receipt fetch that follows creation failed.
///
/// Carries the failure's kind, HTTP status, error type and request ID, never
/// the API's message or the response body: a garbled receipt response can
/// contain the value itself.
public struct ClaimFailure: Error, Sendable, Hashable {
    /// The ``OnetimeSecretError`` case the fetch failed with, for example
    /// `"rateLimited"`, `"server"`, `"transport"` or `"decoding"`.
    public var reason: String

    /// HTTP status code, when the service answered with an error.
    public var statusCode: Int?

    /// Machine-readable error class from the API, for example `"RecordNotFound"`.
    public var errorType: String?

    /// Identifier to quote when contacting support, when the API sent one.
    public var requestID: String?

    public init(reason: String, statusCode: Int? = nil, errorType: String? = nil, requestID: String? = nil) {
        self.reason = reason
        self.statusCode = statusCode
        self.errorType = errorType
        self.requestID = requestID
    }

    init(_ error: OnetimeSecretError) {
        self.init(
            reason: error.caseName,
            statusCode: error.statusCode,
            errorType: error.details?.errorType,
            requestID: error.requestID
        )
    }
}

extension ClaimFailure: CustomStringConvertible, LocalizedError {
    public var description: String {
        var text = "Claiming the generated value failed: \(reason)"
        if let statusCode {
            text += " (HTTP \(statusCode)\(errorType.map { " \($0)" } ?? ""))"
        }
        return text
    }

    public var errorDescription: String? { description }
}

extension OnetimeSecretError {
    /// The case name without its associated values, for reports that must
    /// not carry what the service sent.
    var caseName: String {
        switch self {
        case .invalidArgument: return "invalidArgument"
        case .authenticationRequired: return "authenticationRequired"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .notFound: return "notFound"
        case .validation: return "validation"
        case .passphraseRejected: return "passphraseRejected"
        case .rateLimited: return "rateLimited"
        case .server: return "server"
        case .unexpectedStatus: return "unexpectedStatus"
        case .transport: return "transport"
        case .decoding: return "decoding"
        }
    }
}
