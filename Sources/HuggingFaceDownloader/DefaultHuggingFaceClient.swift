import Foundation

// MARK: - DefaultHuggingFaceClient

public final class DefaultHuggingFaceClient: HuggingFaceClient {

    private let session: URLSession
    private let tokenStore: ConfigTokenStore
    private let baseURL = "https://huggingface.co"

    /// - Parameters:
    ///   - session: URLSession used for requests (inject a mock in tests).
    ///   - tokenStore: token store used for Bearer auth (inject a temp-backed store in tests).
    public init(session: URLSession = .shared, tokenStore: ConfigTokenStore = ConfigTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
    }

    public func resolveFilePath(repo: String, path: String) async throws -> ResolvedFilePath {
        let url = URL(string: "\(baseURL)/api/models/\(repo)/tree/main/\(path)")!
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token = resolveToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HFClientError.fileNotFound
        }

        let decoded = try JSONDecoder().decode(ResolvedFilePath.self, from: data)
        return decoded
    }

    public func resolveDownloadUrl(repo: String, path: String) async throws -> DownloadUrl {
        let url = URL(string: "\(baseURL)/api/models/\(repo)/resolve/main/\(path)")!
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("redirect=false", forHTTPHeaderField: "X-Reference-Redirect")
        if let token = resolveToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HFClientError.downloadUrlNotFound
        }

        let decoded = try JSONDecoder().decode(DownloadUrl.self, from: data)
        return decoded
    }

    public func listFiles(repo: String, path: String = "") async throws -> [ResolvedFilePath] {
        let url = URL(string: "\(baseURL)/api/models/\(repo)/tree/main/\(path)")!
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token = resolveToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HFClientError.fileNotFound
        }

        let decoded = try JSONDecoder().decode([ResolvedFilePath].self, from: data)
        return decoded
    }

    private func resolveToken() -> String? {
        // Config file token (cached in memory) takes priority so size resolution
        // and the actual download use the same credentials.
        let tokenStore = tokenStore
        if let token = tokenStore.load(), !token.isEmpty {
            return token
        }

        if let env = ProcessInfo.processInfo.environment["HF_TOKEN"], !env.isEmpty {
            return env
        }
        let cachePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/token")
        if let token = try? String(contentsOf: cachePath).trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        return nil
    }
}

// MARK: - Errors

public enum HFClientError: LocalizedError {
    case fileNotFound
    case downloadUrlNotFound

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found on Hugging Face Hub."
        case .downloadUrlNotFound:
            return "Could not resolve download URL."
        }
    }
}