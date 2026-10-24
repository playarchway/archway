import Foundation
import Darwin

enum LegacyStorage {
    // Phase 1 keeps the existing data directory and on-disk markers until data migration.
    static let name = "Overcross"
}

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

public struct AppPaths {
    public let dataDirectory: URL
    public var config: URL { dataDirectory.appendingPathComponent("config.json") }
    public var bottle: URL { dataDirectory.appendingPathComponent("bottles/steam-5228920") }
    public var logs: URL { dataDirectory.appendingPathComponent("logs") }

    public init(dataDirectory: URL? = nil) throws {
        let selected = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(LegacyStorage.name)
        guard selected.isFileURL, selected.path.hasPrefix("/"), selected.path != "/" else {
            throw ArchwayError.invalidPath("Data directory must be an absolute local directory other than /.")
        }
        self.dataDirectory = selected.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func ensureDirectories() throws {
        try validateBottleScope()
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try validateBottleScope()
    }

    public func validateBottleScope() throws {
        for location in [dataDirectory, bottle.deletingLastPathComponent(), bottle, logs] {
            guard !isSymlink(location) else {
                throw ArchwayError.invalidPath("Archway directory must not be a symlink: \(location.path)")
            }
        }
    }

    private func isSymlink(_ location: URL) -> Bool {
        (try? location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

public struct BottleMarker: Codable, Equatable {
    public let version: Int
    public let state: State

    public enum State: String, Codable { case initializing, ready }
    public init(state: State) { version = 1; self.state = state }
}

public enum GraphicsBackend: String, Codable {
    case builtin, dxvk, d3dmetal

    public static func parse(_ raw: String) throws -> Self {
        guard let backend = Self(rawValue: raw) else {
            throw ArchwayError.invalidPath("Unknown graphics backend '\(raw)'; use builtin, dxvk, or d3dmetal.")
        }
        return backend
    }
}

public enum GameGraphicsAPI: String {
    case d3d11, d3d12

    public static func parse(_ raw: String) throws -> Self {
        guard let api = Self(rawValue: raw) else {
            throw ArchwayError.invalidPath("Unknown game graphics API '\(raw)'; use d3d11 or d3d12.")
        }
        return api
    }

    public var unityArgument: String { "-force-\(rawValue)" }
}

public struct Configuration: Codable, Equatable {
    public var wine: String
    public var wineserver: String?
    public var libraryDirectory: String?
    public var dxvkConfigFile: String?
    public var vulkanICDFile: String?
    public var graphicsBackend: GraphicsBackend?
    public var d3dMetalDirectory: String?

    public init(wine: String, wineserver: String? = nil, libraryDirectory: String? = nil,
                dxvkConfigFile: String? = nil, vulkanICDFile: String? = nil,
                graphicsBackend: GraphicsBackend? = nil, d3dMetalDirectory: String? = nil) {
        self.wine = wine
        self.wineserver = wineserver
        self.libraryDirectory = libraryDirectory
        self.dxvkConfigFile = dxvkConfigFile
        self.vulkanICDFile = vulkanICDFile
        self.graphicsBackend = graphicsBackend
        self.d3dMetalDirectory = d3dMetalDirectory
    }

    public var selectedGraphicsBackend: GraphicsBackend {
        graphicsBackend ?? (dxvkConfigFile != nil || vulkanICDFile != nil ? .dxvk : .builtin)
    }

    public func validateGraphicsSelection(paths: AppPaths? = nil) throws {
        switch selectedGraphicsBackend {
        case .builtin:
            guard dxvkConfigFile == nil, vulkanICDFile == nil, d3dMetalDirectory == nil else {
                throw ArchwayError.invalidPath("Builtin graphics cannot include DXVK or D3DMetal components.")
            }
        case .dxvk:
            guard d3dMetalDirectory == nil, try validatedGraphicsFiles() != nil else {
                throw ArchwayError.invalidPath("DXVK requires --dxvk-config and --vulkan-icd, without --d3dmetal-dir.")
            }
        case .d3dmetal:
            guard dxvkConfigFile == nil, vulkanICDFile == nil, let d3dMetalDirectory else {
                throw ArchwayError.invalidPath("D3DMetal requires --d3dmetal-dir, without DXVK options.")
            }
            let redist = try D3DMetalRedist(root: PathValidator.libraryDirectory(d3dMetalDirectory))
            if let paths {
                let runtime = URL(fileURLWithPath: wine).deletingLastPathComponent().deletingLastPathComponent()
                let overlay = try D3DMetalRuntimeOverlay(paths: paths, runtimeRoot: runtime, redist: redist)
                guard overlay.capability == .providerDeclared, try overlay.isStaged() else {
                    throw ArchwayError.invalidPath("D3DMetal requires a staged, provider-declared compatible runtime clone; use stage-d3dmetal and doctor first. An unverified diagnostic overlay cannot be selected for normal launches.")
                }
            }
        }
    }

    public func validatedGraphicsFiles() throws -> (dxvk: URL, icd: URL)? {
        guard (dxvkConfigFile == nil) == (vulkanICDFile == nil) else {
            throw ArchwayError.invalidPath("--dxvk-config and --vulkan-icd must be configured together.")
        }
        guard let dxvkConfigFile, let vulkanICDFile else { return nil }
        return (try PathValidator.profileFile(dxvkConfigFile), try PathValidator.profileFile(vulkanICDFile))
    }
}

public enum PathValidator {
    public static func executable(_ path: String) throws -> URL {
        // Some runtimes (Whisky's) ship bin/wine as a symlink to the loader; keep the
        // bin/ path so the runtime root can still be derived from it.
        let url = try absoluteFile(path)
        let target = url.resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: target.path), isRegularFile(target) else {
            throw ArchwayError.invalidPath("Executable not found or not executable: \(path)")
        }
        return url
    }

    public static func installer(_ path: String) throws -> URL {
        let url = try absoluteFile(path)
        guard url.pathExtension.lowercased() == "exe", isRegularFile(url),
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw ArchwayError.invalidPath("Steam installer must be a readable local .exe file: \(path)")
        }
        return url.resolvingSymlinksInPath()
    }

    public static func libraryDirectory(_ path: String) throws -> URL {
        guard !path.contains(":") else {
            throw ArchwayError.invalidPath("Runtime library directory must be a single path without ':': \(path)")
        }
        let url = try absoluteFile(path).resolvingSymlinksInPath()
        guard !url.path.contains(":"),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw ArchwayError.invalidPath("Runtime library directory must be an existing absolute local directory: \(path)")
        }
        return url
    }

    public static func profileFile(_ path: String) throws -> URL {
        guard !path.contains(":") else {
            throw ArchwayError.invalidPath("Graphics profile must use one file path without ':': \(path)")
        }
        let url = try absoluteFile(path).resolvingSymlinksInPath()
        guard !url.path.contains(":"), isRegularFile(url), FileManager.default.isReadableFile(atPath: url.path) else {
            throw ArchwayError.invalidPath("Graphics profile file must be an existing readable absolute local file: \(path)")
        }
        return url
    }

    public static func absoluteFile(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0"), path != "/" else {
            throw ArchwayError.invalidPath("Use an absolute local path: \(path)")
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else { return false }
        return values.isRegularFile == true
    }
}

public struct ConfigStore {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    public func load() throws -> Configuration? {
        guard FileManager.default.fileExists(atPath: paths.config.path) else { return nil }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: paths.config))
    }

    public func save(_ configuration: Configuration) throws {
        var normalized = configuration
        try normalized.validateGraphicsSelection(paths: paths)
        if let directory = normalized.libraryDirectory {
            normalized.libraryDirectory = try PathValidator.libraryDirectory(directory).path
        }
        if let files = try normalized.validatedGraphicsFiles() {
            normalized.dxvkConfigFile = files.dxvk.path
            normalized.vulkanICDFile = files.icd.path
        }
        if let directory = normalized.d3dMetalDirectory {
            normalized.d3dMetalDirectory = try PathValidator.libraryDirectory(directory).path
        }
        try paths.ensureDirectories()
        let data = try JSONEncoder().encode(normalized)
        try data.write(to: paths.config, options: [.atomic])
    }
}

