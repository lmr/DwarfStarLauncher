import Foundation
import SwiftUI
import CryptoKit
import HuggingFaceDownloader


// MARK: - DownloadEngine

@Observable
final class ModelDownloader: NSObject, URLSessionDataDelegate {
    var downloadState: DownloadState = .idle
    var currentTarget: DownloadTarget?
    var availableTargets: [DownloadTarget] = DownloadTarget.allCases
    var resolvedSizes: [String: Int64] = [:]
    var resolvedOids: [String: String] = [:]
    var onDownloadComplete: ((DownloadTarget) -> Void)?
    var onDownloadError: ((String) -> Void)?

    private let huggingFaceClient: HuggingFaceClient
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var outputFile: FileHandle?
    private var partURL: URL?
    private var bytesReceived: Int64 = 0
    private var totalBytes: Int64 = 0
    private var startTime: Date?
    private var speedWindow: [(Date, Int64)] = []
    private var isCancelled = false
    private var isStartingDownload = false
    // Timestamp of the last throttled progress push; gates UI updates to ~4 Hz.
    private var lastProgressUpdate: Date?
    // Expected total size resolved from Hugging Face at download start (not the
    // hardcoded catalog value, which is wrong for some targets).
    private var expectedTotalSize: Int64 = 0

    private static var oidCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ds4-launcher/cache/model_oids.json")
    }

    private func loadOidCache() {
        guard let data = try? Data(contentsOf: Self.oidCacheURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        resolvedOids = dict
    }

    private func saveOidCache() {
        do {
            let cacheDir = Self.oidCacheURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: cacheDir.path) {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            }
            let data = try JSONSerialization.data(withJSONObject: resolvedOids)
            try data.write(to: Self.oidCacheURL)
        } catch {}
    }

    init(huggingFaceClient: HuggingFaceClient = DefaultHuggingFaceClient()) {
        self.huggingFaceClient = huggingFaceClient
        super.init()
        loadOidCache()
    }

    // MARK: - Download

    func download(target: DownloadTarget) {
        guard task == nil, !isStartingDownload else { return }
        isStartingDownload = true

        Task { @MainActor in
            defer { isStartingDownload = false }
            let resolvedSize = await resolveExpectedSize(for: target)
            startDownload(target: target, expectedSize: resolvedSize)
        }
    }

    @MainActor
    private func startDownload(target: DownloadTarget, expectedSize: Int64) {
        currentTarget = target
        let files = target.files
        let partURL = PathResolver.partFileURL(for: files.first?.localName ?? target.rawValue)
        self.partURL = partURL

        // Determine resume offset
        var offset: Int64 = 0
        if FileManager.default.fileExists(atPath: partURL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path)
            let partSize = (attrs?[FileAttributeKey.size] as? Int64) ?? 0
            if partSize > 0, verifyMagicHeader(at: partURL) {
                offset = partSize
            } else {
                try? FileManager.default.removeItem(at: partURL)
            }
        }

        self.expectedTotalSize = expectedSize
        totalBytes = offset
        bytesReceived = 0
        isCancelled = false
        startTime = Date()
        speedWindow = [(Date(), offset)]
        lastProgressUpdate = nil

        let hfURL = buildHFDownloadURL(target: target, file: files.first)
        var request = URLRequest(url: hfURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        // Auth header
        if let token = resolveToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Open output file for writing (append mode for resume)
        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }
        guard let fileHandle = try? FileHandle(forWritingTo: partURL) else {
            downloadState = .error(message: "Could not open output file")
            return
        }
        if offset > 0 {
            _ = try? fileHandle.seekToEnd()
        }
        outputFile = fileHandle

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 7 * 86400 // 7 days
        let session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        self.session = session

        task = session.dataTask(with: request)
        task?.resume()

        downloadState = .progress(
            percent: totalBytes > 0 ? Double(offset) / Double(expectedSize) * 100 : 0,
            bytesDownloaded: offset,
            totalBytes: expectedSize,
            speedBytesPerSec: 0,
            etaSeconds: 0
        )
    }

    /// Sums the real file sizes reported by Hugging Face for each file of the
    /// target, falling back per-file to the catalog size if resolution fails.
    func refreshSizes() async {
        resolvedSizes = await withTaskGroup(of: (String, Int64).self, returning: [String: Int64].self) { group in
            for target in DownloadTarget.allCases {
                group.addTask {
                    (target.rawValue, await self.resolveExpectedSize(for: target))
                }
            }
            var map: [String: Int64] = [:]
            for await entry in group {
                map[entry.0] = entry.1
            }
            return map
        }
    }

    private func resolveExpectedSize(for target: DownloadTarget) async -> Int64 {
        await withTaskGroup(of: (Int64, String?, String).self, returning: Int64.self) { group in
            for file in target.files {
                let oidKey = "\(target.repo)/\(file.remoteName)"
                if resolvedOids[oidKey] != nil { continue }
                group.addTask {
                    let resolved = try? await self.huggingFaceClient.resolveFilePath(
                        repo: target.repo, path: file.remoteName
                    )
                    return (resolved?.size ?? file.size, resolved?.oid, oidKey)
                }
            }
            var total: Int64 = 0
            var newOids: [String: String] = [:]
            for await result in group {
                total += result.0
                if let oid = result.1, !oid.isEmpty {
                    newOids[result.2] = oid
                }
            }
            // Apply on main thread to avoid race conditions with @Observable
            let oidsToApply = newOids
            await MainActor.run {
                self.resolvedOids.merge(oidsToApply) { _, new in new }
                saveOidCache()
            }
            return total
        }
    }

    func downloadMultiFile(target: DownloadTarget) {
        Task {
            await downloadMultiFileAsync(target: target)
        }
    }

    private func downloadMultiFileAsync(target: DownloadTarget) async {
        let files = target.files
        guard !files.isEmpty else { return }

        currentTarget = target
        self.expectedTotalSize = await resolveExpectedSize(for: target)

        for (index, file) in files.enumerated() {
            guard !isCancelled else { return }

            do {
                let (resolvedPath, downloadUrl) = try await resolveFileForDownload(repo: target.repo, file: file)

                // Check for resume
                let partURL = PathResolver.partFileURL(for: file.localName)
                var offset: Int64 = 0
                if FileManager.default.fileExists(atPath: partURL.path) {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path)
                    let partSize = (attrs?[FileAttributeKey.size] as? Int64) ?? 0
                    if partSize > 0 {
                        offset = partSize
                    } else {
                        try? FileManager.default.removeItem(at: partURL)
                    }
                }

                // Resolve the actual download URL (handle LFS redirect)
                let finalUrl = try await resolveActualDownloadUrl(
                    repo: target.repo,
                    path: resolvedPath.path,
                    fileUrl: downloadUrl,
                    resumeOffset: offset
                )

                // Download the file
                try await downloadFile(from: finalUrl, to: partURL, resumeOffset: offset, targetFile: file, currentIndex: index, totalFiles: files.count, target: target)

                // Mark as downloaded
                // (In a real implementation, we'd track per-file state)

            } catch {
                currentTarget = nil
                self.downloadState = .error(message: "Failed to download \(file.remoteName): \(error.localizedDescription)")
                self.onDownloadError?(error.localizedDescription)
                return
            }
        }

        // All files downloaded
        currentTarget = target
        self.downloadState = .complete
        self.onDownloadComplete?(target)
    }

    private func resolveFileForDownload(repo: String, file: ModelFile) async throws -> (ResolvedFilePath, DownloadUrl) {
        let resolvedPath = try await huggingFaceClient.resolveFilePath(repo: repo, path: file.remoteName)
        let downloadUrl = try await huggingFaceClient.resolveDownloadUrl(repo: repo, path: file.remoteName)
        return (resolvedPath, downloadUrl)
    }

    private func resolveActualDownloadUrl(repo: String, path: String, fileUrl: DownloadUrl, resumeOffset: Int64) async throws -> URL {
        // If the file has LFS info with a presigned URL, use it
        if let lfsUrl = fileUrl.lfs?.url, !lfsUrl.isEmpty {
            return URL(string: lfsUrl)!
        }

        // Otherwise use the resolved URL
        let resolveUrl = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(path)")!
        return resolveUrl
    }

    private func downloadFile(from url: URL, to fileURL: URL, resumeOffset: Int64, targetFile: ModelFile, currentIndex: Int, totalFiles: Int, target: DownloadTarget) async throws {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        if let token = resolveToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 7 * 86400
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) else {
            try? FileManager.default.removeItem(at: fileURL)
            throw HFClientError.fileNotFound
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        if resumeOffset > 0 {
            _ = try? fileHandle.seekToEnd()
        }
        // Stream received bytes to the .part file incrementally (memory-bounded).
        // AsyncBytes yields individual bytes; buffer them and flush in bounded chunks.
        var buffer = Data()
        var bytesWritten: Int64 = 0
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 1024 * 1024 {
                fileHandle.write(buffer)
                bytesWritten += Int64(buffer.count)
                buffer = Data()
            }
        }
        if !buffer.isEmpty {
            fileHandle.write(buffer)
            bytesWritten += Int64(buffer.count)
        }
        try? fileHandle.close()

        // Update progress
        let fileProgress = Double(currentIndex + 1) / Double(totalFiles)
        let overallProgress = fileProgress * 100.0
        DispatchQueue.main.async {
            self.downloadState = .progress(
                percent: overallProgress,
                bytesDownloaded: bytesWritten,
                totalBytes: self.expectedTotalSize,
                speedBytesPerSec: 0,
                etaSeconds: 0
            )
        }
    }

    // MARK: - Cancel

    func cancel() {
        guard let t = task else { return }
        isCancelled = true
        currentTarget = nil
        t.cancel()
        cleanup()
        downloadState = .idle
    }

    // MARK: - Token Resolver

    private func resolveToken() -> String? {
        // Try config file (stored as plain text) first
        let tokenStore = ConfigTokenStore()
        if let token = tokenStore.load(), !token.isEmpty {
            return token
        }

        // Fallback to HF_TOKEN env var
        if let env = ProcessInfo.processInfo.environment["HF_TOKEN"], !env.isEmpty {
            return env
        }

        // Fallback to cached token file
        let cachePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/token")
        if let token = try? String(contentsOf: cachePath).trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        return nil
    }

    // MARK: - URL Builder

    private func buildHFDownloadURL(target: DownloadTarget, file: ModelFile?) -> URL {
        let repo = target.repo
        // Use the remote name (actual path in the repo) so files nested in
        // subdirectories (e.g. GLM Unsloth's UD-Q4_K_XL/ shards) resolve correctly.
        let fileName = file?.remoteName ?? target.rawValue
        return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(fileName)")!
    }

    // MARK: - Magic Header

    private let ggufMagic: Set<String> = ["GGUF", "GGML", "FGGU"]

    private func verifyMagicHeader(at fileURL: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? fileHandle.close() }
        let data = fileHandle.readData(ofLength: 4)
        guard data.count == 4, let magic = String(data: data, encoding: .utf8) else { return false }
        return ggufMagic.contains(magic)
    }

    // MARK: - Integrity Check

    private func checkIntegrity(at fileURL: URL, expectedSize: Int64, oidKey: String? = nil) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attrs?[FileAttributeKey.size] as? Int64, size == expectedSize else { return false }
        if !verifyMagicHeader(at: fileURL) { return false }
        // If we have a cached SHA256 hash from HF API, verify it (expensive but thorough)
        if let key = oidKey, let expectedHash = resolvedOids[key] {
            return sha256OfFile(fileURL) == expectedHash.lowercased()
        }
        return true
    }

    private func sha256OfFile(_ fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1024 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Cleanup

    private func cleanup() {
        task = nil
        session = nil
        outputFile = nil
        partURL = nil
        bytesReceived = 0
        totalBytes = 0
        expectedTotalSize = 0
        startTime = nil
        speedWindow = []
        isStartingDownload = false
        lastProgressUpdate = nil
    }
}

