import Foundation
import Testing
@testable import OvercrossCore

private func temporaryDirectory() throws -> URL {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = package.appendingPathComponent(".build/test-temp/overcross-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func executable(_ name: String, in directory: URL, body: String = "exit 0") throws -> URL {
    let file = directory.appendingPathComponent(name)
    try "#!/bin/sh\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    return file
}

private func initializedBottle(_ paths: AppPaths) throws {
    try FileManager.default.createDirectory(at: paths.bottle, withIntermediateDirectories: true)
    try Data("registry".utf8).write(to: paths.bottle.appendingPathComponent("system.reg"))
}

private func steam(_ paths: AppPaths) throws -> URL {
    let file = paths.bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: file)
    return file
}

private func ownedGame(_ paths: AppPaths) throws -> URL {
    try initializedBottle(paths)
    try Data(#"{"version":1,"state":"ready"}"#.utf8).write(to: paths.bottle.appendingPathComponent(".overcross-bottle.json"))
    let game = paths.bottle.appendingPathComponent(GameGraphicsSidecars.gameRelativePath)
    try FileManager.default.createDirectory(at: game.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("game".utf8).write(to: game)
    return game
}

private func windowsDLL(_ name: String, in directory: URL, tag: UInt8) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var bytes = Data(repeating: tag, count: 256)
    bytes[0] = 0x4d
    bytes[1] = 0x5a
    bytes[0x3c] = 0x80
    bytes[0x3d] = 0
    bytes[0x3e] = 0
    bytes[0x3f] = 0
    bytes[0x80] = 0x50
    bytes[0x81] = 0x45
    bytes[0x82] = 0
    bytes[0x83] = 0
    bytes[0x84] = 0x64
    bytes[0x85] = 0x86
    let file = directory.appendingPathComponent(name)
    try bytes.write(to: file)
    return file
}

private func d3dMetalFixture(in directory: URL) throws -> URL {
    let root = directory.appendingPathComponent("redist/lib")
    let external = root.appendingPathComponent("external")
    let framework = external.appendingPathComponent("D3DMetal.framework")
    let version = framework.appendingPathComponent("Versions/A")
    try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
    let macho = Data([0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1, 3, 0, 0, 0, 6, 0, 0, 0])
    try macho.write(to: external.appendingPathComponent("libd3dshared.dylib"))
    try macho.write(to: version.appendingPathComponent("D3DMetal"))
    try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path,
                                               withDestinationPath: "A")
    try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("D3DMetal").path,
                                               withDestinationPath: "Versions/Current/D3DMetal")
    let windows = root.appendingPathComponent("wine/x86_64-windows")
    let unix = root.appendingPathComponent("wine/x86_64-unix")
    try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
    for name in D3DMetalRedist.moduleNames {
        _ = try windowsDLL("\(name).dll", in: windows, tag: 7)
        try FileManager.default.createSymbolicLink(atPath: unix.appendingPathComponent("\(name).so").path,
                                                   withDestinationPath: D3DMetalRedist.unixBridgeTarget)
    }
    return root
}

@Test func d3dMetalRedistRequiresPairedBuiltinModulesAndUnixBridges() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = try d3dMetalFixture(in: directory)
    let validated = try D3DMetalRedist(root: root)
    #expect(validated.root.path == root.path)
    let unixLink = root.appendingPathComponent("wine/x86_64-unix/d3d11.so")
    try FileManager.default.removeItem(at: unixLink)
    try Data("copied bridge".utf8).write(to: unixLink)
    #expect(throws: Error.self) { try D3DMetalRedist(root: root) }
    try FileManager.default.removeItem(at: unixLink)
    try FileManager.default.createSymbolicLink(atPath: unixLink.path,
                                               withDestinationPath: D3DMetalRedist.unixBridgeTarget)
    let pe = root.appendingPathComponent("wine/x86_64-windows/d3d12.dll")
    try Data("wrong architecture".utf8).write(to: pe)
    #expect(throws: Error.self) { try D3DMetalRedist(root: root) }
}

private func compatibleRuntime(in paths: AppPaths) throws -> URL {
    // Whisky's layout: Libraries/WhiskyWineVersion.plist beside Libraries/Wine.
    let root = paths.dataDirectory.appendingPathComponent("runtime-overlays/compatible wine/Wine")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
    _ = try executable("wine", in: root.appendingPathComponent("bin"))
    _ = try executable("wineserver", in: root.appendingPathComponent("bin"))
    let windows = root.appendingPathComponent("lib/wine/x86_64-windows")
    let unix = root.appendingPathComponent("lib/wine/x86_64-unix")
    try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
    for name in D3DMetalRedist.moduleNames {
        _ = try windowsDLL("\(name).dll", in: windows, tag: 9)
        try Data("original \(name)".utf8).write(to: unix.appendingPathComponent("\(name).so"))
    }
    let plist = try PropertyListSerialization.data(fromPropertyList: ["gptkCapable": true],
                                                    format: .xml, options: 0)
    try plist.write(to: root.deletingLastPathComponent().appendingPathComponent("WhiskyWineVersion.plist"))
    return root
}