public struct LaunchRequest: Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let log: URL
    public let label: String
    public let workingDirectory: URL?

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
    public static let firstAppID: UInt32 = 5_228_920
    public let paths: AppPaths
    public let configuration: Configuration

    public init(paths: AppPaths, configuration: Configuration) {
        self.paths = paths
        self.configuration = configuration
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
        let marker = paths.bottle.appendingPathComponent(".\(LegacyStorage.name.lowercased())-bottle.json")
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
        try data.write(to: paths.bottle.appendingPathComponent(".\(LegacyStorage.name.lowercased())-bottle.json"), options: [.atomic])
    }

    public func steamExecutable() -> URL? {
        let candidates = ["drive_c/Program Files (x86)/Steam/steam.exe", "drive_c/Program Files/Steam/steam.exe"]
        let bottleRoot = paths.bottle.resolvingSymlinksInPath().path + "/"
        for candidate in candidates {
            let file = paths.bottle.appendingPathComponent(candidate)
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
        let base = try request(arguments: [windowsExecutable.path] + arguments, label: label, environment: environment)
        return LaunchRequest(executable: base.executable, arguments: base.arguments,
                             environment: base.environment, log: base.log, label: base.label,
                             workingDirectory: windowsExecutable.deletingLastPathComponent())
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
                          wineRenderer: SteamWineRenderer? = nil, webHelperShim: Bool = true,
                          environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        guard cefDebugPort == nil || enableCEFDebugging else {
            throw ArchwayError.invalidPath("--cef-debug-port requires --cef-debugging.")
        }
        guard cefDebugPort.map({ $0 >= 1024 }) ?? true else {
            throw ArchwayError.invalidPath("CEF debug port must be 1024 through 65535.")
        }
        let steam = try requiredSteam()
        let flags = (webHelperShim ? SteamWebHelperShim.launchArguments : [])
                  + (disableCEFGPU ? ["-cef-disable-gpu"] : [])
                  + (enableCEFDebugging ? ["-cef-enable-debugging"] : [])
                  + (cefDebugPort.map { ["-devtools-port", String($0)] } ?? [])
        let base = try windowsRequest(steam, arguments: flags,
                                      label: "steam-open", environment: environment)
        guard let wineRenderer else { return base }
        var scopedEnvironment = base.environment
        scopedEnvironment["WINE_D3D_CONFIG"] = "renderer=\(wineRenderer.rawValue)"
        return LaunchRequest(executable: base.executable, arguments: base.arguments,
                             environment: scopedEnvironment, log: base.log, label: base.label,
                             workingDirectory: base.workingDirectory)
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

    public func gameInstall(appID: UInt32 = firstAppID, webHelperShim: Bool = true,
                            environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        let steam = try requiredSteam()
        // Steam may not be running yet, so these requests can start it like open-steam.
        let shimArguments = webHelperShim ? SteamWebHelperShim.launchArguments : []
        return try windowsRequest(steam, arguments: shimArguments + ["steam://install/\(appID)"],
                                  label: "game-install-\(appID)", environment: environment)
    }

    /// Wine builtin overrides that route only Brick by Brick's Direct3D to the staged D3DMetal runtime.
    public func d3dMetalGameOverrides(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> [LaunchRequest] {
        try ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi"].map { name in
            try request(arguments: ["reg", "add", #"HKCU\Software\Wine\AppDefaults\BrickByBrick.exe\DllOverrides"#,
                                    "/v", name, "/d", "builtin", "/f"],
                        label: "d3dmetal-game-overrides", environment: environment)
        }
    }

    public func gameLaunch(appID: UInt32 = firstAppID, graphicsAPI: GameGraphicsAPI? = nil, webHelperShim: Bool = true,
                           environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LaunchRequest {
        guard graphicsAPI == nil || appID == Self.firstAppID else {
            throw ArchwayError.invalidPath("--graphics-api is currently supported only for Brick by Brick (5228920).")
        }
        // Brick by Brick ships its own DXVK DLLs, so only its game profile must be prepared; other games
        // use the runtime's staged D3DMetal builtins directly.
        if configuration.selectedGraphicsBackend == .d3dmetal, appID == Self.firstAppID {
            try GameGraphicsSidecars(paths: paths).requireD3DMetalReady()
        }
        let steam = try requiredSteam()
        let shimArguments = webHelperShim ? SteamWebHelperShim.launchArguments : []
        let gameArguments = graphicsAPI.map { [$0.unityArgument] } ?? []
        return try windowsRequest(steam, arguments: shimArguments + ["-applaunch", String(appID)] + gameArguments,
                                  label: "game-launch-\(appID)", environment: environment)
    }

    private func requiredSteam() throws -> URL {
        guard bottleIsInitialized() else { throw ArchwayError.missingBottle }
        guard let steam = steamExecutable() else { throw ArchwayError.missingSteam }
        return steam
    }
}

public enum ProcessRunner {
    public static func runSetup(_ request: LaunchRequest, timeout: TimeInterval) throws {
        let logFD = try openLog(request.log)
        defer { close(logFD) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_adddup2(&actions, logFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, logFD, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, logFD)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        let arguments = [request.executable.path] + request.arguments
        let variables = request.environment.map { "\($0.key)=\($0.value)" }
        let argv = arguments.map { strdup($0) }
        let envp = variables.map { strdup($0) }
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var argumentsArray = argv + [nil]
        var environmentArray = envp + [nil]
        var pid: pid_t = 0
        let result = request.executable.path.withCString { path in
            argumentsArray.withUnsafeMutableBufferPointer { args in
                environmentArray.withUnsafeMutableBufferPointer { env in
                    posix_spawn(&pid, path, &actions, &attributes, args.baseAddress, env.baseAddress)
                }
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }

        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                guard exitCode == 0 else { throw ArchwayError.processFailed(request.label, exitCode) }
                return
            }
            if waited == -1 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if Date() >= deadline {
                kill(-pid, SIGTERM)
                // Keep the direct child unreaped so its PID/PGID cannot be reused before cleanup.
                usleep(1_000_000)
                // A surviving descendant can outlive the direct child; signal the owned group again.
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                throw ArchwayError.processTimedOut(request.label, timeout)
            }
            usleep(20_000)
        }
    }

    public static func sendGUIRequest(_ request: LaunchRequest) throws {
        _ = try startGUIProcess(request)
    }

    /// Starts the request and returns its process, for callers that follow its lifetime.
    @discardableResult
    public static func startGUIProcess(_ request: LaunchRequest) throws -> Process {
        let fd = try openLog(request.log)
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.workingDirectory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        return process
    }

    private static func openLog(_ url: URL) throws -> Int32 {
        let parent = url.deletingLastPathComponent()
        guard (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ArchwayError.invalidPath("Log directory must not be a symlink: \(parent.path)")
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ArchwayError.invalidPath("Log directory must not be a symlink: \(parent.path)")
        }
        let directoryFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(directoryFD) }
        let fd = openat(directoryFD, url.lastPathComponent, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        if fstat(fd, &info) != 0 || (info.st_mode & S_IFMT) != S_IFREG {
            close(fd)
            throw ArchwayError.invalidPath("Log path must be a regular file: \(url.path)")
        }
        // Keep repeated requests from appending indefinitely; active GUI logs can still grow.
        if info.st_size > 10 * 1024 * 1024 { _ = ftruncate(fd, 0) }
        return fd
    }
}
