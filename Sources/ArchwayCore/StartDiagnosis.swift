import Foundation

/// A known reason a game didn't start or closed right away, read from what Wine and the game wrote to the logs.
public enum StartDiagnosis: Equatable, Sendable {
    /// A DLL the program imports is nowhere to be found. `neededBy` is the Windows path of the program.
    case missingDLL(name: String, neededBy: String)
    /// The game started an anti-cheat that needs a Windows kernel driver.
    case antiCheat(name: String)
    /// A .NET program found no Wine Mono.
    case missingWineMono
    /// The game couldn't reach Steam through the Steamworks API.
    case steamUnavailable
    /// The game crashed.
    case crashed

    /// The most telling reason in the log text, or nil if nothing known matches. Missing pieces come before the
    /// crash they cause.
    public static func diagnose(_ log: String) -> StartDiagnosis? {
        if let match = log.firstMatch(of: /err:module:import_dll Library (\S+) \(which is needed by L"([^"]+)"\) not found/) {
            return .missingDLL(name: String(match.1), neededBy: String(match.2).replacingOccurrences(of: #"\\"#, with: #"\"#))
        }
        for (marker, name) in [("easyanticheat", "Easy Anti-Cheat"), ("start_protected_game", "Easy Anti-Cheat"),
                               ("beservice", "BattlEye"), ("battleye", "BattlEye"), ("vgc.exe", "Vanguard")]
        where log.range(of: marker, options: .caseInsensitive) != nil {
            return .antiCheat(name: name)
        }
        if log.contains("Wine Mono is not installed") { return .missingWineMono }
        if log.contains("SteamAPI_Init() failed") { return .steamUnavailable }
        if log.contains("Unhandled page fault") || log.contains("Unhandled exception") || log.contains("Unhandled stack overflow") {
            return .crashed
        }
        return nil
    }

    /// Where `.missingDLL`'s program lies in the bottle, to read its architecture.
    public static func file(forWindowsPath path: String, bottle: URL) -> URL? {
        guard path.count > 3, path.uppercased().hasPrefix(#"C:\"#) else { return nil }
        let relative = path.dropFirst(3).split(separator: #"\"#).joined(separator: "/")
        return bottle.appendingPathComponent("drive_c").appendingPathComponent(relative)
    }
}

/// The logs' lengths at one moment, to read only what was written after it: Steam passes a game's output to
/// whichever log its own Wine process writes to, so a game's lines may land in any of them.
public struct LogSnapshot: Sendable {
    private let directory: URL
    private let sizes: [String: UInt64]

    public init(directory: URL) {
        self.directory = directory
        var sizes: [String: UInt64] = [:]
        for file in Self.logs(in: directory) {
            sizes[file.lastPathComponent] = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        }
        self.sizes = sizes
    }

    /// Everything the logs gained since the snapshot, at most the last megabyte of each.
    public func newText() -> String {
        Self.logs(in: directory).compactMap { file -> String? in
            guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            defer { try? handle.close() }
            let end = (try? handle.seekToEnd()) ?? 0
            let start = max(sizes[file.lastPathComponent] ?? 0, end > 1 << 20 ? end - (1 << 20) : 0)
            guard end > start, (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n")
    }

    private static func logs(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension == "log" }
    }
}
