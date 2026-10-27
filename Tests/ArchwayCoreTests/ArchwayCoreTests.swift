import Foundation
import Testing
@testable import ArchwayCore

private func temporaryDirectory() throws -> URL {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = package.appendingPathComponent(".build/test-temp/archway-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func migrationJSON(_ file: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
}

@Test func migratesDefaultAndAlphaDataWithoutChangingExternalPathsOrRelativeState() throws {
    let support = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let old = support.appendingPathComponent("Overcross")
    let new = support.appendingPathComponent("Archway")
    let alpha = old.appendingPathComponent("archway-alpha")
    let bottle = old.appendingPathComponent("bottles/steam")
    let alphaBottle = alpha.appendingPathComponent("bottles/steam")
    let backup = alpha.appendingPathComponent("runtime-overlays/upstream/Wine/.overcross-d3dmetal-backup")
    let defaultBackup = old.appendingPathComponent("runtime-overlays/winecx-gptk-4.7.3/payload/Libraries/Wine/.overcross-d3dmetal-backup")
    let graphicsBackup = old.appendingPathComponent("graphics-backups/123")
    for directory in [bottle, alphaBottle, backup, defaultBackup, graphicsBackup] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let wineBin = backup.deletingLastPathComponent().appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: wineBin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: wineBin.appendingPathComponent("wine"), withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
    let originalDLL = Data([0x4d, 0x5a, 0x01, 0x02])
    try originalDLL.write(to: graphicsBackup.appendingPathComponent("d3d11.dll"))
    for directory in [bottle, alphaBottle] {
        try Data(#"{"version":1,"state":"ready"}"#.utf8)
            .write(to: directory.appendingPathComponent(".overcross-bottle.json"))
        try Data("registry".utf8).write(to: directory.appendingPathComponent("system.reg"))
    }
    let relativeState = Data(#"{"version":1,"phase":"ready","entries":[{"relativePath":"wine/x86_64-windows/d3d11.dll","kind":"file","installedFingerprint":"abc"}]}"#.utf8)
    try relativeState.write(to: backup.appendingPathComponent("state.json"))
    try relativeState.write(to: defaultBackup.appendingPathComponent("state.json"))
    let defaultConfig = ["wine": old.path + "/runtime-overlays/winecx-gptk-4.7.3/payload/Libraries/Wine/bin/wine",
                         "external": "/tmp/external/Wine/bin/wine",
                         "boundary": old.path + "-extra/bin/wine"]
    let alphaConfig = ["wine": alpha.path + "/runtime-overlays/upstream/Wine/bin/wine",
                       "libraryDirectory": alpha.path + "/runtime-overlays/upstream/Wine/lib",
                       "d3dMetalDirectory": "/tmp/redist/lib"]
    try JSONSerialization.data(withJSONObject: defaultConfig).write(to: old.appendingPathComponent("config.json"))
    try JSONSerialization.data(withJSONObject: alphaConfig).write(to: alpha.appendingPathComponent("config.json"))
    let localGames: [[String: Any]] = [["id": 1, "title": "Inside", "path": old.path + "/games/a.exe"],
                                     ["id": 2, "title": "Outside", "path": "/tmp/external.exe"],
                                     ["id": 3, "title": "Adjacent", "path": old.path + "-extra/game.exe"]]
    try JSONSerialization.data(withJSONObject: localGames).write(to: old.appendingPathComponent("local-games.json"))
    let oldWindowsPath = "Z:" + old.path.replacingOccurrences(of: "/", with: "\\\\")
    let newWindowsPath = "Z:" + new.path.replacingOccurrences(of: "/", with: "\\\\")
    let registry = "Wine Registry Version 2\n\"path\"=\"\(oldWindowsPath)\\\\games\"\n\"adjacent\"=\"\(oldWindowsPath)-extra\"\n"
    for root in [bottle, alphaBottle] {
        for name in ["system.reg", "user.reg", "user.reg.before-lldb", "user.reg.before-webhelper-overrides"] {
            try Data(registry.utf8).write(to: root.appendingPathComponent(name))
        }
    }
    let cache = Data(#"{"steamID":"test","games":[]}"#.utf8)
    try cache.write(to: old.appendingPathComponent("steam-library-cache.json"))

    #expect(try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in false }))
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(try migrationJSON(new.appendingPathComponent("config.json"))["wine"] as? String
            == new.path + "/runtime-overlays/winecx-gptk-4.7.3/payload/Libraries/Wine/bin/wine")
    #expect(try migrationJSON(new.appendingPathComponent("config.json"))["external"] as? String == "/tmp/external/Wine/bin/wine")
    #expect(try migrationJSON(new.appendingPathComponent("config.json"))["boundary"] as? String == old.path + "-extra/bin/wine")
    let migratedAlpha = try migrationJSON(new.appendingPathComponent("archway-alpha/config.json"))
    #expect(migratedAlpha["wine"] as? String == new.path + "/archway-alpha/runtime-overlays/upstream/Wine/bin/wine")
    #expect(migratedAlpha["libraryDirectory"] as? String == new.path + "/archway-alpha/runtime-overlays/upstream/Wine/lib")
    #expect(migratedAlpha["d3dMetalDirectory"] as? String == "/tmp/redist/lib")
    let games = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: new.appendingPathComponent("local-games.json"))) as? [[String: Any]])
    #expect(games.map { $0["path"] as? String } == [new.path + "/games/a.exe", "/tmp/external.exe", old.path + "-extra/game.exe"])
    #expect(try Data(contentsOf: new.appendingPathComponent("steam-library-cache.json")) == cache)
    #expect(try Data(contentsOf: new.appendingPathComponent("graphics-backups/123/d3d11.dll")) == originalDLL)
    #expect(try Data(contentsOf: new.appendingPathComponent("archway-alpha/runtime-overlays/upstream/Wine/.archway-d3dmetal-backup/state.json")) == relativeState)
    #expect(try Data(contentsOf: new.appendingPathComponent("runtime-overlays/winecx-gptk-4.7.3/payload/Libraries/Wine/.archway-d3dmetal-backup/state.json")) == relativeState)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: new.appendingPathComponent("archway-alpha/runtime-overlays/upstream/Wine/bin/wine").path) == "/usr/bin/true")
    for root in [new, new.appendingPathComponent("archway-alpha")] {
        let paths = try AppPaths(dataDirectory: root)
        #expect(Orchestrator(paths: paths, configuration: Configuration(wine: "/usr/bin/true")).bottleIsInitialized())
        #expect(!FileManager.default.fileExists(atPath: paths.bottle.appendingPathComponent(".overcross-bottle.json").path))
        for name in ["system.reg", "user.reg", "user.reg.before-lldb", "user.reg.before-webhelper-overrides"] {
            let text = try String(contentsOf: paths.bottle.appendingPathComponent(name), encoding: .utf8)
            #expect(text.contains(newWindowsPath + "\\\\games"))
            #expect(text.contains(oldWindowsPath + "-extra"))
            #expect(!text.contains(oldWindowsPath + "\\\\games"))
        }
    }
    #expect((try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in false })) == false)
}

@Test func registryRebasePreservesOtherBytesAndWindowsPathBoundaries() throws {
    let old = "/tmp/Application Support/Overcross"
    let new = "/tmp/Application Support/Archway"
    let oldWindows = old.replacingOccurrences(of: "/", with: "\\")
    let newWindows = new.replacingOccurrences(of: "/", with: "\\")
    var input = Data([0xff, 0x00])
    input.append(Data("Z:\(oldWindows)\\game\nZ:\(oldWindows)-extra\n/tmp/prefix\(old)/game".utf8))
    let result = try #require(DataMigration.rebaseRegistry(input, from: old, to: new))
    #expect(Data(result.prefix(2)) == Data([0xff, 0x00]))
    let text = try #require(String(data: Data(result.dropFirst(2)), encoding: .utf8))
    #expect(text.contains("Z:\(newWindows)\\game"))
    #expect(text.contains("Z:\(oldWindows)-extra"))
    #expect(text.contains("/tmp/prefix\(old)/game"))
}

@Test func affectedWineProcessMatchingIncludesOrphansWithoutPrefixOvermatch() {
    let root = "/tmp/Application Support/Overcross"
    #expect(DataMigration.affectedWineProcessLine(
        "55006 /opt/wine/bin/wine winedbg --auto WINEPREFIX=\(root)/upstream-1120-probe", root: root))
    #expect(DataMigration.affectedWineProcessLine(
        "55007 /opt/wine/bin/wine WINEPREFIX=/external \(root)/archway-alpha", root: root))
    #expect(!DataMigration.affectedWineProcessLine(
        "55008 /opt/wine/bin/wine WINEPREFIX=\(root)-extra", root: root))
    #expect(!DataMigration.affectedWineProcessLine(
        "55009 /usr/bin/archway WINEPREFIX=\(root)/archway-alpha", root: root))
}

