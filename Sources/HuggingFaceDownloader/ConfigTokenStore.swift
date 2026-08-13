import Foundation
import Observation

// MARK: - ConfigTokenStore (file-backed token store, not using keychain)

@Observable
public final class ConfigTokenStore {

    // In-memory cache shared across all instances, so the config file is only
    // read once per session. This avoids repeated disk reads during downloads.
    private static var cachedToken: String? = nil

    /// Optional override for the config file location. Defaults to the standard
    /// ~/.config/ds4-launcher/config.json path; tests inject a temp file URL.
    private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    public func save(_ newToken: String) throws {
        Self.cachedToken = newToken.isEmpty ? nil : newToken
        try writeConfig(token: newToken.isEmpty ? nil : newToken)
    }

    public func load() -> String? {
        if let cached = Self.cachedToken {
            return cached
        }

        let token = readConfigToken()
        Self.cachedToken = token
        return token
    }

    public func delete() throws {
        Self.cachedToken = nil
        try writeConfig(token: nil)
    }

    public func exists() -> Bool {
        guard let token = load() else { return false }
        return !token.isEmpty
    }

    // MARK: - Config File I/O

    private static var defaultConfigFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ds4-launcher/config.json")
    }

    private var configFileURL: URL {
        fileURL ?? Self.defaultConfigFileURL
    }

    private func readConfigToken() -> String? {
        let url = configFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }

        // Decode only the hf_token field to avoid coupling on full ServerConfig schema.
        struct TokenWrapper: Decodable {
            let hfToken: String?
        }

        guard let decoded = try? JSONDecoder().decode(TokenWrapper.self, from: data) else {
            return nil
        }
        return decoded.hfToken?.isEmpty == true ? nil : decoded.hfToken
    }

    private func writeConfig(token: String?) throws {
        // Read existing config (if any), update hf_token, and write back.
        let url = configFileURL
        var dict: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        if let token, !token.isEmpty {
            dict["hfToken"] = token
        } else {
            dict.removeValue(forKey: "hfToken")
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try JSONSerialization.data(withJSONObject: dict)
        try data.write(to: url, options: .atomic)
    }
}
