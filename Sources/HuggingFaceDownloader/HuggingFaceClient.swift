import Foundation

// MARK: - ResolvedFilePath

public struct ResolvedFilePath: Codable, Equatable {
    public let path: String
    public let size: Int64
    public let oid: String
    public let lfs: LfsInfo?

    public init(path: String, size: Int64, oid: String, lfs: LfsInfo?) {
        self.path = path
        self.size = size
        self.oid = oid
        self.lfs = lfs
    }
}

public struct LfsInfo: Codable, Equatable {
    public let oid: String
    public let size: Int64
    public let url: String?

    public init(oid: String, size: Int64, url: String?) {
        self.oid = oid
        self.size = size
        self.url = url
    }
}

// MARK: - DownloadUrl

public struct DownloadUrl: Codable, Equatable {
    public let location: String
    public let lfs: LfsInfo?

    public init(location: String, lfs: LfsInfo?) {
        self.location = location
        self.lfs = lfs
    }
}

// MARK: - HuggingFaceClient

public protocol HuggingFaceClient {
    func resolveFilePath(repo: String, path: String) async throws -> ResolvedFilePath
    func resolveDownloadUrl(repo: String, path: String) async throws -> DownloadUrl
    func listFiles(repo: String, path: String) async throws -> [ResolvedFilePath]
}