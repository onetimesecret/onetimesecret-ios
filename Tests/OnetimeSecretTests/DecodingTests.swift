import Foundation
import Testing
@testable import OnetimeSecret

@Suite("Decoding")
struct DecodingTests {
    @Test("records with string-typed booleans and numbers decode")
    func legacyStrings() throws {
        let envelope = try JSONDecoder().decode(
            RecordEnvelope<Secret, NoDetails>.self,
            from: Fixtures.data("secret_legacy_strings")
        )
        let secret = envelope.record

        #expect(secret.hasPassphrase == true)
        #expect(secret.requiresVerification == false)
        #expect(secret.displayType == .markdown)
        #expect(secret.createdAt?.timeIntervalSince1970 == 1_792_538_326)
        #expect(secret.updatedAt?.timeIntervalSince1970 == 1_792_538_326.5)
        #expect(secret.lifespan == 300)
        #expect(secret.timeToLive == nil)
        #expect(secret.isPreviewed == false)
        #expect(secret.isRevealed == false)
        #expect(secret.isViewed == false)
        #expect(secret.isReceived == true)
    }

    @Test("unknown states and kinds decode instead of failing")
    func forwardCompatibleEnums() throws {
        let json = #"""
        {"identifier":"abc","shortid":"abc","state":"quarantined","display_type":"ascii-art",
         "created":1,"updated":1,"lifespan":1,"secret_ttl":1}
        """#
        let secret = try JSONDecoder().decode(Secret.self, from: Data(json.utf8))
        #expect(secret.state == SecretState(rawValue: "quarantined"))
        #expect(secret.state != .new)
        #expect(secret.displayType.rawValue == "ascii-art")
    }

    @Test("a receipt with the minimal documented fields decodes")
    func minimalReceipt() throws {
        let json = #"""
        {"identifier":"r1","shortid":"r1","state":"new","created":1,"updated":1,
         "secret_ttl":"300","receipt_ttl":null,"lifespan":null}
        """#
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(json.utf8))
        #expect(receipt.state == .new)
        #expect(receipt.secretTimeToLive == 300)
        #expect(receipt.receiptTimeToLive == nil)
        #expect(receipt.recipients.isEmpty)
        #expect(receipt.isSecretAvailable)
        #expect(receipt.shareURL == nil)
    }

    @Test("comma-separated recipients split into a list")
    func recipientsString() throws {
        let json = #"""
        {"identifier":"r1","shortid":"r1","state":"new","created":1,"updated":1,
         "secret_ttl":1,"receipt_ttl":1,"lifespan":1,"recipients":"a@example.com, b@example.com,"}
        """#
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(json.utf8))
        #expect(receipt.recipients == ["a@example.com", "b@example.com"])
    }

    @Test("a missing identifier is still an error")
    func missingIdentifier() {
        let json = #"{"state":"new"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Secret.self, from: Data(json.utf8))
        }
    }

    @Test("SystemVersion accepts a string or mixed array")
    func systemVersion() throws {
        let fromString = try JSONDecoder().decode(SystemVersion.self, from: Data(#"{"version":"1.2.3"}"#.utf8))
        #expect(fromString.version == "1.2.3")
        let fromArray = try JSONDecoder().decode(SystemVersion.self, from: Data(#"{"version":[1,"2",3]}"#.utf8))
        #expect(fromArray.version == "1.2.3")
    }

    @Test("descriptions never leak secret material")
    func descriptions() throws {
        let secret = Secret(identifier: "abc", shortID: "abc", state: .revealed, value: "top secret")
        #expect(!secret.description.contains("top secret"))
        let credentials = Credentials(username: "me@example.com", apiToken: "tok_sensitive")
        #expect(!credentials.description.contains("tok_sensitive"))
        #expect(!credentials.debugDescription.contains("tok_sensitive"))
        #expect(!"\(credentials)".contains("tok_sensitive"))

        let revealed = RevealedSecret(value: "top secret", secret: secret)
        #expect(!"\(revealed)".contains("top secret"))
        #expect(!revealed.debugDescription.contains("top secret"))

        let options = ConcealOptions(passphrase: "hunter2")
        #expect(!"\(options)".contains("hunter2"))
        let generateOptions = GenerateOptions(passphrase: "hunter2")
        #expect(!"\(generateOptions)".contains("hunter2"))

        let request = try TransportRequest(
            method: .post,
            url: #require(URL(string: "https://example.com")),
            headers: ["Authorization": "Basic c2VjcmV0", "Accept": "application/json"],
            body: Data("passphrase".utf8)
        )
        #expect(!"\(request)".contains("c2VjcmV0"))
        #expect(!"\(request)".contains("passphrase"))
        #expect("\(request)".contains("Accept"))
        let response = TransportResponse(statusCode: 200, body: Data("plaintext".utf8))
        #expect(!"\(response)".contains("plaintext"))
    }

    @Test("a receipt with a null identifier falls back to key")
    func receiptKeyFallback() throws {
        let json = #"""
        {"identifier":null,"key":"r1key","shortid":"r1","state":"new","created":1,"updated":1,
         "secret_ttl":1,"receipt_ttl":1,"lifespan":1}
        """#
        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(json.utf8))
        #expect(receipt.identifier == "r1key")
    }
}

@Suite("Configuration")
struct ConfigurationTests {
    @Test("regions map to their hosts", arguments: Region.allCases)
    func regionHosts(region: Region) {
        #expect(region.baseURL.absoluteString == "https://\(region.rawValue).onetimesecret.com")
    }

    @Test("trailing slashes are removed and the share domain defaults to the host")
    func normalization() throws {
        let configuration = try Configuration(baseURL: #require(URL(string: "https://secrets.example.com///")))
        #expect(configuration.baseURL.absoluteString == "https://secrets.example.com")
        #expect(configuration.resolvedShareDomain == "secrets.example.com")
    }

    @Test("additional headers are sent but cannot override SDK headers")
    func additionalHeaders() async throws {
        let transport = MockTransport(fixture: "system_status")
        let configuration = Configuration(
            region: .canada,
            additionalHeaders: ["X-Trace": "1", "Accept": "text/plain", "accept": "text/html", "user-agent": "spoof"]
        )
        let client = OnetimeSecretClient(configuration: configuration, transport: transport)

        _ = try await client.system.status()

        #expect(transport.lastRequest?.headers["X-Trace"] == "1")
        #expect(transport.lastRequest?.headers["Accept"] == "application/json")
        #expect(transport.lastRequest?.headers["accept"] == nil)
        #expect(transport.lastRequest?.headers["user-agent"] == nil)
        #expect(transport.lastRequest?.headers["User-Agent"]?.hasPrefix("onetimesecret-ios/") == true)
        #expect(transport.lastRequest?.timeout == 30)
    }

    @Test("self-hosted base URLs are used verbatim")
    func selfHosted() async throws {
        let transport = MockTransport(fixture: "system_status")
        let client = try OnetimeSecretClient(
            baseURL: #require(URL(string: "http://localhost:3000")),
            transport: transport
        )

        _ = try await client.system.status()

        #expect(transport.lastRequest?.url.absoluteString == "http://localhost:3000/api/v2/status")
        #expect(!client.isAuthenticated)
    }

    @Test("the version constant looks like semver")
    func version() {
        let parts = OnetimeSecretClient.version.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0.prefix { $0.isNumber }) != nil })
    }
}