@Test func d3dMetalRuntimeOverlayPreservesBuiltinPairsAndRestores() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let redist = try D3DMetalRedist(root: d3dMetalFixture(in: directory))
    let runtime = try compatibleRuntime(in: paths)
    let overlay = try D3DMetalRuntimeOverlay(paths: paths, runtimeRoot: runtime, redist: redist)
    #expect(overlay.capability == .providerDeclared)
    let oldDLL = try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"))
    let oldUnix = try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-unix/d3d11.so"))
    try overlay.stage()
    #expect(try overlay.isStaged())
    #expect(try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"))
            == Data(contentsOf: redist.windowsModules.appendingPathComponent("d3d11.dll")))
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: runtime.appendingPathComponent("lib/wine/x86_64-unix/d3d11.so").path)
            == D3DMetalRedist.unixBridgeTarget)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: runtime.appendingPathComponent("lib/external/D3DMetal.framework/D3DMetal").path)
            == "Versions/Current/D3DMetal")
    try overlay.restore()
    #expect(!(try overlay.isStaged()))
    #expect(try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")) == oldDLL)
    #expect(try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-unix/d3d11.so")) == oldUnix)
    #expect(!FileManager.default.fileExists(atPath: runtime.appendingPathComponent("lib/external/D3DMetal.framework").path))
}

@Test func d3dMetalRuntimeOverlayRollsBackAndGatesUnknownRuntime() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let redist = try D3DMetalRedist(root: d3dMetalFixture(in: directory))
    let runtime = try compatibleRuntime(in: paths)
    let plist = runtime.deletingLastPathComponent().appendingPathComponent("WhiskyWineVersion.plist")
    try FileManager.default.removeItem(at: plist)
    let overlay = try D3DMetalRuntimeOverlay(paths: paths, runtimeRoot: runtime, redist: redist)
    #expect(overlay.capability == .unverified)
    #expect(throws: Error.self) { try overlay.stage() }
    let oldDLL = try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d12core.dll"))
    #expect(throws: Error.self) {
        try overlay.stage(allowUnverifiedRuntime: true) { name in
            if name == "wine/x86_64-windows/d3d11.dll" {
                throw OvercrossError.invalidPath("injected replacement failure")
            }
        }
    }
    #expect(try Data(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d12core.dll")) == oldDLL)
    #expect(!(try overlay.isStaged()))
    #expect(!FileManager.default.fileExists(atPath: overlay.backupDirectory.path))
}

@Test func gameGraphicsSidecarsPreservePreviousDXVKAndRestore() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("Overcross Data"))
    let game = try ownedGame(paths)
    let gameDirectory = game.deletingLastPathComponent()
    let old11 = try windowsDLL("d3d11.dll", in: gameDirectory, tag: 1)
    let oldGI = try windowsDLL("dxgi.dll", in: gameDirectory, tag: 2)
    let old11Bytes = try Data(contentsOf: old11)
    let oldGIBytes = try Data(contentsOf: oldGI)
    let manager = try GameGraphicsSidecars(paths: paths)
    try manager.suspendForD3DMetal()
    #expect(try manager.installedBackend() == .d3dmetal)
    #expect(!FileManager.default.fileExists(atPath: old11.path))
    #expect(!FileManager.default.fileExists(atPath: oldGI.path))
    #expect(!FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("d3d12.dll").path))
    #expect(try Data(contentsOf: manager.backupDirectory.appendingPathComponent("d3d11.dll")) == old11Bytes)
    #expect(throws: Error.self) { try manager.suspendForD3DMetal() }
    try Data("outside change".utf8).write(to: old11)
    #expect(throws: Error.self) { try manager.restore() }
    #expect(try Data(contentsOf: old11) == Data("outside change".utf8))
    try FileManager.default.removeItem(at: old11)
    try manager.restore()
    #expect(try manager.installedBackend() == nil)
    #expect(try Data(contentsOf: old11) == old11Bytes)
    #expect(try Data(contentsOf: oldGI) == oldGIBytes)
    #expect(!FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("d3d12.dll").path))
    #expect(!FileManager.default.fileExists(atPath: manager.backupDirectory.path))
}

