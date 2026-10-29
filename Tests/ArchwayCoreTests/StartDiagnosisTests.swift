import Foundation
import Testing
@testable import ArchwayCore

@Test func startDiagnosisNamesTheMissingDLLBeforeTheCrash() {
    let log = """
    0124:err:module:import_dll Library MSVCP140_ATOMIC_WAIT.dll (which is needed by L"C:\\\\Program Files (x86)\\\\Steam\\\\steamapps\\\\common\\\\Game\\\\Game.exe") not found
    wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140001000 (thread 0124)
    """
    #expect(StartDiagnosis.diagnose(log) == .missingDLL(name: "MSVCP140_ATOMIC_WAIT.dll",
                                                        neededBy: #"C:\Program Files (x86)\Steam\steamapps\common\Game\Game.exe"#))
    #expect(StartDiagnosis.diagnose("wine: Unhandled page fault on read access") == .crashed)
    #expect(StartDiagnosis.diagnose("Starting C:\\Game\\start_protected_game.exe") == .antiCheat(name: "Easy Anti-Cheat"))
    #expect(StartDiagnosis.diagnose("err:mscoree:CLRRuntimeInfo_GetRuntimeHost Wine Mono is not installed") == .missingWineMono)
    #expect(StartDiagnosis.diagnose("[S_API FAIL] SteamAPI_Init() failed; SteamAPI_IsSteamRunning() failed.") == .steamUnavailable)
    #expect(StartDiagnosis.diagnose("fixme:ntdll:NtQuerySystemInformation info_class") == nil)
}

@Test func startDiagnosisFindsTheProgramInTheBottle() {
    let bottle = URL(fileURLWithPath: "/data/bottles/steam")
    #expect(StartDiagnosis.file(forWindowsPath: #"C:\Games\My Game\Game.exe"#, bottle: bottle)?.path
            == "/data/bottles/steam/drive_c/Games/My Game/Game.exe")
    #expect(StartDiagnosis.file(forWindowsPath: #"Z:\Users\me\Game.exe"#, bottle: bottle) == nil)
    #expect(WindowsRuntime.providing(dll: "VCRUNTIME140.dll", architecture: .x86) == WindowsRuntime(family: .vc2015, architecture: .x86))
    #expect(WindowsRuntime.providing(dll: "d3dx9_43.dll", architecture: .x64) == nil)
    #expect(WindowsRuntime(id: "vc2013-x64") == WindowsRuntime(family: .vc2013, architecture: .x64))
}

@Test func logSnapshotReadsOnlyWhatCameAfterIt() throws {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let logs = package.appendingPathComponent(".build/test-temp/logs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: logs) }
    let steam = logs.appendingPathComponent("steam-open.log")
    try "old crash: Unhandled page fault\n".write(to: steam, atomically: true, encoding: .utf8)

    let snapshot = LogSnapshot(directory: logs)
    let handle = try FileHandle(forWritingTo: steam)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("new line\n".utf8))
    try handle.close()
    try "fresh log\n".write(to: logs.appendingPathComponent("game-launch-10.log"), atomically: true, encoding: .utf8)

    let text = snapshot.newText()
    #expect(text.contains("new line") && text.contains("fresh log"))
    #expect(!text.contains("old crash"))
}
