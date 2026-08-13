import SwiftUI

struct TrayTitleLabel: View {
    @Environment(ServerManager.self) private var serverManager

    var body: some View {
        Label(statusTitle(), systemImage: "circle.fill")
    }

    func statusTitle() -> String {
        switch serverManager.status {
        case .starting: return "● Starting"
        case .running:  return "● Running"
        case .stopped:  return "● Stopped"
        case .error:    return "● Error"
        }
    }
}
