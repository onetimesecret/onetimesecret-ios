import Foundation

extension OnetimeSecretClient {
    /// Operations on secrets. Access through ``OnetimeSecretClient/secrets``.
    public struct Secrets: Sendable {
        let client: OnetimeSecretClient

        // MARK: Create

        /// Stores a value and returns a one-time link to it.
        ///
        /// - Parameters:
        ///   - value: The plaintext to share. Must not be empty.
        ///   - options: Lifetime, passphrase, recipient, share domain and
        ///     display type.
        /// - Returns: The links and records for the new secret.
        /// - Throws: ``OnetimeSecretError/invalidArgument(_:)`` for an empty
        ///   value, ``OnetimeSecretError/validation(_:)`` when the service
        ///   rejects a parameter, ``OnetimeSecretError/rateLimited(_:retryAfter:)``.
        public func conceal(
            _ value: String,
            options: ConcealOptions = ConcealOptions()
        ) async throws -> ConcealedSecret {
            guard !value.isEmpty else {
                throw OnetimeSecretError.invalidArgument("The secret value must not be empty.")
            }
            try validate(options)

            let payload = CreateSecretPayload(
                kind: SecretKind.conceal.rawValue,
                shareDomain: options.shareDomain ?? client.configuration.resolvedShareDomain,
                secret: value,
                ttl: options.timeToLive.map { Int($0.rounded()) },
                passphrase: options.passphrase,
                recipient: options.recipient,
                displayType: options.displayType?.rawValue
            )
            let request = try client.makeRequest(
                .post,
                path: client.path("/secret/conceal", guest: "/guest/secret/conceal"),
                body: CreateSecretRequest(secret: payload)
            )
            let envelope: RecordEnvelope<CreateRecord, NoDetails> = try await client.send(request)
            return makeConcealed(envelope.record)
        }

        /// Has the service generate a random value and returns a one-time
        /// link to it.
        ///
        /// By default the generated value is fetched from the receipt
        /// immediately, which uses up the single disclosure the service
        /// allows. See ``GenerateOptions/claimValue``.
        ///
        /// The secret exists as soon as the first request succeeds. If the
        /// follow-up receipt fetch fails (rate limit, network), this still
        /// returns the created secret, with ``GeneratedSecret/value`` `nil`
        /// and the failure in ``GeneratedSecret/claimFailure``, rather than
        /// throwing away identifiers for a secret that is now live.
        ///
        /// - Parameter options: Length, character classes, lifetime,
        ///   passphrase, recipient and share domain.
        /// - Returns: The links and records for the new secret, with the
        ///   generated value when it could be claimed.
        public func generate(options: GenerateOptions = GenerateOptions()) async throws -> GeneratedSecret {
            try validate(options)
            if let length = options.length {
                guard (GenerateOptions.minimumLength ... GenerateOptions.maximumLength).contains(length) else {
                    throw OnetimeSecretError.invalidArgument(
                        "length must be between \(GenerateOptions.minimumLength) and \(GenerateOptions.maximumLength)."
                    )
                }
            }

            let payload = CreateSecretPayload(
                kind: SecretKind.generate.rawValue,
                shareDomain: options.shareDomain ?? client.configuration.resolvedShareDomain,
                ttl: options.timeToLive.map { Int($0.rounded()) },
                passphrase: options.passphrase,
                recipient: options.recipient,
                length: options.length,
                characterSets: options.characterSets
            )
            let request = try client.makeRequest(
                .post,
                path: client.path("/secret/generate", guest: "/guest/secret/generate"),
                body: CreateSecretRequest(secret: payload)
            )
            let envelope: RecordEnvelope<CreateRecord, NoDetails> = try await client.send(request)
            let concealed = makeConcealed(envelope.record)

            var value: String?
            var receipt = concealed.receipt
            var claimFailure: ClaimFailure?
            if options.claimValue {
                do {
                    let fetched = try await client.receipts.get(receipt.identifier)
                    value = fetched.generatedValue
                    receipt = fetched
                } catch let error as OnetimeSecretError {
                    claimFailure = ClaimFailure(error)
                }
            }

            return GeneratedSecret(
                secret: concealed.secret,
                receipt: receipt,
                shareDomain: concealed.shareDomain,
                shareURL: concealed.shareURL,
                receiptURL: concealed.receiptURL,
                burnURL: concealed.burnURL,
                value: value,
                claimFailure: claimFailure
            )
        }

        // MARK: Inspect

        /// Checks whether a secret exists and whether it can still be
        /// revealed, without touching it.
        ///
        /// The check is recorded on the creator's receipt as telemetry but
        /// does not change the secret's state.
        public func status(_ identifier: String) async throws -> SecretStatus {
            let identifier = try validated(identifier)
            let request = try client.makeRequest(.get, path: "\(Self.apiPrefix)/secret/\(identifier)/status")
            let envelope: RecordEnvelope<StatusRecord, StatusDetails> = try await client.send(request)
            switch envelope.record {
            case .unknown:
                return .unknown
            case let .secret(secret):
                return .known(secret, expiresIn: envelope.details?.currentExpiration)
            }
        }

