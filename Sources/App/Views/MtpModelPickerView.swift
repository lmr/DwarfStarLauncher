import SwiftUI

struct MtpModelPickerView: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(ServerManager.self) private var serverManager
    @Binding var path: String

    var body: some View {
        VStack {
            if modelManager.mtpModels.isEmpty {
                Text("No MTP models found")
                    .foregroundStyle(.secondary)
            } else {
                List(modelManager.mtpModels) { model in
                    HStack {
                        Text(model.name)
                            .lineLimit(1)
                        Spacer()
                        Text(model.humanReadableSize)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        modelManager.selectMtpModel(model)
                        serverManager.config.mtpModelPath = model.path
                        path = model.path
                    }
                    .listRowBackground(model.isSelected ? Color.accentColor.opacity(0.2) : nil)
                }
                .listStyle(.plain)
                .frame(minHeight: 100)
            }

            HStack {
                Button("Refresh") {
                    modelManager.refresh()
                }
                .controlSize(.small)

                Spacer()
            }
        }
        .onAppear {
            modelManager.refresh()
            modelManager.selectMtpModel(byPath: path)
        }
    }
}
