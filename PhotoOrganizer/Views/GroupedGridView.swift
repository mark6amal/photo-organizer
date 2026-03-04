import SwiftUI

struct GroupedGridView: View {
    @Environment(AppState.self) private var appState
    @Binding var showWinnersOnly: Bool

    @State private var thumbnailSize: CGFloat = 160

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(appState.groups) { group in
                    Section {
                        if !group.isCollapsed {
                            groupContent(group)
                        }
                    } header: {
                        GroupHeaderRow(group: group)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    // MARK: - Group content

    @ViewBuilder
    private func groupContent(_ group: PhotoGroup) -> some View {
        let cols = [GridItem(.adaptive(minimum: thumbnailSize), spacing: 8)]
        if appState.similarityEnabled,
           let clusters = group.clusters,
           clusters.count > 1 {
            ForEach(Array(clusters.enumerated()), id: \.offset) { idx, cluster in
                clusterDivider(index: idx, total: clusters.count)
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(filter(cluster)) { photo in cell(photo) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        } else {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(filter(group.photos)) { photo in cell(photo) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func clusterDivider(index: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
            Text("Similar group \(index + 1) of \(total)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, index == 0 ? 4 : 8)
    }

    private func cell(_ photo: Photo) -> some View {
        ThumbnailCell(
            photo: photo,
            size: thumbnailSize,
            isSelected: appState.isSelected(photo),
            isFocused: false,
            showHistogram: appState.histogramEnabled
        )
        .onTapGesture { appState.toggleSelected(photo) }
    }

    private func filter(_ photos: [Photo]) -> [Photo] {
        showWinnersOnly ? photos.filter { appState.isSelected($0) } : photos
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            if appState.isGrouping {
                ProgressView().scaleEffect(0.7)
                Text("Grouping…").font(.caption).foregroundStyle(.secondary)
            } else if appState.isSimilarityComputing {
                Text("Computing similarity…").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: appState.similarityProgressFraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text(appState.similarityProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                let g = appState.groups.count, p = appState.photos.count
                Text("\(g) group\(g == 1 ? "" : "s") · \(p) photo\(p == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                if appState.hasSelection {
                    Text("· \(appState.selectionCount) selected")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
            Slider(value: $thumbnailSize, in: 80...360, step: 20)
                .frame(width: 120)
                .help("Thumbnail size")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

// MARK: - Group header

private struct GroupHeaderRow: View {
    @Environment(AppState.self) private var appState
    let group: PhotoGroup

    var body: some View {
        Button { appState.toggleGroupCollapsed(group) } label: {
            HStack(spacing: 8) {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                    .foregroundStyle(.secondary)

                Text(group.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                let p = group.photos.count
                Text("· \(p) photo\(p == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)

                let kept = appState.selectedInGroup(group)
                if kept > 0 {
                    Text("· \(kept) kept").font(.caption).foregroundStyle(.green)
                }

                if let clusters = group.clusters, appState.similarityEnabled {
                    Text("· \(clusters.count) visual group\(clusters.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.blue.opacity(0.7))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial)
    }
}