@Test func gameGraphicsSidecarsRollbackAndRejectEscapes() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let game = try ownedGame(paths)
    let gameDirectory = game.deletingLastPathComponent()
    let old11 = try windowsDLL("d3d11.dll", in: gameDirectory, tag: 1)
    let oldBytes = try Data(contentsOf: old11)
    let package = directory.appendingPathComponent("package")
    let new11 = try windowsDLL("d3d11.dll", in: package, tag: 2)
    let newGI = try windowsDLL("dxgi.dll", in: package, tag: 3)
    let manager = try GameGraphicsSidecars(paths: paths)
    #expect(throws: Error.self) {
        try manager.apply(["d3d11.dll": new11, "dxgi.dll": newGI], backend: .dxvk) { name in
            if name == "dxgi.dll" { throw OvercrossError.invalidPath("injected copy failure") }
        }
    }
    #expect(try Data(contentsOf: old11) == oldBytes)
    #expect(!FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("dxgi.dll").path))
    #expect(try manager.installedBackend() == nil)
    let outside = directory.appendingPathComponent("outside.dll")
    try Data("outside".utf8).write(to: outside)
    let linkedTarget = gameDirectory.appendingPathComponent("dxgi.dll")
    try FileManager.default.createSymbolicLink(at: linkedTarget, withDestinationURL: outside)
    #expect(throws: Error.self) { try manager.apply(["d3d11.dll": new11, "dxgi.dll": newGI], backend: .dxvk) }
    #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    try FileManager.default.removeItem(at: linkedTarget)
    let linkedSource = package.appendingPathComponent("linked.dll")
    try FileManager.default.createSymbolicLink(at: linkedSource, withDestinationURL: newGI)
    #expect(throws: Error.self) { try manager.apply(["d3d11.dll": new11, "dxgi.dll": linkedSource], backend: .dxvk) }
    let bad = package.appendingPathComponent("bad.dll")
    try Data("not PE".utf8).write(to: bad)
    #expect(throws: Error.self) { try manager.apply(["d3d11.dll": new11, "dxgi.dll": bad], backend: .dxvk) }
    #expect(throws: Error.self) { try manager.apply(["d3d11.dll": new11, "dxgi.dll": newGI], backend: .d3dmetal) }
}

@Test func d3dMetalGameGateRejectsDXVKAndNativeOverride() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let game = try ownedGame(paths)
    let profile = try GameGraphicsSidecars(paths: paths)
    let registry = paths.bottle.appendingPathComponent("user.reg")
    let section = "[Software\\\\Wine\\\\AppDefaults\\\\BrickByBrick.exe\\\\DllOverrides]\n"
    try (section + "\"d3d11\"=\"native,builtin\"\n\"d3d12\"=\"builtin\"\n\"d3d12core\"=\"builtin\"\n\"dxgi\"=\"builtin\"\n")
        .write(to: registry, atomically: true, encoding: .utf8)
    #expect(throws: Error.self) { try profile.requireD3DMetalReady() }
    try (section + "\"d3d11\"=\"builtin\"\n\"d3d12\"=\"builtin\"\n\"d3d12core\"=\"builtin\"\n\"dxgi\"=\"builtin\"\n")
        .write(to: registry, atomically: true, encoding: .utf8)
    let dxvk = try windowsDLL("d3d11.dll", in: game.deletingLastPathComponent(), tag: 3)
    #expect(throws: Error.self) { try profile.requireD3DMetalReady() }
    try FileManager.default.removeItem(at: dxvk)
    try profile.requireD3DMetalReady()
}

