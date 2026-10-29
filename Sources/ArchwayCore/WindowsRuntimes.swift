import Foundation

/// A Microsoft runtime that Wine imitates with built-in DLLs. Some games need the real one: Archway installs
/// Microsoft's redistributable in the bottle and tells Wine to prefer its DLLs. Steam's own install of the same
/// redistributable changes nothing, since Wine keeps loading its built-in DLLs without that preference.
public struct WindowsRuntime: Hashable, Sendable, Identifiable {
    public enum Architecture: String, Sendable { case x86, x64 }

    public enum Family: String, CaseIterable, Sendable {
        case vc2010, vc2012, vc2013, vc2015

        /// The DLLs a program imports when it was built with this runtime, without ".dll".
        var dlls: [String] {
            switch self {
            case .vc2010: ["msvcp100", "msvcr100", "vcomp100"]
            case .vc2012: ["msvcp110", "msvcr110", "vcomp110"]
            case .vc2013: ["msvcp120", "msvcr120", "vcomp120"]
            case .vc2015: ["msvcp140", "msvcp140_1", "msvcp140_2", "vcruntime140", "vcruntime140_1", "concrt140",
                           "vcomp140", "vccorlib140"]
            }
        }

        var displayName: String {
            switch self {
            case .vc2010: "Microsoft Visual C++ 2010"
            case .vc2012: "Microsoft Visual C++ 2012"
            case .vc2013: "Microsoft Visual C++ 2013"
            case .vc2015: "Microsoft Visual C++ 2015–2022"
            }
        }
    }

    public let family: Family
    public let architecture: Architecture

    public init(family: Family, architecture: Architecture) {
        self.family = family
        self.architecture = architecture
    }

    public var id: String { "\(family.rawValue)-\(architecture.rawValue)" }

    public init?(id: String) {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let family = Family(rawValue: String(parts[0])),
              let architecture = Architecture(rawValue: String(parts[1])) else { return nil }
        self.init(family: family, architecture: architecture)
    }

    /// The runtime a DLL belongs to, for a program of the given architecture, if it is one Archway installs.
    public static func providing(dll: String, architecture: Architecture) -> WindowsRuntime? {
        let name = dll.lowercased().replacingOccurrences(of: ".dll", with: "")
        return Family.allCases.first { $0.dlls.contains(name) }.map { WindowsRuntime(family: $0, architecture: architecture) }
    }

    /// The architecture of a Windows program or DLL, if it is one.
    public static func architecture(of file: URL) -> Architecture? {
        (try? PortableExecutable(url: file))?.architecture
    }
    public var name: String { "\(family.displayName) (\(architecture == .x64 ? "64-bit" : "32-bit"))" }

    /// Microsoft's own download; each redirects to a microsoft.com host.
    var installerURL: URL {
        let url: String = switch (family, architecture) {
        case (.vc2015, .x64): "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        case (.vc2015, .x86): "https://aka.ms/vs/17/release/vc_redist.x86.exe"
        case (.vc2013, .x64): "https://aka.ms/highdpimfc2013x64enu"
        case (.vc2013, .x86): "https://aka.ms/highdpimfc2013x86enu"
        case (.vc2012, .x64): "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe"
        case (.vc2012, .x86): "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe"
        case (.vc2010, .x64): "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe"
        case (.vc2010, .x86): "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe"
        }
        return URL(string: url)!
    }

    var silentArguments: [String] { family == .vc2010 ? ["/q", "/norestart"] : ["/install", "/quiet", "/norestart"] }

    /// A game's programs, four folders deep, where engines such as Unreal keep the real one
    /// (Game/Binaries/Win64). Skips the installers games ship for their dependencies.
    public static func executables(in folder: URL, depth: Int = 4, limit: Int = 64) -> [URL] {
        let skipped = ["_commonredist", "redist", "redistributables", "directx", "dotnet", "support", "installers"]
        var found: [URL] = []
        func visit(_ directory: URL, _ remaining: Int) {
            let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                         options: .skipsHiddenFiles)) ?? []
            for entry in entries.sorted(by: { $0.path < $1.path }) where found.count < limit {
                if entry.pathExtension.lowercased() == "exe" {
                    found.append(entry)
                } else if remaining > 1, !skipped.contains(entry.lastPathComponent.lowercased()),
                          (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(entry, remaining - 1)
                }
            }
        }
        visit(folder, depth)
        return found
    }

    /// The runtimes the programs import, read from their import tables without running them.
    public static func required(by executables: [URL]) -> Set<WindowsRuntime> {
        var runtimes = Set<WindowsRuntime>()
        for executable in executables {
            guard let image = try? PortableExecutable(url: executable) else { continue }
            let imports = Set(image.importedDLLs.map { $0.lowercased().replacingOccurrences(of: ".dll", with: "") })
            for family in Family.allCases where !imports.isDisjoint(with: family.dlls) {
                runtimes.insert(WindowsRuntime(family: family, architecture: image.architecture))
            }
        }
        return runtimes
    }
}

/// Just enough of a Windows executable to tell its architecture and the DLLs it imports, directly or delay-loaded.
struct PortableExecutable {
    let architecture: WindowsRuntime.Architecture
    let importedDLLs: [String]

    enum Failure: Error { case notAnExecutable }

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    init(data: Data) throws {
        func uint16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 2 <= data.count else { throw Failure.notAnExecutable }
            return Int(data[data.startIndex + offset]) | Int(data[data.startIndex + offset + 1]) << 8
        }
        func uint32(_ offset: Int) throws -> Int {
            let low = try uint16(offset)
            return try low | uint16(offset + 2) << 16
        }

