import SwiftUI

struct LogView: View {
    @Environment(ServerManager.self) private var serverManager
    @State private var autoScroll = true

    @AppStorage("logFontFamily") private var logFontFamily = ""
    @AppStorage("logFontSize") private var logFontSize = 12

    private var logFont: Font {
        logFontFamily.isEmpty
            ? .system(size: 12, design: .monospaced)
            : .custom(logFontFamily, size: CGFloat(logFontSize))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(serverManager.logLines) { line in
                            Text(line.text)
                                .font(logFont)
                                .foregroundColor(line.level.color)
                                .textSelection(.enabled)
                                .padding(.horizontal, DesignTokens.Spacing.s2)
                                .padding(.vertical, 2)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.s1)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: serverManager.logLines.count) { _, _ in
                    if autoScroll, let last = serverManager.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: DesignTokens.Spacing.s2) {
                        if !autoScroll {
                            Button {
                                if let last = serverManager.logLines.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            } label: {
                                Label("Scroll to bottom", systemImage: "chevron.down")
                                    .labelStyle(.iconOnly)
                                    .controlSize(.small)
                            }
                        }

                        Toggle(isOn: $autoScroll) {
                            Label("Auto-scroll", systemImage: "arrow.down.to.line.combined.with.magnifyingglass")
                        }

                        Button {
                            copyLogs()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            serverManager.clearLogs()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }

                    }
                    .padding(DesignTokens.Spacing.s2)
                    .background(DesignTokens.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.Radii.s))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radii.s)
                            .stroke(DesignTokens.separatorStrong, lineWidth: 1)
                    )
                    .padding(DesignTokens.Spacing.s2)
                }
            }

            Divider()
                .background(DesignTokens.separator)

            .padding(.horizontal, DesignTokens.Spacing.s4)
            .padding(.top, DesignTokens.Spacing.s1)
        }
        .background(DesignTokens.panelGradient)
        .navigationTitle("Log")
    }

    private func copyLogs() {
        let text = serverManager.logLines.map(\.text).joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
