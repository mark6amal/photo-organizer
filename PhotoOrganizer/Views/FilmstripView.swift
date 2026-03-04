import SwiftUI
import AppKit

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

    // Comparison
    @State private var comparisonThumbnailImage: NSImage?
    @State private var comparisonPreviewImage: NSImage?

    private var photos: [Photo] { appState.photos }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if appState.metadataEnabled, let photo = appState.currentPhoto {
                    MetadataSidePanel(photo: photo)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if appState.comparisonEnabled, let comparePhoto = appState.comparisonPhoto {
                    compareLayout(comparePhoto: comparePhoto)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    photoArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let photo = appState.currentPhoto {
                    decisionRail(photo: photo)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.metadataEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.histogramEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.loupeEnabled)
            .animation(.easeInOut(duration: 0.2), value: appState.comparisonEnabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            carousel
        }
        .background(Color.black)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) { appState.navigateMoment(by: -1); return .handled }
        .onKeyPress(.rightArrow) { appState.navigateMoment(by: 1); return .handled }
        .onKeyPress(.upArrow) { appState.navigateWithinMoment(by: -1); return .handled }
        .onKeyPress(.downArrow) { appState.navigateWithinMoment(by: 1); return .handled }
        .onKeyPress(KeyEquivalent("k")) { appState.markCurrentPhotoKept(); return .handled }
        .onKeyPress(KeyEquivalent("K")) { appState.markCurrentPhotoKept(); return .handled }
        .onKeyPress(.space) { appState.markCurrentPhotoKept(); return .handled }
        .onKeyPress(KeyEquivalent("r")) { appState.markCurrentPhotoRejected(); return .handled }
        .onKeyPress(KeyEquivalent("R")) { appState.markCurrentPhotoRejected(); return .handled }
        .onKeyPress(KeyEquivalent("u")) { appState.clearCurrentPhotoDecision(); return .handled }
        .onKeyPress(KeyEquivalent("U")) { appState.clearCurrentPhotoDecision(); return .handled }
        .onKeyPress(KeyEquivalent("+")) { zoomIn(); return .handled }
        .onKeyPress(KeyEquivalent("=")) { zoomIn(); return .handled }
        .onKeyPress(KeyEquivalent("-")) { zoomOut(); return .handled }
        .onKeyPress(KeyEquivalent("0")) { resetZoom(); return .handled }
        // Star ratings
        .onKeyPress(KeyEquivalent("1")) { appState.setCurrentPhotoRating(1); return .handled }
        .onKeyPress(KeyEquivalent("2")) { appState.setCurrentPhotoRating(2); return .handled }
        .onKeyPress(KeyEquivalent("3")) { appState.setCurrentPhotoRating(3); return .handled }
        .onKeyPress(KeyEquivalent("4")) { appState.setCurrentPhotoRating(4); return .handled }
        .onKeyPress(KeyEquivalent("5")) { appState.setCurrentPhotoRating(5); return .handled }
        // Comparison mode: c to toggle, [ ] to cycle comparison photo
        .onKeyPress(KeyEquivalent("c")) { appState.toggleComparison(); return .handled }
        .onKeyPress(KeyEquivalent("C")) { appState.toggleComparison(); return .handled }
        .onKeyPress(KeyEquivalent("[")) {
            if appState.comparisonEnabled { appState.cycleComparisonPhoto(by: -1) }
            return .handled
        }
        .onKeyPress(KeyEquivalent("]")) {
            if appState.comparisonEnabled { appState.cycleComparisonPhoto(by: 1) }
            return .handled
        }
        // Fullscreen
        .onKeyPress(KeyEquivalent("f")) { toggleFullscreen(); return .handled }
        .onKeyPress(KeyEquivalent("F")) { toggleFullscreen(); return .handled }
    }

    // MARK: - Compare Layout

    private func compareLayout(comparePhoto: Photo) -> some View {
        HStack(spacing: 2) {
            // Left: current photo
            photoArea
                .overlay(alignment: .top) {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.top, 8)
                }

            // Right: comparison photo
            comparisonPhotoArea(photo: comparePhoto)
                .overlay(alignment: .top) {
                    Text(comparePhoto.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.top, 8)
                }
        }
        .overlay(alignment: .top) {
            compareHint
        }
    }

    private var compareHint: some View {
        Text("[ ] cycle comparison · C exit")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(.top, 36)
    }

    private func comparisonPhotoArea(photo: Photo) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let img = comparisonPreviewImage ?? comparisonThumbnailImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale * magnifyBy, anchor: .center)
                        .offset(zoomOffset)
                } else {
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
            .overlay(alignment: .bottom) {
                HStack {
                    decisionBadgeFor(photo: photo)
                    Spacer()
                    if let signals = appState.qualitySignals(for: photo) {
                        sharpnessBadge(label: signals.sharpnessLabel)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .task(id: photo.id) {
                comparisonPreviewImage = nil
                comparisonThumbnailImage = nil
                let url = photo.thumbnailSourceURL
                let currentID = photo.id
                comparisonThumbnailImage = await ThumbnailService.shared.thumbnail(for: url, maxPixelSize: 512)
                if let preview = await ThumbnailService.shared.preview(for: url, maxPixelSize: 2200),
                   appState.comparisonPhotoID == currentID {
                    comparisonPreviewImage = preview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Tap to promote comparison to current
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
                    appState.currentPhotoIndex = idx
                }
            }
            .clipShape(Rectangle())
        }
    }

    private func decisionBadgeFor(photo: Photo) -> some View {
        let state = appState.decisionState(for: photo)
        return Group {
            switch state {
            case .kept:
                Label("Kept", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .shadow(color: .black.opacity(0.7), radius: 4)
            case .rejected:
                Label("Rejected", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.7), radius: 4)
            case .undecided:
                EmptyView()
            }
        }
    }

    private func sharpnessBadge(label: String) -> some View {
        let color: Color = label == "Sharp" ? .green : (label == "Soft" ? .red : .yellow)
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.7), radius: 4)
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
            .overlay(alignment: .topLeading) { cullingToolbar }
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

                await appState.ensureQualitySignals(for: photo)

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

    private var cullingToolbar: some View {
        HStack(spacing: 10) {
            Button {
                appState.markCurrentPhotoKept()
            } label: {
                Label("Keep", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                appState.markCurrentPhotoRejected()
            } label: {
                Label("Reject", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button("Undecided") {
                appState.clearCurrentPhotoDecision()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(14)
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

            // Star rating display
            if let photo = appState.currentPhoto {
                starRatingView(for: photo)
            }

            Spacer()

            // Best pick indicator
            if let photo = appState.currentPhoto, appState.isBestPick(photo) {
                Label("Best Pick", systemImage: "crown.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.7), radius: 4)
            }

            decisionBadge

            Text(
                (zoomScale * magnifyBy) > 1.01
                    ? "\(Int((zoomScale * magnifyBy) * 100))%"
                    : appState.filmstripInfoText
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func starRatingView(for photo: Photo) -> some View {
        let rating = appState.rating(for: photo)
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(star <= rating ? Color.yellow : Color.white.opacity(0.25))
            }
        }
        .onTapGesture { /* handled via keyboard */ }
    }

    @ViewBuilder
    private var decisionBadge: some View {
        if let photo = appState.currentPhoto {
            switch appState.decisionState(for: photo) {
            case .kept:
                Label("Kept", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .shadow(color: .black.opacity(0.7), radius: 4)
            case .rejected:
                Label("Rejected", systemImage: "xmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.7), radius: 4)
            case .undecided:
                Text("K keep · R reject · U undecided")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
        } else {
            Text("K keep · R reject")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Decision rail

    @ViewBuilder
    private func decisionRail(photo: Photo) -> some View {
        VStack(spacing: 0) {
            decisionSummary(photo: photo)

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
        .frame(width: 220)
        .background(Color(white: 0.06))
    }

    private func decisionSummary(photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Culling")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))

            Text(appState.filmstripInfoText)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            Text(decisionSummaryText(for: photo))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(decisionColor(for: photo))

            // Star rating control
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    let currentRating = appState.rating(for: photo)
                    Image(systemName: star <= currentRating ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(star <= currentRating ? Color.yellow : Color.white.opacity(0.25))
                        .onTapGesture {
                            let newRating = star == currentRating ? 0 : star
                            appState.setRating(newRating, for: photo)
                        }
                }
                Text("1–5")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
            }

            if appState.isBestPick(photo) {
                Label("Best Pick", systemImage: "crown.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow.opacity(0.12))
                    )
            }

            if let signals = appState.qualitySignals(for: photo) {
                ForEach(signals.badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                }
            } else {
                Text("Analyzing photo truth…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Comparison hint
            Text(appState.comparisonEnabled ? "C · exit compare" : "C · compare  [ ] cycle")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.25))

            // Fullscreen hint
            Text("F · fullscreen  1-5 · rate")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(14)
    }

    private func decisionSummaryText(for photo: Photo) -> String {
        switch appState.decisionState(for: photo) {
        case .kept:
            return "Ready for editing"
        case .rejected:
            return "Explicitly rejected"
        case .undecided:
            return "Needs a keep/reject call"
        }
    }

    private func decisionColor(for photo: Photo) -> Color {
        switch appState.decisionState(for: photo) {
        case .kept:
            return .green
        case .rejected:
            return .red
        case .undecided:
            return .white.opacity(0.75)
        }
    }

    // MARK: - Carousel items model

    private enum CarouselItem: Identifiable {
        case photo(Int, Photo)
        case divider(Int, String)
        case clusterDivider(String, Int, Int)

        var id: String {
            switch self {
            case .photo(_, let p):
                return "photo-\(p.id)"
            case .divider(let gi, _):
                return "divider-\(gi)"
            case .clusterDivider(let groupID, let clusterIndex, _):
                return "cluster-\(groupID)-\(clusterIndex)"
            }
        }
    }

    private var carouselItems: [CarouselItem] {
        let filteredIndices = Set(appState.filteredPhotoIndices)
        let allPhotos = photos

        guard appState.groupingEnabled, !appState.groups.isEmpty else {
            return allPhotos.enumerated().compactMap { idx, photo -> CarouselItem? in
                guard filteredIndices.contains(idx) else { return nil }
                return .photo(idx, photo)
            }
        }

        var items: [CarouselItem] = []
        for (gi, group) in appState.groups.enumerated() {
            let groupPhotos: [Photo]
            if appState.similarityEnabled,
               let clusters = group.clusters,
               clusters.count > 1 {
                // With clusters: build items with cluster dividers, filter per photo
                var hasVisible = false
                var groupItems: [CarouselItem] = []
                groupItems.append(.divider(gi, group.momentTitle))
                for (clusterIndex, cluster) in clusters.enumerated() {
                    var clusterItems: [CarouselItem] = []
                    for photo in cluster {
                        if let flatIdx = allPhotos.firstIndex(where: { $0.id == photo.id }),
                           filteredIndices.contains(flatIdx) {
                            clusterItems.append(.photo(flatIdx, photo))
                            hasVisible = true
                        }
                    }
                    if !clusterItems.isEmpty {
                        groupItems.append(.clusterDivider(group.id.uuidString, clusterIndex, clusters.count))
                        groupItems.append(contentsOf: clusterItems)
                    }
                }
                if hasVisible { items.append(contentsOf: groupItems) }
            } else {
                groupPhotos = group.photos
                let visibleInGroup = groupPhotos.compactMap { photo -> CarouselItem? in
                    guard let flatIdx = allPhotos.firstIndex(where: { $0.id == photo.id }),
                          filteredIndices.contains(flatIdx)
                    else { return nil }
                    return .photo(flatIdx, photo)
                }
                if !visibleInGroup.isEmpty {
                    items.append(.divider(gi, group.momentTitle))
                    items.append(contentsOf: visibleInGroup)
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
                isComparison: photo.id == appState.comparisonPhotoID,
                decisionState: appState.decisionState(for: photo),
                starRating: appState.rating(for: photo),
                qualitySignals: appState.qualitySignals(for: photo)
            )
            .id(photo.id)
            .onTapGesture {
                if appState.comparisonEnabled {
                    appState.comparisonPhotoID = photo.id
                } else {
                    appState.currentPhotoIndex = idx
                }
            }
            .task(id: photo.id) {
                await appState.ensureQualitySignals(for: photo)
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

    // MARK: - Zoom

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

    private func toggleFullscreen() {
        NSApp.mainWindow?.toggleFullScreen(nil)
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