@Test func configurationRoundTripAndPathValidation() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("Application Support/Overcross"))
    let store = ConfigStore(paths: paths)
    #expect(try store.load() == nil)
    let config = Configuration(wine: "/some path/wine", wineserver: nil)
    try store.save(config)
    #expect(try store.load() == config)
    let legacy = try JSONDecoder().decode(Configuration.self, from: Data(#"{"wine":"/old/wine","wineserver":null}"#.utf8))
    #expect(legacy.libraryDirectory == nil)
    #expect(legacy.dxvkConfigFile == nil)
    #expect(legacy.vulkanICDFile == nil)
    #expect(legacy.selectedGraphicsBackend == .builtin)
    let support = directory.appendingPathComponent("support libs")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let alias = directory.appendingPathComponent("support alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: support)
    try store.save(Configuration(wine: config.wine, libraryDirectory: alias.path))
    #expect(try store.load()?.libraryDirectory == support.resolvingSymlinksInPath().path)
    #expect(throws: Error.self) { try PathValidator.libraryDirectory("relative/support") }
    #expect(throws: Error.self) { try PathValidator.libraryDirectory(directory.appendingPathComponent("missing").path) }
    #expect(throws: Error.self) { try PathValidator.libraryDirectory(directory.appendingPathComponent("support:other").path) }
    #expect(throws: Error.self) { try store.save(Configuration(wine: config.wine, libraryDirectory: "/tmp/one:/tmp/two")) }
    let dxvk = directory.appendingPathComponent("DXVK config with spaces.conf")
    let icd = directory.appendingPathComponent("Vulkan ICD with spaces.json")
    try Data("dxvk".utf8).write(to: dxvk)
    try Data("{}".utf8).write(to: icd)
    let dxvkAlias = directory.appendingPathComponent("DXVK alias.conf")
    try FileManager.default.createSymbolicLink(at: dxvkAlias, withDestinationURL: dxvk)
    try store.save(Configuration(wine: config.wine, dxvkConfigFile: dxvkAlias.path, vulkanICDFile: icd.path))
    #expect(try store.load()?.selectedGraphicsBackend == .dxvk)
    #expect(try store.load()?.dxvkConfigFile == dxvk.resolvingSymlinksInPath().path)
    #expect(try store.load()?.vulkanICDFile == icd.path)
    #expect(throws: Error.self) { try store.save(Configuration(wine: config.wine, dxvkConfigFile: dxvk.path)) }
    #expect(throws: Error.self) { try store.save(Configuration(wine: config.wine, vulkanICDFile: icd.path)) }
    #expect(throws: Error.self) { try PathValidator.profileFile("relative/dxvk.conf") }
    #expect(throws: Error.self) { try PathValidator.profileFile(directory.appendingPathComponent("missing.conf").path) }
    #expect(throws: Error.self) { try PathValidator.profileFile(support.path) }
    #expect(throws: Error.self) { try PathValidator.profileFile(directory.appendingPathComponent("bad:path").path) }
    #expect(try store.load()?.dxvkConfigFile == dxvk.path)
    let metal = try d3dMetalFixture(in: directory)
    let metalRuntime = try compatibleRuntime(in: paths)
    let metalOverlay = try D3DMetalRuntimeOverlay(paths: paths, runtimeRoot: metalRuntime,
                                                  redist: D3DMetalRedist(root: metal))
    #expect(throws: Error.self) {
        try store.save(Configuration(wine: metalOverlay.wine.path, graphicsBackend: .d3dmetal,
                                     d3dMetalDirectory: metal.path))
    }
    try metalOverlay.stage()
    try store.save(Configuration(wine: metalOverlay.wine.path, graphicsBackend: .d3dmetal, d3dMetalDirectory: metal.path))
    #expect(try store.load()?.graphicsBackend == .d3dmetal)
    #expect(try store.load()?.d3dMetalDirectory == metal.path)
    #expect(throws: Error.self) { try store.save(Configuration(wine: config.wine, graphicsBackend: .d3dmetal)) }
    #expect(throws: Error.self) {
        try store.save(Configuration(wine: config.wine, dxvkConfigFile: dxvk.path,
                                     vulkanICDFile: icd.path, graphicsBackend: .d3dmetal,
                                     d3dMetalDirectory: metal.path))
    }
    #expect(throws: Error.self) { try store.save(Configuration(wine: config.wine, graphicsBackend: .builtin, d3dMetalDirectory: metal.path)) }
    #expect(throws: Error.self) { try GraphicsBackend.parse("metal") }
    #expect(throws: Error.self) { try PathValidator.absoluteFile("relative/wine") }
    #expect(throws: Error.self) { try PathValidator.executable(directory.appendingPathComponent("missing").path) }
    let bad = directory.appendingPathComponent("SteamSetup.txt")
    try Data().write(to: bad)
    #expect(throws: Error.self) { try PathValidator.installer(bad.path) }
}

