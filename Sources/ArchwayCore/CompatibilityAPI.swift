import Foundation

public enum CompatibilityAPI {
    public static let publicBaseURL = "https://archway-compatibility.vercel.app"

    /// A base URL is an HTTPS origin. Endpoint paths are fixed by the API.
    public static func endpointURLs(baseURLString: String?) -> (catalog: String, reports: String) {
        let candidate = baseURLString.flatMap { URLComponents(string: $0) }
        let valid = candidate?.scheme == "https" && candidate?.host?.isEmpty == false &&
            (candidate?.port.map { (1...65535).contains($0) } ?? true) &&
            candidate?.user == nil && candidate?.password == nil &&
            candidate?.query == nil && candidate?.fragment == nil &&
            (candidate?.path.isEmpty == true || candidate?.path == "/")
        let base: String
        if valid, let baseURLString {
            base = baseURLString.hasSuffix("/") ? String(baseURLString.dropLast()) : baseURLString
        } else {
            base = publicBaseURL
        }
        return ("\(base)/api/catalog", "\(base)/api/reports")
    }
}
