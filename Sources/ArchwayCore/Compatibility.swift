import Foundation

/// Saved per-game launch arguments. Each entry is one literal argv value, never shell-evaluated.
public struct GameRuntimeProfile: Codable, Hashable, Sendable {
    public var launchArguments: [String]
    /// Only Brick by Brick currently has a verified graphics API switch.
    public var graphicsAPI: GameGraphicsAPIChoice

    public init(launchArguments: [String] = [], graphicsAPI: GameGraphicsAPIChoice = .gameDefault) {
        self.launchArguments = launchArguments
        self.graphicsAPI = graphicsAPI
    }

    public func arguments(for gameID: Int) throws -> [String] {
        guard launchArguments.count <= 12,
              launchArguments.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 100 && !$0.contains(where: \.isNewline) && !$0.contains("\0") }),
              (gameID == Orchestrator.firstAppID || graphicsAPI == .gameDefault) else {
            throw ArchwayError.invalidPath("Invalid game launch arguments or unsupported graphics API override.")
        }
        return launchArguments + graphicsAPI.arguments
    }
}

public enum GameGraphicsAPIChoice: String, Codable, CaseIterable, Sendable {
    case gameDefault, d3d11, d3d12

    public var arguments: [String] {
        switch self {
        case .gameDefault: []
        case .d3d11: ["-force-d3d11"]
        case .d3d12: ["-force-d3d12"]
        }
    }
}

public struct CompatibilityContext: Codable, Hashable, Sendable {
    public let runtimeVersion: String
    public let appVersion: String
    public let macOSVersion: String
    public let chip: String
    public let gameVersion: String
    public let graphicsBackend: String
    public let profile: GameRuntimeProfile

    public init(runtimeVersion: String, appVersion: String, macOSVersion: String, chip: String, gameVersion: String,
                graphicsBackend: String, profile: GameRuntimeProfile) {
        self.runtimeVersion = runtimeVersion
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.chip = chip
        self.gameVersion = gameVersion
        self.graphicsBackend = graphicsBackend
        self.profile = profile
    }
}

public enum CompatibilityMode: String, Codable, CaseIterable, Sendable { case singleplayer, multiplayer }
public enum CompatibilityOutcome: String, Codable, CaseIterable, Sendable { case works, limited, unplayable, notTested }
public enum MultiplayerFeature: String, Codable, CaseIterable, Sendable {
    case join, host, invites, crossplay, voice, disconnects
}
public enum CompatibilityIssue: String, Codable, CaseIterable, Sendable {
    case start, graphics, audio, performance, network
}

/// Submitted only after a person reviews the fields and explicitly chooses Submit.
public struct CompatibilityReport: Codable, Identifiable, Sendable {
    public let id: UUID
    public let gameID: Int
    public let mode: CompatibilityMode
    public let outcome: CompatibilityOutcome
    public let features: [MultiplayerFeature: CompatibilityOutcome]
    public let issue: CompatibilityIssue?
    public let note: String?
    public let context: CompatibilityContext
    public let createdAt: Date

    public init(id: UUID = UUID(), gameID: Int, mode: CompatibilityMode, outcome: CompatibilityOutcome,
                features: [MultiplayerFeature: CompatibilityOutcome] = [:], issue: CompatibilityIssue? = nil,
                note: String? = nil, context: CompatibilityContext,
                createdAt: Date = .now) {
        self.id = id
        self.gameID = gameID
        self.mode = mode
        self.outcome = outcome
        self.features = mode == .multiplayer ? features : [:]
        self.issue = issue
        self.note = note.map { String($0.prefix(500)) }
        self.context = context
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, gameID, mode, outcome, features, issue, note, context, createdAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        gameID = try values.decode(Int.self, forKey: .gameID)
        mode = try values.decode(CompatibilityMode.self, forKey: .mode)
        outcome = try values.decode(CompatibilityOutcome.self, forKey: .outcome)
        let rawFeatures = try values.decode([String: CompatibilityOutcome].self, forKey: .features)
        features = Dictionary(uniqueKeysWithValues: rawFeatures.compactMap { key, value in
            MultiplayerFeature(rawValue: key).map { ($0, value) }
        })
        issue = try values.decodeIfPresent(CompatibilityIssue.self, forKey: .issue)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        context = try values.decode(CompatibilityContext.self, forKey: .context)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(gameID, forKey: .gameID)
        try values.encode(mode, forKey: .mode)
        try values.encode(outcome, forKey: .outcome)
        try values.encode(Dictionary(uniqueKeysWithValues: features.map { ($0.key.rawValue, $0.value) }), forKey: .features)
        try values.encodeIfPresent(issue, forKey: .issue)
        try values.encodeIfPresent(note, forKey: .note)
        try values.encode(context, forKey: .context)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

public struct CompatibilityAggregate: Codable, Sendable {
    public let gameID: Int
    public let mode: CompatibilityMode
    public let context: CompatibilityContext
    public let counts: [CompatibilityOutcome: Int]
    public let features: [MultiplayerFeature: [CompatibilityOutcome: Int]]
    public let suggestedProfile: GameRuntimeProfile?

    public init(gameID: Int, mode: CompatibilityMode, context: CompatibilityContext,
                counts: [CompatibilityOutcome: Int],
                features: [MultiplayerFeature: [CompatibilityOutcome: Int]] = [:],
                suggestedProfile: GameRuntimeProfile? = nil) {
        self.gameID = gameID
        self.mode = mode
        self.context = context
        self.counts = counts
        self.features = features
        self.suggestedProfile = suggestedProfile
    }

    private enum CodingKeys: String, CodingKey { case gameID, mode, context, counts, features, suggestedProfile }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try values.decode(Int.self, forKey: .gameID)
        mode = try values.decode(CompatibilityMode.self, forKey: .mode)
        context = try values.decode(CompatibilityContext.self, forKey: .context)
        let rawCounts = try values.decode([String: Int].self, forKey: .counts)
        counts = Dictionary(uniqueKeysWithValues: rawCounts.compactMap { key, value in
            CompatibilityOutcome(rawValue: key).map { ($0, value) }
        })
        let rawFeatures = try values.decode([String: [String: Int]].self, forKey: .features)
        features = Dictionary(uniqueKeysWithValues: rawFeatures.compactMap { key, values in
            MultiplayerFeature(rawValue: key).map { feature in
                (feature, Dictionary(uniqueKeysWithValues: values.compactMap { outcome, count in
                    CompatibilityOutcome(rawValue: outcome).map { ($0, count) }
                }))
            }
        })
        suggestedProfile = try values.decodeIfPresent(GameRuntimeProfile.self, forKey: .suggestedProfile)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(gameID, forKey: .gameID)
        try values.encode(mode, forKey: .mode)
        try values.encode(context, forKey: .context)
        try values.encode(Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }), forKey: .counts)
        try values.encode(Dictionary(uniqueKeysWithValues: features.map { feature, counts in
            (feature.rawValue, Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }))
        }), forKey: .features)
        try values.encodeIfPresent(suggestedProfile, forKey: .suggestedProfile)
    }
}

