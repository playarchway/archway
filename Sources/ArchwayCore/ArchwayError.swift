import Foundation

public enum ArchwayError: Error, LocalizedError, Equatable {
    case invalidPath(String)
    case invalidAppID(String)
    case missingConfiguration
    case missingBottle
    case missingSteam
    case processFailed(String, Int32)
    case processTimedOut(String, TimeInterval)
    case unownedBottle
    case missingWineserver

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let detail): return detail
        case .invalidAppID(let value): return "Invalid Steam app ID '\(value)'; use a positive 32-bit integer."
        case .missingConfiguration: return "Wine is not configured. Run: archway configure --wine /absolute/path/to/wine"
        case .missingBottle: return "The Archway bottle is not initialized. Run: archway init-bottle"
        case .missingSteam: return "Windows Steam is not installed in the Archway bottle. Run: archway install-steam --installer /absolute/path/to/SteamSetup.exe"
        case .processFailed(let command, let code): return "\(command) failed with exit code \(code). Check the log path shown above."
        case .processTimedOut(let command, let seconds): return "\(command) timed out after \(Int(seconds)) seconds. Check the log and bottle state before retrying."
        case .unownedBottle: return "Bottle path contains an existing Wine prefix without an Archway ownership marker. Choose a fresh --data-dir; Archway will not adopt or modify it."
        case .missingWineserver: return "A configured wineserver is required to confirm Steam shutdown. Run configure with --wine and --wineserver paths."
        }
    }
}
