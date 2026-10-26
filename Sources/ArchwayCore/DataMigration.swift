import Darwin
import Foundation

/// Moves the former default data root once. Explicit data directories are never migrated.
public enum DataMigration {
    // These are the only retained legacy names: they identify data written by older releases.
    private static let oldRootName = "Overcross"
    private static let oldBottleMarker = ".overcross-bottle.json"
    private static let oldRuntimeBackup = ".overcross-d3dmetal-backup"
    private static let stagingName = ".archway-migration"

    /// Returns true when the legacy root was moved. Pass a temporary support directory in tests.
    @discardableResult
    public static func migrateIfNeeded(
        applicationSupportDirectory: URL? = nil,
        wineIsRunning: ((URL) throws -> Bool)? = nil
    ) throws -> Bool {
        let support = (applicationSupportDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]).standardizedFileURL
        guard support.isFileURL, support.path.hasPrefix("/"), support.path != "/" else {
            throw ArchwayError.invalidPath("Application Support must be a local directory.")
        }
        let old = support.appendingPathComponent(oldRootName)
        let new = support.appendingPathComponent("Archway")
        let staging = support.appendingPathComponent(stagingName)
        guard try !checkedExists(staging) else {
            throw ArchwayError.invalidPath("An interrupted Archway data migration remains at \(staging.path). Inspect it before retrying.")
        }
        guard try checkedExists(old) else { return false }
        guard try !checkedExists(new) else {
            throw ArchwayError.invalidPath("Both legacy data at \(old.path) and Archway data at \(new.path) exist. Keep both and resolve the conflict before starting Archway.")
        }
        guard isDirectory(old), !isSymbolicLink(old) else {
            throw ArchwayError.invalidPath("Legacy data root must be a real directory: \(old.path)")
        }

        let prefixes = try affectedPrefixes(in: old)
        let running = wineIsRunning ?? activeWinePrefix
        for prefix in prefixes {
            if try running(prefix) {
                throw ArchwayError.invalidPath("Wine is running in \(prefix.path). Close that session before migrating Archway data.")
            }
        }
        try rejectAffectedWineProcesses(in: old)

        let edits = try jsonEdits(in: old, rebasingTo: new) + registryEdits(in: old, rebasingTo: new)
        let markers = try markerMoves(in: old)
        try rejectAffectedWineProcesses(in: old)
        // Recheck immediately before the atomic move, after potentially slow preflight reads.
        for prefix in prefixes {
            if try running(prefix) {
                throw ArchwayError.invalidPath("Wine started in \(prefix.path). Close that session before migrating Archway data.")
            }
        }

