import Foundation
import Testing
@testable import ArchwayCore

@Test func compatibilityAPIBaseURLResolution() {
    let custom = CompatibilityAPI.endpointURLs(baseURLString: "https://compatibility.example.org/")
    #expect(custom.catalog == "https://compatibility.example.org/api/catalog")
    #expect(custom.reports == "https://compatibility.example.org/api/reports")
    for invalid in ["http://compatibility.example.org", "https://user@compatibility.example.org",
                    "https://compatibility.example.org/prefix", "https://compatibility.example.org?key=value"] {
        let endpoints = CompatibilityAPI.endpointURLs(baseURLString: invalid)
        #expect(endpoints.catalog == "\(CompatibilityAPI.publicBaseURL)/api/catalog")
        #expect(endpoints.reports == "\(CompatibilityAPI.publicBaseURL)/api/reports")
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
