public import Foundation

/// Connection settings for an ``OnetimeSecretClient``.
public struct Configuration: Sendable, Hashable {
    /// Origin of the API, without a trailing path. For example
    /// `https://eu.onetimesecret.com`.
    ///
    /// Plain `http://` is accepted for guest use and for `localhost`. With
    /// ``credentials`` set, requests to a non-loopback `http://` origin are
    /// refused, because HTTP Basic would send the token in the clear.
    public var baseURL: URL

    /// Account credentials. `nil` makes every request as a guest.
    public var credentials: Credentials?

    /// Domain that share links are generated for.
    ///
    /// Accounts with custom domains can set this to one of them. When `nil`,
    /// the host of ``baseURL`` is used, which is correct for the hosted
    /// regions and for most self-hosted installations.
    public var shareDomain: String?

    /// Per-request timeout, in seconds. Defaults to 30.
    public var timeout: TimeInterval

    /// Extra headers to send with every request. Headers the SDK sets
    /// (`Accept`, `Content-Type`, `Authorization`, `User-Agent`,
    /// `X-Onetime-Client`) cannot be overridden; entries with those names,
    /// in any letter case, are ignored.
    public var additionalHeaders: [String: String]

    /// Creates a configuration for an arbitrary installation.
    ///
    /// - Parameters:
    ///   - baseURL: Origin of the installation. A trailing slash is removed.
    ///   - credentials: Optional account credentials.
    ///   - shareDomain: Optional custom share domain.
    ///   - timeout: Per-request timeout in seconds.
    ///   - additionalHeaders: Extra headers for every request.
    public init(
        baseURL: URL,
        credentials: Credentials? = nil,
        shareDomain: String? = nil,
        timeout: TimeInterval = 30,
        additionalHeaders: [String: String] = [:]
    ) {
        self.baseURL = Self.normalize(baseURL)
        self.credentials = credentials
        self.shareDomain = shareDomain
        self.timeout = timeout
        self.additionalHeaders = additionalHeaders
    }

    /// Creates a configuration for a hosted region.
    public init(
        region: Region,
        credentials: Credentials? = nil,
        shareDomain: String? = nil,
        timeout: TimeInterval = 30,
        additionalHeaders: [String: String] = [:]
    ) {
        self.init(
            baseURL: region.baseURL,
            credentials: credentials,
            shareDomain: shareDomain,
            timeout: timeout,
            additionalHeaders: additionalHeaders
        )
    }

    /// The share domain that is sent to the API: ``shareDomain`` if set,
    /// otherwise the host of ``baseURL``.
    public var resolvedShareDomain: String {
        if let shareDomain, !shareDomain.isEmpty {
            return shareDomain
        }
        return baseURL.host ?? ""
    }

    private static func normalize(_ url: URL) -> URL {
        var string = url.absoluteString
        while string.hasSuffix("/") {
            string.removeLast()
        }
        return URL(string: string) ?? url
    }
}