@Test func migrationPreservesConflictingRootsAndRefusesRunningWine() throws {
    let support = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let old = support.appendingPathComponent("Overcross")
    let new = support.appendingPathComponent("Archway")
    let bottle = old.appendingPathComponent("bottles/steam")
    try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
    try Data("registry".utf8).write(to: bottle.appendingPathComponent("system.reg"))
    #expect(throws: Error.self) {
        try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in true })
    }
    #expect(FileManager.default.fileExists(atPath: old.path))
    #expect(!FileManager.default.fileExists(atPath: new.path))
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: false)
    try Data("keep".utf8).write(to: new.appendingPathComponent("sentinel"))
    #expect(throws: Error.self) {
        try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in false })
    }
    #expect(try Data(contentsOf: new.appendingPathComponent("sentinel")) == Data("keep".utf8))
    #expect(FileManager.default.fileExists(atPath: old.path))
}

@Test func migrationPreflightRejectsInvalidJSONBeforeMovingData() throws {
    let support = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let old = support.appendingPathComponent("Overcross")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: old.appendingPathComponent("config.json"))
    #expect(throws: Error.self) {
        try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in false })
    }
    #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("config.json").path))
    #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Archway").path))
}

@Test func migrationRejectsSymlinkedAlphaConfigParentWithoutChangingExternalConfig() throws {
    let support = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let old = support.appendingPathComponent("Overcross")
    let external = support.appendingPathComponent("external-alpha")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    let config = external.appendingPathComponent("config.json")
    let original = try JSONSerialization.data(withJSONObject: ["wine": old.path + "/runtime-overlays/upstream/Wine/bin/wine"])
    try original.write(to: config)
    try FileManager.default.createSymbolicLink(at: old.appendingPathComponent("archway-alpha"), withDestinationURL: external)

    do {
        _ = try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in false })
        Issue.record("Migration accepted a symlinked alpha config parent")
    } catch {
        #expect(error.localizedDescription.contains("symlink"))
    }
    #expect(try Data(contentsOf: config) == original)
    #expect(FileManager.default.fileExists(atPath: old.path))
    #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Archway").path))
}

