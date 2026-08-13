import Foundation
import SwiftUI

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let level: LogLevel

    enum LogLevel: String, Equatable {
        case prefill
        case generation
        case kvcache
        case tool
        case timing
        case warning
        case error
        case info
    }
}

extension LogLine.LogLevel {
    var color: Color {
        switch self {
        case .prefill, .timing:
            return Color(red: 0.25, green: 0.50, blue: 0.50)
        case .generation:
            return Color(red: 0.00, green: 0.50, blue: 0.25)
        case .kvcache:
            return Color(red: 0.50, green: 0.50, blue: 0.00)
        case .tool:
            return Color(red: 0.56, green: 0.56, blue: 0.56)
        case .warning:
            return Color(red: 1.00, green: 0.40, blue: 0.10)
        case .error:
            return Color(red: 1.00, green: 0.23, blue: 0.18)
        case .info:
            return Color.primary
        }
    }
}
