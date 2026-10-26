import Foundation

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
