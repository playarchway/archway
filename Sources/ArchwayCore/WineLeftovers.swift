import Darwin
import Foundation

/// Wine processes a bottle left behind once its wineserver is gone, for example a debugger and console that hung
/// after a crash. They belong to no session any more, so nothing else ends them.
public enum WineLeftovers {
    /// Processes started from `runtime` (the Wine folder) with `WINEPREFIX` set to `bottle`. Other bottles' processes,
    /// even on the same runtime, never match.
    static func processes(runtime: URL, bottle: URL) -> [pid_t] {
        let runtimePath = runtime.resolvingSymlinksInPath().path + "/"
        let bottlePath = bottle.resolvingSymlinksInPath().path
        return allProcesses().filter { pid in
            guard pid != getpid(), let path = executablePath(of: pid),
                  URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(runtimePath),
                  let prefix = environment(of: pid)?["WINEPREFIX"] else { return false }
            return URL(fileURLWithPath: prefix).resolvingSymlinksInPath().path == bottlePath
        }
    }

    /// Ends them with SIGKILL; they no longer answer to anything gentler. Returns how many there were.
    @discardableResult
    static func kill(_ pids: [pid_t]) -> Int {
        pids.filter { Darwin.kill($0, SIGKILL) == 0 }.count
    }

    private static func allProcesses() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(max(0, Int(filled)))).filter { $0 > 0 }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The process's environment, which macOS shows only for the user's own processes.
    private static func environment(of pid: pid_t) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseEnvironment(procArgs: Array(buffer.prefix(size)))
    }

    /// KERN_PROCARGS2 holds argc, the executable path, padding, argc arguments, then the environment, each
    /// NUL-terminated.
    static func parseEnvironment(procArgs data: [UInt8]) -> [String: String]? {
        guard data.count > 4 else { return nil }
        let argc = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = 4
        func skipString() { while index < data.count, data[index] != 0 { index += 1 } }
        func skipPadding() { while index < data.count, data[index] == 0 { index += 1 } }
        skipString()
        skipPadding()
        for _ in 0..<max(0, Int(argc)) {
            skipString()
            index += 1
        }
        var environment: [String: String] = [:]
        while index < data.count, data[index] != 0 {
            let start = index
            skipString()
            let entry = String(decoding: data[start..<index], as: UTF8.self)
            if let equals = entry.firstIndex(of: "=") {
                environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
            }
            index += 1
        }
        return environment
    }
}

extension Orchestrator {
    /// Ends this bottle's leftover Wine processes, but only while its wineserver isn't running: with a session up,
    /// every one of them may still be in use. Returns how many it ended.
    @discardableResult
    public func endLeftoverProcesses() -> Int {
        guard !wineserverIsRunning() else { return 0 }
        // The configured wine sits in <runtime>/bin.
        let runtime = URL(fileURLWithPath: configuration.wine).deletingLastPathComponent().deletingLastPathComponent()
        return WineLeftovers.kill(WineLeftovers.processes(runtime: runtime, bottle: paths.bottle))
    }
}
