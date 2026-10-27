import Foundation

public struct LaunchRequest: Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var log: URL
    public var label: String
    public var workingDirectory: URL?

    public init(executable: URL, arguments: [String], environment: [String: String], log: URL, label: String,
                workingDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.log = log
        self.label = label
        self.workingDirectory = workingDirectory
    }
}

public enum SteamWineRenderer: String {
    case gl

    public static func parse(_ value: String) throws -> Self {
        guard let renderer = Self(rawValue: value) else {
            throw ArchwayError.invalidPath("Unsupported Wine renderer '\(value)'; use gl.")
        }
        return renderer
    }
}

public struct Orchestrator {
    public let paths: AppPaths
    public let configuration: Configuration

    public init(paths: AppPaths, configuration: Configuration) {
        self.paths = paths
        self.configuration = configuration
    }

    /// With the saved configuration; throws `missingConfiguration` before Archway is configured.
    public init(paths: AppPaths) throws {
        guard let configuration = try ConfigStore(paths: paths).load() else { throw ArchwayError.missingConfiguration }
        self.init(paths: paths, configuration: configuration)
    }

    public static func appID(_ raw: String) throws -> UInt32 {
        guard let id = UInt32(raw), id > 0 else { throw ArchwayError.invalidAppID(raw) }
        return id
    }

    public static func cefDebugPort(_ raw: String) throws -> UInt16 {
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = UInt16(raw), port >= 1024 else {
            throw ArchwayError.invalidPath("Invalid CEF debug port '\(raw)'; use 1024 through 65535.")
        }
        return port
    }

    public func bottleIsInitialized() -> Bool {
        bottleMarker()?.state == .ready && wineRegistryExists()
    }

