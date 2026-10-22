import Foundation
import Testing
@testable import OnetimeSecret

@Suite("Secrets")
struct SecretsTests {
    // MARK: Conceal

    @Test("conceal sends the documented payload to the guest endpoint")
    func concealGuestRequest() async throws {
        let transport = MockTransport(fixture: "conceal")
        let client = OnetimeSecretClient.guest(transport)

        _ = try await client.secrets.conceal(
            "hello",
            options: ConcealOptions(timeToLive: 3600, passphrase: "pw", displayType: .markdown)
        )

        let request = try #require(transport.lastRequest)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://us.onetimesecret.com/api/v2/guest/secret/conceal")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Authorization"] == nil)
        let userAgent = try #require(request.headers["User-Agent"])
        #expect(userAgent.hasPrefix("onetimesecret-ios/\(OnetimeSecretClient.version) (Swift/"))
        #expect(request.headers["X-Onetime-Client"]?.hasPrefix("swift:6.") == true)
        #expect(request.headers["X-Onetime-Client"]?.hasSuffix("/\(OnetimeSecretClient.version)") == true)

        let secret = try #require(request.jsonBody?["secret"] as? [String: Any])
        #expect(secret["kind"] as? String == "conceal")
        #expect(secret["secret"] as? String == "hello")
        #expect(secret["share_domain"] as? String == "us.onetimesecret.com")
        #expect(secret["ttl"] as? Int == 3600)
        #expect(secret["passphrase"] as? String == "pw")
        #expect(secret["display_type"] as? String == "markdown")
        #expect(secret["recipient"] == nil)
    }

    @Test("conceal uses the authenticated endpoint and Basic auth when credentials are set")
    func concealAuthenticatedRequest() async throws {
        let transport = MockTransport(fixture: "conceal")
        let client = OnetimeSecretClient.authenticated(transport)

        _ = try await client.secrets.conceal("hello", options: ConcealOptions(recipient: "friend@example.com"))

        let request = try #require(transport.lastRequest)
        #expect(request.url.absoluteString == "https://eu.onetimesecret.com/api/v2/secret/conceal")
        let expected = "Basic " + Data("user@example.com:tok_123".utf8).base64EncodedString()
        #expect(request.headers["Authorization"] == expected)
        let secret = try #require(request.jsonBody?["secret"] as? [String: Any])
        #expect(secret["recipient"] as? String == "friend@example.com")
        #expect(secret["share_domain"] as? String == "eu.onetimesecret.com")
    }

