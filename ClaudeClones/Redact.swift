import Foundation

/// Strips secrets out of a claude:// link before it is logged or shown.
///
/// These links carry magic-link tokens, SSO callback codes and MCP OAuth codes in
/// their query. Anything that reaches the log file or the screen keeps the shape of
/// the link, which is what makes it debuggable, and drops the values.
enum Redact {
    /// Plain text on purpose: URLComponents percent encodes angle brackets, which
    /// turns a tidy "token=redacted" into "token=%3Credacted%3E".
    static let placeholder = "redacted"
    static let unrecognized = "unrecognized link"

    static func link(_ url: URL) -> String {
        // Fail closed. URL(string:) happily accepts arbitrary text by percent
        // encoding it, and anything without a scheme is not a link we understand,
        // so it never reaches the log or the screen.
        guard let scheme = url.scheme, !scheme.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return unrecognized }
        components.user = nil
        components.password = nil
        components.fragment = components.fragment == nil ? nil : placeholder
        if let items = components.queryItems, !items.isEmpty {
            components.queryItems = items.map {
                URLQueryItem(name: $0.name, value: $0.value == nil ? nil : placeholder)
            }
        }
        return components.string ?? unrecognized
    }

    static func link(_ string: String) -> String {
        URL(string: string).map(link) ?? unrecognized
    }
}