        try FileManager.default.moveItem(at: old, to: staging)
        var renamed: [(String, String)] = []
        var rewritten: [(String, Data)] = []
        do {
            for (relative, original, updated) in edits {
                try rejectSymlinks(in: staging, along: relative)
                try updated.write(to: staging.appendingPathComponent(relative), options: .atomic)
                rewritten.append((relative, original))
            }
            for (source, destination) in markers {
                try rejectSymlinks(in: staging, along: source)
                try rejectSymlinks(in: staging, along: destination)
                try FileManager.default.moveItem(at: staging.appendingPathComponent(source),
                                                 to: staging.appendingPathComponent(destination))
                renamed.append((source, destination))
            }
            try FileManager.default.moveItem(at: staging, to: new)
            return true
        } catch {
            do {
                for (source, destination) in renamed.reversed() {
                    try rejectSymlinks(in: staging, along: destination)
                    try rejectSymlinks(in: staging, along: source)
                    try FileManager.default.moveItem(at: staging.appendingPathComponent(destination),
                                                     to: staging.appendingPathComponent(source))
                }
                for (relative, original) in rewritten.reversed() {
                    try rejectSymlinks(in: staging, along: relative)
                    try original.write(to: staging.appendingPathComponent(relative), options: .atomic)
                }
                try FileManager.default.moveItem(at: staging, to: old)
            } catch let rollbackError {
                throw ArchwayError.invalidPath("Archway data migration failed: \(error.localizedDescription). Recovery also failed: \(rollbackError.localizedDescription). Data remains at \(staging.path).")
            }
            throw ArchwayError.invalidPath("Archway data migration failed; original data remains at \(old.path): \(error.localizedDescription)")
        }
    }

    private static func jsonEdits(in old: URL, rebasingTo new: URL) throws -> [(String, Data, Data)] {
        var edits: [(String, Data, Data)] = []
        for relative in ["config.json", "archway-alpha/config.json", "local-games.json"] {
            try rejectSymlinks(in: old, along: relative)
            let file = old.appendingPathComponent(relative)
            guard exists(file) else { continue }
            guard isRegularFile(file), !isSymbolicLink(file) else {
                throw ArchwayError.invalidPath("Migration JSON must be a regular file: \(file.path)")
            }
            let original = try Data(contentsOf: file)
            let object = try JSONSerialization.jsonObject(with: original, options: [.fragmentsAllowed])
            let (updated, changed) = rebase(object, from: old.path, to: new.path)
            if changed {
                let data = try JSONSerialization.data(withJSONObject: updated, options: [.fragmentsAllowed, .sortedKeys])
                edits.append((relative, original, data))
            }
        }
        return edits
    }

    private static func registryEdits(in old: URL, rebasingTo new: URL) throws -> [(String, Data, Data)] {
        var edits: [(String, Data, Data)] = []
        for prefix in try affectedPrefixes(in: old) {
            for file in try FileManager.default.contentsOfDirectory(at: prefix, includingPropertiesForKeys: nil) {
                let name = file.lastPathComponent
                guard ["system.reg", "user.reg", "userdef.reg"].contains(name)
                        || name.contains(".reg.before-") else { continue }
                let relative = String(file.path.dropFirst(old.path.count + 1))
                try rejectSymlinks(in: old, along: relative)
                guard isRegularFile(file), !isSymbolicLink(file) else {
                    throw ArchwayError.invalidPath("Wine registry must be a regular file: \(file.path)")
                }
                let original = try Data(contentsOf: file)
                if let updated = rebaseRegistry(original, from: old.path, to: new.path) {
                    edits.append((relative, original, updated))
                }
            }
        }
        return edits
    }

    /// Wine stores host paths with either one or two escaped backslashes. Edit bytes so all
    /// unrelated registry content, including snapshots and non-UTF-8 bytes, stays exact.
    static func rebaseRegistry(_ original: Data, from old: String, to new: String) -> Data? {
        let patterns: [([UInt8], [UInt8])] = ["\\\\", "\\", "/"].map { separator in
            (Array(old.replacingOccurrences(of: "/", with: separator).utf8),
             Array(new.replacingOccurrences(of: "/", with: separator).utf8))
        }
        let input = Array(original)
        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        var index = 0
        var changed = false
        while index < input.count {
            var matched = false
            for (source, destination) in patterns where index + source.count <= input.count {
                let previous = index == 0 ? nil : input[index - 1]
                let next = index + source.count == input.count ? nil : input[index + source.count]
                guard (previous == nil || [UInt8(32), 34, 39, 58, 61].contains(previous!)),
                      (next == nil || [UInt8(9), 10, 13, 32, 34, 39, 47, 59, 92].contains(next!)),
                      input[index..<(index + source.count)].elementsEqual(source) else { continue }
                output.append(contentsOf: destination)
                index += source.count
                changed = true
                matched = true
                break
            }
            if !matched {
                output.append(input[index])
                index += 1
            }
        }
        return changed ? Data(output) : nil
    }

    private static func rebase(_ value: Any, from old: String, to new: String) -> (Any, Bool) {
        if let string = value as? String {
            guard string == old || string.hasPrefix(old + "/") else { return (string, false) }
            return (new + String(string.dropFirst(old.count)), true)
        }
        if let array = value as? [Any] {
            var changed = false
            let result = array.map { element -> Any in
                let (replacement, didChange) = rebase(element, from: old, to: new)
                changed = changed || didChange
                return replacement
            }
            return (result, changed)
        }
        if let dictionary = value as? [String: Any] {
            var changed = false
            var result = dictionary
            for (key, element) in dictionary {
                let (replacement, didChange) = rebase(element, from: old, to: new)
                result[key] = replacement
                changed = changed || didChange
            }
            return (result, changed)
        }
        return (value, false)
    }

    private static func markerMoves(in root: URL) throws -> [(String, String)] {
        var moves: [(String, String)] = []
        for prefix in try affectedPrefixes(in: root) {
            let relative = String(prefix.path.dropFirst(root.path.count + 1)) + "/"
            try appendMove(relative + oldBottleMarker, relative + ".archway-bottle.json", in: root, to: &moves)
        }
        for dataRoot in try dataRoots(in: root) {
            let relativeRoot = dataRoot.path == root.path ? "" : String(dataRoot.path.dropFirst(root.path.count + 1)) + "/"
            for overlay in try children(of: dataRoot.appendingPathComponent("runtime-overlays")) {
                let overlayRoot = relativeRoot + "runtime-overlays/" + overlay.lastPathComponent + "/"
                for layout in ["Wine/", "payload/Libraries/Wine/"] {
                    let prefix = overlayRoot + layout
                    try appendMove(prefix + oldRuntimeBackup, prefix + ".archway-d3dmetal-backup", in: root, to: &moves)
                }
            }
        }
        return moves
    }

    private static func appendMove(_ source: String, _ destination: String, in root: URL,
                                   to moves: inout [(String, String)]) throws {
        try rejectSymlinks(in: root, along: source)
        let old = root.appendingPathComponent(source)
        guard exists(old) else { return }
        try rejectSymlinks(in: root, along: destination)
        let new = root.appendingPathComponent(destination)
        guard !isSymbolicLink(old), !exists(new) else {
            throw ArchwayError.invalidPath("Legacy marker cannot be safely renamed: \(old.path)")
        }
        moves.append((source, destination))
    }

    /// Check only paths the migration reads or changes, leaving unrelated runtime links alone.
    private static func rejectSymlinks(in root: URL, along relative: String) throws {
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard !isSymbolicLink(current) else {
                throw ArchwayError.invalidPath("Migration path must not contain a symlink: \(current.path)")
            }
        }
    }

    private static func affectedPrefixes(in root: URL) throws -> [URL] {
        var prefixes = try dataRoots(in: root).flatMap { dataRoot in
            try children(of: dataRoot.appendingPathComponent("bottles"))
        }
        prefixes += try children(of: root).filter { exists($0.appendingPathComponent("system.reg")) }
        var seen = Set<String>()
        return prefixes.filter { seen.insert($0.path).inserted }
    }

    private static func dataRoots(in root: URL) throws -> [URL] {
        [root] + (try children(of: root)).filter { exists($0.appendingPathComponent("bottles")) }
    }

    private static func children(of directory: URL) throws -> [URL] {
        guard isDirectory(directory) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { isDirectory($0) }
    }

    private static func activeWinePrefix(_ prefix: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "/wineserver$"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 1 { return false }
        guard process.terminationStatus == 0 else {
            throw ArchwayError.invalidPath("Unable to check running Wine sessions before data migration.")
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: prefix.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return false }
        let socket = "/tmp/.wine-\(getuid())/server-\(String(device, radix: 16))-\(String(inode, radix: 16))/socket"
        return FileManager.default.fileExists(atPath: socket)
    }

    private static func rejectAffectedWineProcesses(in old: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["axeww", "-o", "pid=,command="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let lines = String(data: output, encoding: .utf8) else {
            throw ArchwayError.invalidPath("Unable to inspect Wine processes before data migration.")
        }
        guard !lines.split(separator: "\n").contains(where: { affectedWineProcessLine(String($0), root: old.path) }) else {
            throw ArchwayError.invalidPath("A Wine process still references \(old.path). Close that session before migrating Archway data; Archway will not stop it.")
        }
    }

    static func affectedWineProcessLine(_ line: String, root: String) -> Bool {
        let wineNames = ["/wine ", "/wine\t", "/wine64 ", "/wine64-preloader ",
                         "/wine-preloader ", "/winedbg ", " winedbg ", "/wineserver ",
                         " wine ", " wineserver "]
        guard wineNames.contains(where: line.contains) || line.hasSuffix("/wine")
                || line.hasSuffix("/wineserver") || line.hasSuffix("/wine64-preloader") else { return false }
        var search = line.startIndex..<line.endIndex
        while let range = line.range(of: root, range: search) {
            let before = range.lowerBound == line.startIndex ? nil : line[line.index(before: range.lowerBound)]
            let after = range.upperBound == line.endIndex ? nil : line[range.upperBound]
            if (before == nil || " =:\"'".contains(before!)),
               (after == nil || "/\\ \t\n\r\"'".contains(after!)) { return true }
            search = range.upperBound..<line.endIndex
        }
        return false
    }

    private static func fileMode(_ url: URL) -> Int32? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Int32(info.st_mode) & Int32(S_IFMT)
    }

    private static func checkedExists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw ArchwayError.invalidPath("Cannot inspect migration path \(url.path): \(String(cString: strerror(errno)))")
    }

    private static func exists(_ url: URL) -> Bool { fileMode(url) != nil }
    private static func isDirectory(_ url: URL) -> Bool { fileMode(url).map { $0 == Int32(S_IFDIR) } ?? false }
    private static func isRegularFile(_ url: URL) -> Bool { fileMode(url).map { $0 == Int32(S_IFREG) } ?? false }
    private static func isSymbolicLink(_ url: URL) -> Bool { fileMode(url).map { $0 == Int32(S_IFLNK) } ?? false }
}