@Test func migrationRejectsSymlinkedWineMarkerParentWithoutChangingExternalBackup() throws {
    let support = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let old = support.appendingPathComponent("Overcross")
    let library = old.appendingPathComponent("runtime-overlays/winecx-gptk-4.7.3/payload/Libraries")
    let external = support.appendingPathComponent("external-wine")
    let backup = external.appendingPathComponent(".overcross-d3dmetal-backup")
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
    let state = Data(#"{"phase":"ready"}"#.utf8)
    try state.write(to: backup.appendingPathComponent("state.json"))
    try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("Wine"), withDestinationURL: external)

    do {
        _ = try DataMigration.migrateIfNeeded(applicationSupportDirectory: support, wineIsRunning: { _ in false })
        Issue.record("Migration accepted a symlinked Wine marker parent")
    } catch {
        #expect(error.localizedDescription.contains("symlink"))
    }
    #expect(try Data(contentsOf: backup.appendingPathComponent("state.json")) == state)
    #expect(!FileManager.default.fileExists(atPath: external.appendingPathComponent(".archway-d3dmetal-backup").path))
    #expect(FileManager.default.fileExists(atPath: old.path))
    #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("Archway").path))
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
    try Data(#"{"version":1,"state":"ready"}"#.utf8).write(to: paths.bottle.appendingPathComponent(".archway-bottle.json"))
    let game = paths.steamApps.appendingPathComponent("common/Example Game/Example.exe")
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
                throw ArchwayError.invalidPath("injected replacement failure")
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
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("Archway Data"))
    let game = try ownedGame(paths)
    let gameDirectory = game.deletingLastPathComponent()
    let old11 = try windowsDLL("d3d11.dll", in: gameDirectory, tag: 1)
    let oldGI = try windowsDLL("dxgi.dll", in: gameDirectory, tag: 2)
    let old11Bytes = try Data(contentsOf: old11)
    let oldGIBytes = try Data(contentsOf: oldGI)
    let manager = try GameGraphicsSidecars(paths: paths, gameDirectory: gameDirectory, backupName: "123")
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

@Test func gameGraphicsSidecarsFindNestedExecutablesAndRejectEscapes() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let gameDirectory = try ownedGame(paths).deletingLastPathComponent()
    let binaries = gameDirectory.appendingPathComponent("Binaries")
    try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
    try Data("game".utf8).write(to: binaries.appendingPathComponent("Shipping.exe"))
    try Data("helper".utf8).write(to: binaries.appendingPathComponent("UnityCrashHandler64.exe"))
    let nested = try windowsDLL("dxgi.dll", in: binaries, tag: 4)
    let manager = try GameGraphicsSidecars(paths: paths, gameDirectory: gameDirectory, backupName: "123")
    #expect(manager.executables.map(\.lastPathComponent) == ["Shipping.exe", "Example.exe"])
    #expect(throws: Error.self) { try manager.requireD3DMetalReady() }
    try manager.suspendForD3DMetal()
    #expect(!FileManager.default.fileExists(atPath: nested.path))
    #expect(FileManager.default.fileExists(atPath: manager.backupDirectory.appendingPathComponent("Binaries/dxgi.dll").path))
    try manager.restore()
    #expect(FileManager.default.fileExists(atPath: nested.path))

    let outside = directory.appendingPathComponent("outside.dll")
    try Data("outside".utf8).write(to: outside)
    let linkedTarget = gameDirectory.appendingPathComponent("d3d11.dll")
    try FileManager.default.createSymbolicLink(at: linkedTarget, withDestinationURL: outside)
    #expect(throws: Error.self) { try manager.suspendForD3DMetal() }
    #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    #expect(try manager.installedBackend() == nil)
    for name in ["", "../escape", ".hidden", "a/b"] {
        #expect(throws: Error.self) { try GameGraphicsSidecars(paths: paths, gameDirectory: gameDirectory, backupName: name) }
    }
    #expect(throws: Error.self) { try GameGraphicsSidecars(paths: paths, gameDirectory: directory, backupName: "123") }
}

