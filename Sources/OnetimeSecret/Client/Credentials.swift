import Foundation

/// Account credentials for HTTP Basic authentication.
///
/// The username is the account's email address or external ID and the token
/// is an API token from the account's API settings page. The token is never
/// included in `description` or `debugDescription`, so instances are safe to
/// log.
public struct Credentials: Sendable, Hashable {
    /// Account email address or external ID.
    public var username: String

    /// API token.
    public var apiToken: String

    /// Creates credentials.
    public init(username: String, apiToken: String) {
        self.username = username
        self.apiToken = apiToken
    }

    /// Value for the `Authorization` header (RFC 7617).
    var authorizationHeaderValue: String {
        let raw = Data("\(username):\(apiToken)".utf8)
        return "Basic \(raw.base64EncodedString())"
    }
}

extension Credentials: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Credentials(username: \"\(username)\", apiToken: <redacted>)"
    }

    public var debugDescription: String {
        description
    }
}
