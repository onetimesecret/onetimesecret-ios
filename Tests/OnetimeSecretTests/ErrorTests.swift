import Foundation
import Testing
@testable import OnetimeSecret

@Suite("Errors")
struct ErrorTests {
    @Test("404 maps to notFound with the API's error type and request id")
    func notFound() async throws {
        let transport = MockTransport(status: 404, fixture: "error_404")
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.preview("gone")
            Issue.record("Expected an error")
        } catch let OnetimeSecretError.notFound(details) {
            #expect(details.statusCode == 404)
            #expect(details.errorType == "RecordNotFound")
            #expect(details.requestID == "19i55nvkljwk8")
            #expect(details.message == nil)
        }
    }

    @Test("401 maps to unauthorized and keeps the code")
    func unauthorized() async throws {
        let transport = MockTransport(status: 401, fixture: "error_401")
        let client = OnetimeSecretClient.authenticated(transport)

        do {
            _ = try await client.receipts.list()
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case let .unauthorized(details) = error else {
                Issue.record("Expected .unauthorized, got \(error)")
                return
            }
            #expect(details.message == "Authentication Required")
            #expect(details.detail == "[CREDENTIALS_INVALID] Invalid credentials")
            #expect(details.code == "api_key_invalid")
            #expect(error.statusCode == 401)
            #expect(!error.isRetryable)
            #expect(error.errorDescription == "Authentication Required")
        }
    }

    @Test("422 with a field maps to validation")
    func validation() async throws {
        let transport = MockTransport(status: 422, fixture: "error_422_missing")
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.conceal("x")
            Issue.record("Expected an error")
        } catch let OnetimeSecretError.validation(details) {
            #expect(details.field == "secret")
            #expect(details.errorType == "missing")
            #expect(details.message == "You did not provide anything to share")
        }
    }

    @Test("a passphrase complaint maps to passphraseRejected")
    func passphrase() async throws {
        let transport = MockTransport(status: 422, fixture: "error_422_passphrase")
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.reveal("abc", passphrase: "wrong")
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case let .passphraseRejected(details) = error else {
                Issue.record("Expected .passphraseRejected, got \(error)")
                return
            }
            #expect(details.message == "Incorrect passphrase")
            #expect(error.requestID == "0ivnpf8jl0p42")
        }
    }

    @Test("a passphrase complaint on conceal is ordinary validation, since nothing could be consumed")
    func passphraseOnConceal() async throws {
        let transport = MockTransport(status: 422, json: #"{"error":"Passphrase is too long","field":"passphrase"}"#)
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.conceal("x", options: ConcealOptions(passphrase: "pw"))
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case .validation = error else {
                Issue.record("Expected .validation, got \(error)")
                return
            }
        }
    }

    @Test("decoding errors from reveal never carry the plaintext")
    func decodingRedaction() async throws {
        // A reveal body the SDK cannot decode (no identifier) that still has a value in it.
        let transport = MockTransport(
            status: 200,
            json: #"{"record":{"state":"revealed","secret_value":"the plaintext"}}"#
        )
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.reveal("abc")
            Issue.record("Expected an error")
        } catch let OnetimeSecretError.decoding(_, body) {
            let text = String(decoding: body, as: UTF8.self)
            #expect(!text.contains("the plaintext"))
            #expect(text.contains("[redacted]"))
        }
    }

    @Test("credentials are not sent over plain http to a remote host")
    func credentialsOverHTTP() async throws {
        let transport = MockTransport(fixture: "system_status")
        let client = try OnetimeSecretClient(
            baseURL: #require(URL(string: "http://secrets.example.com")),
            credentials: Credentials(username: "u", apiToken: "t"),
            transport: transport
        )

        await #expect(throws: OnetimeSecretError.self) {
            try await client.system.status()
        }
        #expect(transport.requests.isEmpty)

        // Loopback is fine for local development.
        let local = try OnetimeSecretClient(
            baseURL: #require(URL(string: "http://localhost:3000")),
            credentials: Credentials(username: "u", apiToken: "t"),
            transport: transport
        )
        _ = try await local.system.status()
        #expect(transport.requests.count == 1)
    }

    @Test("429 maps to rateLimited with Retry-After")
    func rateLimited() async throws {
        let transport = MockTransport(
            status: 429,
            json: #"{"error":"Too many requests"}"#,
            headers: ["retry-after": "17"]
        )
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.conceal("x")
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case let .rateLimited(_, retryAfter) = error else {
                Issue.record("Expected .rateLimited, got \(error)")
                return
            }
            #expect(retryAfter == 17)
            #expect(error.isRetryable)
        }
    }

    @Test("503 with retry_after in the body exposes it")
    func serverRetryAfter() async throws {
        let transport = MockTransport(status: 503, json: #"{"error":"Try again shortly","retry_after":30}"#)
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.system.status()
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case .server = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(error.retryAfter == 30)
            #expect(error.isRetryable)
        }
    }

    @Test("5xx maps to server, even with a non-JSON body")
    func server() async throws {
        let transport = MockTransport(status: 502, json: "<html>Bad Gateway</html>")
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.system.status()
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case let .server(details) = error else {
                Issue.record("Expected .server, got \(error)")
                return
            }
            #expect(details.statusCode == 502)
            #expect(details.message == nil)
            #expect(String(decoding: details.body, as: UTF8.self).contains("Bad Gateway"))
            #expect(error.isRetryable)
        }
    }

    @Test("transport failures are wrapped")
    func transport() async throws {
        let transport = MockTransport([.failure(URLError(.notConnectedToInternet))])
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.system.status()
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case let .transport(underlying) = error else {
                Issue.record("Expected .transport, got \(error)")
                return
            }
            #expect((underlying as? URLError)?.code == .notConnectedToInternet)
            #expect(error.isRetryable)
        }
    }

    @Test("an undecodable 2xx body maps to decoding and keeps the body")
    func decoding() async throws {
        let transport = MockTransport(status: 200, json: #"{"unexpected": true}"#)
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.conceal("x")
            Issue.record("Expected an error")
        } catch let OnetimeSecretError.decoding(_, body) {
            #expect(String(decoding: body, as: UTF8.self).contains("unexpected"))
        }
    }

    @Test("a reveal that returns no value is a decoding error, not a silent empty string")
    func revealWithoutValue() async throws {
        let transport = MockTransport(fixture: "show_secret")
        let client = OnetimeSecretClient.guest(transport)

        await #expect(throws: OnetimeSecretError.self) {
            try await client.secrets.reveal("abc")
        }
    }
}

@Suite("Account-required mapping")
struct AccountRequiredTests {
    @Test("a 400 FormError with field requires_account maps to unauthorized", arguments: [
        #"{"error":"Account required","error_type":"FormError","field":"requires_account"}"#,
        #"{"error":"Account required","error_type":"RequiresAccount"}"#,
        #"{"error":"Account required","code":"GUEST_CONCEAL_REQUIRES_ACCOUNT"}"#,
    ])
    func accountRequired(json: String) async throws {
        let transport = MockTransport(status: 400, json: json)
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.conceal("x")
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case .unauthorized = error else {
                Issue.record("Expected .unauthorized, got \(error)")
                return
            }
        }
    }
}