// MARK: - URLSession Delegate (synchronous ObjC-compatible methods)

extension ModelDownloader {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        guard let httpResponse = response as? HTTPURLResponse else { return .cancel }

        if httpResponse.statusCode == 206 || httpResponse.statusCode == 200 {
            return .allow
        }

        // Handle errors (e.g. 404, 401)
        let message: String
        switch httpResponse.statusCode {
        case 401: message = "Authentication failed. Check HF_TOKEN."
        case 404: message = "File not found on Hugging Face Hub."
        case 429: message = "Rate limited. Add HF_TOKEN for higher limits."
        default:  message = "HTTP \(httpResponse.statusCode)"
        }
        DispatchQueue.main.async {
            self.downloadState = .error(message: message)
            self.cleanup()
        }
        return .cancel
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled else { return }

        outputFile?.write(data)

        bytesReceived += Int64(data.count)
        totalBytes += Int64(data.count)

        // Speed / ETA calculation
        let now = Date()
        speedWindow.append((now, bytesReceived))
        // Keep last 5 seconds
        speedWindow = speedWindow.filter { now.timeIntervalSince($0.0) <= 5 }

        let speed: Int64
        if let first = speedWindow.first, speedWindow.count > 1 {
            let elapsed = now.timeIntervalSince(first.0)
            if elapsed > 0 {
                speed = Int64(Double(bytesReceived - first.1) / elapsed)
            } else {
                speed = 0
            }
        } else {
            speed = 0
        }