    @Test("conceal decodes the response and builds share links")
    func concealResponse() async throws {
        let transport = MockTransport(fixture: "conceal")
        let client = OnetimeSecretClient.guest(transport)

        let result = try await client.secrets.conceal("hello")

        #expect(result.secret.identifier.hasPrefix("secret00"))
        #expect(result.secret.shortID == "secret00")
        #expect(result.secret.state == .new)
        #expect(result.secret.value == nil)
        #expect(result.secret.lifespan == 300)
        #expect(result.secret.hasPassphrase == false)
        #expect(result.receipt.shortID == "receipt0")
        #expect(result.receipt.kind == .conceal)
        #expect(result.receipt.source == .standard)
        #expect(result.receipt.recipients.isEmpty)
        #expect(result.receipt.createdAt?.timeIntervalSince1970 == 1_792_538_326.1823587)
        #expect(result.shareDomain == nil)
        #expect(result.shareURL.absoluteString == "https://us.onetimesecret.com/secret/\(result.secret.identifier)")
        #expect(result.receiptURL.absoluteString == "https://us.onetimesecret.com/receipt/\(result.receipt.identifier)")
        #expect(result.burnURL
            .absoluteString == "https://us.onetimesecret.com/receipt/\(result.receipt.identifier)/burn")
    }

    @Test("a configured share domain is sent and used for the share link")
    func concealCustomShareDomain() async throws {
        let transport = MockTransport(status: 200, json: Self.concealJSON(shareDomain: "secrets.example.com"))
        let client = OnetimeSecretClient.guest(transport, shareDomain: "secrets.example.com")

        let result = try await client.secrets.conceal("hello")

        let secret = try #require(transport.lastRequest?.jsonBody?["secret"] as? [String: Any])
        #expect(secret["share_domain"] as? String == "secrets.example.com")
        #expect(result.shareDomain == "secrets.example.com")
        #expect(result.shareURL.absoluteString == "https://secrets.example.com/secret/\(result.secret.identifier)")
        #expect(result.receiptURL.host == "us.onetimesecret.com")
    }

    @Test("self-hosted share links keep the origin's scheme and port")
    func concealSelfHostedShareURL() async throws {
        let transport = MockTransport(fixture: "conceal")
        let client = try OnetimeSecretClient(
            baseURL: #require(URL(string: "http://localhost:3000")),
            transport: transport
        )

        let result = try await client.secrets.conceal("hello")

        #expect(result.shareURL.absoluteString == "http://localhost:3000/secret/\(result.secret.identifier)")
        let secret = try #require(transport.lastRequest?.jsonBody?["secret"] as? [String: Any])
        #expect(secret["share_domain"] as? String == "localhost")
    }

    @Test("conceal rejects an empty value before any request")
    func concealEmpty() async {
        let transport = MockTransport()
        let client = OnetimeSecretClient.guest(transport)

        await #expect(throws: OnetimeSecretError.self) {
            try await client.secrets.conceal("")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("recipient requires credentials")
    func concealRecipientAsGuest() async throws {
        let transport = MockTransport()
        let client = OnetimeSecretClient.guest(transport)

        do {
            _ = try await client.secrets.conceal("hello", options: ConcealOptions(recipient: "a@example.com"))
            Issue.record("Expected an error")
        } catch OnetimeSecretError.authenticationRequired {
            // expected
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Status

    @Test("status returns the secret and remaining lifetime")
    func statusKnown() async throws {
        let transport = MockTransport(fixture: "status_known")
        let client = OnetimeSecretClient.guest(transport)

        let status = try await client.secrets.status("secret00000000000000000000000000000000000000000000000000000000")

        guard case let .known(secret, expiresIn) = status else {
            Issue.record("Expected .known, got \(status)")
            return
        }
        #expect(secret.state == .new)
        #expect(expiresIn == 281)
        #expect(status.isAvailable)
        #expect(transport.lastRequest?.method == .get)
        #expect(transport.lastRequest?.url.path.hasSuffix("/status") == true)
        #expect(transport.lastRequest?.body == nil)
    }

    @Test("status reports unknown secrets without throwing")
    func statusUnknown() async throws {
        let transport = MockTransport(fixture: "status_unknown")
        let client = OnetimeSecretClient.guest(transport)

        let status = try await client.secrets.status("doesnotexist")

        #expect(status == .unknown)
        #expect(status.secret == nil)
        #expect(!status.isAvailable)
    }

    @Test("identifiers are extracted from share, receipt and burn links", arguments: [
        "https://us.onetimesecret.com/secret/abc123DEF",
        "https://us.onetimesecret.com/receipt/abc123DEF",
        "https://us.onetimesecret.com/receipt/abc123DEF/burn",
        "  abc123DEF\n",
    ])
    func statusFromLink(input: String) async throws {
        let transport = MockTransport(fixture: "status_known")
        let client = OnetimeSecretClient.guest(transport)

        _ = try await client.secrets.status(input)

        #expect(transport.lastRequest?.url.path == "/api/v2/secret/abc123DEF/status")
    }

    @Test(
        "identifiers that could change the path are rejected",
        arguments: ["", "  ", "../receipt", "a/b", "x?y=1", "a%2Fb"]
    )
    func badIdentifiers(identifier: String) async {
        let transport = MockTransport()
        let client = OnetimeSecretClient.guest(transport)

        await #expect(throws: OnetimeSecretError.self) {
            try await client.secrets.status(identifier)
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Preview and reveal

    @Test("preview returns metadata without the value")
    func preview() async throws {
        let transport = MockTransport(fixture: "show_secret")
        let client = OnetimeSecretClient.guest(transport)

        let secret = try await client.secrets.preview("secret00000000000000000000000000000000000000000000000000000000")

        #expect(secret.value == nil)
        #expect(secret.displayType == .text)
        #expect(secret.requiresVerification == false)
        #expect(transport.lastRequest?.url
            .path == "/api/v2/guest/secret/secret00000000000000000000000000000000000000000000000000000000")
    }

    @Test("reveal posts continue and the passphrase, and returns the value")
    func reveal() async throws {
        let transport = MockTransport(fixture: "reveal")
        let client = OnetimeSecretClient.guest(transport)

        let revealed = try await client.secrets.reveal(
            "secret00000000000000000000000000000000000000000000000000000000",
            passphrase: "pw"
        )

        let request = try #require(transport.lastRequest)
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/reveal"))
        #expect(request.jsonBody?["continue"] as? String == "true")
        #expect(request.jsonBody?["passphrase"] as? String == "pw")

        #expect(revealed.value == "sdk fixture capture, safe to discard")
        #expect(revealed.secret.state == .revealed)
        #expect(revealed.secret.isRevealed)
        #expect(!revealed.secret.isAvailable)
    }

    @Test("reveal without a passphrase omits the key")
    func revealNoPassphrase() async throws {
        let transport = MockTransport(fixture: "reveal")
        let client = OnetimeSecretClient.authenticated(transport)

        _ = try await client.secrets.reveal("abc")

        let request = try #require(transport.lastRequest)
        #expect(request.url.path == "/api/v2/secret/abc/reveal")
        #expect(request.jsonBody?["passphrase"] == nil)
    }

    @Test("bulk status posts identifiers")
    func bulkStatus() async throws {
        let transport = MockTransport(status: 200, json: #"{"records":[],"count":0}"#)
        let client = OnetimeSecretClient.guest(transport)

        let secrets = try await client.secrets.statuses(of: ["a", "b"])

        #expect(secrets.isEmpty)
        #expect(transport.lastRequest?.url.path == "/api/v2/secret/status")
        #expect(transport.lastRequest?.jsonBody?["identifiers"] as? String == "a,b")
    }

    @Test("bulk status decodes every record the service knows and keeps their order")
    func bulkStatusRecords() async throws {
        let transport = MockTransport(fixture: "statuses_known")
        let client = OnetimeSecretClient.authenticated(transport)

        let secrets = try await client.secrets.statuses(of: [
            "https://eu.onetimesecret.com/secret/secret00000000000000000000000000000000000000000000000000000000",
            "secret11111111111111111111111111111111111111111111111111111111",
            "doesnotexist0000",
        ])

        let request = try #require(transport.lastRequest)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://eu.onetimesecret.com/api/v2/secret/status")
        #expect(request.jsonBody?["identifiers"] as? String == [
            "secret00000000000000000000000000000000000000000000000000000000",
            "secret11111111111111111111111111111111111111111111111111111111",
            "doesnotexist0000",
        ].joined(separator: ","))

        // The unknown identifier is omitted rather than reported.
        #expect(secrets.count == 2)
        #expect(secrets.map(\.shortID) == ["secret00", "secret11"])
        #expect(secrets.map(\.hasPassphrase) == [false, true])
        #expect(secrets.allSatisfy { $0.state == .new })
        #expect(secrets.map(\.isAvailable) == [true, true])
        #expect(secrets.allSatisfy { $0.value == nil })
        #expect(secrets[0].lifespan == 300)
        #expect(secrets[0].timeToLive == 300)
        #expect(secrets[1].createdAt?.timeIntervalSince1970 == 1_792_597_029.65599)
    }

    @Test("bulk status with no identifiers makes no request")
    func bulkStatusEmpty() async throws {
        let transport = MockTransport()
        let client = OnetimeSecretClient.guest(transport)

        let secrets = try await client.secrets.statuses(of: [])

        #expect(secrets.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    // MARK: Helpers

    static func concealJSON(shareDomain: String) -> String {
        let base = String(decoding: Fixtures.data("conceal"), as: UTF8.self)
        // The last "share_domain": null is the top-level one.
        guard let range = base.range(of: "\"share_domain\": null", options: .backwards) else {
            fatalError("fixture changed")
        }
        return base.replacingCharacters(in: range, with: "\"share_domain\": \"\(shareDomain)\"")
    }
}
