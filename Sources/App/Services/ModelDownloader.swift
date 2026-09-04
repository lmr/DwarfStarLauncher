import Foundation
import SwiftUI
import CryptoKit
import HuggingFaceDownloader

// MARK: - Download engine

@Observable
final class ModelDownloader: NSObject, URLSessionDataDelegate {
    var downloadState: DownloadState = .idle
    var currentTarget: DownloadTarget?
    var availableTargets: [DownloadTarget] = DownloadTarget.allCases
    var resolvedSizes: [String: Int64] = [:]
    var resolvedOids: [String: String] = [:]
    private(set) var partialFiles: Set<String> = []
    var onDownloadComplete: ((DownloadTarget) -> Void)?
    var onDownloadError: ((String) -> Void)?

    private let huggingFaceClient: HuggingFaceClient
    private let tokenStore: ConfigTokenStore
    private let sessionConfiguration: URLSessionConfiguration

    // URLSession retains its delegate. A single serial queue owns every piece
    // of transfer state and all file I/O, so callbacks cannot race one another
    // or block the main thread.
    private let transferQueue: OperationQueue
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var outputFile: FileHandle?
    private var partURL: URL?
    private var activeTarget: DownloadTarget?
    private var activeFileIndex = 0
    private var activeIsMultiFile = false
    private var cumulativeBytes: Int64 = 0
    private var currentFileExpectedSize: Int64 = 0
    private var expectedTotalSize: Int64 = 0
    private var bytesReceivedInFile: Int64 = 0
    private var totalBytesInFile: Int64 = 0
    private var speedWindow: [(Date, Int64)] = []
    private var lastProgressUpdate: Date?
    private var transferCancelled = false
    private var pendingResponseError: String?
    private var resumeRangeRejected = false
    private var resumeOffsetRequested: Int64 = 0
    private var fileSizes: [String: Int64] = [:]
    private var fileOids: [String: String] = [:]
    private var operationID = 0
    private var lastCancelledOperationID = 0
    private var activeOperationID = 0
    private var isStartingDownload = false

