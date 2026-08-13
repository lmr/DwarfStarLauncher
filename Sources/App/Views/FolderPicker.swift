import SwiftUI
import AppKit

struct FolderPicker: NSViewControllerRepresentable {
    let completion: (URL?) -> Void
    var title: String? = nil
    var prompt: String = "Choose"

    func makeNSViewController(context: Context) -> NSViewController {
        let controller = NSViewController()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            if let title {
                panel.message = title
            } else {
                panel.message = "Select the DS4 project root directory"
            }
            panel.prompt = prompt

            panel.begin(completionHandler: { response in
                if response == .OK {
                    self.completion(panel.urls.first)
                } else {
                    self.completion(nil)
                }
            })
        }
        return controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