@Test func commandArgumentsEnvironmentAndBottleScope() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let wine = try executable("wine with spaces", in: directory)
    let server = try executable("wineserver", in: directory)
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("Overcross Data"))
    let orchestrator = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path, wineserver: server.path))
    let source = ["PATH": "/bin", "WINEPREFIX": "/other/bottle", "WINEARCH": "win32", "WINEDLLOVERRIDES": "bad", "WINE_D3D_CONFIG": "renderer=vulkan", "DXVK_HUD": "1", "DXVK_CONFIG_FILE": "/untrusted/dxvk.conf", "VK_ICD_FILENAMES": "/untrusted/icd.json", "DYLD_INSERT_LIBRARIES": "bad", "DYLD_LIBRARY_PATH": "/untrusted", "STEAM_RUNTIME": "bad"]
    let initRequest = try orchestrator.bottleInit(environment: source)
    #expect(initRequest.arguments == ["wineboot", "-u"])
    #expect(initRequest.workingDirectory == nil)
    #expect(initRequest.environment["WINEPREFIX"] == paths.bottle.path)
    #expect(initRequest.environment["WINESERVER"] == server.path)
    #expect(initRequest.environment["WINEARCH"] == nil)
    #expect(initRequest.environment["WINEDLLOVERRIDES"] == nil)
    #expect(initRequest.environment["WINE_D3D_CONFIG"] == nil)
    #expect(initRequest.environment["DXVK_HUD"] == nil)
    #expect(initRequest.environment["DXVK_CONFIG_FILE"] == nil)
    #expect(initRequest.environment["VK_ICD_FILENAMES"] == nil)
    #expect(initRequest.environment["DYLD_INSERT_LIBRARIES"] == nil)
    #expect(initRequest.environment["DYLD_LIBRARY_PATH"] == nil)
    #expect(initRequest.environment["STEAM_RUNTIME"] == nil)
    #expect(initRequest.environment["PATH"] == "/bin")

    try initializedBottle(paths)
    #expect(throws: OvercrossError.missingBottle) { try orchestrator.steamOpen(environment: source) }
    #expect(throws: OvercrossError.missingBottle) { try orchestrator.steamShutdown(environment: source) }
    #expect(throws: OvercrossError.missingBottle) { try orchestrator.wineserverWait(environment: source) }
    #expect(throws: OvercrossError.unownedBottle) { try orchestrator.bottleInit(environment: source) }
    try FileManager.default.removeItem(at: paths.bottle.appendingPathComponent("system.reg"))
    try orchestrator.prepareBottleInitialization()
    try Data("registry".utf8).write(to: paths.bottle.appendingPathComponent("system.reg"))
    try orchestrator.markBottleReady()
    #expect(orchestrator.bottleIsInitialized())
    let installer = directory.appendingPathComponent("Steam Setup.exe")
    try Data().write(to: installer)
    #expect(try orchestrator.steamInstaller(installer, environment: source).arguments == [installer.path])
    let silentInstaller = try orchestrator.steamInstaller(installer, silent: true, environment: source)
    #expect(silentInstaller.arguments == [installer.path, "/S"])
    #expect(silentInstaller.workingDirectory == installer.deletingLastPathComponent())
    #expect(silentInstaller.environment["WINEPREFIX"] == paths.bottle.path)
    #expect(silentInstaller.environment["WINEARCH"] == nil)
    let steamFile = try steam(paths)
    #expect(try orchestrator.gameInstall(environment: source).arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "steam://install/5228920"])
    #expect(try orchestrator.gameInstall(webHelperShim: false, environment: source).arguments == [steamFile.path, "steam://install/5228920"])
    #expect(try orchestrator.gameLaunch(environment: source).arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-applaunch", "5228920"])
    #expect(try orchestrator.gameLaunch(graphicsAPI: .d3d11, environment: source).arguments
            == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-applaunch", "5228920", "-force-d3d11"])
    #expect(try orchestrator.gameLaunch(graphicsAPI: .d3d12, environment: source).arguments
            == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-applaunch", "5228920", "-force-d3d12"])
    #expect(throws: Error.self) { try orchestrator.gameLaunch(appID: 123, graphicsAPI: .d3d12, environment: source) }
    #expect(throws: Error.self) { try GameGraphicsAPI.parse("vulkan") }
    #expect(try orchestrator.gameLaunch(webHelperShim: false, environment: source).arguments == [steamFile.path, "-applaunch", "5228920"])
    let defaultOpen = try orchestrator.steamOpen(environment: source)
    #expect(defaultOpen.arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles"])
    #expect(try orchestrator.steamOpen(webHelperShim: false, environment: source).arguments == [steamFile.path])
    #expect(defaultOpen.environment["WINE_D3D_CONFIG"] == nil)
    let debugOpen = try orchestrator.steamOpen(enableCEFDebugging: true, environment: source)
    #expect(debugOpen.arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-cef-enable-debugging"])
    #expect(debugOpen.environment == defaultOpen.environment)
    #expect(debugOpen.workingDirectory == steamFile.deletingLastPathComponent())
    let alternateDebug = try orchestrator.steamOpen(enableCEFDebugging: true, cefDebugPort: 15873, environment: source)
    #expect(alternateDebug.arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-cef-enable-debugging", "-devtools-port", "15873"])
    #expect(alternateDebug.environment == defaultOpen.environment)
    #expect(try Orchestrator.cefDebugPort("15873") == 15873)
    #expect(try Orchestrator.cefDebugPort("65535") == 65535)
    for invalid in ["", "0", "1023", "65536", "-1", "+15873", "15873:8080", "abc"] {
        #expect(throws: Error.self) { try Orchestrator.cefDebugPort(invalid) }
    }
    #expect(throws: Error.self) { try orchestrator.steamOpen(cefDebugPort: 15873, environment: source) }
    #expect(throws: Error.self) { try orchestrator.steamOpen(enableCEFDebugging: true, cefDebugPort: 1, environment: source) }
    #expect(try orchestrator.steamOpen(disableCEFGPU: true, environment: source).arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-cef-disable-gpu"])
    let glOpen = try orchestrator.steamOpen(wineRenderer: .gl, environment: source)
    #expect(glOpen.arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles"])
    #expect(glOpen.environment["WINE_D3D_CONFIG"] == "renderer=gl")
    #expect(glOpen.environment["WINEPREFIX"] == paths.bottle.path)
    let combined = try orchestrator.steamOpen(disableCEFGPU: true, wineRenderer: .gl, environment: source)
    #expect(combined.arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-cef-disable-gpu"])
    #expect(combined.environment["WINE_D3D_CONFIG"] == "renderer=gl")
    #expect(combined.workingDirectory == steamFile.deletingLastPathComponent())
    #expect(try orchestrator.steamOpen(disableCEFGPU: true, enableCEFDebugging: true, environment: source).arguments
            == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-cef-disable-gpu", "-cef-enable-debugging"])
    #expect(throws: Error.self) { try SteamWineRenderer.parse("vulkan") }
    #expect(throws: Error.self) { try SteamWineRenderer.parse("") }
    #expect(try orchestrator.steamShutdown(environment: source).arguments == [steamFile.path, "-shutdown"])
    let overrides = try orchestrator.d3dMetalGameOverrides(environment: source)
    #expect(overrides.map { $0.arguments[4] } == ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi"])
    #expect(overrides.allSatisfy { $0.arguments.prefix(3) == ["reg", "add", #"HKCU\Software\Wine\AppDefaults\BrickByBrick.exe\DllOverrides"#]
        && $0.arguments.suffix(3) == ["/d", "builtin", "/f"] && $0.environment["WINEPREFIX"] == paths.bottle.path })
    let wait = try orchestrator.wineserverWait(environment: source)
    #expect(wait.executable == server)
    #expect(wait.arguments == ["-w"])
    #expect(wait.environment["WINEPREFIX"] == paths.bottle.path)
    #expect(wait.environment["WINESERVER"] == server.path)
    #expect(wait.environment["STEAM_RUNTIME"] == nil)
    #expect(wait.workingDirectory == nil)
    let noServer = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path))
    #expect(throws: OvercrossError.missingWineserver) { try noServer.wineserverWait(environment: source) }

    let support = directory.appendingPathComponent("runtime support libs")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let withLibraries = Orchestrator(paths: paths,
                                    configuration: Configuration(wine: wine.path, wineserver: server.path,
                                                                 libraryDirectory: support.path))
    let requests = try [withLibraries.bottleInit(environment: source),
                        withLibraries.steamInstaller(installer, environment: source),
                        withLibraries.steamOpen(environment: source),
                        withLibraries.steamShutdown(environment: source),
                        withLibraries.wineserverWait(environment: source),
                        withLibraries.gameInstall(environment: source),
                        withLibraries.gameLaunch(environment: source)]
    for request in requests {
        #expect(request.environment["WINEPREFIX"] == paths.bottle.path)
        #expect(request.environment["DYLD_LIBRARY_PATH"] == support.path)
        #expect(request.environment["DYLD_INSERT_LIBRARIES"] == nil)
    }
    let dxvk = directory.appendingPathComponent("DXVK config.conf")
    let icd = directory.appendingPathComponent("Vulkan ICD.json")
    try Data("dxvk".utf8).write(to: dxvk)
    try Data("{}".utf8).write(to: icd)
    let withGraphics = Orchestrator(paths: paths,
                                    configuration: Configuration(wine: wine.path, wineserver: server.path,
                                                                 dxvkConfigFile: dxvk.path, vulkanICDFile: icd.path))
    let graphicsRequests = try [withGraphics.bottleInit(environment: source),
                                withGraphics.steamInstaller(installer, environment: source),
                                withGraphics.steamOpen(environment: source),
                                withGraphics.steamShutdown(environment: source),
                                withGraphics.wineserverWait(environment: source),
                                withGraphics.gameInstall(environment: source),
                                withGraphics.gameLaunch(environment: source)]
    for request in graphicsRequests {
        #expect(request.environment["WINEPREFIX"] == paths.bottle.path)
        #expect(request.environment["DXVK_CONFIG_FILE"] == dxvk.path)
        #expect(request.environment["VK_ICD_FILENAMES"] == icd.path)
        #expect(request.environment["DXVK_HUD"] == nil)
        #expect(request.environment["DYLD_LIBRARY_PATH"] == nil)
    }
    let metal = try d3dMetalFixture(in: directory)
    let metalRuntime = try compatibleRuntime(in: paths)
    try D3DMetalRuntimeOverlay(paths: paths, runtimeRoot: metalRuntime,
                               redist: D3DMetalRedist(root: metal)).stage()
    _ = try ownedGame(paths)
    let gameOverrides = "[Software\\\\Wine\\\\AppDefaults\\\\BrickByBrick.exe\\\\DllOverrides]\n"
        + ["d3d11", "d3d12", "d3d12core", "dxgi"].map { "\"\($0)\"=\"builtin\"\n" }.joined()
    try gameOverrides.write(to: paths.bottle.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
    let withMetal = Orchestrator(paths: paths,
                                 configuration: Configuration(wine: metalRuntime.appendingPathComponent("bin/wine").path,
                                                              wineserver: server.path,
                                                              graphicsBackend: .d3dmetal, d3dMetalDirectory: metal.path))
    let metalRequests = try [withMetal.bottleInit(environment: source),
                             withMetal.steamInstaller(installer, environment: source),
                             withMetal.steamOpen(environment: source),
                             withMetal.steamShutdown(environment: source),
                             withMetal.wineserverWait(environment: source),
                             withMetal.gameInstall(environment: source),
                             withMetal.gameLaunch(environment: source)]
    for request in metalRequests {
        #expect(request.environment["WINEPREFIX"] == paths.bottle.path)
        #expect(request.environment["DXVK_CONFIG_FILE"] == nil)
        #expect(request.environment["VK_ICD_FILENAMES"] == nil)
        #expect(request.environment["DXVK_HUD"] == nil)
    }
    #expect(throws: Error.self) {
        try Orchestrator(paths: paths, configuration: Configuration(wine: wine.path, dxvkConfigFile: dxvk.path))
            .steamOpen(environment: source)
    }
    for request in [try orchestrator.steamOpen(environment: source),
                    try orchestrator.steamShutdown(environment: source),
                    try orchestrator.gameInstall(environment: source),
                    try orchestrator.gameLaunch(environment: source)] {
        #expect(request.workingDirectory == steamFile.deletingLastPathComponent())
    }
}

