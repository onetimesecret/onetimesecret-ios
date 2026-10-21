import Foundation
import Testing
@testable import OnetimeSecret

@Suite("Receipts")
struct ReceiptsTests {
    @Test("get decodes the record and merges telemetry details")
    func get() async throws {
        let transport = MockTransport(fixture: "receipt_revealed")
        let client = OnetimeSecretClient.guest(transport)

        let receipt = try await client.receipts.get("receipt0000000000000000000000000000000000000000000000000000000")

        #expect(transport.lastRequest?.url
            .path == "/api/v2/guest/receipt/receipt0000000000000000000000000000000000000000000000000000000")
        #expect(receipt.state == .revealed)
        #expect(receipt.isRevealed)
        #expect(receipt.isDestroyed)
        #expect(!receipt.isSecretAvailable)
        #expect(receipt.revealedAt?.timeIntervalSince1970 == 1_792_538_346)
        #expect(receipt.previewedAt != nil)
        #expect(receipt.burnedAt == nil)
        #expect(receipt.naturalExpiration == "5 minutes")
        #expect(receipt.expiresAt?.timeIntervalSince1970 == 1_792_538_626)
        #expect(receipt.recipients.isEmpty)
        #expect(receipt.memo == nil)
        #expect(receipt.secretState == nil)
        #expect(receipt.receiptURL?.absoluteString == "https://us.onetimesecret.com/receipt/\(receipt.identifier)")
        #expect(receipt.burnURL?.absoluteString == "https://us.onetimesecret.com/receipt/\(receipt.identifier)/burn")
        // The API sends "https://host/secret/" once the secret is gone.
        #expect(receipt.shareURL == nil)

        #expect(receipt.viewCount == 2)
        #expect(receipt.firstAccessedAt?.timeIntervalSince1970 == 1_792_538_345.298835)
        #expect(receipt.lastAccessedAt != nil)
        #expect(receipt.generatedValue == nil)
    }

    @Test("get on a fresh generated secret exposes the value once")
    func getGenerated() async throws {
        let transport = MockTransport(fixture: "receipt_generated")
        let client = OnetimeSecretClient.authenticated(transport)

        let receipt = try await client.receipts.get("receipt0000000000000000000000000000000000000000000000000000000")

        #expect(transport.lastRequest?.url.path.hasPrefix("/api/v2/receipt/") == true)
        #expect(receipt.generatedValue == "bvpPtGPgtLd7ApUVqdEn")
        #expect(receipt.isSecretAvailable)
        #expect(receipt.shareURL?.lastPathComponent == receipt.secretIdentifier)
        #expect(receipt.secretTimeToLive == 299)
        #expect(receipt.description.contains("bvpPtGPgtLd7ApUVqdEn") == false)
    }

    @Test("list requires credentials")
    func listAsGuest() async {
        let transport = MockTransport()
        let client = OnetimeSecretClient.guest(transport)

        await #expect(throws: OnetimeSecretError.self) {
            try await client.receipts.list()
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("list decodes records including array recipients")
    func list() async throws {
        let transport = MockTransport(fixture: "receipts_recent")
        let client = OnetimeSecretClient.authenticated(transport)

        let receipts = try await client.receipts.list()

        #expect(transport.lastRequest?.url.path == "/api/v2/receipt/recent")
        #expect(receipts.count == 2)
        #expect(receipts[0].recipients.isEmpty)
        #expect(receipts[1].recipients == ["a@example.com", "b@example.com"])
        #expect(receipts[1].state == .burned)
    }

    @Test("burn posts continue and an optional passphrase, and tolerates a bare success body")
    func burn() async throws {
        let transport = MockTransport(fixture: "burn_already")
        let client = OnetimeSecretClient.guest(transport)

        try await client.receipts.burn(
            "receipt0000000000000000000000000000000000000000000000000000000",
            passphrase: "pw"
        )

        let request = try #require(transport.lastRequest)
        #expect(request.method == .post)
        #expect(request.url
            .path == "/api/v2/guest/receipt/receipt0000000000000000000000000000000000000000000000000000000/burn")
        #expect(request.jsonBody?["continue"] as? String == "true")
        #expect(request.jsonBody?["passphrase"] as? String == "pw")
    }

    @Test("burn with a wrong or missing passphrase maps the 422 to passphraseRejected")
    func burnPassphraseRejected() async throws {
        let transport = MockTransport(status: 422, fixture: "error_422_passphrase")
        let client = OnetimeSecretClient.guest(transport)

        do {
            try await client.receipts.burn(
                "receipt0000000000000000000000000000000000000000000000000000000",
                passphrase: "wrong"
            )
            Issue.record("Expected passphraseRejected")
        } catch let error as OnetimeSecretError {
            guard case let .passphraseRejected(details) = error else {
                Issue.record("Expected .passphraseRejected, got \(error)")
                return
            }
            #expect(details.statusCode == 422)
            #expect(details.message == "Incorrect passphrase")
            #expect(error.requestID == "0ivnpf8jl0p42")
            #expect(!error.isRetryable)
        }
        #expect(transport.requests.count == 1)
        #expect(transport.lastRequest?.jsonBody?["passphrase"] as? String == "wrong")
    }

    @Test("updateMemo patches the receipt")
    func updateMemo() async throws {
        let transport = MockTransport(fixture: "receipt_revealed")
        let client = OnetimeSecretClient.authenticated(transport)

        _ = try await client.receipts.updateMemo("abc", memo: "for the on-call handover")

        let request = try #require(transport.lastRequest)
        #expect(request.method == .patch)
        #expect(request.url.path == "/api/v2/receipt/abc")
        #expect(request.jsonBody?["memo"] as? String == "for the on-call handover")
    }

    @Test("updateMemo enforces the length limit and credentials")
    func updateMemoValidation() async {
        let transport = MockTransport()

        await #expect(throws: OnetimeSecretError.self) {
            try await OnetimeSecretClient.guest(transport).receipts.updateMemo("abc", memo: "x")
        }
        await #expect(throws: OnetimeSecretError.self) {
            try await OnetimeSecretClient.authenticated(transport)
                .receipts.updateMemo("abc", memo: String(repeating: "x", count: 501))
        }
        #expect(transport.requests.isEmpty)
    }
}

@Suite("System")
struct SystemTests {
    @Test func status() async throws {
        let transport = MockTransport(fixture: "system_status")
        let client = OnetimeSecretClient.guest(transport)

        let status = try await client.system.status()

        #expect(status.isNominal)
        #expect(status.locale == "en")
        #expect(transport.lastRequest?.url.path == "/api/v2/status")
    }

    @Test func supportedLocales() async throws {
        let transport = MockTransport(fixture: "supported_locales")
        let client = OnetimeSecretClient.guest(transport)

        let locales = try await client.system.supportedLocales()

        #expect(locales.locales == ["de", "en", "fr_FR"])
        #expect(locales.defaultLocale == "en")
    }

    @Test func version() async throws {
        let transport = MockTransport(fixture: "system_version")
        let client = OnetimeSecretClient.authenticated(transport)

        let version = try await client.system.version()

        #expect(version.version == "0.27.1")
        #expect(transport.lastRequest?.url.path == "/api/v2/version")
    }

    @Test func versionRequiresCredentials() async {
        let transport = MockTransport()
        await #expect(throws: OnetimeSecretError.self) {
            try await OnetimeSecretClient.guest(transport).system.version()
        }
    }
}
