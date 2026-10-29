import Foundation
import ArchwayCore

extension Bundle {
    /// The app's resources; see `Bundle.packageResources`.
    static let archway = packageResources("Archway_Archway") ?? .module
}
