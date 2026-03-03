import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var showWinnersOnly = false
    @State private var showExport = false
    @State private var showNewRoundAlert = false
    @State private var showSettings = false
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            detailContent
                .toolbar { toolbarItems }
        }
        .onChange(of: appState.photos.count) { _, newCount in
            guard appState.groupingEnabled, newCount > 0 else { return }
            Task { await appState.computeGroups() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            SessionStore.save(appState)
        }
        .sheet(isPresented: $showExport) {
            ExportView().environment(appState)
        }
        .alert("Start New Round?", isPresented: $showNewRoundAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Start Round \(appState.rounds.count + 2)") {
                showWinnersOnly = false
                appState.startNewRound()
            }
        } message: {
            Text("Your \(appState.selectionCount) selected photo\(appState.selectionCount == 1 ? "" : "s") will become the pool for the next round.")
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List {
            Section("Current") {
                Label(appState.sourceURL?.lastPathComponent ?? "Untitled", systemImage: "folder")
                    .lineLimit(1)
                HStack {
                    Text("\(appState.photos.count) photos")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if appState.hasSelection {
                        Text("\(appState.selectionCount) selected")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
            }

            if !appState.rounds.isEmpty {
                Section("Round History") {
                    ForEach(appState.rounds.reversed()) { round in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Round \(round.number)").fontWeight(.medium)
                            Text("\(round.winnerCount) of \(round.sourcePhotos.count) selected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if appState.isScanning {
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5)
                Text("Scanning folder…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.photos.isEmpty {
            ContentUnavailableView(
                "No Photos Found",
                systemImage: "photo.slash",
                description: Text("No RAW or JPEG files were found in the selected folder.")
            )
        } else {
            switch appState.viewMode {
            case .filmstrip:
                FilmstripView()
            case .grid:
                if appState.groupingEnabled {
                    GroupedGridView(showWinnersOnly: $showWinnersOnly)
                } else {
                    FlatGridView(showWinnersOnly: $showWinnersOnly)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // Change folder
        ToolbarItem(placement: .navigation) {
            Button { appState.reset() } label: {
                Label("Change Folder", systemImage: "folder")
            }
            .help("Open a different folder")
        }

        // View mode: filmstrip / grid
        ToolbarItem(placement: .principal) {
            Picker("View", selection: .init(
                get: { appState.viewMode },
                set: { appState.viewMode = $0 }
            )) {
                Image(systemName: "film").tag(AppState.ViewMode.filmstrip)
                Image(systemName: "square.grid.3x3").tag(AppState.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Switch between filmstrip and grid view")
            .disabled(appState.photos.isEmpty)
        }

        // Winners-only (grid only)
        ToolbarItem {
            Toggle(isOn: $showWinnersOnly) {
                Label("Winners Only", systemImage: showWinnersOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .disabled(!appState.hasSelection || appState.viewMode == .filmstrip)
            .help("Show selected photos only")
        }

        ToolbarItemGroup {
            // Metadata panel (filmstrip only)
            Toggle(isOn: .init(
                get: { appState.metadataEnabled },
                set: { appState.metadataEnabled = $0 }
            )) {
                Label("Info", systemImage: "info.circle")
            }
            .toggleStyle(.button)
            .disabled(appState.photos.isEmpty || appState.viewMode == .grid)
            .help("Show photo metadata panel")

            Toggle(isOn: .init(
                get: { appState.loupeEnabled },
                set: { appState.loupeEnabled = $0 }
            )) {
                Label("Loupe", systemImage: "magnifyingglass.circle")
            }
            .toggleStyle(.button)
            .disabled(appState.photos.isEmpty || appState.viewMode == .grid)
            .help("Focus magnifier - hover to inspect sharpness")

            // Histogram
            Toggle(isOn: .init(
                get: { appState.histogramEnabled },
                set: { appState.histogramEnabled = $0 }
            )) {
                Label("Histogram", systemImage: "waveform.path.ecg")
            }
            .toggleStyle(.button)
            .disabled(appState.photos.isEmpty)
            .help("Show tonal histogram overlay")
        }

        // Group by Time
        ToolbarItem {
            Toggle(isOn: .init(
                get: { appState.groupingEnabled },
                set: { newValue in
                    appState.groupingEnabled = newValue
                    if !newValue { appState.similarityEnabled = false }
                    Task { await appState.computeGroups() }
                }
            )) {
                Label("Group by Time", systemImage: "clock.arrow.2.circlepath")
            }
            .toggleStyle(.button)
            .disabled(appState.photos.isEmpty)
            .help("Group burst shots by capture time")
        }

        // Visual Similarity (requires grouping)
        ToolbarItem {
            Toggle(isOn: .init(
                get: { appState.similarityEnabled },
                set: { newValue in
                    appState.similarityEnabled = newValue
                    Task { await appState.computeSimilarity() }
                }
            )) {
                Label("Similarity", systemImage: "square.3.layers.3d")
            }
            .toggleStyle(.button)
            .disabled(!appState.groupingEnabled || appState.groups.isEmpty)
            .help("Sub-cluster visually similar photos within each time group (may be slow)")
        }

        // New Round
        ToolbarItem {
            Button { showNewRoundAlert = true } label: {
                Label("New Round", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!appState.hasSelection)
            .help("Use current winners as the pool for a new round")
        }

        // Export
        ToolbarItem {
            Button { showExport = true } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!appState.hasSelection)
            .help("Copy selected photos to a destination folder")
        }

        // Settings
        ToolbarItem {
            Button { showSettings.toggle() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Adjust thresholds and preferences")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                settingsPopover
            }
        }
    }

    // MARK: - Settings Popover

    private var settingsPopover: some View {
        Form {
            Section("Time Grouping") {
                LabeledContent("Gap threshold") {
                    HStack {
                        Slider(value: .init(
                            get: { appState.groupGapThreshold },
                            set: { appState.groupGapThreshold = $0 }
                        ), in: 1...120, step: 1)
                        .frame(width: 140)
                        Text("\(Int(appState.groupGapThreshold))s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            Section("Visual Similarity") {
                LabeledContent("Mode") {
                    Picker("Similarity Mode", selection: .init(
                        get: { appState.similarityMode },
                        set: { newValue in
                            appState.similarityMode = newValue
                            guard appState.similarityEnabled else { return }
                            Task { await appState.computeSimilarity() }
                        }
                    )) {
                        ForEach(AppState.SimilarityMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                LabeledContent("RMS delta") {
                    HStack {
                        Slider(value: .init(
                            get: { Double(appState.similarityThreshold) },
                            set: { appState.similarityThreshold = Float($0) }
                        ), in: 0.01...0.20, step: 0.01)
                        .frame(width: 140)
                        Text(String(format: "%.2f", appState.similarityThreshold))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Text("Lower = stricter matching. Re-run similarity after changing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(appState.similarityMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize()
    }
}
