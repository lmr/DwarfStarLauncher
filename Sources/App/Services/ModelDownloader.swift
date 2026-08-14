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
    // Multi-file bookkeeping: whether the active download spans several files,
    // which file is being fetched, and the bytes already written to completed
    // files (used to report overall progress across the whole target).
    private var isMultiFile = false
    private var currentFileIndex = 0
    private var multiFileCumulativeBytes: Int64 = 0
    // Expected size of the file currently being fetched. For multi-file targets
    // this is the per-file size (not the whole-target sum) so integrity checks
    // compare each file against its own expected size.
    private var currentFileExpectedSize: Int64 = 0
    // Local file names (under the models dir) whose full catalog size is present
    // on disk. This is the in-memory source of truth for "already downloaded" —
    // the catalog's `ModelFile.downloaded` flag is never mutated, so views must
    // not read it. Refreshed on a background queue; updated immediately on rename.
    private var downloadedFiles: Set<String> = []

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
        refreshDownloadedFiles()
    }

    // MARK: - Downloaded-state (in-memory, background-refreshed)

    /// Scans the models directory on a background queue and records which
    /// catalog files are already fully on disk. Views read `isDownloaded` /
    /// `downloadedFileCount` which hit this set — never the disk.
    func refreshDownloadedFiles() {
        let complete = completedFileNames()
        Task { @MainActor in
            self.downloadedFiles = complete
        }
    }

    private func completedFileNames() -> Set<String> {
        let fm = FileManager.default
        let modelsDir = PathResolver.modelsDir
        var result: Set<String> = []
        for target in DownloadTarget.allCases {
            for file in target.files {
                let url = modelsDir.appendingPathComponent(file.localName)
                guard fm.fileExists(atPath: url.path),
                      let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? Int64,
                      size == file.size else { continue }
                result.insert(file.localName)
            }
        }
        return result
    }

    /// True when every file of the target is present on disk at full size.
    func isDownloaded(_ target: DownloadTarget) -> Bool {
        target.files.allSatisfy { downloadedFiles.contains($0.localName) }
    }

    func downloadedFileCount(for target: DownloadTarget) -> Int {
        target.files.reduce(0) { $0 + (downloadedFiles.contains($1.localName) ? 1 : 0) }
    }

    // MARK: - Download

    func download(target: DownloadTarget) {
        // `currentTarget != nil` also guards the multi-file gap between files,
        // where `task` is nil but a download is still in progress.
        guard task == nil, currentTarget == nil, !isStartingDownload else { return }
        isStartingDownload = true

        Task { @MainActor in
            defer { isStartingDownload = false }
            if target.files.count > 1 {
                // Multi-shard targets (e.g. GLM 11 shards, PRO 2-file split)
                // download each file through the same delegate-driven engine,
                // sequenced one after the other.
                await downloadMultiFileAsync(target: target)
            } else {
                let resolvedSize = await resolveExpectedSize(for: target)
                startDownload(target: target, expectedSize: resolvedSize)
            }
        }
    }

    @MainActor
    private func startDownload(target: DownloadTarget, expectedSize: Int64) {
        currentTarget = target
        let files = target.files
        let file = files[currentFileIndex]
        let partURL = PathResolver.partFileURL(for: file.localName)
        self.partURL = partURL
        // Per-file expected size: resolved single-file size for single-file
        // targets; the catalog size per file for multi-file targets.
        currentFileExpectedSize = isMultiFile ? file.size : expectedSize

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

        let hfURL = buildHFDownloadURL(target: target, file: file)
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

        // For multi-file targets, overall progress accounts for the bytes already
        // written to completed files plus this file's resume offset.
        let overallBytes = multiFileCumulativeBytes + totalBytes
        downloadState = .progress(
            percent: overallBytes > 0 ? Double(overallBytes) / Double(expectedSize) * 100 : 0,
            bytesDownloaded: overallBytes,
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

    /// Downloads a multi-file target by feeding each file through the same
    /// delegate-driven engine used for single-file targets, one file at a time.
    /// `didCompleteWithError` advances `currentFileIndex` and starts the next
    /// file, so this coordinator only sets up the first one.
    @MainActor
    private func downloadMultiFileAsync(target: DownloadTarget) async {
        let files = target.files
        guard !files.isEmpty else { return }

        currentTarget = target
        isMultiFile = true
        currentFileIndex = 0
        multiFileCumulativeBytes = 0
        expectedTotalSize = await resolveExpectedSize(for: target)

        startDownload(target: target, expectedSize: expectedTotalSize)
    }

    // MARK: - Cancel

    func cancel() {
        // Always mark cancelled first: the active single-file task may be nil
        // (multi-file downloads never assign `task`), so the flag is what stops
        // the next file from starting and lets the in-flight file abort cleanly.
        isCancelled = true
        currentTarget = nil
        task?.cancel()
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

    /// Clears state that belongs to a single file's transfer. Keeps
    /// `expectedTotalSize`, `isMultiFile`, `currentFileIndex`,
    /// `multiFileCumulativeBytes`, and `currentFileExpectedSize` so the next
    /// file in a multi-file download can continue.
    private func resetPerFileState() {
        task = nil
        session = nil
        outputFile = nil
        partURL = nil
        bytesReceived = 0
        totalBytes = 0
        startTime = nil
        speedWindow = []
        lastProgressUpdate = nil
    }

    private func cleanup() {
        resetPerFileState()
        expectedTotalSize = 0
        currentFileExpectedSize = 0
        isMultiFile = false
        currentFileIndex = 0
        multiFileCumulativeBytes = 0
        isStartingDownload = false
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
        // For multi-file targets, overall progress includes bytes already
        // written to completed files plus this file's bytes so far.
        let overallBytes = self.multiFileCumulativeBytes + self.totalBytes
        let eta: Int
        if speed > 0 {
            let remaining = max(expectedSize - overallBytes, 0)
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
                percent: Double(overallBytes) / Double(expectedSize) * 100,
                bytesDownloaded: overallBytes,
                totalBytes: expectedSize,
                speedBytesPerSec: speed,
                etaSeconds: eta
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            let partURL = self.partURL
            let target = partURL.flatMap { url in
                let localName = url.lastPathComponent.replacingOccurrences(of: ".part", with: "")
                return self.availableTargets.first { target in
                    target.files.contains { $0.localName == localName }
                }
            }

            // Terminal cancellation: tear down and exit without surfacing an error.
            guard !self.isCancelled else {
                self.cleanup()
                self.currentTarget = nil
                return
            }

            if let error = error as NSError? {
                self.cleanup()
                self.currentTarget = nil
                if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                    return
                }
                let msg = error.localizedDescription
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            guard let partURL = partURL else {
                self.cleanup()
                self.currentTarget = nil
                let msg = "Internal error: missing file path"
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            guard let target = target else {
                self.cleanup()
                self.currentTarget = nil
                let msg = "Unknown download target"
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            // Integrity check against this file's expected size (plus optional OID).
            let file = target.files[self.currentFileIndex]
            let oidKey = "\(target.repo)/\(file.remoteName)"
            guard self.checkIntegrity(at: partURL, expectedSize: self.currentFileExpectedSize, oidKey: oidKey) else {
                self.cleanup()
                self.currentTarget = nil
                try? FileManager.default.removeItem(at: partURL)
                let msg = "Integrity check failed: size or magic header mismatch"
                self.downloadState = .failed(reason: msg)
                self.onDownloadError?(msg)
                return
            }

            // Rename .part -> .gguf
            let finalURL = PathResolver.modelsDir.appendingPathComponent(file.localName)
            do {
                try FileManager.default.moveItem(at: partURL, to: finalURL)
                self.downloadedFiles.insert(file.localName)
            } catch {
                self.cleanup()
                self.currentTarget = nil
                let msg = "Failed to finalize download: \(error.localizedDescription)"
                self.downloadState = .error(message: msg)
                self.onDownloadError?(msg)
                return
            }

            // Multi-file target: advance to the next file, keeping currentTarget set.
            if self.isMultiFile {
                self.multiFileCumulativeBytes += self.totalBytes
                self.currentFileIndex += 1
                if self.currentFileIndex < target.files.count {
                    self.resetPerFileState()
                    self.startDownload(target: target, expectedSize: self.expectedTotalSize)
                    return
                }
            }

            self.cleanup()
            self.currentTarget = nil
            self.downloadState = .complete
            self.onDownloadComplete?(target)
        }
    }
}