    /// Whether this bottle's wineserver runs. It listens in /tmp/.wine-<uid>/server-<device>-<inode>/socket
    /// and removes the socket when it exits.
    public func wineserverIsRunning() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: paths.bottle.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return false }
        let socket = "/tmp/.wine-\(getuid())/server-\(String(device, radix: 16))-\(String(inode, radix: 16))/socket"
        return FileManager.default.fileExists(atPath: socket)
    }

    public func bottleMarker() -> BottleMarker? {
        let marker = paths.bottle.appendingPathComponent(".archway-bottle.json")
        guard (try? marker.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let data = try? Data(contentsOf: marker),
              let decoded = try? JSONDecoder().decode(BottleMarker.self, from: data),
              decoded.version == 1 else { return nil }
        return decoded
    }

    public func prepareBottleInitialization() throws {
        try paths.validateBottleScope()
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.bottle.path), bottleMarker() == nil {
            let contents = try fm.contentsOfDirectory(atPath: paths.bottle.path)
            guard contents.isEmpty else { throw ArchwayError.unownedBottle }
        }
        try fm.createDirectory(at: paths.bottle, withIntermediateDirectories: true)
        try saveBottleMarker(.init(state: .initializing))
    }

    public func markBottleReady(timeout: TimeInterval = 30) throws {
        guard bottleMarker()?.state == .initializing else {
            throw ArchwayError.invalidPath("Wine exited without a valid owned bottle; inspect the bottle log.")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !wineRegistryExists() && Date() < deadline { usleep(200_000) }
        guard wineRegistryExists() else {
            throw ArchwayError.invalidPath("Wine exited but its registry did not appear within \(Int(timeout)) seconds; inspect the bottle log and retry init-bottle.")
        }
        try saveBottleMarker(.init(state: .ready))
    }

    private func wineRegistryExists() -> Bool {
        let file = paths.bottle.appendingPathComponent("system.reg")
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) > 0
    }

    private func saveBottleMarker(_ marker: BottleMarker) throws {
        let data = try JSONEncoder().encode(marker)
        try data.write(to: paths.bottle.appendingPathComponent(".archway-bottle.json"), options: [.atomic])
    }

    public func steamExecutable() -> URL? {
        let candidates = [paths.steamApps.deletingLastPathComponent(),
                          paths.bottle.appendingPathComponent("drive_c/Program Files/Steam")]
        let bottleRoot = paths.bottle.resolvingSymlinksInPath().path + "/"
        for candidate in candidates {
            let file = candidate.appendingPathComponent("steam.exe")
            let resolved = file.resolvingSymlinksInPath()
            if resolved.path.hasPrefix(bottleRoot), FileManager.default.isReadableFile(atPath: file.path),
               (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return file
            }
        }
        return nil
    }

    public func request(arguments: [String], label: String, environment source: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        let wine = try PathValidator.executable(configuration.wine)
        let environment = try runtimeEnvironment(source)
        return LaunchRequest(executable: wine, arguments: arguments, environment: environment,
                             log: paths.logs.appendingPathComponent("\(label).log"), label: label)
    }

    func windowsRequest(_ windowsExecutable: URL, arguments: [String], label: String,
                                environment: [String: String]) throws -> LaunchRequest {
        var request = try request(arguments: [windowsExecutable.path] + arguments, label: label, environment: environment)
        request.workingDirectory = windowsExecutable.deletingLastPathComponent()
        return request
    }

    private func runtimeEnvironment(_ source: [String: String]) throws -> [String: String] {
        try paths.validateBottleScope()
        try configuration.validateGraphicsSelection(paths: paths)
        var environment = source.filter { key, _ in
            let upper = key.uppercased()
            return !upper.hasPrefix("WINE") && !upper.hasPrefix("STEAM_") && !upper.hasPrefix("DXVK") && !upper.hasPrefix("VK_") && !upper.hasPrefix("DYLD_")
        }
        environment["WINEPREFIX"] = paths.bottle.path
        if let server = configuration.wineserver {
            environment["WINESERVER"] = try PathValidator.executable(server).path
        }
        if let directory = configuration.libraryDirectory {
            environment["DYLD_LIBRARY_PATH"] = try PathValidator.libraryDirectory(directory).path
        }
        if configuration.selectedGraphicsBackend == .dxvk,
           let files = try configuration.validatedGraphicsFiles() {
            environment["DXVK_CONFIG_FILE"] = files.dxvk.path
            environment["VK_ICD_FILENAMES"] = files.icd.path
        }
        return environment
    }

    public func bottleInit(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        if FileManager.default.fileExists(atPath: paths.bottle.path), bottleMarker() == nil,
           let contents = try? FileManager.default.contentsOfDirectory(atPath: paths.bottle.path), !contents.isEmpty {
            throw ArchwayError.unownedBottle
        }
        return try request(arguments: ["wineboot", "-u"], label: "bottle-init", environment: environment)
    }

    public func steamInstaller(_ installer: URL, silent: Bool = false,
                               environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        guard bottleIsInitialized() else { throw ArchwayError.missingBottle }
        let file = try PathValidator.installer(installer.path)
        return try windowsRequest(file, arguments: silent ? ["/S"] : [],
                                  label: "steam-installer", environment: environment)
    }

    public func steamWebHelperShim(shim: Data) throws -> SteamWebHelperShim {
        let directory = try requiredSteam().deletingLastPathComponent().appendingPathComponent("bin/cef/cef.win64")
        guard directory.resolvingSymlinksInPath().path.hasPrefix(paths.bottle.resolvingSymlinksInPath().path + "/") else {
            throw ArchwayError.invalidPath("Steam's webhelper directory must stay inside the owned bottle: \(directory.path)")
        }
        return SteamWebHelperShim(directory: directory, shim: shim)
    }

    public func steamOpen(disableCEFGPU: Bool = false, enableCEFDebugging: Bool = false, cefDebugPort: UInt16? = nil,
                          wineRenderer: SteamWineRenderer? = nil, webHelperShim: Bool = true, silent: Bool = false,
                          environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        guard cefDebugPort == nil || enableCEFDebugging else {
            throw ArchwayError.invalidPath("--cef-debug-port requires --cef-debugging.")
        }
        guard cefDebugPort.map({ $0 >= 1024 }) ?? true else {
            throw ArchwayError.invalidPath("CEF debug port must be 1024 through 65535.")
        }
        let steam = try requiredSteam()
        var flags: [String] = webHelperShim ? SteamWebHelperShim.launchArguments : []
        if silent { flags.append("-silent") }
        if disableCEFGPU { flags.append("-cef-disable-gpu") }
        if enableCEFDebugging { flags.append("-cef-enable-debugging") }
        if let cefDebugPort { flags += ["-devtools-port", String(cefDebugPort)] }
        var request = try windowsRequest(steam, arguments: flags, label: "steam-open", environment: environment)
        if let wineRenderer { request.environment["WINE_D3D_CONFIG"] = "renderer=\(wineRenderer.rawValue)" }
        return request
    }

    public func steamShutdown(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        let steam = try requiredSteam()
        return try windowsRequest(steam, arguments: ["-shutdown"], label: "steam-shutdown", environment: environment)
    }

    public func wineserverWait(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        guard bottleIsInitialized() else { throw ArchwayError.missingBottle }
        guard let server = configuration.wineserver else { throw ArchwayError.missingWineserver }
        return LaunchRequest(executable: try PathValidator.executable(server), arguments: ["-w"],
                             environment: try runtimeEnvironment(environment),
                             log: paths.logs.appendingPathComponent("steam-shutdown-wait.log"), label: "steam-shutdown-wait")
    }

    public func gameInstall(appID: UInt32, webHelperShim: Bool = true,
                            environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        let steam = try requiredSteam()
        // Steam may not be running yet, so these requests can start it like open-steam.
        let shimArguments = webHelperShim ? SteamWebHelperShim.launchArguments : []
        return try windowsRequest(steam, arguments: shimArguments + ["steam://install/\(appID)"],
                                  label: "game-install-\(appID)", environment: environment)
    }

    /// Wine builtin overrides that route only these executables' Direct3D to the staged D3DMetal runtime.
    public func d3dMetalGameOverrides(executables: [String],
                                      environment: [String: String] = ProcessInfo.processInfo.environment) throws -> [LaunchRequest] {
        try executables.flatMap { executable in
            try GameGraphicsSidecars.builtinLibraries.map { name in
                try request(arguments: ["reg", "add", #"HKCU\Software\Wine\AppDefaults\"# + executable + #"\DllOverrides"#,
                                        "/v", name, "/d", "builtin", "/f"],
                            label: "d3dmetal-game-overrides", environment: environment)
            }
        }
    }

    /// `silent` keeps Steam's own window closed when Steam starts for the game. `graphicsAPI` uses Unity's
    /// switches, so other engines ignore it.
    public func gameLaunch(appID: UInt32, graphicsAPI: GameGraphicsAPI? = nil, webHelperShim: Bool = true,
                           silent: Bool = false, gameArguments additionalGameArguments: [String] = [],
                           environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        // Games that ship their own Direct3D DLLs need them moved aside first (`prepareD3DMetalGame`);
        // all others use the runtime's staged D3DMetal builtins directly.
        if configuration.selectedGraphicsBackend == .d3dmetal {
            try graphicsSidecars(appID: Int(appID))?.requireD3DMetalReady()
        }
        let steam = try requiredSteam()
        let shimArguments = webHelperShim ? SteamWebHelperShim.launchArguments : []
        let gameArguments = (graphicsAPI.map { [$0.unityArgument] } ?? []) + additionalGameArguments
        return try windowsRequest(steam, arguments: shimArguments + (silent ? ["-silent"] : [])
                                      + ["-applaunch", String(appID)] + gameArguments,
                                  label: "game-launch-\(appID)", environment: environment)
    }

    private func requiredSteam() throws -> URL {
        guard bottleIsInitialized() else { throw ArchwayError.missingBottle }
        guard let steam = steamExecutable() else { throw ArchwayError.missingSteam }
        return steam
    }
}
