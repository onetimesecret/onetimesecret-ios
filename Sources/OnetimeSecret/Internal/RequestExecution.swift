import Foundation

/// Request building, sending, status mapping and decoding. Everything the
/// resources share.
extension OnetimeSecretClient {
    static let apiPrefix = "/api/v2"

    /// Headers the SDK owns. Values from ``Configuration/additionalHeaders``
    /// with these names (in any letter case) are dropped.
    private static let reservedHeaders: Set = [
        "accept", "content-type", "authorization", "user-agent", "x-onetime-client",
    ]

    /// Builds the path for an operation that has a guest and an
    /// authenticated form.
    func path(_ suffix: String, guest: String? = nil) -> String {
        if isAuthenticated {
            return Self.apiPrefix + suffix
        }
        return Self.apiPrefix + (guest ?? suffix)
    }

    func makeRequest(_ method: TransportRequest.Method, path: String) throws -> TransportRequest {
        try makeRequest(method, path: path, bodyData: nil)
    }

    func makeRequest(
        _ method: TransportRequest.Method,
        path: String,
        body: some Encodable
    ) throws -> TransportRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            throw OnetimeSecretError.invalidArgument("Could not encode the request body: \(error)")
        }
        return try makeRequest(method, path: path, bodyData: data)
    }

    private func makeRequest(
        _ method: TransportRequest.Method,
        path: String,
        bodyData: Data?
    ) throws -> TransportRequest {
        guard let url = URL(string: configuration.baseURL.absoluteString + path) else {
            throw OnetimeSecretError.invalidArgument("Could not build a URL for \(path)")
        }
        if configuration.credentials != nil, !Self.isSafeForCredentials(url) {
            let host = url.host ?? "the server"
            throw OnetimeSecretError.invalidArgument(
                "Refusing to send credentials over plain HTTP to \(host). Use https, or http only to localhost."
            )
        }

        var headers = configuration.additionalHeaders.filter {
            !Self.reservedHeaders.contains($0.key.lowercased())
        }
        headers["Accept"] = "application/json"
        headers["User-Agent"] = Self.userAgent
        headers["X-Onetime-Client"] = Self.clientHeader
        if let credentials = configuration.credentials {
            headers["Authorization"] = credentials.authorizationHeaderValue
        }

        var data = bodyData
        if data == nil, method != .get {
            // Mutating endpoints expect a JSON body even when it is empty.
            data = Data("{}".utf8)
        }
        if data != nil {
            headers["Content-Type"] = "application/json"
        }

        return TransportRequest(
            method: method,
            url: url,
            headers: headers,
            body: data,
            timeout: configuration.timeout
        )
    }

    /// Credentials travel as HTTP Basic, so plain http is only acceptable to
    /// a loopback address (a local development server).
    static func isSafeForCredentials(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" {
            return true
        }
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
            || host.hasSuffix(".localhost")
    }

    /// What a response body may contain, which decides how much of it an
    /// error is allowed to keep.
    enum BodySensitivity {
        /// Metadata only.
        case plain
        /// May carry `secret_value`; redact before attaching to an error.
        case mayContainSecret
    }

    /// Sends a request and returns a 2xx response.
    ///
    /// - Parameter passphraseGated: `true` for reveal and burn, the only
    ///   operations where a 422 mentioning the passphrase means "wrong
    ///   passphrase, nothing consumed". Elsewhere such a 422 is ordinary
    ///   validation.
    func send(_ request: TransportRequest, passphraseGated: Bool = false) async throws -> TransportResponse {
        let response: TransportResponse
        do {
            response = try await transport.send(request)
        } catch let error as OnetimeSecretError {
            throw error
        } catch {
            throw OnetimeSecretError.transport(error)
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            throw Self.error(for: response, passphraseGated: passphraseGated)
        }
        return response
    }

    /// Sends a request and decodes the 2xx body.
    func send<Response: Decodable>(
        _ request: TransportRequest,
        as _: Response.Type = Response.self,
        passphraseGated: Bool = false,
        sensitivity: BodySensitivity = .plain
    ) async throws -> Response {
        let response = try await send(request, passphraseGated: passphraseGated)
        return try decode(Response.self, from: response.body, sensitivity: sensitivity)
    }

    func decode<Response: Decodable>(
        _: Response.Type,
        from data: Data,
        sensitivity: BodySensitivity = .plain
    ) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnetimeSecretError.decoding(error, body: Self.redactedBody(data, sensitivity: sensitivity))
        }
    }

    /// Bodies attached to errors must not leak the one thing this SDK exists
    /// to protect. Replace secret-bearing values; if the body cannot even be
    /// parsed, keep nothing.
    static func redactedBody(_ data: Data, sensitivity: BodySensitivity) -> Data {
        guard sensitivity == .mayContainSecret else { return data }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return Data() }
        let redacted = redact(object)
        return (try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys])) ?? Data()
    }

    private static let redactedKeys: Set = ["secret_value", "passphrase", "secret"]

    private static func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, inner) in dictionary {
                if redactedKeys.contains(key), inner is String {
                    result[key] = "[redacted]"
                } else {
                    result[key] = redact(inner)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(redact)
        }
        return value
    }

    /// Maps a non-2xx response to an error.
    static func error(for response: TransportResponse, passphraseGated: Bool = false) -> OnetimeSecretError {
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: response.body)
        let retryAfter = retryAfter(from: response) ?? body?.retryAfter
        let details = APIErrorDetails(
            statusCode: response.statusCode,
            message: body?.error ?? body?.message,
            detail: body?.error == nil ? nil : body?.message,
            errorType: body?.errorType,
            code: body?.code,
            field: body?.field,
            requestID: body?.requestID,
            errorID: body?.errorID,
            retryAfter: retryAfter,
            body: response.body
        )

        // "Needs an account" arrives in several shapes depending on the
        // endpoint: a 401, or a 400 FormError whose field/code/type says
        // requires_account. All of them are an authentication problem.
        if response.statusCode != 401, isAccountRequired(details) {
            return .unauthorized(details)
        }

        switch response.statusCode {
        case 401:
            return .unauthorized(details)
        case 403:
            return .forbidden(details)
        case 404:
            return .notFound(details)
        case 400, 422:
            if passphraseGated, isPassphraseComplaint(details) {
                return .passphraseRejected(details)
            }
            return .validation(details)
        case 429:
            return .rateLimited(details, retryAfter: retryAfter)
        case 500...:
            return .server(details)
        default:
            return .unexpectedStatus(details)
        }
    }

    private static func isAccountRequired(_ details: APIErrorDetails) -> Bool {
        let slots = [details.errorType, details.code, details.field].compactMap { $0?.lowercased() }
        return slots.contains { slot in
            let normalized = slot.replacingOccurrences(of: "-", with: "_")
            return normalized.contains("requires_account") || normalized.contains("account_required")
                || normalized == "requiresaccount" || normalized == "accountrequired"
        }
    }

    /// The API does not yet send a machine-readable type for a rejected
    /// passphrase, so match the messages it uses.
    private static func isPassphraseComplaint(_ details: APIErrorDetails) -> Bool {
        if let type = details.errorType?.lowercased(), type.contains("passphrase") {
            return true
        }
        if details.field?.lowercased() == "passphrase" {
            return true
        }
        return details.message?.lowercased().contains("passphrase") ?? false
    }

    private static func retryAfter(from response: TransportResponse) -> TimeInterval? {
        guard let value = response.header("Retry-After") else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        return nil
    }
}