@Test func steamWebHelperShimInstallsUpdatesAndRestores() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let wine = try executable("wine", in: directory)
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    try initializedBottle(paths)
    try FileManager.default.createDirectory(at: paths.bottle, withIntermediateDirectories: true)
    try Data(#"{"version":1,"state":"ready"}"#.utf8).write(to: paths.bottle.appendingPathComponent(".overcross-bottle.json"))
    let orchestrator = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path))
    _ = try steam(paths)
    let shim = try orchestrator.steamWebHelperShim(shim: Data("overcross shim".utf8))
    let fm = FileManager.default

    #expect(try shim.state() == .missing)
    #expect(try shim.install() == false)
    try fm.createDirectory(at: shim.directory, withIntermediateDirectories: true)
    try Data("valve v1".utf8).write(to: shim.helper)
    #expect(try shim.state() == .original)

    #expect(try shim.install())
    #expect(try shim.state() == .installed)
    #expect(try Data(contentsOf: shim.helper) == shim.shim)
    #expect(try Data(contentsOf: shim.realHelper) == Data("valve v1".utf8))
    #expect(fm.isExecutableFile(atPath: shim.helper.path))
    #expect(try shim.install())
    #expect(try Data(contentsOf: shim.realHelper) == Data("valve v1".utf8))

    // A Steam update writes Valve's new helper over the shim.
    try Data("valve v2".utf8).write(to: shim.helper)
    #expect(try shim.state() == .original)
    #expect(try shim.install())
    #expect(try Data(contentsOf: shim.realHelper) == Data("valve v2".utf8))
    #expect(try fm.contentsOfDirectory(atPath: shim.directory.path).sorted() == ["steamwebhelper.exe", "steamwebhelper.real.exe"])

    try shim.remove()
    #expect(try shim.state() == .original)
    #expect(try Data(contentsOf: shim.helper) == Data("valve v2".utf8))
    #expect(!fm.fileExists(atPath: shim.realHelper.path))

    try shim.install()
    try fm.removeItem(at: shim.realHelper)
    #expect(try shim.state() == .incomplete)
    #expect(throws: Error.self) { try shim.install() }
    try shim.remove()
    #expect(try shim.state() == .missing)

    try fm.createSymbolicLink(at: shim.helper, withDestinationURL: directory)
    #expect(throws: Error.self) { try shim.state() }
}

