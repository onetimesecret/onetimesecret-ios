public import Foundation

/// The entry point to the Onetime Secret API.
///
/// A client is a lightweight, immutable value. Create one per base URL and
/// credential pair and share it freely; it is safe to use from any task or
/// actor.
///
/// ```swift
/// let client = OnetimeSecretClient(region: .europe)
/// let link = try await client.secrets.conceal("the launch code is 0000")
/// print(link.shareURL)
/// ```
///
/// Requests are made as a guest unless ``Configuration/credentials`` are
/// set. Guest requests are rate limited more aggressively and cannot list
/// or edit receipts.
public struct OnetimeSecretClient: Sendable {
    /// The configuration this client was created with.
    public let configuration: Configuration

    /// The transport used to send HTTP requests.
    public let transport: any HTTPTransport

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - configuration: Base URL, credentials and request defaults.
    ///   - transport: The HTTP transport. Defaults to
    ///     ``URLSessionTransport/shared``. Supply your own to add logging,
    ///     retries, custom TLS handling, or to stub the network in tests.
    public init(
        configuration: Configuration,
        transport: any HTTPTransport = URLSessionTransport.shared
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Creates a client for one of the hosted regions.
    ///
    /// - Parameters:
    ///   - region: The hosted region to talk to. Defaults to ``Region/unitedStates``.
    ///   - credentials: Optional account credentials. Without them the client
    ///     acts as a guest.
    ///   - transport: The HTTP transport. Defaults to ``URLSessionTransport/shared``.
    public init(
        region: Region = .unitedStates,
        credentials: Credentials? = nil,
        transport: any HTTPTransport = URLSessionTransport.shared
    ) {
        self.init(configuration: Configuration(region: region, credentials: credentials), transport: transport)
    }

    /// Creates a client for a self-hosted installation.
    ///
    /// - Parameters:
    ///   - baseURL: Origin of the installation, for example `https://secrets.example.com`.
    ///   - credentials: Optional account credentials.
    ///   - transport: The HTTP transport. Defaults to ``URLSessionTransport/shared``.
    public init(
        baseURL: URL,
        credentials: Credentials? = nil,
        transport: any HTTPTransport = URLSessionTransport.shared
    ) {
        self.init(configuration: Configuration(baseURL: baseURL, credentials: credentials), transport: transport)
    }

    /// Whether the client sends account credentials with its requests.
    public var isAuthenticated: Bool {
        configuration.credentials != nil
    }

    /// Operations on secrets: create, inspect, and reveal them.
    public var secrets: Secrets { Secrets(client: self) }

    /// Operations on receipts: the creator-side record of a secret.
    public var receipts: Receipts { Receipts(client: self) }

    /// Read-only information about the service itself.
    public var system: System { System(client: self) }
}