public struct CompatibilityCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let aggregates: [CompatibilityAggregate]

    public init(generatedAt: Date, aggregates: [CompatibilityAggregate]) {
        self.schemaVersion = 1
        self.generatedAt = generatedAt
        self.aggregates = aggregates
    }
}

public struct CompatibilityDiskStore {
    public let directory: URL
    public var profilesURL: URL { directory.appendingPathComponent("game-runtime-profiles.json") }
    public var pendingURL: URL { directory.appendingPathComponent("pending-compatibility-reports.json") }
    public var historyURL: URL { directory.appendingPathComponent("submitted-compatibility-reports.json") }
    public var catalogURL: URL { directory.appendingPathComponent("compatibility-catalog-cache.json") }

    public init(directory: URL) { self.directory = directory }

    public func loadProfiles() -> [Int: GameRuntimeProfile] {
        read([Int: GameRuntimeProfile].self, from: profilesURL) ?? [:]
    }

    public func saveProfiles(_ profiles: [Int: GameRuntimeProfile]) throws { try write(profiles, to: profilesURL) }
    public func loadPending() -> [CompatibilityReport] { read([CompatibilityReport].self, from: pendingURL) ?? [] }
    public func savePending(_ reports: [CompatibilityReport]) throws { try write(reports, to: pendingURL) }
    public func loadHistory() -> [CompatibilityReport] { read([CompatibilityReport].self, from: historyURL) ?? [] }
    public func saveHistory(_ reports: [CompatibilityReport]) throws { try write(reports, to: historyURL) }
    public func loadCatalog() -> CompatibilityCatalog? { read(CompatibilityCatalog.self, from: catalogURL) }
    public func saveCatalog(_ catalog: CompatibilityCatalog) throws { try write(catalog, to: catalogURL) }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), data.count <= 2_000_000 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 2_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}

public enum CompatibilityTransportError: Error { case invalidEndpoint, invalidResponse, oversizedResponse }

public struct CompatibilityHTTPClient: Sendable {
    public let catalogURL: URL?
    public let reportURL: URL?
    public let session: URLSession

    public init(catalogURL: URL?, reportURL: URL?, session: URLSession = .shared) {
        self.catalogURL = catalogURL
        self.reportURL = reportURL
        self.session = session
    }

    public func fetchCatalog() async throws -> CompatibilityCatalog {
        guard let catalogURL, catalogURL.scheme == "https" else { throw CompatibilityTransportError.invalidEndpoint }
        var request = URLRequest(url: catalogURL)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CompatibilityTransportError.invalidResponse }
        guard data.count <= 2_000_000 else { throw CompatibilityTransportError.oversizedResponse }
        let catalog = try JSONDecoder().decode(CompatibilityCatalog.self, from: data)
        guard catalog.schemaVersion == 1, catalog.aggregates.count <= 5_000,
              catalog.aggregates.allSatisfy({ aggregate in
                  aggregate.gameID > 0 && aggregate.gameID <= Int(UInt32.max) &&
                  aggregate.counts.values.allSatisfy { (0...1_000_000).contains($0) } &&
                  aggregate.features.values.allSatisfy { $0.values.allSatisfy { (0...1_000_000).contains($0) } } &&
                  aggregate.context.runtimeVersion.count <= 100 && aggregate.context.appVersion.count <= 100 &&
                  aggregate.context.macOSVersion.count <= 100 &&
                  aggregate.context.chip.count <= 100 && aggregate.context.gameVersion.count <= 100 &&
                  aggregate.context.graphicsBackend.count <= 100 &&
                  (try? aggregate.context.profile.arguments(for: aggregate.gameID)) != nil &&
                  (aggregate.suggestedProfile == nil ||
                   (try? aggregate.suggestedProfile?.arguments(for: aggregate.gameID)) != nil)
              }) else { throw CompatibilityTransportError.invalidResponse }
        return catalog
    }

    public func submit(_ report: CompatibilityReport) async throws {
        guard let reportURL, reportURL.scheme == "https" else { throw CompatibilityTransportError.invalidEndpoint }
        let data = try JSONEncoder().encode(report)
        guard data.count <= 16_384 else { throw CompatibilityTransportError.oversizedResponse }
        var request = URLRequest(url: reportURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 8
        let (_, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else {
            throw CompatibilityTransportError.invalidResponse
        }
    }
}
