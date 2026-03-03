import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false
    @State private var recentFolders: [URL] = []

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            VStack(spacing: 24) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Photo Organizer")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("Pick a folder of RAW and JPEG photos to get started.")
                        .foregroundStyle(.secondary)
                }

                Button("Open Folder…") { openFolder() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)

                Text("or drag a folder onto this window")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Recent folders
                if !recentFolders.isEmpty {
                    Divider().frame(maxWidth: 320)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Folders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(recentFolders, id: \.self) { url in
                            Button {
                                loadFolder(url)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(url.deletingLastPathComponent().lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                    .frame(maxWidth: 320)
                }
            }
            .padding(40)

            if isTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.blue, lineWidth: 3)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear {
            recentFolders = RecentFolders.all()
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFolder(url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            Task { @MainActor in self.loadFolder(url) }
        }
        return true
    }

    private func loadFolder(_ url: URL) {
        appState.sourceURL = url
        Task { await appState.loadPhotos(from: url) }
    }
}
