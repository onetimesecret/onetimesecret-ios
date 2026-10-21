public import Foundation

/// A hosted Onetime Secret region. Each region stores data only within its
/// jurisdiction; secrets created in one region cannot be read from another.
public enum Region: String, Sendable, Hashable, CaseIterable, Codable {
    /// `https://us.onetimesecret.com`
    case unitedStates = "us"
    /// `https://eu.onetimesecret.com`
    case europe = "eu"
    /// `https://ca.onetimesecret.com`
    case canada = "ca"
    /// `https://uk.onetimesecret.com`
    case unitedKingdom = "uk"
    /// `https://nz.onetimesecret.com`
    case newZealand = "nz"

    /// The API origin for the region.
    public var baseURL: URL {
        guard let url = URL(string: "https://\(rawValue).onetimesecret.com") else {
            preconditionFailure("Region host for \(rawValue) must be a valid URL")
        }
        return url
    }
}
