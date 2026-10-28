import Foundation
import Testing
@testable import ArchwayCore

@Test func compatibilityAPIBaseURLResolution() {
    let custom = CompatibilityAPI.endpointURLs(baseURLString: "https://compatibility.example.org/")
    #expect(custom?.catalog == "https://compatibility.example.org/v1/catalog")
    #expect(custom?.reports == "https://compatibility.example.org/v1/reports")
    for invalid in [nil, "", "http://compatibility.example.org", "https://user@compatibility.example.org",
                    "https://compatibility.example.org/prefix", "https://compatibility.example.org?key=value"] {
        #expect(CompatibilityAPI.endpointURLs(baseURLString: invalid) == nil)
    }
}

@Test func gameProfileArgumentsAreLiteral() throws {
    let profile = GameRuntimeProfile(launchArguments: ["-dx12", "a b"], graphicsAPI: .gameDefault)
    #expect(try profile.arguments() == ["-dx12", "a b"])
    let forced = GameRuntimeProfile(launchArguments: ["-windowed"], graphicsAPI: .d3d11)
    #expect(try forced.arguments() == ["-windowed", "-force-d3d11"])
    #expect(throws: ArchwayError.self) { try GameRuntimeProfile(launchArguments: ["bad\nvalue"]).arguments() }
}

@Test func compatibilityDiskAndWireRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archway-compatibility-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let disk = CompatibilityDiskStore(directory: directory)
    let profile = GameRuntimeProfile(launchArguments: ["-dx11"])
    try disk.saveProfiles([1144200: profile])
    #expect(disk.loadProfiles()[1144200] == profile)
    let context = CompatibilityContext(runtimeVersion: "11.20", appVersion: "1.0", macOSVersion: "15.1",
                                       chip: "Apple M4", gameVersion: "123", graphicsBackend: "d3dmetal",
                                       profile: profile)
    let report = CompatibilityReport(gameID: 1144200, mode: .multiplayer, outcome: .limited,
                                     features: [.join: .works, .voice: .notTested], issue: .network,
                                     note: "Disconnected once", context: context)
    try disk.savePending([report])
    #expect(disk.loadPending().first?.id == report.id)
    let reportObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    let featureObject = try #require(reportObject["features"] as? [String: String])
    #expect(featureObject["join"] == "works")
    let aggregate = CompatibilityAggregate(gameID: 1144200, mode: .multiplayer, context: context,
                                           counts: [.limited: 2, .notTested: 1],
                                           features: [.join: [.works: 2]])
    let catalog = CompatibilityCatalog(generatedAt: .now, aggregates: [aggregate])
    try disk.saveCatalog(catalog)
    #expect(disk.loadCatalog()?.aggregates.first?.counts[.limited] == 2)
    let aggregateObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(aggregate)) as? [String: Any])
    let counts = try #require(aggregateObject["counts"] as? [String: Int])
    #expect(counts["limited"] == 2)
}

private func context(runtime: String = "11.20", macOS: String = "27.0.1", chip: String = "Apple M4",
                     app: String = "1.0") -> CompatibilityContext {
    CompatibilityContext(runtimeVersion: runtime, appVersion: app, macOSVersion: macOS, chip: chip,
                         gameVersion: "42", graphicsBackend: "d3dmetal", profile: GameRuntimeProfile())
}

private func aggregate(_ gameID: Int, _ context: CompatibilityContext,
                       _ counts: [CompatibilityOutcome: Int]) -> CompatibilityAggregate {
    CompatibilityAggregate(gameID: gameID, mode: .singleplayer, context: context, counts: counts)
}

@Test func gamesNeedSeveralReportsAndTheCurrentRuntimeDecides() {
    let catalog = CompatibilityCatalog(generatedAt: Date(), aggregates: [
        aggregate(1, context(), [.works: 1]),
        aggregate(2, context(), [.works: 2, .limited: 1]),
        aggregate(3, context(runtime: "11.18"), [.works: 5]),
        aggregate(3, context(), [.unplayable: 3]),
        aggregate(4, context(runtime: "11.18"), [.works: 5]),
        aggregate(4, context(), [.unplayable: 1]),
    ])

    #expect(catalog.workingGameIDs(runtimeVersion: "11.20") == [2, 4])
}

@Test func summaryCombinesComparableSetups() {
    let current = context()
    let catalog = CompatibilityCatalog(generatedAt: Date(), aggregates: [
        aggregate(1, context(macOS: "27.1", chip: "Apple M4 Pro", app: "1.1"), [.works: 2]),
        aggregate(1, context(), [.works: 1, .limited: 1]),
        aggregate(1, context(macOS: "26.4"), [.unplayable: 4]),
        aggregate(1, context(runtime: "11.18"), [.unplayable: 4]),
    ])

    let summary = catalog.summary(gameID: 1, mode: .singleplayer, context: current)
    #expect(summary?.counts == [.works: 3, .limited: 1])
    #expect(catalog.summary(gameID: 1, mode: .multiplayer, context: current) == nil)
}
