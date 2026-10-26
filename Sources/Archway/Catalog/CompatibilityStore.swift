import Foundation
import Darwin
import Observation
import ArchwayCore

@MainActor
@Observable
final class CompatibilityStore {
    private static let defaultEndpoints = CompatibilityAPI.endpointURLs(
        baseURLString: Bundle.main.object(forInfoDictionaryKey: "ArchwayAPIBaseURL") as? String)
    static let defaultCatalogURL = defaultEndpoints.catalog
    static let defaultReportURL = defaultEndpoints.reports
    private(set) var profiles: [Int: GameRuntimeProfile]
    private(set) var catalog: CompatibilityCatalog?
    private(set) var pendingReports: [CompatibilityReport]
    private(set) var submittedReports: [CompatibilityReport]
    private(set) var lastSubmissionError: String?
    private let disk: CompatibilityDiskStore
    private let paths: AppPaths
    private var isRetrying = false

    init(paths: AppPaths) {
        self.paths = paths
        disk = CompatibilityDiskStore(directory: paths.dataDirectory)
        profiles = disk.loadProfiles().filter { (try? $0.value.arguments(for: $0.key)) != nil }
        catalog = disk.loadCatalog()
        pendingReports = disk.loadPending()
        submittedReports = disk.loadHistory()
    }

    func profile(for gameID: Int) -> GameRuntimeProfile { profiles[gameID] ?? GameRuntimeProfile() }

    func save(_ profile: GameRuntimeProfile, for gameID: Int) throws {
        _ = try profile.arguments(for: gameID)
        var updated = profiles
        updated[gameID] = profile
        try disk.saveProfiles(updated)
        profiles = updated
    }

    func context(for gameID: Int, profile: GameRuntimeProfile? = nil) -> CompatibilityContext {
        let configuration = try? ConfigStore(paths: paths).load()
        let runtime = configuration?.wine.components(separatedBy: "/").first { $0.hasPrefix("archway-wine-") }
            .map { String($0.dropFirst("archway-wine-".count)) } ?? "Unknown"
        let backend = configuration?.selectedGraphicsBackend.rawValue ?? "Unknown"
        let manifest = paths.bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/appmanifest_\(gameID).acf")
        let manifestText = try? String(contentsOf: manifest, encoding: .utf8)
        let buildID = manifestText.flatMap { text -> String? in
            guard let range = text.range(of: #""buildid"\s+"([^"]+)""#, options: .regularExpression) else { return nil }
            return text[range].split(separator: "\"").last.map(String.init)
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return CompatibilityContext(runtimeVersion: runtime,
                                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                                    macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                    chip: Self.machineIdentifier(), gameVersion: buildID ?? "Unknown",
                                    graphicsBackend: backend, profile: profile ?? self.profile(for: gameID))
    }

    private static func machineIdentifier() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1, size <= 256 else {
            return "Unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func aggregates(for gameID: Int, mode: CompatibilityMode) -> [CompatibilityAggregate] {
        guard let catalog else { return [] }
        let current = context(for: gameID)
        return catalog.aggregates.filter { aggregate in
            aggregate.gameID == gameID && aggregate.mode == mode &&
            aggregate.context.runtimeVersion == current.runtimeVersion &&
            aggregate.context.appVersion == current.appVersion &&
            aggregate.context.macOSVersion == current.macOSVersion &&
            aggregate.context.chip == current.chip &&
            aggregate.context.gameVersion == current.gameVersion &&
            aggregate.context.graphicsBackend == current.graphicsBackend &&
            aggregate.context.profile == current.profile
        }
    }

    func refreshCatalog() async {
        let client = client()
        guard client.catalogURL != nil else { return }
        do {
            let fetched = try await client.fetchCatalog()
            try disk.saveCatalog(fetched)
            catalog = fetched
        } catch {
            // Keep the last verified catalog for offline use.
        }
    }

    /// The caller presents every field and obtains Submit consent before this method.
    func submit(_ report: CompatibilityReport) async {
        if report.gameID <= 0 {
            var history = submittedReports
            history.append(report)
            do { try disk.saveHistory(history); submittedReports = history }
            catch { lastSubmissionError = error.localizedDescription }
            return
        }
        var updated = pendingReports
        updated.append(report)
        do { try disk.savePending(updated) } catch { lastSubmissionError = error.localizedDescription; return }
        pendingReports = updated
        await retryPending()
    }

    /// Retries only reports that were previously submitted with explicit consent.
    func retryPending() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        let client = client()
        guard client.reportURL != nil else {
            lastSubmissionError = String(localized: "No report endpoint is configured. Your report is saved locally.")
            return
        }
        for report in pendingReports {
            do {
                try await client.submit(report)
                var history = submittedReports
                if !history.contains(where: { $0.id == report.id }) { history.append(report) }
                try disk.saveHistory(history)
                submittedReports = history
                var remaining = pendingReports
                remaining.removeAll { $0.id == report.id }
                try disk.savePending(remaining)
                pendingReports = remaining
                lastSubmissionError = nil
            } catch {
                lastSubmissionError = String(localized: "Couldn’t send the report. It remains saved locally for retry.")
                break
            }
        }
    }

    private func client() -> CompatibilityHTTPClient {
        let defaults = UserDefaults.standard
        return CompatibilityHTTPClient(
            catalogURL: URL(string: defaults.string(forKey: "compatibilityCatalogURL") ?? Self.defaultCatalogURL),
            reportURL: URL(string: defaults.string(forKey: "compatibilityReportURL") ?? Self.defaultReportURL))
    }
}
