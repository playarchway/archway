import Foundation
import ArchwayCore

extension AppPaths {
    /// Archway's data directory. ARCHWAY_DATA_DIR points the app at another one, for example to try a first start.
    static func app() throws -> AppPaths {
        if let custom = ProcessInfo.processInfo.environment["ARCHWAY_DATA_DIR"] {
            return try AppPaths(dataDirectory: URL(fileURLWithPath: custom))
        }
        return try AppPaths()
    }
}
