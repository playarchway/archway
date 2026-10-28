import AppKit

/// The standard About panel, with the notice the GPL asks for. The credits are built here rather than read from a
/// Credits.html, which stays black in Dark Mode.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
        NSApp.activate()
    }

    private static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString()
        text.append(paragraph(String(localized: "Archway is free software under the [GNU General Public License, version 3](https://www.gnu.org/licenses/gpl-3.0.html), and comes without any warranty. Its source code is on [GitHub](https://github.com/playarchway/archway).")))
        text.append(paragraph(String(localized: "The licenses of the open source software in Archway and its Windows runtime are in Settings, under Licenses.")))
        return text
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
