import Foundation

enum ServerStatus: Equatable {
    case starting
    case running
    case stopped
    case error(exitCode: Int32)

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .error:    return "Error"
        }
    }

    var color: String {
        switch self {
        case .starting: return "yellow"
        case .running:  return "green"
        case .stopped:  return "gray"
        case .error:    return "red"
        }
    }
}
