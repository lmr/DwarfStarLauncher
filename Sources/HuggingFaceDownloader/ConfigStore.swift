import Foundation

/// The single serialized writer for the launcher's JSON configuration file.
///
/// The app and the Hugging Face token store can each hold a ConfigStore value,
/// but all instances share the same process-wide lock. JSON-object
/// read-modify-write updates therefore cannot lose fields when two callers
/// save at the same time. Writes use a temporary file/rename via `.atomic`
/// and tighten the resulting file permissions to owner-read/write only.
public final class ConfigStore {
    private static let lock = NSLock()

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ds4-launcher/config.json")
    }

    public func load<T: Decodable>(_ type: T.Type) -> T? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        try write(data)
    }

    /// Reads the current top-level JSON object and applies a serialized update.
    /// Invalid or missing files are treated as an empty object so a token or
    /// import-path update can repair a partial configuration file safely.
    public func updateJSONObject(_ update: (inout [String: Any]) -> Void) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        }
        update(&object)
        let data = try JSONSerialization.data(withJSONObject: object)
        try writeUnlocked(data)
    }

    private func write(_ data: Data) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try writeUnlocked(data)
    }

    private func writeUnlocked(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }
}