@Test func d3dMetalGameGateRequiresBuiltinOverridesAfterMovingDLLs() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("data"))
    let game = try ownedGame(paths)
    let profile = try GameGraphicsSidecars(paths: paths, gameDirectory: game.deletingLastPathComponent(), backupName: "123")
    // Nothing of its own beside the game: the runtime serves it as is.
    try profile.requireD3DMetalReady()
    _ = try windowsDLL("d3d11.dll", in: game.deletingLastPathComponent(), tag: 3)
    #expect(throws: Error.self) { try profile.requireD3DMetalReady() }
    try profile.suspendForD3DMetal()
    let registry = paths.bottle.appendingPathComponent("user.reg")
    let section = "[Software\\\\Wine\\\\AppDefaults\\\\Example.exe\\\\DllOverrides]\n"
    try (section + "\"d3d10\"=\"builtin\"\n\"d3d11\"=\"native,builtin\"\n\"d3d12\"=\"builtin\"\n\"d3d12core\"=\"builtin\"\n\"dxgi\"=\"builtin\"\n")
        .write(to: registry, atomically: true, encoding: .utf8)
    #expect(throws: Error.self) { try profile.requireD3DMetalReady() }
    try (section + "\"d3d10\"=\"builtin\"\n\"d3d11\"=\"builtin\"\n\"d3d12\"=\"builtin\"\n\"d3d12core\"=\"builtin\"\n\"dxgi\"=\"builtin\"\n")
        .write(to: registry, atomically: true, encoding: .utf8)
    try profile.requireD3DMetalReady()
    _ = try windowsDLL("d3d11.dll", in: game.deletingLastPathComponent(), tag: 5)
    #expect(throws: Error.self) { try profile.requireD3DMetalReady() }
}

