import Foundation
import ArchwayCore

private let help = """
Archway technical proof of concept (Brick by Brick, Steam app 5228920)

Usage: archway [--data-dir ABSOLUTE_PATH] COMMAND [OPTIONS]

Commands:
  help                                      Show this help
  doctor                                    Read-only setup checks
  locations                                 Show configuration, bottle, and log paths
  migrate-data                              Move legacy default data to Archway after Wine is stopped
  configure --wine PATH [--wineserver PATH] [--library-dir PATH] [--backend builtin|dxvk|d3dmetal] [--dxvk-config PATH --vulkan-icd PATH] [--d3dmetal-dir PATH] Save runtime paths
  check-d3dmetal --redist-lib PATH         Validate a local Apple GPTK redist/lib directory
  stage-d3dmetal --redist-lib PATH --runtime-root PATH [--allow-unverified-runtime]  Stage into an owned Wine clone
  restore-d3dmetal --redist-lib PATH --runtime-root PATH  Restore the owned Wine clone
  init-bottle                               Initialize the owned Wine bottle
  install-steam --installer PATH [--silent] Send local Windows Steam installer to Wine
  open-steam [--disable-cef-gpu] [--cef-debugging [--cef-debug-port PORT]] [--wine-renderer gl] [--without-webhelper-shim]  Send Windows Steam launch request
  close-steam                               Ask owned Windows Steam to exit; wait for its Wine server
  install-game [--app-id ID]                Request install through a Steam URI
  launch-game [--app-id ID] [--graphics-api d3d11|d3d12] Request launch through Windows Steam

GUI commands only confirm that a request was sent. Check Steam, the game, and logs for results.
open-steam, install-game, and launch-game install the steamwebhelper shim that keeps Steam's
window from rendering black; --without-webhelper-shim restores Valve's helper for diagnosis.
"""

/// Returns whether Steam must start with the shim's launch arguments.
private func applyWebHelperShim(_ orchestrator: Orchestrator, enabled: Bool = true) throws -> Bool {
    guard enabled else {
        try orchestrator.removeSteamShim()
        print("Steam webhelper shim: removed; Valve's helper restored. Steam's window is expected to stay black.")
        return false
    }
    guard try orchestrator.prepareSteam() else {
        print("Steam webhelper shim: Steam has not downloaded its webhelper yet. Let this first start finish updating, then run close-steam and open-steam again.")
        return false
    }
    print("Steam webhelper shim: installed (--in-process-gpu); Steam starts with \(SteamWebHelperShim.launchArguments.joined(separator: " ")).")
    return true
}

private func takeOption(_ name: String, from arguments: inout [String]) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
        throw ArchwayError.invalidPath("Missing value for \(name).")
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

private func takeFlag(_ name: String, from arguments: inout [String]) throws -> Bool {
    let matches = arguments.indices.filter { arguments[$0] == name }
    guard matches.count <= 1 else { throw ArchwayError.invalidPath("Duplicate option: \(name)") }
    guard let index = matches.first else { return false }
    arguments.remove(at: index)
    return true
}

private func requireNoExtras(_ arguments: [String]) throws {
    guard arguments.isEmpty else { throw ArchwayError.invalidPath("Unexpected arguments: \(arguments.joined(separator: " "))") }
}

private func requiredConfiguration(_ store: ConfigStore) throws -> Configuration {
    guard let config = try store.load() else { throw ArchwayError.missingConfiguration }
    return config
}

