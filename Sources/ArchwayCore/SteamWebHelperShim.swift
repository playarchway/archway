import Foundation

/// Keeps Steam's client UI visible under Wine's macOS driver.
///
/// Chromium's GPU process draws into a window owned by Steam's browser process, and
/// winemac.drv cannot present cross-process drawing (Wine bugs 35456 and 60263), so
/// the window stays black. The bundled shim takes the place of `steamwebhelper.exe`
/// and starts Valve's helper, moved to `steamwebhelper.real.exe`, with
/// `--in-process-gpu`. Steam must then start with ``launchArguments`` so its
/// bootstrapper does not restore the original file.
public struct SteamWebHelperShim {
    public enum State: Equatable {
        /// Steam's webhelper is not installed yet.
        case missing
        /// Valve's helper is in place; the UI will render black.
        case original
        case installed
        /// The shim is present but Valve's helper next to it is gone.
        case incomplete
    }

    public static let launchArguments = ["-noverifyfiles", "-norepairfiles"]

    public let directory: URL
    public let shim: Data

    public var helper: URL { directory.appendingPathComponent("steamwebhelper.exe") }
    public var realHelper: URL { directory.appendingPathComponent("steamwebhelper.real.exe") }

    public init(directory: URL, shim: Data) {
        self.directory = directory
        self.shim = shim
    }

    public static func bundledShim() throws -> Data {
        guard let url = Bundle.module.url(forResource: "steamwebhelper-shim", withExtension: "exe") else {
            throw ArchwayError.invalidPath("The bundled steamwebhelper shim is missing from this Archway build.")
        }
        return try Data(contentsOf: url)
    }

    public func state() throws -> State {
        guard try isRegularFile(helper) else {
            return try isRegularFile(realHelper) ? .incomplete : .missing
        }
        guard try isShim(helper) else { return .original }
        return try isRegularFile(realHelper) ? .installed : .incomplete
    }

    /// Moves Valve's helper aside and puts the shim in its place. After a Steam update
    /// has restored Valve's helper, this replaces the stale copy with the new one.
    /// Returns false while Steam has not downloaded its webhelper yet; launch Steam
    /// without ``launchArguments`` then so its bootstrapper can complete the client.
    @discardableResult
    public func install() throws -> Bool {
        switch try state() {
        case .installed:
            return true
        case .missing:
            return false
        case .incomplete:
            guard try isRegularFile(realHelper) else {
                throw ArchwayError.invalidPath("Steam's webhelper is missing next to the Archway shim. Run open-steam --without-webhelper-shim once so Steam can repair it.")
            }
            try writeShim()
            return true
        case .original:
            let staged = directory.appendingPathComponent("steamwebhelper.archway-staged.exe")
            try? FileManager.default.removeItem(at: staged)
            try shim.write(to: staged)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
            if try isRegularFile(realHelper) { try FileManager.default.removeItem(at: realHelper) }
            try FileManager.default.moveItem(at: helper, to: realHelper)
            try FileManager.default.moveItem(at: staged, to: helper)
            return true
        }
    }

    /// Restores Valve's helper. Without it, Steam repairs the file on its next verified start.
    public func remove() throws {
        let fm = FileManager.default
        switch try state() {
        case .missing:
            return
        case .original:
            if try isRegularFile(realHelper) { try fm.removeItem(at: realHelper) }
        case .installed:
            try fm.removeItem(at: helper)
            try fm.moveItem(at: realHelper, to: helper)
        case .incomplete:
            if try isRegularFile(helper) { try fm.removeItem(at: helper) }
            if try isRegularFile(realHelper) { try fm.moveItem(at: realHelper, to: helper) }
        }
    }

    private func writeShim() throws {
        try shim.write(to: helper, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    }

    private func isShim(_ url: URL) throws -> Bool {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return try size == shim.count && Data(contentsOf: url) == shim
    }

    private func isRegularFile(_ url: URL) throws -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        guard values.isSymbolicLink != true else {
            throw ArchwayError.invalidPath("Steam webhelper path must not be a symlink: \(url.path)")
        }
        return values.isRegularFile == true
    }
}
