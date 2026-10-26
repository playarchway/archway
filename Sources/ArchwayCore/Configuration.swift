import Foundation

public enum GraphicsBackend: String, Codable {
    case builtin, dxvk, d3dmetal

    public static func parse(_ raw: String) throws -> Self {
        guard let backend = Self(rawValue: raw) else {
            throw ArchwayError.invalidPath("Unknown graphics backend '\(raw)'; use builtin, dxvk, or d3dmetal.")
        }
        return backend
    }
}

public enum GameGraphicsAPI: String {
    case d3d11, d3d12

    public static func parse(_ raw: String) throws -> Self {
        guard let api = Self(rawValue: raw) else {
            throw ArchwayError.invalidPath("Unknown game graphics API '\(raw)'; use d3d11 or d3d12.")
        }
        return api
    }

    public var unityArgument: String { "-force-\(rawValue)" }
}

public struct Configuration: Codable, Equatable {
    public var wine: String
    public var wineserver: String?
    public var libraryDirectory: String?
    public var dxvkConfigFile: String?
    public var vulkanICDFile: String?
    public var graphicsBackend: GraphicsBackend?
    public var d3dMetalDirectory: String?

    public init(wine: String, wineserver: String? = nil, libraryDirectory: String? = nil,
                dxvkConfigFile: String? = nil, vulkanICDFile: String? = nil,
                graphicsBackend: GraphicsBackend? = nil, d3dMetalDirectory: String? = nil) {
        self.wine = wine
        self.wineserver = wineserver
        self.libraryDirectory = libraryDirectory
        self.dxvkConfigFile = dxvkConfigFile
        self.vulkanICDFile = vulkanICDFile
        self.graphicsBackend = graphicsBackend
        self.d3dMetalDirectory = d3dMetalDirectory
    }

    public var selectedGraphicsBackend: GraphicsBackend {
        graphicsBackend ?? (dxvkConfigFile != nil || vulkanICDFile != nil ? .dxvk : .builtin)
    }

    public func validateGraphicsSelection(paths: AppPaths? = nil) throws {
        switch selectedGraphicsBackend {
        case .builtin:
            guard dxvkConfigFile == nil, vulkanICDFile == nil, d3dMetalDirectory == nil else {
                throw ArchwayError.invalidPath("Builtin graphics cannot include DXVK or D3DMetal components.")
            }
        case .dxvk:
            guard d3dMetalDirectory == nil, try validatedGraphicsFiles() != nil else {
                throw ArchwayError.invalidPath("DXVK requires --dxvk-config and --vulkan-icd, without --d3dmetal-dir.")
            }
        case .d3dmetal:
            guard dxvkConfigFile == nil, vulkanICDFile == nil, let d3dMetalDirectory else {
                throw ArchwayError.invalidPath("D3DMetal requires --d3dmetal-dir, without DXVK options.")
            }
            let redist = try D3DMetalRedist(root: PathValidator.libraryDirectory(d3dMetalDirectory))
            if let paths {
                let runtime = URL(fileURLWithPath: wine).deletingLastPathComponent().deletingLastPathComponent()
                let overlay = try D3DMetalRuntimeOverlay(paths: paths, runtimeRoot: runtime, redist: redist)
                guard overlay.capability == .providerDeclared, try overlay.isStaged() else {
                    throw ArchwayError.invalidPath("D3DMetal requires a staged, provider-declared compatible runtime clone; use stage-d3dmetal and doctor first. An unverified diagnostic overlay cannot be selected for normal launches.")
                }
            }
        }
    }

    public func validatedGraphicsFiles() throws -> (dxvk: URL, icd: URL)? {
        guard (dxvkConfigFile == nil) == (vulkanICDFile == nil) else {
            throw ArchwayError.invalidPath("--dxvk-config and --vulkan-icd must be configured together.")
        }
        guard let dxvkConfigFile, let vulkanICDFile else { return nil }
        return (try PathValidator.profileFile(dxvkConfigFile), try PathValidator.profileFile(vulkanICDFile))
    }
}

public struct ConfigStore {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    public func load() throws -> Configuration? {
        guard FileManager.default.fileExists(atPath: paths.config.path) else { return nil }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: paths.config))
    }

    public func save(_ configuration: Configuration) throws {
        var normalized = configuration
        try normalized.validateGraphicsSelection(paths: paths)
        if let directory = normalized.libraryDirectory {
            normalized.libraryDirectory = try PathValidator.libraryDirectory(directory).path
        }
        if let files = try normalized.validatedGraphicsFiles() {
            normalized.dxvkConfigFile = files.dxvk.path
            normalized.vulkanICDFile = files.icd.path
        }
        if let directory = normalized.d3dMetalDirectory {
            normalized.d3dMetalDirectory = try PathValidator.libraryDirectory(directory).path
        }
        try paths.ensureDirectories()
        let data = try JSONEncoder().encode(normalized)
        try data.write(to: paths.config, options: [.atomic])
    }
}
