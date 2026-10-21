import Foundation
import OnetimeSecret

/// Round-trips a secret against a real server: conceal it, read the receipt,
/// reveal it once, and confirm the receipt records the reveal.
///
///     swift run --package-path Examples/Roundtrip
///
/// Environment:
///
///     ONETIME_BASE_URL         API origin. Defaults to https://eu.onetimesecret.com.
///     ONETIME_CUSTOMER_EXTID   Account external ID (optional).
///     ONETIME_API_TOKEN        API token (optional).
///
/// Without both credentials every request is made as a guest. A local
/// server works too: `ONETIME_BASE_URL=http://localhost:3000`.
@main
enum Roundtrip {
    static func main() async {
        do {
            try await run()
        } catch let error as OnetimeSecretError {
            let requestID = error.requestID.map { " (request \($0))" } ?? ""
            fail((error.errorDescription ?? "\(error)") + requestID)
        } catch {
            fail("\(error)")
        }
    }

    static func run() async throws {
        let client = makeClient()
        let mode = client.isAuthenticated ? "account" : "guest"
        print("server:        \(client.configuration.baseURL) (\(mode))")

        // Creator side: store the value and get the links.
        let created = try await client.secrets.conceal(
            "roundtrip example, created \(Date())",
            options: ConcealOptions(timeToLive: 300)
        )
        print("share link:    \(created.shareURL)")
        print("receipt link:  \(created.receiptURL)")

        // The receipt is the creator's view. Nothing has been consumed yet.
        let before = try await client.receipts.get(created.receipt.identifier)
        print("before reveal: receipt \(before.state), secret available: \(before.isSecretAvailable)")

        // A status check is the recipient-side equivalent and is also non-destructive.
        let status = try await client.secrets.status(created.secret.identifier)
        print("status:        \(status.secret.map { "\($0.state)" } ?? "unknown")")

        // Recipient side: the one-time read.
        let revealed = try await client.secrets.reveal(created.secret.identifier)
        print("revealed:      \(revealed.value)")

        // The receipt now says so, and the secret is gone.
        let after = try await client.receipts.get(created.receipt.identifier)
        print("after reveal:  receipt \(after.state), secret available: \(after.isSecretAvailable)")
        let gone = try await client.secrets.status(created.secret.identifier)
        print("status:        \(gone.secret.map { "\($0.state)" } ?? "unknown")")

        guard before.isSecretAvailable, after.isRevealed, !after.isSecretAvailable, !gone.isAvailable else {
            fail("the receipt did not change state as expected")
        }
        print("ok")
    }

    static func makeClient() -> OnetimeSecretClient {
        let env = ProcessInfo.processInfo.environment
        var credentials: Credentials?
        if let extid = env["ONETIME_CUSTOMER_EXTID"], let token = env["ONETIME_API_TOKEN"],
           !extid.isEmpty, !token.isEmpty {
            credentials = Credentials(username: extid, apiToken: token)
        }
        if let raw = env["ONETIME_BASE_URL"], !raw.isEmpty {
            guard let url = URL(string: raw), url.scheme != nil, url.host != nil else {
                fail("ONETIME_BASE_URL is not an absolute URL: \(raw)")
            }
            return OnetimeSecretClient(baseURL: url, credentials: credentials)
        }
        return OnetimeSecretClient(region: .europe, credentials: credentials)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
