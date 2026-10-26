import Foundation
import Darwin

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
