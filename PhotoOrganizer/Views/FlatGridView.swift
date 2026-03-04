import SwiftUI

struct FlatGridView: View {
    @Environment(AppState.self) private var appState
    @Binding var activeFilter: AppState.DecisionFilter

    @State private var thumbnailSize: CGFloat = 180
    @State private var focusedID: UUID?
    @FocusState private var isGridFocused: Bool

    private var displayedPhotos: [Photo] {
        switch activeFilter {
        case .all: return appState.photos
        case .kept: return appState.keptPhotos
        case .rejected: return appState.rejectedPhotos
        case .undecided: return appState.undecidedPhotos
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: 4)],
                spacing: 4
            ) {
                ForEach(displayedPhotos) { photo in
                    ThumbnailCell(
                        photo: photo,
                        size: thumbnailSize,
                        decisionState: appState.decisionState(for: photo),
                        isFocused: focusedID == photo.id,
                        showHistogram: appState.histogramEnabled,
                        qualitySignals: appState.qualitySignals(for: photo)
                    )
                    .onTapGesture {
                        focusedID = photo.id
                        isGridFocused = true
                        appState.toggleSelected(photo)
                    }
                    .task(id: photo.id) {
                        await appState.ensureQualitySignals(for: photo)
                    }
                }
            }
            .padding(8)
        }
        .focusable()
        .focused($isGridFocused)
        .onKeyPress(.space)      { toggleFocused(); return .handled }
        .onKeyPress(.return)     { toggleFocused(); return .handled }
        .onKeyPress(.leftArrow)  { navigate(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigate(by:  1); return .handled }
        .background(Color(NSColor.underPageBackgroundColor))
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    // MARK: - Keyboard

    private func toggleFocused() {
        guard let id = focusedID,
              let photo = displayedPhotos.first(where: { $0.id == id }) else { return }
        appState.toggleSelected(photo)
    }

    private func navigate(by delta: Int) {
        let photos = displayedPhotos
        guard !photos.isEmpty else { return }
        let newIndex: Int
        if let id = focusedID, let current = photos.firstIndex(where: { $0.id == id }) {
            newIndex = max(0, min(photos.count - 1, current + delta))
        } else {
            newIndex = delta > 0 ? 0 : photos.count - 1
        }
        focusedID = photos[newIndex].id
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if appState.hasKeptPhotos {
                Text("\(appState.keptCount) of \(appState.photos.count) kept")
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else {
                Text("\(appState.photos.count) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Slider(value: $thumbnailSize, in: 80...360, step: 20)
                    .frame(width: 100)
                    .controlSize(.mini)
                Image(systemName: "photo.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
