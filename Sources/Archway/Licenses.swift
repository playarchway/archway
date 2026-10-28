import AppKit
import SwiftUI
import ArchwayCore

/// One piece of software Archway ships or downloads, with the license text that has to travel with it.
struct OpenSourceNotice: Identifiable {
    let name: String
    let version: String?
    let license: String
    let url: URL
    /// Nil until the Windows runtime that carries it is installed; runtimes before 11.20-e51c772 lack Wine Mono's.
    let text: String?

    var id: String { name }

    /// What the app bundle carries: Archway itself and Sparkle (copied by scripts/build-app.sh).
    static func app() -> [OpenSourceNotice] {
        let sparkle = Bundle(identifier: "org.sparkle-project.Sparkle")
        return [
            OpenSourceNotice(name: "Archway",
                             version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                             license: "GPL-3.0", url: URL(string: "https://github.com/playarchway/archway")!,
                             text: bundled("Archway-LICENSE")),
            OpenSourceNotice(name: "Sparkle",
                             version: sparkle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                             license: "MIT", url: URL(string: "https://sparkle-project.org")!,
                             text: bundled("Sparkle-LICENSE")),
        ]
    }

    /// What the Windows runtime package carries, read from the installed package (scripts in archway-runtime).
    static func runtime(paths: AppPaths?) -> [OpenSourceNotice] {
        let wine = paths.flatMap { try? ConfigStore(paths: $0).load() }
            .map { URL(fileURLWithPath: $0.wine).deletingLastPathComponent().deletingLastPathComponent() }
        let docs = wine?.appendingPathComponent("share/doc/archway-wine")
        let source = docs.flatMap { try? String(contentsOf: $0.appendingPathComponent("SOURCE"), encoding: .utf8) }
        // SOURCE lines read "FreeType: 2.15.0 (https://freetype.org)"; the first names the runtime.
        func version(of name: String) -> String? {
            source?.split(separator: "\n").first { $0.hasPrefix(name + ":") }?
                .dropFirst(name.count + 1).split(separator: " ").first.map(String.init)
        }
        let runtimeVersion = source?.split(separator: "\n").first?.split(separator: " ").last.map(String.init)
        return [
            OpenSourceNotice(name: "Wine", version: runtimeVersion, license: "LGPL-2.1-or-later",
                             url: URL(string: "https://github.com/playarchway/archway-wine")!,
                             text: docs.flatMap { text(at: $0.appendingPathComponent("LICENSE")) }),
            OpenSourceNotice(name: "FreeType", version: version(of: "FreeType"), license: "FTL",
                             url: URL(string: "https://freetype.org")!,
                             text: docs.flatMap { text(at: $0.appendingPathComponent("FreeType-LICENSE.TXT")) }),
            OpenSourceNotice(name: "Wine Mono", version: version(of: "Wine Mono"), license: "MIT, LGPL",
                             url: URL(string: "https://github.com/wine-mono/wine-mono")!,
                             text: docs.flatMap { text(at: $0.appendingPathComponent("WineMono-COPYING")) }),
            OpenSourceNotice(name: "D3DMetal", version: nil, license: "Apple",
                             url: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!,
                             text: wine.flatMap { rtf(at: $0.appendingPathComponent("lib/external/GPTK-License.rtf")) }),
        ]
    }

    private static func bundled(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses").flatMap(text(at:))
    }

    private static func text(at url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func rtf(at url: URL) -> String? {
        (try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                 documentAttributes: nil))?.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The Licenses tab in Settings: Archway's own notice, then each component as a row that opens to its license.
struct LicensesView: View {
    let paths: AppPaths?
    @State private var app = OpenSourceNotice.app()
    @State private var runtime: [OpenSourceNotice] = []

    var body: some View {
        Form {
            Section {
                Text("Archway is free software under the [GNU General Public License, version 3](https://www.gnu.org/licenses/gpl-3.0.html), and comes without any warranty. Its source code is on [GitHub](https://github.com/playarchway/archway).")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Included in Archway") {
                ForEach(app) { NoticeRow(notice: $0) }
            }
            Section {
                ForEach(runtime) { NoticeRow(notice: $0) }
            } header: {
                Text("Downloaded with the Wine runtime")
            } footer: {
                Text("The license texts come from the installed Windows runtime. [archway-runtime](https://github.com/playarchway/archway-runtime) describes how it is built.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .tint(.archwayAccent)
        .task { runtime = OpenSourceNotice.runtime(paths: paths) }
    }
}

private struct NoticeRow: View {
    let notice: OpenSourceNotice
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                if let text = notice.text {
                    ScrollView {
                        Text(verbatim: text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                } else {
                    Text("The license is on the project page.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Button { isExpanded.toggle() } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: notice.name).fontWeight(.medium)
                        if let version = notice.version {
                            Text(verbatim: version).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: notice.license).font(.callout).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Link(destination: notice.url) { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open Project Page")
            }
        }
    }
}
