extension OnetimeSecretClient {
    /// The SDK version, kept in sync with the git tag by the release workflow.
    public static let version = "0.1.0"

    /// Value sent in the `X-Onetime-Client` header: `swift:<language>/<sdk>`,
    /// the same shape as `ruby:<ruby>/<sdk>` from onetime-ruby.
    static let clientHeader = "swift:\(swiftVersion)/\(version)"

    /// Swift language version the SDK was compiled with.
    static let swiftVersion: String = {
        #if swift(>=6.4)
            return "6.4"
        #elseif swift(>=6.3)
            return "6.3"
        #elseif swift(>=6.2)
            return "6.2"
        #elseif swift(>=6.1)
            return "6.1"
        #else
            return "6.0"
        #endif
    }()

    /// Value sent in the `User-Agent` header. Names the SDK repository, as
    /// the other official clients do, so the service can tell them apart.
    static let userAgent: String = {
        #if os(iOS)
            let platform = "iOS"
        #elseif os(macOS)
            let platform = "macOS"
        #elseif os(tvOS)
            let platform = "tvOS"
        #elseif os(watchOS)
            let platform = "watchOS"
        #elseif os(visionOS)
            let platform = "visionOS"
        #elseif os(Linux)
            let platform = "Linux"
        #else
            let platform = "unknown"
        #endif
        return "onetimesecret-ios/\(version) (Swift/\(swiftVersion); \(platform))"
    }()
}
