import Foundation
import Testing
@testable import ArchwayCore

private func steamRoot() throws -> URL {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = package.appendingPathComponent(".build/test-temp/native-steam-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("steamapps/common"), withIntermediateDirectories: true)
    return url
}

private func manifest(_ appID: Int, flags: Int, installdir: String, in library: URL) throws {
    let text = """
    "AppState"
    {
    \t"appid"\t\t"\(appID)"
    \t"StateFlags"\t\t"\(flags)"
    \t"installdir"\t\t"\(installdir)"
    }
    """
    let steamapps = library.appendingPathComponent("steamapps")
    try FileManager.default.createDirectory(at: steamapps.appendingPathComponent("common/\(installdir)"), withIntermediateDirectories: true)
    try text.write(to: steamapps.appendingPathComponent("appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
}

/// An app bundle whose executable is `binary`.
private func app(named name: String, in folder: URL, binary: URL) throws {
    let contents = folder.appendingPathComponent("\(name).app/Contents")
    try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    let plist: [String: String] = ["CFBundleExecutable": name, "CFBundleIdentifier": "test.\(name)", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    try FileManager.default.copyItem(at: binary, to: contents.appendingPathComponent("MacOS/\(name)"))
}

@Test func nativeSteamReadsInstallStateFromManifests() throws {
    let root = try steamRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try manifest(10, flags: 4, installdir: "Done", in: root)
    try manifest(20, flags: 1026, installdir: "Loading", in: root)
    let steam = NativeSteam(root: root)

    #expect(steam.state(of: 10) == .installed(runsOnThisMac: true))
    #expect(steam.state(of: 20) == .installing)
    #expect(steam.state(of: 30) == .notInstalled)
}

@Test func nativeSteamFindsGamesInOtherLibraries() throws {
    let root = try steamRoot()
    let external = try steamRoot()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
    try """
    "libraryfolders"
    {
    \t"0"
    \t{
    \t\t"path"\t\t"\(root.path)"
    \t}
    \t"1"
    \t{
    \t\t"path"\t\t"\(external.path)"
    \t}
    }
    """.write(to: root.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
    try manifest(40, flags: 4, installdir: "Elsewhere", in: external)

    #expect(NativeSteam(root: root).libraries().count == 2)
    #expect(NativeSteam(root: root).state(of: 40) == .installed(runsOnThisMac: true))
}

@Test func nativeSteamTellsWhetherTheGameRunsOnThisMac() throws {
    let root = try steamRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try manifest(50, flags: 4, installdir: "Modern", in: root)
    try app(named: "Modern", in: root.appendingPathComponent("steamapps/common/Modern"), binary: URL(fileURLWithPath: "/usr/bin/true"))
    // A script is no Mach-O binary, so it has no architecture this Mac runs, like a 32-bit port.
    try manifest(60, flags: 4, installdir: "Old", in: root)
    let script = root.appendingPathComponent("script")
    try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)
    try app(named: "Old", in: root.appendingPathComponent("steamapps/common/Old/Game"), binary: script)
    let steam = NativeSteam(root: root)

    #expect(steam.state(of: 50) == .installed(runsOnThisMac: true))
    #expect(steam.state(of: 60) == .installed(runsOnThisMac: false))
}
