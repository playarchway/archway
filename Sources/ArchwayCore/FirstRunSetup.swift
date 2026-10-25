import CryptoKit
import Foundation

/// The Wine runtime package Archway downloads on first start (see scripts/package-runtime.sh).
public struct RuntimeRelease: Codable, Equatable, Sendable {
    public let version: String
    public let url: URL
    public let sha256: String
    public let size: Int64

    public init(version: String, url: URL, sha256: String, size: Int64) {
        self.version = version
        self.url = url
        self.sha256 = sha256
        self.size = size
    }

    /// The release this build of Archway ships with.
    public static func bundled() throws -> RuntimeRelease {
        guard let file = Bundle.module.url(forResource: "runtime", withExtension: "json") else {
            throw ArchwayError.invalidPath("Archway's runtime description is missing from its resources.")
        }
        return try JSONDecoder().decode(RuntimeRelease.self, from: Data(contentsOf: file))
    }

    public func directory(in paths: AppPaths) -> URL {
        paths.dataDirectory.appendingPathComponent("runtime-overlays/archway-wine-\(version)")
    }

    public func wineRoot(in paths: AppPaths) -> URL { directory(in: paths).appendingPathComponent("Wine") }

    public func isInstalled(in paths: AppPaths) -> Bool {
        FileManager.default.isExecutableFile(atPath: wineRoot(in: paths).appendingPathComponent("bin/wine").path)
    }

    /// The package carries D3DMetal staged in `Wine/lib`, which also has the layout of GPTK's `redist/lib`.
    public func configuration(in paths: AppPaths) -> Configuration {
        let root = wineRoot(in: paths)
        let lib = root.appendingPathComponent("lib").path
        return Configuration(wine: root.appendingPathComponent("bin/wine").path,
                             wineserver: root.appendingPathComponent("bin/wineserver").path,
                             libraryDirectory: lib, graphicsBackend: .d3dmetal, d3dMetalDirectory: lib)
    }

    /// Checks a downloaded archive and unpacks it into the data directory. A failed attempt leaves nothing behind.
    public func install(archive: URL, in paths: AppPaths) throws {
        guard try Self.sha256(of: archive) == sha256.lowercased() else {
            throw ArchwayError.invalidPath("The downloaded runtime doesn't match its checksum. Try again.")
        }
        try paths.ensureDirectories()
        let fm = FileManager.default
        let target = directory(in: paths)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).partial")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try Self.run("/usr/bin/tar", ["-xJf", archive.path, "-C", staging.path])
            guard fm.isExecutableFile(atPath: staging.appendingPathComponent("Wine/bin/wine").path) else {
                throw ArchwayError.invalidPath("The runtime package has no Wine in it.")
            }
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging, to: target)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ArchwayError.processFailed(URL(fileURLWithPath: executable).lastPathComponent, process.terminationStatus)
        }
    }
}

/// Wine and its runtime are x86_64 programs, so Apple silicon Macs need Rosetta.
public enum Rosetta {
    public static func isInstalled() -> Bool {
        (try? RuntimeRelease.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])) != nil
    }

    /// Asks for an administrator password through the system dialog, then installs Rosetta.
    public static func install() throws {
        try RuntimeRelease.run("/usr/bin/osascript", ["-e",
            "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"])
    }
}

/// Valve's Windows Steam installer.
public enum SteamSetup {
    public static let installerURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    /// Runs the downloaded installer silently. It returns within seconds and does not start Steam.
    public static func install(_ installer: URL, with orchestrator: Orchestrator) throws {
        let header = try FileHandle(forReadingFrom: installer).read(upToCount: 2)
        guard header == Data("MZ".utf8) else {
            throw ArchwayError.invalidPath("The downloaded Steam installer isn't a Windows program.")
        }
        try ProcessRunner.runSetup(orchestrator.steamInstaller(installer, silent: true), timeout: 300)
        guard orchestrator.steamExecutable() != nil else { throw ArchwayError.missingSteam }
    }
}

extension Orchestrator {
    /// Creates the owned bottle, as `archway init-bottle` does.
    public func initializeBottle() throws {
        guard !bottleIsInitialized() else { return }
        let request = try bottleInit()
        try prepareBottleInitialization()
        try ProcessRunner.runSetup(request, timeout: 300)
        try markBottleReady()
    }
}