private func doctor(_ paths: AppPaths, _ store: ConfigStore) {
    print("Data: \(paths.dataDirectory.path)")
    print("Bottle: \(paths.bottle.path)")
    print("Logs: \(paths.logs.path)")
    print("Host: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    do {
        try paths.validateBottleScope()
        print("Bottle scope: OK")
    } catch {
        print("Bottle scope: \(error.localizedDescription)")
    }
    do {
        guard let config = try store.load() else {
            print("Wine: not configured; run configure --wine /absolute/path/to/wine")
            print("Bottle: not initialized")
            print("Windows Steam: not installed")
            print("Compatibility: unverified; manual install, play, save, restart, and reload required")
            return
        }
        do {
            let wine = try PathValidator.executable(config.wine)
            print("Wine: executable at \(wine.path)")
        } catch {
            print("Wine: \(error.localizedDescription)")
        }
        if let server = config.wineserver {
            do {
                let executable = try PathValidator.executable(server)
                print("Wineserver: executable at \(executable.path)")
            } catch {
                print("Wineserver: \(error.localizedDescription)")
            }
        } else {
            print("Wineserver: Wine runtime default")
        }
        if let directory = config.libraryDirectory {
            do {
                print("Runtime libraries: \(try PathValidator.libraryDirectory(directory).path)")
            } catch {
                print("Runtime libraries: \(error.localizedDescription)")
            }
        } else {
            print("Runtime libraries: not configured")
        }
        print("Graphics backend: \(config.selectedGraphicsBackend.rawValue)")
        do {
            try config.validateGraphicsSelection(paths: paths)
            switch config.selectedGraphicsBackend {
            case .builtin: print("Graphics profile: Wine builtin")
            case .dxvk:
                let files = try config.validatedGraphicsFiles()!
                print("Graphics profile: DXVK \(files.dxvk.path); Vulkan ICD \(files.icd.path)")
            case .d3dmetal:
                let directory = try PathValidator.libraryDirectory(config.d3dMetalDirectory!)
                print("Graphics profile: D3DMetal redist \(directory.path); staged provider metadata found, game execution unverified")
            }
        } catch {
            print("Graphics profile: \(error.localizedDescription)")
        }
        let orchestrator = Orchestrator(paths: paths, configuration: config)
        let bottleStatus: String
        if orchestrator.bottleIsInitialized() {
            bottleStatus = "ready (owned marker and Wine registry present)"
        } else if orchestrator.bottleMarker()?.state == .initializing {
            bottleStatus = "initialization incomplete; run init-bottle to retry"
        } else if FileManager.default.fileExists(atPath: paths.bottle.path) {
            bottleStatus = "unowned or invalid marker; choose a fresh --data-dir"
        } else {
            bottleStatus = "not initialized; run init-bottle"
        }
        print("Bottle: \(bottleStatus)")
        print(orchestrator.steamExecutable() == nil
              ? "Windows Steam: not found; run install-steam --installer /absolute/path/to/SteamSetup.exe after bottle initialization"
              : "Windows Steam: executable found in owned bottle")
        if orchestrator.steamExecutable() != nil {
            let state = try? orchestrator.steamWebHelperShim(shim: SteamWebHelperShim.bundledShim()).state()
            let description: String
            switch state {
            case .installed: description = "installed"
            case .original: description = "not installed; open-steam installs it"
            case .incomplete: description = "incomplete; run open-steam --without-webhelper-shim once so Steam can repair its helper"
            case .missing: description = "Steam's webhelper not found yet; start Steam once"
            case nil: description = "unreadable"
            }
            print("Steam webhelper shim: \(description)")
        }
    } catch {
        print("Configuration: unreadable (\(error.localizedDescription)); inspect \(paths.config.path)")
    }
    print("Compatibility: unverified; manual install, play, save, restart, and reload required")
}

