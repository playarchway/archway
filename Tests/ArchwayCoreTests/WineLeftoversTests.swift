import Foundation
import Testing
@testable import ArchwayCore

@Test func wineLeftoversReadTheEnvironmentFromProcArgs() {
    var data = withUnsafeBytes(of: Int32(2)) { Array($0) }
    for part in ["/runtime/bin/wine", "", "", "wine", "C:\\windows\\system32\\conhost.exe",
                 "WINEPREFIX=/bottles/steam", "PATH=/bin:/usr/bin", "EMPTY="] {
        data += Array(part.utf8) + [0]
    }
    let environment = WineLeftovers.parseEnvironment(procArgs: data)
    #expect(environment?["WINEPREFIX"] == "/bottles/steam")
    #expect(environment?["PATH"] == "/bin:/usr/bin")
    #expect(environment?["EMPTY"] == "")
    #expect(environment?["wine"] == nil)
}

@Test func wineLeftoversMatchOnlyTheirOwnBottle() throws {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = package.appendingPathComponent(".build/test-temp/leftovers-\(UUID().uuidString)")
    let runtime = root.appendingPathComponent("Wine")
    try FileManager.default.createDirectory(at: runtime.appendingPathComponent("bin"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    // Stands in for a Wine process: a binary inside the runtime, with the bottle in its environment.
    // macOS kills copies of its own binaries, so build one.
    let binary = runtime.appendingPathComponent("bin/sleeper")
    let source = root.appendingPathComponent("sleeper.c")
    try "#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
    let clang = Process()
    clang.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    clang.arguments = ["clang", source.path, "-o", binary.path]
    try clang.run()
    clang.waitUntilExit()
    try #require(clang.terminationStatus == 0)
    func start(bottle: String) throws -> Process {
        let process = Process()
        process.executableURL = binary
        process.environment = ["WINEPREFIX": root.appendingPathComponent(bottle).path]
        try process.run()
        return process
    }
    let mine = try start(bottle: "mine")
    let other = try start(bottle: "other")
    defer { other.terminate(); mine.terminate() }
    Thread.sleep(forTimeInterval: 0.2)

    let found = WineLeftovers.processes(runtime: runtime, bottle: root.appendingPathComponent("mine"))
    #expect(found == [mine.processIdentifier])
    #expect(WineLeftovers.kill(found) == 1)
    mine.waitUntilExit()
    #expect(mine.terminationReason == .uncaughtSignal)
    #expect(other.isRunning)
}
