import Foundation
import Observation

// MARK: - ConfigTokenStore (file-backed token store, not using keychain)

@Observable
public final class ConfigTokenStore {
    private let configStore: ConfigStore
    private let cacheLock = NSLock()
    private var cachedToken: String?
    private var didLoadToken = false

    public init(fileURL: URL? = nil, configStore: ConfigStore? = nil) {
        self.configStore = configStore ?? ConfigStore(fileURL: fileURL)
    }

    public func save(_ newToken: String) throws {
        let token = newToken.isEmpty ? nil : newToken
        cacheLock.lock()
        defer { cacheLock.unlock() }
        try configStore.updateJSONObject { object in
            if let token {
                object["hfToken"] = token
            } else {
                object.removeValue(forKey: "hfToken")
            }
        }
        cachedToken = token
        didLoadToken = true
    }

    public func load() -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if didLoadToken {
            return cachedToken
        }

        let token = readConfigToken()
        cachedToken = token
        didLoadToken = true
        return token
    }

    public func delete() throws {
        try save("")
    }

    public func exists() -> Bool {
        guard let token = load() else { return false }
        return !token.isEmpty
    }

    private func readConfigToken() -> String? {
        // Decode only the hfToken field to avoid coupling on full ServerConfig schema.
        struct TokenWrapper: Decodable {
            let hfToken: String?
        }
        guard let decoded = configStore.load(TokenWrapper.self) else { return nil }
        return decoded.hfToken?.isEmpty == true ? nil : decoded.hfToken
    }
}
