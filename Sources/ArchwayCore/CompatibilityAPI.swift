import Foundation

public enum CompatibilityAPI {
    /// The service's endpoints under a base URL, an HTTPS origin that builds embed from `ARCHWAY_API_BASE_URL`.
    /// Nil without a valid base URL; the app then has no compatibility service until one is set in Settings.
    public static func endpointURLs(baseURLString: String?) -> (catalog: String, reports: String)? {
        guard let baseURLString, let candidate = URLComponents(string: baseURLString),
              candidate.scheme == "https", candidate.host?.isEmpty == false,
              candidate.port.map({ (1...65535).contains($0) }) ?? true,
              candidate.user == nil, candidate.password == nil, candidate.query == nil, candidate.fragment == nil,
              candidate.path.isEmpty || candidate.path == "/" else { return nil }
        let base = baseURLString.hasSuffix("/") ? String(baseURLString.dropLast()) : baseURLString
        return ("\(base)/v1/catalog", "\(base)/v1/reports")
    }
}