private func run() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let dataDir = try takeOption("--data-dir", from: &arguments).map { try PathValidator.absoluteFile($0) }
    let command = arguments.isEmpty ? "help" : arguments.removeFirst()
    if command == "migrate-data" {
        try requireNoExtras(arguments)
        guard dataDir == nil else { throw ArchwayError.invalidPath("migrate-data only applies to the default data directory.") }
        print(try DataMigration.migrateIfNeeded() ? "Archway data migrated." : "No legacy data to migrate.")
        return
    }
    let paths = try AppPaths(dataDirectory: dataDir)
    let store = ConfigStore(paths: paths)

    switch command {
    case "help", "--help", "-h":
        try requireNoExtras(arguments)
        print(help)
    case "locations":
        try requireNoExtras(arguments)
        print("Configuration: \(paths.config.path)\nBottle: \(paths.bottle.path)\nLogs: \(paths.logs.path)")
    case "doctor":
        try requireNoExtras(arguments)
        doctor(paths, store)
    case "check-d3dmetal":
        guard let redistPath = try takeOption("--redist-lib", from: &arguments) else {
            throw ArchwayError.invalidPath("Missing --redist-lib /absolute/path/to/redist/lib.")
        }
        try requireNoExtras(arguments)
        let redist = try D3DMetalRedist(root: PathValidator.libraryDirectory(redistPath))
        print("D3DMetal redist validated: \(redist.root.path). Runtime compatibility and game execution unverified.")
    case "stage-d3dmetal", "restore-d3dmetal":
        guard let redistPath = try takeOption("--redist-lib", from: &arguments),
              let runtimePath = try takeOption("--runtime-root", from: &arguments) else {
            throw ArchwayError.invalidPath("Supply --redist-lib and --runtime-root absolute paths.")
        }
        let allowUnverified = try takeFlag("--allow-unverified-runtime", from: &arguments)
        guard command == "stage-d3dmetal" || !allowUnverified else {
            throw ArchwayError.invalidPath("--allow-unverified-runtime applies only to staging.")
        }
        try requireNoExtras(arguments)
        let redist = try D3DMetalRedist(root: PathValidator.libraryDirectory(redistPath))
        let overlay = try D3DMetalRuntimeOverlay(paths: paths,
            runtimeRoot: PathValidator.libraryDirectory(runtimePath), redist: redist)
        if command == "stage-d3dmetal" {
            try overlay.stage(allowUnverifiedRuntime: allowUnverified)
            print("D3DMetal components staged in owned runtime clone: \(overlay.runtimeRoot.path). Capability: \(overlay.capability.rawValue). Game execution unverified.")
        } else {
            try overlay.restore()
            print("Owned runtime clone restored: \(overlay.runtimeRoot.path)")
        }
    case "configure":
        guard let wine = try takeOption("--wine", from: &arguments) else {
            throw ArchwayError.invalidPath("Missing --wine /absolute/path/to/wine.")
        }
        let server = try takeOption("--wineserver", from: &arguments)
        let libraryDirectory = try takeOption("--library-dir", from: &arguments)
        let backend = try takeOption("--backend", from: &arguments).map(GraphicsBackend.parse)
        let dxvkConfigFile = try takeOption("--dxvk-config", from: &arguments)
        let vulkanICDFile = try takeOption("--vulkan-icd", from: &arguments)
        let d3dMetalDirectory = try takeOption("--d3dmetal-dir", from: &arguments)
        try requireNoExtras(arguments)
        let config = Configuration(wine: try PathValidator.executable(wine).path,
                                   wineserver: try server.map { try PathValidator.executable($0).path },
                                   libraryDirectory: try libraryDirectory.map { try PathValidator.libraryDirectory($0).path },
                                   dxvkConfigFile: dxvkConfigFile, vulkanICDFile: vulkanICDFile,
                                   graphicsBackend: backend, d3dMetalDirectory: d3dMetalDirectory)
        try store.save(config)
        print("Wine configured in \(paths.config.path). Bottle: \(paths.bottle.path)")
    case "init-bottle":
        try requireNoExtras(arguments)
        let orchestrator = Orchestrator(paths: paths, configuration: try requiredConfiguration(store))
        guard !orchestrator.bottleIsInitialized() else {
            print("Bottle already initialized: \(paths.bottle.path)")
            return
        }
        let request = try orchestrator.bottleInit()
        try orchestrator.prepareBottleInitialization()
        print("Running Wine bottle initialization; log: \(request.log.path)")
        try ProcessRunner.runSetup(request, timeout: 300)
        try orchestrator.markBottleReady()
        print("Bottle initialized: \(paths.bottle.path)")
    case "install-steam":
        guard let installer = try takeOption("--installer", from: &arguments) else {
            throw ArchwayError.invalidPath("Missing --installer /absolute/path/to/SteamSetup.exe.")
        }
        let silent = try takeFlag("--silent", from: &arguments)
        try requireNoExtras(arguments)
        let orchestrator = Orchestrator(paths: paths, configuration: try requiredConfiguration(store))
        let request = try orchestrator.steamInstaller(PathValidator.absoluteFile(installer), silent: silent)
        print("Sending Steam installer request\(silent ? " with /S" : ""); log: \(request.log.path)")
        try ProcessRunner.sendGUIRequest(request)
        print(silent
              ? "Request sent. Run doctor to check for Windows Steam; installation is not yet confirmed."
              : "Request sent. Complete the installer in Wine, then run doctor. Installation is not yet confirmed.")
    case "open-steam":
        let disableCEFGPU = try takeFlag("--disable-cef-gpu", from: &arguments)
        let enableCEFDebugging = try takeFlag("--cef-debugging", from: &arguments)
        let debugPort = try takeOption("--cef-debug-port", from: &arguments).map(Orchestrator.cefDebugPort)
        guard debugPort == nil || enableCEFDebugging else {
            throw ArchwayError.invalidPath("--cef-debug-port requires --cef-debugging.")
        }
        let renderer = try takeOption("--wine-renderer", from: &arguments).map(SteamWineRenderer.parse)
        let withoutShim = try takeFlag("--without-webhelper-shim", from: &arguments)
        try requireNoExtras(arguments)
        let orchestrator = Orchestrator(paths: paths, configuration: try requiredConfiguration(store))
        let shimActive = try applyWebHelperShim(orchestrator, enabled: !withoutShim)
        let request = try orchestrator.steamOpen(disableCEFGPU: disableCEFGPU, enableCEFDebugging: enableCEFDebugging,
                                                 cefDebugPort: debugPort, wineRenderer: renderer,
                                                 webHelperShim: shimActive)
        let options = [disableCEFGPU ? "-cef-disable-gpu" : nil,
                       enableCEFDebugging ? "-cef-enable-debugging" : nil,
                       debugPort.map { "-devtools-port \($0)" },
                       renderer == .gl ? "WINE_D3D_CONFIG=renderer=gl" : nil].compactMap { $0 }
        print("Sending Windows Steam launch request\(options.isEmpty ? "" : " with " + options.joined(separator: ", ")); log: \(request.log.path)")
        try ProcessRunner.sendGUIRequest(request)
        print("Request sent. Sign in through Windows Steam; startup is not yet confirmed.")
    case "close-steam":
        try requireNoExtras(arguments)
        let orchestrator = Orchestrator(paths: paths, configuration: try requiredConfiguration(store))
        let shutdown = try orchestrator.steamShutdown()
        let wait = try orchestrator.wineserverWait()
        print("Asking Windows Steam in the owned bottle to exit; logs: \(shutdown.log.path), \(wait.log.path)")
        try ProcessRunner.sendGUIRequest(shutdown)
        print("Shutdown request sent; waiting up to 30 seconds for the owned bottle's Wine server to exit.")
        try ProcessRunner.runSetup(wait, timeout: 30)
        print("The owned bottle's Wine server exited. Steam shutdown was requested; no force stop was used.")
    case "install-game", "launch-game":
        let rawID = try takeOption("--app-id", from: &arguments)
        let graphicsAPI = try takeOption("--graphics-api", from: &arguments).map(GameGraphicsAPI.parse)
        guard command == "launch-game" || graphicsAPI == nil else {
            throw ArchwayError.invalidPath("--graphics-api is available only for launch-game.")
        }
        try requireNoExtras(arguments)
        let appID = try rawID.map(Orchestrator.appID) ?? Orchestrator.firstAppID
        let orchestrator = Orchestrator(paths: paths, configuration: try requiredConfiguration(store))
        if command == "launch-game", appID == Orchestrator.firstAppID,
           orchestrator.configuration.selectedGraphicsBackend == .d3dmetal {
            print("Preparing Brick by Brick for D3DMetal (game-only builtin Direct3D overrides).")
            try orchestrator.prepareD3DMetalGame()
        }
        let shimActive = try applyWebHelperShim(orchestrator)
        let request = try command == "install-game"
            ? orchestrator.gameInstall(appID: appID, webHelperShim: shimActive)
            : orchestrator.gameLaunch(appID: appID, graphicsAPI: graphicsAPI, webHelperShim: shimActive)
        print("Sending \(command) request for Steam app \(appID); log: \(request.log.path)")
        try ProcessRunner.sendGUIRequest(request)
        print("Request sent. Confirm the result in Windows Steam and the game; success is not yet verified.")
    default:
        throw ArchwayError.invalidPath("Unknown command '\(command)'. Run archway help.")
    }
}

do {
    try run()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
