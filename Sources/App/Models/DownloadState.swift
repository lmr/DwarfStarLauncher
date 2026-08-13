import Foundation

enum DownloadState: Equatable {
    case idle
    case progress(percent: Double, bytesDownloaded: Int64, totalBytes: Int64, speedBytesPerSec: Int64, etaSeconds: Int)
    case complete
    case error(message: String)
    case failed(reason: String)
}