@Test func configurationRoundTripAndPathValidation() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("Application Support/Archway"))
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
    let paths = try AppPaths(dataDirectory: directory.appendingPathComponent("Archway Data"))
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
    #expect(throws: ArchwayError.missingBottle) { try orchestrator.steamOpen(environment: source) }
    #expect(throws: ArchwayError.missingBottle) { try orchestrator.steamShutdown(environment: source) }
    #expect(throws: ArchwayError.missingBottle) { try orchestrator.wineserverWait(environment: source) }
    #expect(throws: ArchwayError.unownedBottle) { try orchestrator.bottleInit(environment: source) }
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
    #expect(try orchestrator.gameInstall(appID: 123, environment: source).arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "steam://install/123"])
    #expect(try orchestrator.gameInstall(appID: 123, webHelperShim: false, environment: source).arguments == [steamFile.path, "steam://install/123"])
    #expect(try orchestrator.gameLaunch(appID: 123, environment: source).arguments == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-applaunch", "123"])
    #expect(try orchestrator.gameLaunch(appID: 123, graphicsAPI: .d3d11, environment: source).arguments
            == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-applaunch", "123", "-force-d3d11"])
    #expect(try orchestrator.gameLaunch(appID: 123, graphicsAPI: .d3d12, environment: source).arguments
            == [steamFile.path, "-noverifyfiles", "-norepairfiles", "-applaunch", "123", "-force-d3d12"])
    #expect(throws: Error.self) { try GameGraphicsAPI.parse("vulkan") }
    #expect(try orchestrator.gameLaunch(appID: 123, webHelperShim: false, environment: source).arguments == [steamFile.path, "-applaunch", "123"])
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
    let overrides = try orchestrator.d3dMetalGameOverrides(executables: ["Example.exe"], environment: source)
    #expect(overrides.map { $0.arguments[4] } == ["d3d10", "d3d11", "d3d12", "d3d12core", "dxgi"])
    #expect(overrides.allSatisfy { $0.arguments.prefix(3) == ["reg", "add", #"HKCU\Software\Wine\AppDefaults\Example.exe\DllOverrides"#]
        && $0.arguments.suffix(3) == ["/d", "builtin", "/f"] && $0.environment["WINEPREFIX"] == paths.bottle.path })
    let wait = try orchestrator.wineserverWait(environment: source)
    #expect(wait.executable == server)
    #expect(wait.arguments == ["-w"])
    #expect(wait.environment["WINEPREFIX"] == paths.bottle.path)
    #expect(wait.environment["WINESERVER"] == server.path)
    #expect(wait.environment["STEAM_RUNTIME"] == nil)
    #expect(wait.workingDirectory == nil)
    let noServer = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path))
    #expect(throws: ArchwayError.missingWineserver) { try noServer.wineserverWait(environment: source) }

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
                        withLibraries.gameInstall(appID: 123, environment: source),
                        withLibraries.gameLaunch(appID: 123, environment: source)]
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
                                withGraphics.gameInstall(appID: 123, environment: source),
                                withGraphics.gameLaunch(appID: 123, environment: source)]
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
    let gameOverrides = "[Software\\\\Wine\\\\AppDefaults\\\\Example.exe\\\\DllOverrides]\n"
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
                             withMetal.gameInstall(appID: 123, environment: source),
                             withMetal.gameLaunch(appID: 123, environment: source)]
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
                    try orchestrator.gameInstall(appID: 123, environment: source),
                    try orchestrator.gameLaunch(appID: 123, environment: source)] {
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
    try Data(#"{"version":1,"state":"ready"}"#.utf8).write(to: paths.bottle.appendingPathComponent(".archway-bottle.json"))
    let orchestrator = Orchestrator(paths: paths, configuration: Configuration(wine: wine.path))
    _ = try steam(paths)
    let shim = try orchestrator.steamWebHelperShim(shim: Data("archway shim".utf8))
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
    #expect(try Orchestrator.appID("123") == 123)
    for invalid in ["0", "-1", "4294967296", "abc"] {
        #expect(throws: Error.self) { try Orchestrator.appID(invalid) }
    }
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let failure = try executable("failure", in: directory, body: "exit 7")
    let failedRequest = LaunchRequest(executable: failure, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("failure.log"), label: "failure")
    #expect(throws: ArchwayError.processFailed("failure", 7)) { try ProcessRunner.runSetup(failedRequest, timeout: 3) }
    let slow = try executable("slow", in: directory, body: "exec /bin/sleep 2")
    let slowRequest = LaunchRequest(executable: slow, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("slow.log"), label: "slow")
    #expect(throws: ArchwayError.processTimedOut("slow", 0.1)) { try ProcessRunner.runSetup(slowRequest, timeout: 0.1) }
}

@Test func timeoutKillsOwnedProcessGroupDescendant() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let childPID = directory.appendingPathComponent("child.pid")
    let script = "trap '' TERM\n/bin/sleep 30 &\necho $! > '\(childPID.path)'\nwhile :; do /bin/sleep 1; done"
    let stubborn = try executable("stubborn", in: directory, body: script)
    let request = LaunchRequest(executable: stubborn, arguments: [], environment: ["PATH": "/bin"], log: directory.appendingPathComponent("group.log"), label: "stubborn")
    #expect(throws: ArchwayError.processTimedOut("stubborn", 0.2)) { try ProcessRunner.runSetup(request, timeout: 0.2) }
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
    #expect(throws: ArchwayError.processTimedOut("term-responsive", 0.2)) { try ProcessRunner.runSetup(request, timeout: 0.2) }
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

@Test func gameProcessesMatchWindowsCommandLines() {
    let ps = """
      101 /Applications/T3 Code.app/Contents/MacOS/T3 Code
      202 C:\\Program Files (x86)\\Steam\\steamapps\\common\\Example Game: Deluxe Edition!\\Example.exe -force-d3d11
      303 Example.exe NoDefaultCurrentDirectoryInExePath=1
      404 C:\\Program Files (x86)\\Steam\\steam.exe -noverifyfiles
      505 /Users/me/Games/Other.EXE
    """
    let found = GameProcesses.parse(psOutput: ps, imageNames: ["example.exe", "other.exe"])
    #expect(found == [.init(pid: 202, imageName: "example.exe"),
                      .init(pid: 303, imageName: "example.exe"),
                      .init(pid: 505, imageName: "other.exe")])
    #expect(GameProcesses.imageName(inCommandLine: "no executable here") == nil)
}

