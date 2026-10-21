public import Foundation

/// A fully formed request, ready to be sent by an ``HTTPTransport``.
///
/// Named `TransportRequest` rather than `HTTPRequest` so that it never
/// collides with `HTTPTypes.HTTPRequest` or other networking libraries in
/// the same app.
public struct TransportRequest: Sendable, Hashable {
    /// An HTTP method.
    public enum Method: String, Sendable, Hashable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    /// Timeout in seconds. On Apple platforms this maps to
    /// `URLRequest.timeoutInterval`, which is an idle timeout between bytes,
    /// not a total budget for the request.
    public var timeout: TimeInterval

    public init(
        method: Method,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// Header lookup that ignores case.
    public func header(_ name: String) -> String? {
        TransportRequest.header(name, in: headers)
    }

    static func header(_ name: String, in headers: [String: String]) -> String? {
        if let exact = headers[name] {
            return exact
        }
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }
}

extension TransportRequest: CustomStringConvertible, CustomDebugStringConvertible {
    /// Omits the `Authorization` header and the body, which may hold a
    /// secret or passphrase.
    public var description: String {
        let safeHeaders = headers
            .filter { $0.key.lowercased() != "authorization" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        let bodyNote = body.map { "body: \($0.count) bytes" } ?? "no body"
        return "TransportRequest(\(method.rawValue) \(url.absoluteString), headers: [\(safeHeaders)], \(bodyNote))"
    }

    public var debugDescription: String {
        description
    }
}

/// A response as seen by the SDK.
public struct TransportResponse: Sendable, Hashable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// Header lookup that ignores case, as HTTP header names are case-insensitive.
    public func header(_ name: String) -> String? {
        TransportRequest.header(name, in: headers)
    }
}

extension TransportResponse: CustomStringConvertible, CustomDebugStringConvertible {
    /// Omits the body, which may hold a secret value.
    public var description: String {
        "TransportResponse(\(statusCode), body: \(body.count) bytes)"
    }

    public var debugDescription: String {
        description
    }
}

/// Sends HTTP requests on behalf of the SDK.
///
/// The SDK ships ``URLSessionTransport``. Conform your own type to add
/// retries, logging, certificate pinning, or to return canned responses in
/// tests. A transport must not throw for non-2xx status codes; the SDK maps
/// those to ``OnetimeSecretError`` itself.
///
/// If you log requests or responses, log their `description`, which omits
/// credentials and bodies. Bodies can contain secret values.
public protocol HTTPTransport: Sendable {
    /// Sends the request and returns the response, whatever its status code.
    ///
    /// Throw only for failures below HTTP: no network, DNS, TLS, timeouts,
    /// cancellation. Thrown errors surface as ``OnetimeSecretError/transport(_:)``.
    func send(_ request: TransportRequest) async throws -> TransportResponse
}
