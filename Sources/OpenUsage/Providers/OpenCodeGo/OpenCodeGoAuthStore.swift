import Foundation

enum OpenCodeGoAuthError: Error, LocalizedError, Equatable, CategorizedError {
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "OpenCode Go not logged in. Run `opencode login` or sign in via the CLI."
        }
    }

    var errorCategory: ErrorCategory { .notLoggedIn }
}

/// Reads OpenCode Go local credentials. The local assistant stores its API key at
/// `~/.local/share/opencode/auth.json` and writes usage history to `~/.local/share/opencode/opencode.db`.
/// We only need the key to confirm the user has authenticated; the usage itself comes from the DB.
struct OpenCodeGoAuthStore: Sendable {
    static let authPath = "~/.local/share/opencode/auth.json"
    static let databasePath = "~/.local/share/opencode/opencode.db"

    var files: TextFileAccessing

    init(files: TextFileAccessing = LocalTextFileAccessor()) {
        self.files = files
    }

    func hasAuthKey() -> Bool {
        guard let text = try? files.readTextIfPresent(Self.authPath) else { return false }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        for entryKey in ["opencode", "opencode-go"] {
            guard let entry = object[entryKey] as? [String: Any],
                  let key = entry["key"] as? String else { continue }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    func hasDatabase() -> Bool {
        files.exists(Self.databasePath)
    }
}