        guard try uint16(0) == 0x5A4D else { throw Failure.notAnExecutable }            // "MZ"
        let pe = try uint32(0x3C)
        guard try uint32(pe) == 0x4550 else { throw Failure.notAnExecutable }            // "PE\0\0"
        switch try uint16(pe + 4) {
        case 0x8664: architecture = .x64
        case 0x14C: architecture = .x86
        default: throw Failure.notAnExecutable
        }
        let sectionCount = try uint16(pe + 6)
        let optionalHeader = pe + 24
        let optionalSize = try uint16(pe + 20)
        let isPE32Plus = try uint16(optionalHeader) == 0x20B
        let dataDirectories = optionalHeader + (isPE32Plus ? 112 : 96)

        // Sections map the addresses the import tables use to places in the file.
        var sections: [(address: Int, size: Int, offset: Int)] = []
        for index in 0..<sectionCount {
            let header = optionalHeader + optionalSize + index * 40
            let address = try uint32(header + 12)
            let size = try max(uint32(header + 8), uint32(header + 16))
            try sections.append((address, size, uint32(header + 20)))
        }
        func offset(of address: Int) -> Int? {
            sections.first { address >= $0.address && address < $0.address + $0.size }.map { address - $0.address + $0.offset }
        }
        func string(at address: Int) -> String? {
            guard let start = offset(of: address), start < data.count else { return nil }
            let bytes = data[(data.startIndex + start)...].prefix(256).prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }

        var names: [String] = []
        // Directory 1 holds the imports (20-byte entries, name at +12); 13 the delay-loaded ones (32 bytes, name at +4).
        for (directory, entrySize, nameField) in [(1, 20, 12), (13, 32, 4)] {
            guard let table = offset(of: try uint32(dataDirectories + directory * 8)), table > 0 else { continue }
            var entry = table
            while entry + entrySize <= data.count, names.count < 512 {
                let nameAddress = try uint32(entry + nameField)
                guard nameAddress != 0, let name = string(at: nameAddress) else { break }
                names.append(name)
                entry += entrySize
            }
        }
        importedDLLs = names
    }
}

extension Orchestrator {
    private var runtimesRecord: URL { paths.bottle.appendingPathComponent(".archway-runtimes.json") }

    /// The runtimes Archway installed in this bottle.
    public func installedRuntimes() -> Set<String> {
        guard let data = try? Data(contentsOf: runtimesRecord),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    /// What a Steam game or a local executable needs and the bottle doesn't have yet, sorted by name.
    public func missingRuntimes(appID: Int? = nil, executable: URL? = nil) -> [WindowsRuntime] {
        let executables = executable.map { [$0] } ?? appID.flatMap(steamInstallDirectory).map { WindowsRuntime.executables(in: $0) } ?? []
        let installed = installedRuntimes()
        return WindowsRuntime.required(by: executables).filter { !installed.contains($0.id) }.sorted { $0.name < $1.name }
    }

    /// Wine marks its own DLLs in the DOS stub; Microsoft's have the usual "This program cannot be run" there.
    static func isWineBuiltin(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        try? handle.seek(toOffset: 0x40)
        return (try? handle.read(upToCount: 16)) == Data("Wine builtin DLL".utf8)
    }

    /// Downloads Microsoft's redistributable, installs it silently, and makes Wine prefer its DLLs over the built-in
    /// ones for the whole bottle.
    public func install(_ runtime: WindowsRuntime) async throws {
        let (download, response) = try await URLSession.shared.download(from: runtime.installerURL)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let host = response.url?.host(), host == "microsoft.com" || host.hasSuffix(".microsoft.com") else {
            throw ArchwayError.invalidPath("The \(runtime.name) download didn't come from Microsoft.")
        }
        let installer = paths.bottle.appendingPathComponent("drive_c/windows/temp/archway-\(runtime.id).exe")
        try FileManager.default.createDirectory(at: installer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: installer)
        try FileManager.default.moveItem(at: download, to: installer)
        defer { try? FileManager.default.removeItem(at: installer) }

        // Wine's stand-ins carry a high version number, so the installer would keep them as "newer". Without them,
        // Wine falls back to the built-in DLLs from its own folder until the installer has put Microsoft's in place.
        let systemFolder = paths.bottle.appendingPathComponent(
            runtime.architecture == .x64 ? "drive_c/windows/system32" : "drive_c/windows/syswow64")
        for dll in runtime.family.dlls {
            let file = systemFolder.appendingPathComponent("\(dll).dll")
            if Self.isWineBuiltin(file) { try FileManager.default.removeItem(at: file) }
        }
        do {
            try ProcessRunner.runSetup(request(arguments: [installer.path] + runtime.silentArguments,
                                               label: "runtime-\(runtime.id)"), timeout: 600)
        } catch ArchwayError.processFailed(_, let code) where [1638, 3010].contains(code) {
            // 1638: a newer version is already there; 3010: installed, Windows would like a restart.
        }
        let main = systemFolder.appendingPathComponent("\(runtime.family.dlls[0]).dll")
        guard FileManager.default.fileExists(atPath: main.path), !Self.isWineBuiltin(main) else {
            throw ArchwayError.invalidPath("The \(runtime.name) installer didn't install Microsoft's DLLs.")
        }
        for dll in runtime.family.dlls {
            try ProcessRunner.runSetup(request(arguments: ["reg", "add", #"HKCU\Software\Wine\DllOverrides"#,
                                                           "/v", dll, "/d", "native,builtin", "/f"],
                                               label: "runtime-\(runtime.id)-overrides"), timeout: 60)
        }
        var installed = installedRuntimes()
        installed.insert(runtime.id)
        try JSONEncoder().encode(installed.sorted()).write(to: runtimesRecord, options: .atomic)
    }
}
