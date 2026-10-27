import Foundation

/// Logs name the Mac user in paths: `/Users/<name>` on the Mac side, `C:\users\<name>` and `Z:\Users\<name>`
/// inside Wine. An exported log replaces that name, so it can go into a public issue.
public enum LogRedaction {
    public static let placeholder = "user"

    public static func redact(_ text: String, userName: String = NSUserName()) -> String {
        guard !userName.isEmpty else { return text }
        let pattern = #"([\\/])(users)([\\/])"# + NSRegularExpression.escapedPattern(for: userName) + #"(?![^\\/\s"':;,)\]])"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "$1$2$3" + placeholder)
    }
}