@Test func bundledSteamWebHelperShimIsWindowsExecutable() throws {
    let shim = try SteamWebHelperShim.bundledShim()
    #expect(shim.prefix(2) == Data("MZ".utf8))
}

@Test func guiRequestUsesExplicitWorkingDirectory() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let executableFile = try executable("fake wine", in: directory, body: "/bin/pwd > \"$1\"")
    let workingDirectory = directory.appendingPathComponent("Program Files (x86)/Steam")
    try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    let output = directory.appendingPathComponent("cwd.txt")
    let request = LaunchRequest(executable: executableFile, arguments: [output.path],
                                environment: ["PATH": "/bin"], log: directory.appendingPathComponent("gui.log"),
                                label: "gui-cwd", workingDirectory: workingDirectory)
    try ProcessRunner.sendGUIRequest(request)
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if let contents = try? Data(contentsOf: output), !contents.isEmpty { break }
        usleep(20_000)
    }
    #expect(try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == workingDirectory.path)
}

@Test func rejectsEscapingBottleSymlink() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let wine = try executable("wine", in: directory)
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    try FileManager.default.createDirectory(at: paths.bottle.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: paths.bottle, withDestinationURL: directory)
    let orchestrator = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path))
    #expect(throws: Error.self) { try orchestrator.bottleInit(environment: [:]) }
}

