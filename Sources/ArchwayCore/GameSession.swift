import Darwin
import Foundation

/// Preparing, finding, and stopping games in the owned bottle. Shared by the CLI and the app.
extension Orchestrator {
    /// Installs the steamwebhelper shim before Steam starts. Returns whether Steam must start with the
    /// shim's launch arguments; false while Steam has not downloaded its webhelper yet.
    public func prepareSteam() throws -> Bool {
        try steamWebHelperShim(shim: SteamWebHelperShim.bundledShim()).install()
    }

    /// Restores Valve's webhelper, for comparing against the shim.
    public func removeSteamShim() throws {
        try steamWebHelperShim(shim: SteamWebHelperShim.bundledShim()).remove()
    }

    /// Removes Brick by Brick's app-local DXVK files and sets its builtin Direct3D overrides, so the staged
    /// D3DMetal runtime serves the game. Idempotent; does nothing for other backends.
    public func prepareD3DMetalGame() throws {
        guard configuration.selectedGraphicsBackend == .d3dmetal else { return }
        let sidecars = try GameGraphicsSidecars(paths: paths)
        if (try? sidecars.requireD3DMetalReady()) != nil { return }
        if let backend = try sidecars.installedBackend(), backend != .d3dmetal { try sidecars.restore() }
        if try sidecars.installedBackend() == nil { try sidecars.suspendForD3DMetal() }
        for request in try d3dMetalGameOverrides() {
            try ProcessRunner.runSetup(request, timeout: 60)
        }
        // A running wineserver writes user.reg about every 30 seconds.
        let deadline = Date().addingTimeInterval(45)
        while (try? sidecars.requireD3DMetalReady()) == nil && Date() < deadline { usleep(500_000) }
    }

    /// Starts a Windows program from anywhere on the Mac inside the owned bottle.
    public func localGameLaunch(executable: URL, label: String, gameArguments: [String] = [],
                                environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        guard bottleIsInitialized() else { throw ArchwayError.missingBottle }
        guard FileManager.default.isReadableFile(atPath: executable.path) else {
            throw ArchwayError.invalidPath("The game file is missing: \(executable.path)")
        }
        return try windowsRequest(executable, arguments: gameArguments, label: label, environment: environment)
    }

    /// Asks Windows programs with this image name to close; `force` ends them immediately.
    public func stopRequest(imageName: String, force: Bool,
                            environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        try request(arguments: ["taskkill", "/IM", imageName] + (force ? ["/F"] : []),
                    label: "game-stop", environment: environment)
    }

    public var steamAppsDirectory: URL? {
        steamExecutable()?.deletingLastPathComponent().appendingPathComponent("steamapps")
    }

    /// The installed game's folder, from the `installdir` in Steam's app manifest.
    public func steamInstallDirectory(appID: Int) -> URL? {
        guard let steamapps = steamAppsDirectory,
              let text = try? String(contentsOf: steamapps.appendingPathComponent("appmanifest_\(appID).acf"), encoding: .utf8),
              let installDir = GameProcesses.value(of: "installdir", inManifest: text) else { return nil }
        return steamapps.appendingPathComponent("common").appendingPathComponent(installDir)
    }
}

/// Finds a game's Windows processes. Wine processes show their Windows command line in the Mac process list.
public enum GameProcesses {
    public struct Running: Equatable, Sendable {
        public let pid: Int32
        public let imageName: String
    }

    /// Helpers that sit beside many games but are not the game itself.
    private static let ignoredExecutables = ["crashhandler", "crashreport", "unins", "redist", "setup", "dxsetup", "vc_"]

    /// The game's own executables in its folder and one level below, lowercased.
    public static func executableNames(in directory: URL) -> Set<String> {
        let fm = FileManager.default
        var names = Set<String>()
        let top = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in top {
            if item.pathExtension.lowercased() == "exe" {
                names.insert(item.lastPathComponent.lowercased())
            } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                for nested in (try? fm.contentsOfDirectory(atPath: item.path)) ?? [] where nested.lowercased().hasSuffix(".exe") {
                    names.insert(nested.lowercased())
                }
            }
        }
        return names.filter { name in !ignoredExecutables.contains { name.contains($0) } }
    }

    /// Processes whose command line starts with one of the image names.
    public static func running(imageNames: Set<String>) -> [Running] {
        guard !imageNames.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pid=,args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(psOutput: String(decoding: data, as: UTF8.self), imageNames: imageNames)
    }

    static func parse(psOutput: String, imageNames: Set<String>) -> [Running] {
        psOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]),
                  let image = imageName(inCommandLine: String(trimmed[space...]).trimmingCharacters(in: .whitespaces)),
                  imageNames.contains(image) else { return nil }
            return Running(pid: pid, imageName: image)
        }
    }

    /// `C:\Games\My Game\Game.exe -arg` or `/path/to/Game.exe` → `game.exe`.
    static func imageName(inCommandLine commandLine: String) -> String? {
        guard let range = commandLine.range(of: ".exe", options: .caseInsensitive) else { return nil }
        let path = commandLine[..<range.upperBound]
        let name = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? String(path)
        return name.lowercased()
    }

    static func value(of key: String, inManifest text: String) -> String? {
        guard let range = text.range(of: #""\#(key)"\s+"([^"]*)""#, options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: "\"")
        return parts.count >= 3 ? String(parts[2]) : nil
    }
}
