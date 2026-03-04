import SwiftUI

struct ExportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var destination: URL?
    @State private var flatten = true
    @State private var writeXMP = false
    @State private var renamePattern = ""
    @State private var phase: Phase = .setup
    @State private var exportProgress: CopyService.Progress?
    @State private var exportedURL: URL?

    private enum Phase { case setup, exporting, done }

    private var autoDestName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return "Keepers_\(f.string(from: Date()))"
    }

    private func resolvedDestination() -> URL {
        if let dest = destination { return dest }
        let parent = appState.sourceURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return parent.appendingPathComponent(autoDestName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Send Keepers To Editing")
                .font(.title2).fontWeight(.semibold)

            Divider()

            switch phase {
            case .setup:    setupView
            case .exporting: progressView
            case .done:     doneView
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                "\(appState.keptCount) photo\(appState.keptCount == 1 ? "" : "s") kept",
                systemImage: "photo.on.rectangle.angled"
            )
            .foregroundStyle(.secondary)

            // Destination
            VStack(alignment: .leading, spacing: 6) {
                Text("Destination").fontWeight(.medium)

                HStack {
                    Group {
                        if let dest = destination {
                            Text(dest.path).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text(autoDestName).foregroundStyle(.secondary).italic()
                        }
                    }
                    .font(.callout)

                    Spacer()

                    Button("Choose…") { chooseDestination() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if destination == nil {
                    Text("Will be created next to the source folder")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Options
            VStack(alignment: .leading, spacing: 10) {
                Text("Options").fontWeight(.medium)

                Toggle("Flatten into one folder", isOn: $flatten)
                if !flatten {
                    Text("Original subfolder structure will be preserved")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Write XMP sidecars", isOn: $writeXMP)
                if writeXMP {
                    Text("Creates .xmp files with rating and pick status for Lightroom / Capture One compatibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rename pattern")
                        Spacer()
                        if !renamePattern.isEmpty {
                            Button("Clear") { renamePattern = "" }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("e.g. {date}_{seq}_{name}", text: $renamePattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                    Text("Tokens: {name} original filename · {seq} sequence number · {date} YYYYMMDD. Leave empty to keep original filenames.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !renamePattern.isEmpty {
                        let preview = previewRename(pattern: renamePattern, index: 1, name: "IMG_1234", ext: "CR3")
                        Text("Preview: \(preview)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.blue)
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Export") { startExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.keptPhotos.isEmpty)
            }
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = exportProgress {
                Text("Copying \(p.completed) of \(p.total)…")
                    .foregroundStyle(.secondary)
                ProgressView(value: p.fraction)
                Text(p.currentFileName)
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                ProgressView("Preparing…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export complete!", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if let url = exportedURL {
                Text("\(appState.keptCount) keepers copied to \"\(url.lastPathComponent)\"")
                    .foregroundStyle(.secondary)
            }

            if writeXMP {
                Label("XMP sidecars written", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if let url = exportedURL {
                    Button("Reveal in Finder") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Destination"
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func startExport() {
        let dest = resolvedDestination()
        exportedURL = dest
        phase = .exporting

        let photos = appState.keptPhotos
        let root = appState.sourceURL ?? URL(fileURLWithPath: NSHomeDirectory())
        let options = CopyService.ExportOptions(
            flatten: flatten,
            writeXMP: writeXMP,
            renamePattern: renamePattern,
            decisions: appState.photoDecisions,
            ratings: appState.photoRatings
        )

        Task {
            for await p in CopyService.export(photos: photos, to: dest, sourceRoot: root, options: options) {
                exportProgress = p
            }
            phase = .done
        }
    }

    // MARK: - Preview helper

    private func previewRename(pattern: String, index: Int, name: String, ext: String) -> String {
        let paddedSeq = String(format: "%04d", index)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        let dateStr = f.string(from: Date())
        let resolved = pattern
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{seq}", with: paddedSeq)
            .replacingOccurrences(of: "{date}", with: dateStr)
        return resolved.hasSuffix(".\(ext)") ? resolved : "\(resolved).\(ext)"
    }
}
