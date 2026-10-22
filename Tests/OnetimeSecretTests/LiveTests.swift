import Foundation
import Testing
@testable import OnetimeSecret

/// End-to-end tests against the hosted service. Off by default; enable with
/// `ONETIME_LIVE=1`. They run as a guest against the US region
/// unless `ONETIME_BASE_URL`, `ONETIME_CUSTOMER_EXTID` and
/// `ONETIME_API_TOKEN` are set. Each test creates throwaway secrets
/// with a five-minute lifetime and consumes or burns them.
@Suite("Live", .serialized, .enabled(if: LiveEnvironment.isEnabled))
struct LiveTests {
    let client = LiveEnvironment.makeClient()

    @Test("conceal, status, reveal")
    func concealAndReveal() async throws {
        let value = "onetimesecret-swift live test \(UUID().uuidString)"
        let created = try await client.secrets.conceal(value, options: ConcealOptions(timeToLive: 300))
        #expect(created.secret.state == .new)
        #expect(created.shareURL.lastPathComponent == created.secret.identifier)

        let status = try await client.secrets.status(created.secret.identifier)
        #expect(status.isAvailable)

        let bulk = try await client.secrets.statuses(of: [created.secret.identifier, "doesnotexist0000"])
        #expect(bulk.map(\.identifier) == [created.secret.identifier])

        let revealed = try await client.secrets.reveal(created.secret.identifier)
        #expect(revealed.value == value)

        let after = try await client.receipts.get(created.receipt.identifier)
        #expect(after.isRevealed)
        #expect(!after.isSecretAvailable)
    }

    @Test("passphrase is enforced and reported")
    func passphrase() async throws {
        let created = try await client.secrets.conceal(
            "guarded",
            options: ConcealOptions(timeToLive: 300, passphrase: "correct horse")
        )
        #expect(created.secret.hasPassphrase)

        do {
            _ = try await client.secrets.reveal(created.secret.identifier, passphrase: "wrong")
            Issue.record("Expected passphraseRejected")
        } catch OnetimeSecretError.passphraseRejected {
            // expected; the secret survives
        }

        let still = try await client.secrets.status(created.secret.identifier)
        #expect(still.isAvailable)

        let revealed = try await client.secrets.reveal(created.secret.identifier, passphrase: "correct horse")
        #expect(revealed.value == "guarded")
    }

    @Test("generate returns the value once and burn destroys the secret")
    func generateAndBurn() async throws {
        let generated = try await client.secrets.generate(
            options: GenerateOptions(length: 24, characterSets: CharacterSets(symbols: false), timeToLive: 300)
        )
        let value = try #require(generated.value)
        #expect(value.count == 24)

        // The disclosure is single-use.
        let again = try await client.receipts.get(generated.receipt.identifier)
        #expect(again.generatedValue == nil)

        // The server builds receipt links from its HOST setting; a local
        // server whose HOST differs from ONETIME_BASE_URL fails here.
        #expect(again.shareURL == generated.shareURL)

        try await client.receipts.burn(generated.receipt.identifier)

        let after = try await client.receipts.get(generated.receipt.identifier)
        #expect(after.isBurned)

        let status = try await client.secrets.status(generated.secret.identifier)
        #expect(!status.isAvailable)
    }

    @Test("unknown identifiers")
    func unknown() async throws {
        let status = try await client.secrets.status("thisdoesnotexist00000000")
        #expect(status == .unknown)

        await #expect(throws: OnetimeSecretError.self) {
            try await client.secrets.preview("thisdoesnotexist00000000")
        }
    }

    @Test("system status")
    func system() async throws {
        let status = try await client.system.status()
        #expect(status.isNominal)
    }
}

enum LiveEnvironment {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ONETIME_LIVE"] == "1"
    }

    static func makeClient() -> OnetimeSecretClient {
        let env = ProcessInfo.processInfo.environment
        var credentials: Credentials?
        // CI expands unset secrets to empty strings; treat those as absent so
        // the suite runs as a guest instead of sending empty credentials.
        if let username = env["ONETIME_CUSTOMER_EXTID"], let token = env["ONETIME_API_TOKEN"],
           !username.isEmpty, !token.isEmpty {
            credentials = Credentials(username: username, apiToken: token)
        }
        if let raw = env["ONETIME_BASE_URL"], !raw.isEmpty, let url = URL(string: raw) {
            return OnetimeSecretClient(baseURL: url, credentials: credentials)
        }
        return OnetimeSecretClient(region: .unitedStates, credentials: credentials)
    }
}