        let expectedSize = self.expectedTotalSize
        let eta: Int
        if speed > 0 {
            let remaining = max(expectedSize - totalBytes, 0)
            eta = Int(remaining / speed)
        } else {
            eta = 0
        }

        // Throttle progress-state pushes to ~4 Hz (250ms) so the UI does not
        // reflow on every network chunk. Speed/ETA math above still runs per
        // chunk; only the main-thread push is gated.
        if let last = lastProgressUpdate, now.timeIntervalSince(last) < 0.25 {
            return
        }
        lastProgressUpdate = now

        DispatchQueue.main.async {
            self.downloadState = .progress(
                percent: Double(self.totalBytes) / Double(expectedSize) * 100,
                bytesDownloaded: self.totalBytes,
                totalBytes: expectedSize,
                speedBytesPerSec: speed,
                etaSeconds: eta
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            let partURL = self.partURL
            let expectedSize = self.expectedTotalSize
            let target = partURL.flatMap { url in
                self.availableTargets.first { $0.filename == url.lastPathComponent.replacingOccurrences(of: ".part", with: "") }
            }

            self.cleanup()
            self.currentTarget = nil

            guard !self.isCancelled else { return }

            if let error = error as NSError? {
                if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                    return
                }
                let msg = error.localizedDescription
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            guard let partURL = partURL else {
                let msg = "Internal error: missing file path"
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            guard let target = target else {
                let msg = "Unknown download target"
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            // Integrity check (with optional SHA256 verification if we have a cached OID)
            let oidKey = target.files.first.map { "\(target.repo)/\($0.remoteName)" }
            guard self.checkIntegrity(at: partURL, expectedSize: expectedSize, oidKey: oidKey) else {
                try? FileManager.default.removeItem(at: partURL)
                let msg = "Integrity check failed: size or magic header mismatch"
                self.downloadState = .failed(reason: msg)
                self.onDownloadError?(msg)
                return
            }

            // Rename .part -> .gguf
            let finalURL = PathResolver.modelsDir.appendingPathComponent(target.filename)
            do {
                try FileManager.default.moveItem(at: partURL, to: finalURL)
            } catch {
                let msg = "Failed to finalize download: \(error.localizedDescription)"
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            self.downloadState = .complete
            self.onDownloadComplete?(target)
        }
    }
}
