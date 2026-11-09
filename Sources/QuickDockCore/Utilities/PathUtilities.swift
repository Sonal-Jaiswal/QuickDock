import Foundation

public enum PathUtilities {
    /// Expands `~`, resolves `.`/`..` and removes trailing slashes.
    public static func standardize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var standardized = (expanded as NSString).standardizingPath
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    /// Replaces the home directory prefix with `~` for compact display.
    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// Validation and normalization of website addresses.
public enum WebAddress {
    public enum ValidationError: Error, Equatable, LocalizedError {
        case empty
        case unsupportedScheme(String)
        case missingHost
        case tooLong

        public var errorDescription: String? {
            switch self {
            case .empty: return "Enter a website address."
            case .unsupportedScheme(let scheme):
                return "“\(scheme):” links aren’t supported. Use an address that starts with https:// or http://."
            case .missingHost: return "That doesn’t look like a website address."
            case .tooLong: return "That address is too long."
            }
        }
    }

    public static let allowedSchemes: Set<String> = ["https", "http"]
    public static let maximumLength = 4_096

    /// Turns user input such as `example.com/docs` into `https://example.com/docs`.
    /// Only `http` and `https` are accepted so a "website" can never trigger an
    /// arbitrary URL-scheme handler.
    public static func normalize(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }
        guard trimmed.count <= maximumLength else { throw ValidationError.tooLong }

        var candidate = trimmed
        if let schemeEnd = candidate.range(of: "://") {
            let scheme = candidate[..<schemeEnd.lowerBound].lowercased()
            guard allowedSchemes.contains(scheme) else { throw ValidationError.unsupportedScheme(scheme) }
        } else if let colon = candidate.firstIndex(of: ":"),
                  case let prefix = candidate[..<colon],
                  !prefix.isEmpty,
                  prefix.allSatisfy({ $0.isLetter || $0 == "+" || $0 == "-" || $0 == "." }),
                  !looksLikeHostWithPort(candidate) {
            // e.g. "mailto:x", "javascript:...", "file:..."
            throw ValidationError.unsupportedScheme(prefix.lowercased())
        } else {
            candidate = "https://" + candidate
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), allowedSchemes.contains(scheme),
              let host = components.host, !host.isEmpty,
              host.contains(".") || host == "localhost",
              !host.contains(" "),
              let url = components.url else {
            throw ValidationError.missingHost
        }
        return url
    }

    /// True for input such as `localhost:3000` or `example.com:8080/path`.
    private static func looksLikeHostWithPort(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let afterColon = text[text.index(after: colon)...]
        let portDigits = afterColon.prefix { $0.isNumber }
        return !portDigits.isEmpty && (afterColon.count == portDigits.count || afterColon.dropFirst(portDigits.count).first == "/")
    }

    /// A canonical string used to detect duplicate websites.
    public static func canonicalString(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" { components.path = "" }
        components.fragment = nil
        return components.string ?? url.absoluteString.lowercased()
    }

    /// A short display name for a URL: the host without `www.`.
    public static func displayName(for url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