@Test func gameExecutablesSkipHelpersAndManifestValuesParse() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let game = directory.appendingPathComponent("My Game")
    try FileManager.default.createDirectory(at: game.appendingPathComponent("bin"), withIntermediateDirectories: true)
    for name in ["Game.exe", "UnityCrashHandler64.exe", "unins000.exe", "bin/Server.exe", "readme.txt"] {
        try Data().write(to: game.appendingPathComponent(name))
    }
    #expect(GameProcesses.executableNames(in: game) == ["game.exe", "server.exe"])

    let manifest = """
    "AppState"
    {
        "appid"\t\t"123"
        "installdir"\t\t"Example Game: Deluxe Edition!"
        "StateFlags"\t\t"4"
    }
    """
    #expect(GameProcesses.value(of: "installdir", inManifest: manifest) == "Example Game: Deluxe Edition!")
    #expect(GameProcesses.value(of: "missing", inManifest: manifest) == nil)
}

private func runtimeArchive(in directory: URL) throws -> (archive: URL, sha256: String) {
    let source = directory.appendingPathComponent("package")
    let bin = source.appendingPathComponent("Wine/bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let wine = bin.appendingPathComponent("wine")
    try Data("#!/bin/sh\n".utf8).write(to: wine)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    let archive = directory.appendingPathComponent("runtime.tar.xz")
    try RuntimeRelease.run("/usr/bin/tar", ["-cJf", archive.path, "-C", source.path, "."])
    return (archive, try RuntimeRelease.sha256(of: archive))
}

@Test func installsVerifiedRuntimeAndConfiguresItsD3DMetal() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try AppPaths(dataDirectory: root.appendingPathComponent("data"))
    let (archive, sha256) = try runtimeArchive(in: root)
    let release = RuntimeRelease(version: "1.0-test", url: URL(string: "https://example.com/r.tar.xz")!, sha256: sha256, size: 0)

    try release.install(archive: archive, in: paths)

    #expect(release.isInstalled(in: paths))
    let configuration = release.configuration(in: paths)
    #expect(configuration.wine == release.wineRoot(in: paths).appendingPathComponent("bin/wine").path)
    #expect(configuration.libraryDirectory == configuration.d3dMetalDirectory)
    #expect(configuration.graphicsBackend == .d3dmetal)
}

@Test func rejectsRuntimeWithWrongChecksumAndLeavesNothingBehind() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try AppPaths(dataDirectory: root.appendingPathComponent("data"))
    let (archive, _) = try runtimeArchive(in: root)
    let release = RuntimeRelease(version: "1.0-test", url: URL(string: "https://example.com/r.tar.xz")!,
                                 sha256: String(repeating: "0", count: 64), size: 0)

    #expect(throws: ArchwayError.self) { try release.install(archive: archive, in: paths) }
    #expect(!release.isInstalled(in: paths))
    #expect(!FileManager.default.fileExists(atPath: release.directory(in: paths).path))
}

