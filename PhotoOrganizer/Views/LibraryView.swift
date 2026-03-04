import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var showExport = false
    @State private var showNewRoundAlert = false
    @State private var showSettings = false
    @State private var columnVisibility = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            ZStack(alignment: .top) {
                detailContent
                if appState.isSimilarityComputing {
                    similarityProgressOverlay
                }
            }
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !appState.photos.isEmpty {
                    filterBar
                }
            }
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
                appState.startNewRound()
            }
        } message: {
            Text("Your \(appState.keptCount) kept photo\(appState.keptCount == 1 ? "" : "s") will become the pool for the next round.")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(AppState.DecisionFilter.allCases) { filter in
                let count = filterCount(for: filter)
                let isSelected = appState.activeFilter == filter

                Button {
                    appState.activeFilter = filter
                    // Snap current index to the first matching photo when filter changes
                    if filter != .all {
                        let indices = appState.filteredPhotoIndices
                        if let idx = indices.first, !indices.contains(appState.currentPhotoIndex) {
                            appState.currentPhotoIndex = idx
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.systemImage)
                            .font(.system(size: 11))
                        Text(filter.label)
                            .font(.caption.weight(.medium))
                        if filter != .all {
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        isSelected
                            ? filterAccentColor(for: filter).opacity(0.25)
                            : Color.clear
                    )
                    .foregroundStyle(
                        isSelected
                            ? filterAccentColor(for: filter)
                            : Color.primary.opacity(0.6)
                    )
                }
                .buttonStyle(.plain)

                if filter != AppState.DecisionFilter.allCases.last {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 2)
                }
            }

            Spacer()

            if appState.activeFilter != .all {
                Text("\(appState.filteredPhotoCount) shown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.trailing, 12)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func filterCount(for filter: AppState.DecisionFilter) -> Int {
        switch filter {
        case .all: return appState.photos.count
        case .kept: return appState.keptCount
        case .rejected: return appState.rejectedPhotos.count
        case .undecided: return appState.undecidedPhotos.count
        }
    }

    private func filterAccentColor(for filter: AppState.DecisionFilter) -> Color {
        switch filter {
        case .all: return .primary
        case .kept: return .green
        case .rejected: return .red
        case .undecided: return .orange
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
                    if appState.hasKeptPhotos {
                        Text("\(appState.keptCount) kept")
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
                            Text("\(round.winnerCount) of \(round.sourcePhotos.count) kept")
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
                    GroupedGridView(activeFilter: .init(
                        get: { appState.activeFilter },
                        set: { appState.activeFilter = $0 }
                    ))
                } else {
                    FlatGridView(activeFilter: .init(
                        get: { appState.activeFilter },
                        set: { appState.activeFilter = $0 }
                    ))
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

            // Comparison mode (filmstrip only)
            Toggle(isOn: .init(
                get: { appState.comparisonEnabled },
                set: { newVal in
                    if newVal { appState.toggleComparison() }
                    else { appState.comparisonEnabled = false; appState.comparisonPhotoID = nil }
                }
            )) {
                Label("Compare", systemImage: "rectangle.split.2x1")
            }
            .toggleStyle(.button)
            .disabled(appState.photos.isEmpty || appState.viewMode == .grid)
            .help("Side-by-side A/B comparison (C)")
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
            .help("Group shots into moments by capture time")
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
            .help("Sub-cluster visually similar photos within each moment (may be slow)")
        }

        // New Round
        ToolbarItem {
            Button { showNewRoundAlert = true } label: {
                Label("New Round", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!appState.hasKeptPhotos)
            .help("Use current keepers as the pool for a new round")
        }

        // Export
        ToolbarItem {
            Button { showExport = true } label: {
                Label("Send to Editing", systemImage: "square.and.arrow.up")
            }
            .disabled(!appState.hasKeptPhotos)
            .help("Copy kept photos to a destination folder")
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

            Section("Workflow") {
                Toggle("Auto-advance after Keep/Reject", isOn: .init(
                    get: { appState.autoAdvanceEnabled },
                    set: { appState.autoAdvanceEnabled = $0 }
                ))

                Text("Automatically move to the next photo after marking a decision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize()
    }

    private var similarityProgressOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Computing Similarity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(appState.similarityProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: appState.similarityProgressFraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 12)
    }
}
