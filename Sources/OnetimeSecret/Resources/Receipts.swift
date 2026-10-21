import Foundation

extension OnetimeSecretClient {
    /// Operations on receipts. Access through ``OnetimeSecretClient/receipts``.
    public struct Receipts: Sendable {
        let client: OnetimeSecretClient

        /// Fetches a receipt with its view telemetry.
        ///
        /// For a generated secret, the first fetch within the disclosure
        /// window also carries ``Receipt/generatedValue``; see
        /// ``GenerateOptions/claimValue``.
        public func get(_ identifier: String) async throws -> Receipt {
            let identifier = try OnetimeSecretClient.validated(identifier)
            let request = try client.makeRequest(
                .get,
                path: client.path("/receipt/\(identifier)", guest: "/guest/receipt/\(identifier)")
            )
            let envelope: RecordEnvelope<Receipt, Receipt.Details> = try await client.send(
                request,
                sensitivity: .mayContainSecret
            )
            var receipt = envelope.record
            if let details = envelope.details {
                receipt.apply(details)
            }
            return receipt
        }

        /// Lists the account's recent receipts, newest first. Requires
        /// credentials.
        public func list() async throws -> [Receipt] {
            guard client.isAuthenticated else {
                throw OnetimeSecretError.authenticationRequired
            }
            let request = try client.makeRequest(.get, path: "\(OnetimeSecretClient.apiPrefix)/receipt/recent")
            let envelope: RecordsEnvelope<Receipt> = try await client.send(request)
            return envelope.records
        }

        /// Destroys the secret before anyone reads it.
        ///
        /// Burning is idempotent: burning an already burned or revealed
        /// secret succeeds. The service does not return a fresh record from
        /// this call, so fetch the receipt afterwards if you need its new
        /// state.
        ///
        /// - Parameters:
        ///   - identifier: The receipt identifier (not the secret identifier).
        ///   - passphrase: Required for guests when the secret has a passphrase
        ///     (the service answers 422 "Double check that passphrase" without
        ///     it; verified against the live API). Owners with credentials
        ///     can omit it.
        /// - Throws: ``OnetimeSecretError/passphraseRejected(_:)``,
        ///   ``OnetimeSecretError/notFound(_:)``.
        public func burn(_ identifier: String, passphrase: String? = nil) async throws {
            let identifier = try OnetimeSecretClient.validated(identifier)
            let request = try client.makeRequest(
                .post,
                path: client.path("/receipt/\(identifier)/burn", guest: "/guest/receipt/\(identifier)/burn"),
                body: BurnRequest(passphrase: passphrase)
            )
            _ = try await client.send(request, passphraseGated: true)
        }

        /// Longest memo the service accepts.
        public static let memoMaximumLength = 500

        /// Sets the creator's note on a receipt. Requires credentials and
        /// ownership of the receipt.
        public func updateMemo(_ identifier: String, memo: String) async throws -> Receipt {
            guard client.isAuthenticated else {
                throw OnetimeSecretError.authenticationRequired
            }
            guard memo.count <= Self.memoMaximumLength else {
                throw OnetimeSecretError.invalidArgument("memo must be at most \(Self.memoMaximumLength) characters.")
            }
            let identifier = try OnetimeSecretClient.validated(identifier)
            let request = try client.makeRequest(
                .patch,
                path: "\(OnetimeSecretClient.apiPrefix)/receipt/\(identifier)",
                body: UpdateReceiptRequest(memo: memo)
            )
            let envelope: RecordEnvelope<Receipt, Receipt.Details> = try await client.send(request)
            var receipt = envelope.record
            if let details = envelope.details {
                receipt.apply(details)
            }
            return receipt
        }
    }

    /// Read-only information about the service. Access through
    /// ``OnetimeSecretClient/system``.
    public struct System: Sendable {
        let client: OnetimeSecretClient

        /// Service health. Useful as a connectivity check; needs no credentials.
        public func status() async throws -> SystemStatus {
            let request = try client.makeRequest(.get, path: "\(OnetimeSecretClient.apiPrefix)/status")
            return try await client.send(request)
        }

        /// Service version. Requires credentials.
        public func version() async throws -> SystemVersion {
            guard client.isAuthenticated else {
                throw OnetimeSecretError.authenticationRequired
            }
            let request = try client.makeRequest(.get, path: "\(OnetimeSecretClient.apiPrefix)/version")
            return try await client.send(request)
        }

        /// Locales the service supports.
        public func supportedLocales() async throws -> SupportedLocales {
            let request = try client.makeRequest(.get, path: "\(OnetimeSecretClient.apiPrefix)/supported-locales")
            return try await client.send(request)
        }
    }
}