@Test func bundledRuntimeReleaseIsComplete() throws {
    let release = try RuntimeRelease.bundled()
    #expect(release.sha256.count == 64)
    #expect(release.url.scheme == "https")
    #expect(release.url.lastPathComponent == "archway-wine-\(release.version).tar.xz")
}

@Test func tellsRuntimePackagesFromHandConfiguredWine() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try AppPaths(dataDirectory: root.appendingPathComponent("data"))
    let release = RuntimeRelease(version: "1.0-test", url: URL(string: "https://example.com/r.tar.xz")!, sha256: "", size: 0)

    #expect(RuntimeRelease.isPackaged(release.configuration(in: paths), in: paths))
    let other = paths.dataDirectory.appendingPathComponent("runtime-overlays/whisky/Wine/bin/wine").path
    #expect(!RuntimeRelease.isPackaged(Configuration(wine: other), in: paths))
    #expect(!RuntimeRelease.isPackaged(Configuration(wine: "/opt/wine/bin/wine"), in: paths))
}

@Test func removesOtherRuntimePackagesOnly() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try AppPaths(dataDirectory: root.appendingPathComponent("data"))
    let release = RuntimeRelease(version: "2.0-test", url: URL(string: "https://example.com/r.tar.xz")!, sha256: "", size: 0)
    let overlays = paths.dataDirectory.appendingPathComponent("runtime-overlays")
    let names = ["archway-wine-1.0-test", ".archway-wine-1.5-test.partial", "archway-wine-2.0-test", "whisky"]
    for name in names {
        try FileManager.default.createDirectory(at: overlays.appendingPathComponent(name), withIntermediateDirectories: true)
    }

    try release.removeOtherPackages(in: paths)

    #expect(try FileManager.default.contentsOfDirectory(atPath: overlays.path).sorted() == ["archway-wine-2.0-test", "whisky"])
}

private func steamOrchestrator(in root: URL) throws -> (Orchestrator, URL) {
    let paths = try AppPaths(dataDirectory: root.appendingPathComponent("data"))
    let steam = paths.bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam")
    try FileManager.default.createDirectory(at: steam.appendingPathComponent("config"), withIntermediateDirectories: true)
    try Data("MZ".utf8).write(to: steam.appendingPathComponent("steam.exe"))
    return (Orchestrator(paths: paths, configuration: Configuration(wine: "/usr/bin/true")), steam)
}

@Test func queuesSteamInstallAsUpdateRequiredManifestOnce() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (orchestrator, steam) = try steamOrchestrator(in: root)

    #expect(try orchestrator.queueSteamInstall(appID: 48000, name: "LIMBO™: \"Edition\""))
    let manifest = steam.appendingPathComponent("steamapps/appmanifest_48000.acf")
    let text = try String(contentsOf: manifest, encoding: .utf8)
    #expect(GameProcesses.value(of: "StateFlags", inManifest: text) == "1026")
    #expect(GameProcesses.value(of: "installdir", inManifest: text) == "LIMBO Edition")
    #expect(text.contains(#""LIMBO™: \"Edition\"""#))
    // An existing manifest belongs to Steam and stays untouched.
    #expect(try !orchestrator.queueSteamInstall(appID: 48000, name: "Other"))
    #expect(orchestrator.steamInstallProgress(appID: 48000) == nil)

    try Data(#""AppState" { "BytesToStage" "16384" "BytesStaged" "0" }"#.utf8).write(to: manifest)
    #expect(orchestrator.steamInstallProgress(appID: 48000) == 0)
    let downloading = steam.appendingPathComponent("steamapps/downloading/48000")
    try FileManager.default.createDirectory(at: downloading, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 8192).write(to: downloading.appendingPathComponent("chunk"))
    #expect(orchestrator.steamInstallProgress(appID: 48000) == 0.5)
}

@Test func detectsRememberedSteamSignIn() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (orchestrator, steam) = try steamOrchestrator(in: root)
    #expect(!orchestrator.steamIsSignedIn())
    let users = steam.appendingPathComponent("config/loginusers.vdf")
    try Data("\"users\"\n{\n\t\"1\"\n\t{\n\t\t\"RememberPassword\"\t\t\"0\"\n\t}\n}\n".utf8).write(to: users)
    #expect(!orchestrator.steamIsSignedIn())
    try Data("\"users\"\n{\n\t\"1\"\n\t{\n\t\t\"RememberPassword\"\t\t\"1\"\n\t}\n}\n".utf8).write(to: users)
    #expect(orchestrator.steamIsSignedIn())
}

