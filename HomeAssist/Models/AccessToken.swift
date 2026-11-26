import Foundation

/// Helpers for the long-lived access token the user pastes in.
enum AccessToken {
    /// Removes surrounding whitespace and newlines, which are easy to pick up when copying.
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A rough sanity check: Home Assistant long-lived tokens are ~180-character strings with
    /// no whitespace. Used only to warn the user (e.g. after a truncated paste), never to block.
    static func looksComplete(_ raw: String) -> Bool {
        let token = normalized(raw)
        return token.count >= 100 && !token.contains(where: \.isWhitespace)
    }
}