        /// Checks several secrets at once. Secrets the service has no record
        /// of are omitted from the result.
        public func statuses(of identifiers: [String]) async throws -> [Secret] {
            let identifiers = try identifiers.map(validated)
            guard !identifiers.isEmpty else { return [] }
            let request = try client.makeRequest(
                .post,
                path: "\(Self.apiPrefix)/secret/status",
                body: ListStatusRequest(identifiers: identifiers)
            )
            let envelope: RecordsEnvelope<Secret> = try await client.send(request)
            return envelope.records
        }

        /// Fetches a secret's metadata the way the recipient's confirmation
        /// page does: whether it needs a passphrase, how it is displayed, and
        /// so on. Does not reveal the value.
        ///
        /// Unlike ``status(_:)``, this marks the secret as previewed on the
        /// creator's receipt.
        public func preview(_ identifier: String) async throws -> Secret {
            let identifier = try validated(identifier)
            let request = try client.makeRequest(
                .get,
                path: client.path("/secret/\(identifier)", guest: "/guest/secret/\(identifier)")
            )
            let envelope: RecordEnvelope<Secret, NoDetails> = try await client.send(
                request,
                sensitivity: .mayContainSecret
            )
            return envelope.record
        }

        // MARK: Consume

        /// Reveals a secret's value. This is the one-time read: the value is
        /// returned and the secret is destroyed.
        ///
        /// - Parameters:
        ///   - identifier: The secret identifier from the share link.
        ///   - passphrase: Required when ``Secret/hasPassphrase`` is `true`.
        /// - Throws: ``OnetimeSecretError/passphraseRejected(_:)`` when the
        ///   passphrase is missing or wrong (the secret survives),
        ///   ``OnetimeSecretError/notFound(_:)`` when it is already gone.
        public func reveal(_ identifier: String, passphrase: String? = nil) async throws -> RevealedSecret {
            let identifier = try validated(identifier)
            let request = try client.makeRequest(
                .post,
                path: client.path("/secret/\(identifier)/reveal", guest: "/guest/secret/\(identifier)/reveal"),
                body: RevealRequest(passphrase: passphrase)
            )
            let envelope: RecordEnvelope<Secret, NoDetails> = try await client.send(
                request,
                passphraseGated: true,
                sensitivity: .mayContainSecret
            )
            guard let value = envelope.record.value else {
                throw OnetimeSecretError.decoding(
                    DecodingError.valueNotFound(
                        String.self,
                        .init(codingPath: [], debugDescription: "Reveal succeeded but no secret_value was returned.")
                    ),
                    body: Data()
                )
            }
            return RevealedSecret(value: value, secret: envelope.record)
        }

        // MARK: Helpers

        /// Share links live on the custom domain when the API applied one
        /// (always https), otherwise on the configured origin, scheme and
        /// port included, so self-hosted and local installs get usable links.
        private func makeConcealed(_ record: CreateRecord) -> ConcealedSecret {
            let base = client.configuration.baseURL
            let secretPath = "secret/\(record.secret.identifier)"
            let shareURL: URL = if let domain = record.shareDomain,
                                   let custom = URL(string: "https://\(domain)/\(secretPath)") {
                custom
            } else {
                base.appendingPathComponent(secretPath)
            }
            return ConcealedSecret(
                secret: record.secret,
                receipt: record.receipt,
                shareDomain: record.shareDomain,
                shareURL: shareURL,
                receiptURL: base.appendingPathComponent("receipt/\(record.receipt.identifier)"),
                burnURL: base.appendingPathComponent("receipt/\(record.receipt.identifier)/burn")
            )
        }

        private func validate(_ options: some SecretCreationOptions) throws {
            if let ttl = options.timeToLive, ttl <= 0 {
                throw OnetimeSecretError.invalidArgument("timeToLive must be positive.")
            }
            if let passphrase = options.passphrase, passphrase.isEmpty {
                throw OnetimeSecretError.invalidArgument("passphrase must not be empty when set.")
            }
            if options.recipient != nil, !client.isAuthenticated {
                throw OnetimeSecretError.authenticationRequired
            }
        }
    }
}

extension OnetimeSecretClient {
    /// Accepts a bare identifier or a full share, receipt or burn link and
    /// returns the identifier. Rejects anything that could alter the request
    /// path.
    static func validated(_ identifier: String) throws -> String {
        var candidate = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.contains("://"), let url = URL(string: candidate) {
            // ".../secret/<id>", ".../receipt/<id>", ".../receipt/<id>/burn"
            let components = url.pathComponents.filter { $0 != "/" }
            if components.last == "burn", components.count >= 2 {
                candidate = components[components.count - 2]
            } else {
                candidate = components.last ?? ""
            }
        }
        guard !candidate.isEmpty else {
            throw OnetimeSecretError.invalidArgument("The identifier must not be empty.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard candidate.unicodeScalars.allSatisfy(allowed.contains) else {
            throw OnetimeSecretError.invalidArgument("The identifier contains characters that are not allowed.")
        }
        return candidate
    }
}

extension OnetimeSecretClient.Secrets {
    static var apiPrefix: String { OnetimeSecretClient.apiPrefix }

    func validated(_ identifier: String) throws -> String {
        try OnetimeSecretClient.validated(identifier)
    }
}
