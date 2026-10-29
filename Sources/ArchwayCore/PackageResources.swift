import Foundation

extension Bundle {
    /// A SwiftPM resource bundle that the app keeps in Contents/Resources (scripts/build-app.sh). SwiftPM's own
    /// `Bundle.module` looks for it at the app's root, where code signing doesn't allow it, and then in the build
    /// directory, which exists only on the Mac that built the app. Nil outside the app, for example in the CLI.
    public static func packageResources(_ name: String) -> Bundle? {
        Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent(name + ".bundle")) }
    }

    static let archwayCore = packageResources("Archway_ArchwayCore") ?? .module
}