@Test func waitsForDelayedWineRegistryBeforeMarkingReady() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let wine = try executable("fake-wine", in: directory, body: "( /bin/sleep 0.3; echo registry > \"$WINEPREFIX/system.reg\" ) &\nexit 0")
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let orchestrator = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path))
    let request = try orchestrator.bottleInit(environment: ["PATH": "/bin"])
    try orchestrator.prepareBottleInitialization()
    try ProcessRunner.runSetup(request, timeout: 2)
    #expect(!orchestrator.bottleIsInitialized())
    try orchestrator.markBottleReady(timeout: 2)
    #expect(orchestrator.bottleIsInitialized())
}

@Test func rejectsSymlinkLogs() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let success = try executable("success", in: directory, body: "echo unsafe")
    let outside = directory.appendingPathComponent("outside.log")
    try "original".write(to: outside, atomically: true, encoding: .utf8)
    let logs = directory.appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let linkedFile = logs.appendingPathComponent("linked.log")
    try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: outside)
    let request = LaunchRequest(executable: success, arguments: [], environment: [:], log: linkedFile, label: "linked")
    #expect(throws: Error.self) { try ProcessRunner.runSetup(request, timeout: 2) }
    #expect(try String(contentsOf: outside, encoding: .utf8) == "original")
    let linkedDirectory = directory.appendingPathComponent("linked-logs")
    try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: logs)
    let second = LaunchRequest(executable: success, arguments: [], environment: [:], log: linkedDirectory.appendingPathComponent("new.log"), label: "linked-dir")
    #expect(throws: Error.self) { try ProcessRunner.runSetup(second, timeout: 2) }
    #expect(!FileManager.default.fileExists(atPath: logs.appendingPathComponent("new.log").path))
}

@Test func appIDsAndProcessFailures() throws {
    #expect(try Orchestrator.appID("5228920") == 5_228_920)
    for invalid in ["0", "-1", "4294967296", "abc"] {
        #expect(throws: Error.self) { try Orchestrator.appID(invalid) }
    }
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let failure = try executable("failure", in: directory, body: "exit 7")
    let failedRequest = LaunchRequest(executable: failure, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("failure.log"), label: "failure")
    #expect(throws: OvercrossError.processFailed("failure", 7)) { try ProcessRunner.runSetup(failedRequest, timeout: 3) }
    let slow = try executable("slow", in: directory, body: "exec /bin/sleep 2")
    let slowRequest = LaunchRequest(executable: slow, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("slow.log"), label: "slow")
    #expect(throws: OvercrossError.processTimedOut("slow", 0.1)) { try ProcessRunner.runSetup(slowRequest, timeout: 0.1) }
}

@Test func timeoutKillsOwnedProcessGroupDescendant() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let childPID = directory.appendingPathComponent("child.pid")
    let script = "trap '' TERM\n/bin/sleep 30 &\necho $! > '\(childPID.path)'\nwhile :; do /bin/sleep 1; done"
    let stubborn = try executable("stubborn", in: directory, body: script)
    let request = LaunchRequest(executable: stubborn, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("group.log"), label: "stubborn")
    #expect(throws: OvercrossError.processTimedOut("stubborn", 0.2)) { try ProcessRunner.runSetup(request, timeout: 0.2) }
    let pid = try Int32(String(contentsOf: childPID, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
    #expect(pid != nil)
    if let pid {
        let check = Process()
        let output = Pipe()
        check.executableURL = URL(fileURLWithPath: "/bin/ps")
        check.arguments = ["-o", "stat=", "-p", String(pid)]
        check.standardOutput = output
        try check.run()
        check.waitUntilExit()
        let state = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.hasPrefix("Z"))
    }
}

@Test func timeoutKeepsGroupReservedWhenDirectChildExitsOnTerm() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let childPID = directory.appendingPathComponent("child.pid")
    let script = "( trap '' TERM; exec /bin/sleep 30 ) &\necho $! > '\(childPID.path)'\ntrap 'exit 0' TERM\nwait"
    let parent = try executable("term-responsive-parent", in: directory, body: script)
    let request = LaunchRequest(executable: parent, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("group.log"), label: "term-responsive")
    #expect(throws: OvercrossError.processTimedOut("term-responsive", 0.2)) { try ProcessRunner.runSetup(request, timeout: 0.2) }
    let pid = try Int32(String(contentsOf: childPID, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
    #expect(pid != nil)
    if let pid {
        let check = Process()
        let output = Pipe()
        check.executableURL = URL(fileURLWithPath: "/bin/ps")
        check.arguments = ["-o", "stat=", "-p", String(pid)]
        check.standardOutput = output
        try check.run()
        check.waitUntilExit()
        let state = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.hasPrefix("Z"))
    }
}
