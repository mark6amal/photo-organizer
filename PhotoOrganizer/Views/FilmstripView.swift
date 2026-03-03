import SwiftUI

struct FilmstripView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool

    @State private var thumbnailImage: NSImage?
    @State private var previewImage: NSImage?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1
    @State private var loupeCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var loupeLocked = false
    @State private var loupeZoom: Int = 10

    private var photos: [Photo] { appState.photos }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if appState.metadataEnabled, let photo = appState.currentPhoto {
                    MetadataSidePanel(photo: photo)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                photoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if (appState.histogramEnabled || appState.loupeEnabled), let photo = appState.currentPhoto {
                    VStack(spacing: 0) {
                        if appState.loupeEnabled {
                            LoupePanelView(
                                image: previewImage ?? thumbnailImage,
                                center: loupeCenter,
                                zoom: $loupeZoom,
                                locked: loupeLocked
                            )
                        }
                        if appState.histogramEnabled {
                            HistogramSidePanel(photo: photo)
                        }
                    }
                    .frame(width: 200)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.metadataEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.histogramEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.loupeEnabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            carousel
        }
        .background(Color.black)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow)         { appState.navigateGroup(by: -1);       return .handled }
        .onKeyPress(.rightArrow)        { appState.navigateGroup(by:  1);       return .handled }
        .onKeyPress(.upArrow)           { appState.navigateWithinGroup(by: -1); return .handled }
        .onKeyPress(.downArrow)         { appState.navigateWithinGroup(by:  1); return .handled }
        .onKeyPress(KeyEquivalent("k")) { appState.toggleCurrentPhoto(); return .handled }
        .onKeyPress(KeyEquivalent("K")) { appState.toggleCurrentPhoto(); return .handled }
        .onKeyPress(.space)             { appState.toggleCurrentPhoto(); return .handled }
        .onKeyPress(KeyEquivalent("+")) { zoomIn(); return .handled }
        .onKeyPress(KeyEquivalent("=")) { zoomIn(); return .handled }
        .onKeyPress(KeyEquivalent("-")) { zoomOut(); return .handled }
        .onKeyPress(KeyEquivalent("0")) { resetZoom(); return .handled }
    }

    // MARK: - Large photo area

    private var photoArea: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let img = previewImage ?? thumbnailImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale * magnifyBy, anchor: .center)
                        .offset(zoomOffset)
                        .animation(.easeIn(duration: 0.12), value: previewImage != nil)
                        .gesture(
                            MagnificationGesture()
                                .updating($magnifyBy) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    zoomScale = min(20, max(1, zoomScale * value))
                                    if zoomScale <= 1 {
                                        resetZoom()
                                    } else {
                                        zoomOffset = clampedOffset(zoomOffset, in: geometry.size)
                                        dragStartOffset = zoomOffset
                                    }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard zoomScale > 1 else { return }
                                    zoomOffset = CGSize(
                                        width: dragStartOffset.width + value.translation.width,
                                        height: dragStartOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    guard zoomScale > 1 else { return }
                                    zoomOffset = clampedOffset(zoomOffset, in: geometry.size)
                                    dragStartOffset = zoomOffset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.25)) {
                                resetZoom()
                            }
                        }
                        .clipShape(Rectangle())
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard !loupeLocked, let image = previewImage ?? thumbnailImage else { return }
                guard case .active(let point) = phase else { return }
                loupeCenter = imageNormalizedPoint(
                    point,
                    viewSize: geometry.size,
                    imageSize: image.size,
                    scale: zoomScale * magnifyBy,
                    offset: zoomOffset
                )
            }
            .onTapGesture {
                guard appState.loupeEnabled else { return }
                loupeLocked.toggle()
            }
            .overlay(alignment: .bottom) { infoBar }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: appState.currentPhoto?.id) {
                resetZoom()
                loupeLocked = false
                loupeCenter = CGPoint(x: 0.5, y: 0.5)
                previewImage = nil
                thumbnailImage = nil
                guard let photo = appState.currentPhoto else { return }
                let currentID = photo.id
                let currentURL = photo.thumbnailSourceURL

                await ThumbnailService.shared.retainWindow(
                    currentURL: currentURL,
                    nearbyURLs: retentionWindowURLs(around: currentID)
                )

                thumbnailImage = await ThumbnailService.shared.thumbnail(for: currentURL, maxPixelSize: 512)

                if let preview = await ThumbnailService.shared.preview(for: currentURL, maxPixelSize: 2200),
                   appState.currentPhoto?.id == currentID {
                    previewImage = preview
                }

                if let full = await ThumbnailService.shared.fullResolution(for: currentURL),
                   appState.currentPhoto?.id == currentID {
                    previewImage = full
                }
            }
        }
    }

    // MARK: - Info overlay

    private var infoBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if let photo = appState.currentPhoto {
                Text(photo.displayName)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.7), radius: 4)
            }

            Spacer()

            if let photo = appState.currentPhoto, appState.isSelected(photo) {
                Label("Kept", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .shadow(color: .black.opacity(0.7), radius: 4)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("K — keep")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text((zoomScale * magnifyBy) > 1.01 ? "\(Int((zoomScale * magnifyBy) * 100))%" : appState.filmstripInfoText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Carousel items model

    private enum CarouselItem: Identifiable {
        case photo(Int, Photo)    // (flatIndex, photo)
        case divider(Int, String) // (groupIndex, label)
        case clusterDivider(String, Int, Int) // (groupID, clusterIndex, total)

        var id: String {
            switch self {
            case .photo(_, let p):  return "photo-\(p.id)"
            case .divider(let gi, _): return "divider-\(gi)"
            case .clusterDivider(let groupID, let clusterIndex, _):
                return "cluster-\(groupID)-\(clusterIndex)"
            }
        }
    }

    private var carouselItems: [CarouselItem] {
        guard appState.groupingEnabled, !appState.groups.isEmpty else {
            return photos.enumerated().map { .photo($0.offset, $0.element) }
        }
        var items: [CarouselItem] = []
        for (gi, group) in appState.groups.enumerated() {
            items.append(.divider(gi, group.label))
            if appState.similarityEnabled,
               let clusters = group.clusters,
               clusters.count > 1 {
                for (clusterIndex, cluster) in clusters.enumerated() {
                    items.append(.clusterDivider(group.id.uuidString, clusterIndex, clusters.count))
                    for photo in cluster {
                        if let flatIdx = photos.firstIndex(where: { $0.id == photo.id }) {
                            items.append(.photo(flatIdx, photo))
                        }
                    }
                }
            } else {
                for photo in group.photos {
                    if let flatIdx = photos.firstIndex(where: { $0.id == photo.id }) {
                        items.append(.photo(flatIdx, photo))
                    }
                }
            }
        }
        return items
    }

    @ViewBuilder
    private func carouselItemView(_ item: CarouselItem) -> some View {
        switch item {
        case .photo(let idx, let photo):
            CarouselCell(
                photo: photo,
                isActive: photo.id == appState.currentPhoto?.id,
                isSelected: appState.isSelected(photo),
                sharpnessScore: appState.sharpnessScores[photo.id]
            )
            .id(photo.id)
            .onTapGesture {
                appState.currentPhotoIndex = idx
            }
        case .divider(let gi, let label):
            CarouselGroupDivider(label: label, isActive: appState.currentGroupIndex == gi)
        case .clusterDivider(_, let clusterIndex, let total):
            CarouselClusterDivider(index: clusterIndex, total: total)
        }
    }

    // MARK: - Carousel

    private var carousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(carouselItems) { item in
                        carouselItemView(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .onChange(of: appState.currentPhotoIndex) { _, _ in
                guard let photo = appState.currentPhoto else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(photo.id, anchor: .center)
                }
            }
            .onAppear {
                if let photo = appState.currentPhoto {
                    proxy.scrollTo(photo.id, anchor: .center)
                }
            }
        }
        .frame(height: 100)
        .background(Color(white: 0.08))
    }

    private func zoomIn() {
        zoomScale = min(20, zoomScale * 1.5)
    }

    private func zoomOut() {
        zoomScale = max(1, zoomScale / 1.5)
        if zoomScale <= 1 {
            resetZoom()
        }
    }

    private func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
        dragStartOffset = .zero
    }

    private func imageNormalizedPoint(
        _ point: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let fitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawnWidth = imageSize.width * fitScale * scale
        let drawnHeight = imageSize.height * fitScale * scale
        let offsetX = (viewSize.width - drawnWidth) / 2 + offset.width
        let offsetY = (viewSize.height - drawnHeight) / 2 + offset.height

        return CGPoint(
            x: clamp((point.x - offsetX) / drawnWidth, to: 0...1),
            y: clamp((point.y - offsetY) / drawnHeight, to: 0...1)
        )
    }

    private func clampedOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        guard size != .zero else { return offset }
        guard zoomScale > 1 else { return .zero }

        let maxX = size.width * (zoomScale - 1) / 2
        let maxY = size.height * (zoomScale - 1) / 2
        return CGSize(
            width: clamp(offset.width, to: (-maxX)...maxX),
            height: clamp(offset.height, to: (-maxY)...maxY)
        )
    }

    private func retentionWindowURLs(around photoID: UUID, radius: Int = 24) -> [URL] {
        guard let currentIndex = photos.firstIndex(where: { $0.id == photoID }) else { return [] }
        let start = max(0, currentIndex - radius)
        let end = min(photos.count - 1, currentIndex + radius)
        guard start <= end else { return [] }
        return photos[start...end].map(\.thumbnailSourceURL)
    }
}

private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
    min(max(value, range.lowerBound), range.upperBound)
}

// MARK: - Carousel group divider

private struct CarouselGroupDivider: View {
    let label: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.white.opacity(0.2))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(isActive ? Color.accentColor : Color.white.opacity(0.4))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16)
    }
}

private struct CarouselClusterDivider: View {
    let index: Int
    let total: Int

    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            Text("V\(index + 1)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))

            if total > 1 {
                Text("/\(total)")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 12)
        .padding(.vertical, 4)
    }
}