@Test func silentSteamRequestsKeepSteamsWindowClosed() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (orchestrator, _) = try steamOrchestrator(in: root)
    try orchestrator.paths.ensureDirectories()
    try JSONEncoder().encode(BottleMarker(state: .ready)).write(to: orchestrator.paths.bottle.appendingPathComponent(".archway-bottle.json"))
    try Data("registry".utf8).write(to: orchestrator.paths.bottle.appendingPathComponent("system.reg"))

    #expect(try orchestrator.steamOpen(webHelperShim: false, silent: true, environment: [:]).arguments.contains("-silent"))
    #expect(try !orchestrator.steamOpen(webHelperShim: false, environment: [:]).arguments.contains("-silent"))
    let launch = try orchestrator.gameLaunch(appID: 48000, webHelperShim: false, silent: true, environment: [:]).arguments
    #expect(Array(launch.suffix(3)) == ["-silent", "-applaunch", "48000"])
}

@Test func readsSteamInstallPhaseFromContentLog() {
    let log = """
    [2026-10-25 20:27:00] AppID 48000 App update changed : Running Update,Reconfiguring,
    [2026-10-25 20:27:02] AppID 48000 App update changed : Running Update,Preallocating,
    [2026-10-25 20:27:02] AppID 99 App update changed : Running Update,Committing,
    """
    #expect(Orchestrator.installPhase(appID: 48000, contentLog: log) == .preparing)
    #expect(Orchestrator.installPhase(appID: 48000, contentLog: log + "\n[x] AppID 48000 App update changed : Running Update,Downloading,Staging,") == .downloading)
    #expect(Orchestrator.installPhase(appID: 48000, contentLog: log + "\n[x] AppID 48000 App update changed : Running Update,Committing,") == .installing)
    #expect(Orchestrator.installPhase(appID: 7, contentLog: log) == nil)
}

@Test func uninstallsSteamGameButKeepsOtherGames() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (orchestrator, steam) = try steamOrchestrator(in: root)
    let steamapps = steam.appendingPathComponent("steamapps")
    for (id, folder) in [(48000, "LIMBO"), (550, "Left 4 Dead 2")] {
        try FileManager.default.createDirectory(at: steamapps.appendingPathComponent("common/\(folder)"), withIntermediateDirectories: true)
        try Data("\"AppState\" { \"installdir\" \"\(folder)\" }".utf8)
            .write(to: steamapps.appendingPathComponent("appmanifest_\(id).acf"))
    }
    try FileManager.default.createDirectory(at: steamapps.appendingPathComponent("shadercache/48000"), withIntermediateDirectories: true)

    try orchestrator.uninstallSteamGame(appID: 48000)

    for gone in ["appmanifest_48000.acf", "common/LIMBO", "shadercache/48000"] {
        #expect(!FileManager.default.fileExists(atPath: steamapps.appendingPathComponent(gone).path))
    }
    #expect(FileManager.default.fileExists(atPath: steamapps.appendingPathComponent("common/Left 4 Dead 2").path))

    try Data("\"AppState\" { \"installdir\" \"..\" }".utf8).write(to: steamapps.appendingPathComponent("appmanifest_550.acf"))
    #expect(throws: ArchwayError.self) { try orchestrator.uninstallSteamGame(appID: 550) }
    #expect(FileManager.default.fileExists(atPath: steamapps.appendingPathComponent("common").path))
}

@Test func removalDeletesDataAndTheAppsOwnLibraryFilesOnly() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let data = root.appendingPathComponent("Archway")
    let library = root.appendingPathComponent("Library")
    let id = "com.example.archway"
    let own = ["Caches/\(id)", "WebKit/\(id)", "HTTPStorages/\(id)"].map { library.appendingPathComponent($0) }
    let foreign = library.appendingPathComponent("Caches/com.example.other")
    for folder in [data.appendingPathComponent("bottles/steam")] + own + [foreign] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    ArchwayRemoval.stopWine(dataDirectory: data)
    ArchwayRemoval.delete(ArchwayRemoval.filesToDelete(dataDirectory: data, library: library, bundleIdentifier: id))

    for gone in [data] + own { #expect(!FileManager.default.fileExists(atPath: gone.path)) }
    #expect(FileManager.default.fileExists(atPath: foreign.path))
    #expect(ArchwayRemoval.filesToDelete(dataDirectory: data, library: library, bundleIdentifier: nil) == [data])
}
