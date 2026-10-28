import AppKit

/// The standard About panel, with the notices the GPL asks for and the licenses of the software Archway ships and
/// downloads. The credits are built here rather than read from a Credits.html, which stays black in Dark Mode.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
        NSApp.activate()
    }

    private static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString()
        text.append(paragraph(String(localized: "Archway is free software under the [GNU General Public License, version 3](https://www.gnu.org/licenses/gpl-3.0.html), and comes without any warranty. Its source code is on [GitHub](https://github.com/playarchway/archway).")))

        text.append(heading(String(localized: "Included in Archway")))
        text.append(paragraph(String(localized: "[Sparkle](https://sparkle-project.org) installs updates. MIT License:")))
        if let url = Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt", subdirectory: "Licenses"),
           let license = try? String(contentsOf: url, encoding: .utf8) {
            text.append(NSAttributedString(string: license.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }

        text.append(heading(String(localized: "Downloaded with the Wine runtime")))
        text.append(paragraph(String(localized: "[Wine](https://www.winehq.org) with Archway's changes from [archway-wine](https://github.com/playarchway/archway-wine): GNU Lesser General Public License, version 2.1 or later.")))
        text.append(paragraph(String(localized: "[FreeType](https://freetype.org): FreeType License.")))
        text.append(paragraph(String(localized: "[Wine Mono](https://github.com/wine-mono/wine-mono): MIT License, with parts under other open source licenses.")))
        text.append(paragraph(String(localized: "D3DMetal from Apple's Game Porting Toolkit: © Apple Inc., passed on unmodified and for non-commercial use under Apple's license.")))
        text.append(paragraph(String(localized: "The license files are in the runtime package; [archway-runtime](https://github.com/playarchway/archway-runtime) describes how it is built.")))
        return text
    }

    private static func heading(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    /// A paragraph from Markdown, so translations keep their links.
    private static func paragraph(_ markdown: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: markdown)).map(NSMutableAttributedString.init)
            ?? NSMutableAttributedString(string: markdown)
        let range = NSRange(location: 0, length: parsed.length)
        parsed.addAttributes([.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                              .foregroundColor: NSColor.labelColor], range: range)
        parsed.append(NSAttributedString(string: "\n\n"))
        return parsed
    }
}
