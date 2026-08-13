import Foundation

struct GGUFModel: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    var isSelected: Bool = false

    var humanReadableSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