    private static var oidCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ds4-launcher/cache/model_oids.json")
    }

    init(
        huggingFaceClient: HuggingFaceClient = DefaultHuggingFaceClient(),
        tokenStore: ConfigTokenStore = ConfigTokenStore(),
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.huggingFaceClient = huggingFaceClient
        self.tokenStore = tokenStore
        self.sessionConfiguration = sessionConfiguration

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        self.transferQueue = queue

        super.init()
        loadOidCache()
        refreshDownloadedFiles()
        refreshPartialFiles()
    }

    // MARK: - Downloaded and partial file state

    func refreshDownloadedFiles() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let complete = self?.completedFileNames() ?? []
            DispatchQueue.main.async {
                self?.downloadedFiles = complete
            }
        }
    }

    func refreshPartialFiles() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let partial = self?.partialFileNames() ?? []
            DispatchQueue.main.async {
                self?.partialFiles = partial
            }
        }
    }

    /// True when every file of the target is present on disk at a known full
    /// catalog size. The catalog fallback is intentional because resolved
    /// sizes are session-local and are not persisted with the model files.
    func isDownloaded(_ target: DownloadTarget) -> Bool {
        target.files.allSatisfy { downloadedFiles.contains($0.localName) }
    }

    func downloadedFileCount(for target: DownloadTarget) -> Int {
        target.files.reduce(0) { $0 + (downloadedFiles.contains($1.localName) ? 1 : 0) }
    }

    func hasPartialFiles(_ target: DownloadTarget) -> Bool {
        target.files.contains { partialFiles.contains($0.localName) }
    }

    private(set) var downloadedFiles: Set<String> = []

    private func completedFileNames() -> Set<String> {
        let fm = FileManager.default
        var result: Set<String> = []
        for target in DownloadTarget.allCases {
            for file in target.files {
                let urls = [
                    PathResolver.modelsDirectory(for: target.storageKind).appendingPathComponent(file.localName),
                    PathResolver.modelsDir.appendingPathComponent(file.localName)
                ]
                if urls.contains(where: { url in
                    guard fm.fileExists(atPath: url.path),
                          let attrs = try? fm.attributesOfItem(atPath: url.path),
                          let size = attrs[.size] as? Int64 else {
                        return false
                    }
                    return size == file.size
                }) {
                    result.insert(file.localName)
                }
            }
        }
        return result
    }

    private func partialFileNames() -> Set<String> {
        let fm = FileManager.default
        var result: Set<String> = []
        for target in DownloadTarget.allCases {
            for file in target.files {
                let urls = [
                    PathResolver.partFileURL(for: file.localName, in: target.storageKind),
                    PathResolver.modelsDir.appendingPathComponent("\(file.localName).part")
                ]
                if urls.contains(where: { url in
                    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                          let size = attrs[.size] as? Int64 else {
                        return false
                    }
                    return size > 0
                }) {
                    result.insert(file.localName)
                }
            }
        }
        return result
    }

    // MARK: - Download setup

    func download(target: DownloadTarget) {
        guard currentTarget == nil, !isStartingDownload else { return }

        isStartingDownload = true
        currentTarget = target
        operationID += 1
        let thisOperation = operationID

        Task { [weak self] in
            guard let self else { return }
            let metadata = await resolveMetadata(for: target)
            await MainActor.run {
                guard self.operationID == thisOperation, self.currentTarget == target else { return }
                self.isStartingDownload = false
                self.transferQueue.addOperation { [weak self] in
                    guard let self, self.lastCancelledOperationID < thisOperation else { return }
                    self.beginTransfer(target: target, metadata: metadata, operationID: thisOperation)
                }
            }
        }
    }

    private struct TargetMetadata {
        let totalSize: Int64
        let fileSizes: [String: Int64]
        let oids: [String: String]
    }

    /// Resolves each file independently. This preserves the real per-shard
    /// sizes for integrity checks while retaining the catalog value only as a
    /// fallback when the API cannot resolve a file.
    private func resolveMetadata(for target: DownloadTarget) async -> TargetMetadata {
        let cachedOids = await MainActor.run { resolvedOids }
        let entries = await withTaskGroup(of: (String, Int64, String?, String).self, returning: [(String, Int64, String?, String)].self) { group in
            for file in target.files {
                group.addTask {
                    let key = "\(target.repo)/\(file.remoteName)"
                    let resolved = try? await self.huggingFaceClient.resolveFilePath(
                        repo: target.repo,
                        path: file.remoteName
                    )
                    return (key, resolved?.size ?? file.size, resolved?.oid, file.localName)
                }
            }

            var values: [(String, Int64, String?, String)] = []
            for await entry in group {
                values.append(entry)
            }
            return values
        }

        var sizes: [String: Int64] = [:]
        var oids: [String: String] = [:]
        for (key, size, oid, localName) in entries {
            sizes[localName] = size
            if let oid, !oid.isEmpty {
                oids[key] = oid
            } else if let cachedOID = cachedOids[key] {
                oids[key] = cachedOID
            }
        }
        let metadataOids = oids
        let total = sizes.values.reduce(0, +)

        await MainActor.run {
            self.resolvedSizes[target.rawValue] = total
            self.resolvedOids.merge(metadataOids) { _, new in new }
            self.saveOidCache()
        }

        return TargetMetadata(totalSize: total, fileSizes: sizes, oids: metadataOids)
    }

    func refreshSizes() async {
        let entries = await withTaskGroup(of: (String, Int64).self, returning: [(String, Int64)].self) { group in
            for target in DownloadTarget.allCases {
                group.addTask {
                    let metadata = await self.resolveMetadata(for: target)
                    return (target.rawValue, metadata.totalSize)
                }
            }
            var values: [(String, Int64)] = []
            for await entry in group {
                values.append(entry)
            }
            return values
        }
        await MainActor.run {
            for (target, size) in entries {
                self.resolvedSizes[target] = size
            }
        }
    }

    private func beginTransfer(target: DownloadTarget, metadata: TargetMetadata, operationID: Int) {
        activeTarget = target
        activeOperationID = operationID
        activeFileIndex = 0
        activeIsMultiFile = target.files.count > 1
        cumulativeBytes = 0
        expectedTotalSize = metadata.totalSize
        fileSizes = metadata.fileSizes
        fileOids = metadata.oids
        transferCancelled = false
        beginCurrentFile()
    }

    private func beginCurrentFile() {
        guard let target = activeTarget, activeFileIndex < target.files.count else {
            finishSuccessfully(target: activeTarget)
            return
        }

        let file = target.files[activeFileIndex]
        let url = PathResolver.partFileURL(for: file.localName, in: target.storageKind)
        partURL = url
        currentFileExpectedSize = fileSizes[file.localName] ?? file.size
        expectedTotalSize = max(expectedTotalSize, 0)

        // Resume a legacy root-level partial download in its new category
        // directory when possible.
        if !FileManager.default.fileExists(atPath: url.path) {
            let legacyURL = PathResolver.modelsDir.appendingPathComponent("\(file.localName).part")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.moveItem(at: legacyURL, to: url)
            }
        }

        var offset: Int64 = 0
        if FileManager.default.fileExists(atPath: url.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let partSize = (attrs?[.size] as? Int64) ?? 0
            if partSize > 0, verifyMagicHeader(at: url) {
                offset = partSize
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            let message = "Could not open output file"
            failTransfer(message: message, state: .error(message: message))
            return
        }

        if offset > 0 {
            _ = try? handle.seekToEnd()
        } else {
            _ = try? handle.seek(toOffset: 0)
        }

        outputFile = handle
        totalBytesInFile = offset
        bytesReceivedInFile = 0
        speedWindow = [(Date(), 0)]
        lastProgressUpdate = nil
        pendingResponseError = nil
        resumeRangeRejected = false
        resumeOffsetRequested = offset

        var request = URLRequest(url: buildHFDownloadURL(target: target, file: file))
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        if let token = resolveToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: self,
            delegateQueue: transferQueue
        )
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()

        publishProgress()
        refreshPartialFiles()
    }

    // MARK: - Cancellation

    func cancel() {
        operationID += 1
        let cancellationID = operationID
        isStartingDownload = false
        currentTarget = nil
        downloadState = .idle

        transferQueue.addOperation { [weak self] in
            guard let self else { return }
            self.lastCancelledOperationID = cancellationID
            self.transferCancelled = true
            self.task?.cancel()
            self.session?.finishTasksAndInvalidate()
            self.closeOutputFile()
            self.resetTransferState()
        }
        refreshPartialFiles()
    }

    // MARK: - Token and URL helpers

    private func resolveToken() -> String? {
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

    private func buildHFDownloadURL(target: DownloadTarget, file: ModelFile?) -> URL {
        let fileName = file?.remoteName ?? target.rawValue
        return URL(string: "https://huggingface.co/\(target.repo)/resolve/main/\(fileName)")!
    }

    // MARK: - Integrity

    private let ggufMagic: Set<String> = ["GGUF", "GGML", "FGGU"]

    private func verifyMagicHeader(at fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 4)
        guard data.count == 4, let magic = String(data: data, encoding: .utf8) else { return false }
        return ggufMagic.contains(magic)
    }

    private func checkIntegrity(at fileURL: URL, expectedSize: Int64, oidKey: String) -> Bool {
        if expectedSize > 0 {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let size = attrs?[.size] as? Int64, size == expectedSize else { return false }
        }
        guard verifyMagicHeader(at: fileURL) else { return false }
        if let expectedHash = fileOids[oidKey] {
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

    // MARK: - URLSession delegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let response = response as? HTTPURLResponse else {
            pendingResponseError = "Invalid response from Hugging Face Hub."
            return .cancel
        }

        if response.statusCode == 200 || response.statusCode == 206 {
            if response.statusCode == 200 && resumeOffsetRequested > 0 {
                // A server that ignores Range would append a full response to
                // the existing partial file. Discard the partial deterministically
                // and surface a retryable error instead.
                resumeRangeRejected = true
                closeOutputFile()
                if let partURL { try? FileManager.default.removeItem(at: partURL) }
                return .cancel
            }
            return .allow
        }

        pendingResponseError = Self.httpErrorMessage(statusCode: response.statusCode)
        return .cancel
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !transferCancelled, let outputFile else { return }

        do {
            try outputFile.write(contentsOf: data)
        } catch {
            pendingResponseError = "Could not write download: \(error.localizedDescription)"
            dataTask.cancel()
            return
        }

        let count = Int64(data.count)
        bytesReceivedInFile += count
        totalBytesInFile += count

        let now = Date()
        speedWindow.append((now, bytesReceivedInFile))
        speedWindow.removeAll { now.timeIntervalSince($0.0) > 5 }

        publishProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let target = activeTarget else {
            finishSession()
            return
        }

        if transferCancelled {
            finishSession()
            closeOutputFile()
            resetTransferState()
            refreshPartialFiles()
            return
        }

        if resumeRangeRejected {
            let message = "The server ignored the resume range; the partial download was discarded. Retry to start over."
            finishWithError(message: message, state: .error(message: message))
            return
        }

        if let pendingResponseError {
            finishWithError(message: pendingResponseError, state: .error(message: pendingResponseError))
            return
        }

        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                finishWithError(message: nsError.localizedDescription, state: .error(message: nsError.localizedDescription))
            } else {
                finishWithError(message: error.localizedDescription, state: .error(message: error.localizedDescription))
            }
            return
        }

        guard let partURL, activeFileIndex < target.files.count else {
            let message = "Internal error: missing download file path"
            finishWithError(message: message, state: .error(message: message))
            return
        }

        let file = target.files[activeFileIndex]
        let oidKey = "\(target.repo)/\(file.remoteName)"
        guard checkIntegrity(at: partURL, expectedSize: currentFileExpectedSize, oidKey: oidKey) else {
            closeOutputFile()
            finishSession()
            try? FileManager.default.removeItem(at: partURL)
            let message = "Integrity check failed: size or magic header mismatch"
            finishWithError(message: message, state: .failed(reason: message), sessionAlreadyFinished: true)
            return
        }

        closeOutputFile()
        finishSession()

        let finalURL = PathResolver.modelsDirectory(for: target.storageKind)
            .appendingPathComponent(file.localName)
        do {
            try FileManager.default.moveItem(at: partURL, to: finalURL)
        } catch {
            let message = "Failed to finalize download: \(error.localizedDescription)"
            finishWithError(message: message, state: .error(message: message), sessionAlreadyFinished: true)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.downloadedFiles.insert(file.localName)
            self?.partialFiles.remove(file.localName)
        }

        if activeIsMultiFile {
            cumulativeBytes += totalBytesInFile
            activeFileIndex += 1
            resetPerFileState()
            if activeFileIndex < target.files.count {
                beginCurrentFile()
                return
            }
        }

        finishSuccessfully(target: target)
    }

    private static func httpErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 401: return "Authentication failed. Check HF_TOKEN."
        case 404: return "File not found on Hugging Face Hub."
        case 429: return "Rate limited. Add HF_TOKEN for higher limits."
        default: return "HTTP \(statusCode)"
        }
    }

    // MARK: - Transfer bookkeeping

    private func publishProgress() {
        let now = Date()
        if let last = lastProgressUpdate, now.timeIntervalSince(last) < 0.25 {
            return
        }
        lastProgressUpdate = now

        let overallBytes = max(cumulativeBytes + totalBytesInFile, 0)
        let expected = expectedTotalSize
        let percent: Double
        if expected > 0 {
            percent = min(max(Double(overallBytes) / Double(expected) * 100, 0), 100)
        } else {
            // DownloadState has no separate indeterminate case. A zero total
            // is the sentinel used by the view to show an indeterminate bar.
            percent = 0
        }

        let speed: Int64
        if let first = speedWindow.first, speedWindow.count > 1 {
            let elapsed = now.timeIntervalSince(first.0)
            speed = elapsed > 0 ? max(Int64(Double(bytesReceivedInFile - first.1) / elapsed), 0) : 0
        } else {
            speed = 0
        }
        let eta: Int
        if speed > 0, expected > 0 {
            eta = Int(max(expected - overallBytes, 0) / speed)
        } else {
            eta = 0
        }

        let state = DownloadState.progress(
            percent: percent,
            bytesDownloaded: overallBytes,
            totalBytes: expected,
            speedBytesPerSec: speed,
            etaSeconds: eta
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentTarget != nil else { return }
            self.downloadState = state
        }
    }

    private func closeOutputFile() {
        try? outputFile?.close()
        outputFile = nil
    }

    private func finishSession() {
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }

    private func resetPerFileState() {
        closeOutputFile()
        finishSession()
        partURL = nil
        bytesReceivedInFile = 0
        totalBytesInFile = 0
        currentFileExpectedSize = 0
        speedWindow = []
        lastProgressUpdate = nil
        pendingResponseError = nil
        resumeRangeRejected = false
        resumeOffsetRequested = 0
    }

    private func resetTransferState() {
        resetPerFileState()
        activeTarget = nil
        activeOperationID = 0
        activeFileIndex = 0
        activeIsMultiFile = false
        cumulativeBytes = 0
        expectedTotalSize = 0
        fileSizes = [:]
        fileOids = [:]
    }

    private func failTransfer(message: String, state: DownloadState) {
        finishWithError(message: message, state: state)
    }

    private func finishWithError(
        message: String,
        state: DownloadState,
        sessionAlreadyFinished: Bool = false
    ) {
        let transferOperationID = activeOperationID
        let transferTarget = activeTarget
        if !sessionAlreadyFinished {
            finishSession()
            closeOutputFile()
        }
        transferCancelled = true
        resetTransferState()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.operationID == transferOperationID,
                  self.currentTarget == transferTarget else { return }
            self.currentTarget = nil
            self.isStartingDownload = false
            self.downloadState = state
            self.onDownloadError?(message)
            self.refreshPartialFiles()
        }
    }

    private func finishSuccessfully(target: DownloadTarget?) {
        guard let target else { return }
        let transferOperationID = activeOperationID
        finishSession()
        closeOutputFile()
        transferCancelled = true
        resetTransferState()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.operationID == transferOperationID,
                  self.currentTarget == target else { return }
            self.currentTarget = nil
            self.isStartingDownload = false
            self.downloadState = .complete
            self.refreshDownloadedFiles()
            self.refreshPartialFiles()
            self.onDownloadComplete?(target)
        }
    }

    // MARK: - OID cache

    private func loadOidCache() {
        guard let data = try? Data(contentsOf: Self.oidCacheURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        resolvedOids = dict
    }

    private func saveOidCache() {
        do {
            let directory = Self.oidCacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: resolvedOids)
            try data.write(to: Self.oidCacheURL, options: .atomic)
        } catch {
            // OID caching is an optimization; a cache failure must not stop a download.
        }
    }
}
