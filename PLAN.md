# Photo Organizer App — Plan

## Context
A macOS native app for photographers who shoot large volumes (1000s) of RAW+JPEG photos. The core workflow is simple: **pick winners, copy them out**. Everything else (grouping, smart clustering, histogram analysis) is an optional enhancement the user can toggle on.

---

## Core Workflow (always available)
1. **Pick a source folder** → folder picker UI on launch
2. **Preview photos** → filmstrip view: one large photo + scrollable carousel at the bottom
3. **Mark winners** → `K` to keep, `←/→` to navigate; also available in grid view
4. **Export winners** → copy to a destination folder
5. **Repeat** → start a new round from previous winners

---

## Primary UI: Filmstrip View
The default viewing mode. Designed for careful one-at-a-time culling.

```
┌─────────────────────────────────────────────────────┐
│  [toolbar: Change Folder | Grid | ★ Winners | Export]│
├─────────────────────────────────────────────────────┤
│                                                     │
│                                                     │
│              [ large photo preview ]                │
│                                                     │
│                                                     │
├─────────────────────────────────────────────────────┤
│  [thumb][thumb][THUMB*][thumb][thumb][thumb][thumb] │  ← carousel
└─────────────────────────────────────────────────────┘
   * active photo highlighted, carousel scrolls with it
```

**Keyboard shortcuts:**
- `←` / `→` — previous / next photo (carousel follows)
- `K` — toggle winner (green checkmark overlay on thumbnail)
- `Space` — also toggles winner
- Click a carousel thumbnail → jump to that photo

**Winner state:**
- Carousel thumbnails show green checkmark + tint when marked
- Status bar: `X of Y selected`

---

## Secondary UI: Grid View
Overview / batch mode. Toggle via toolbar icon (like Finder's view switcher).
Good for: spotting obvious duds across many photos, reviewing all picks at once.

- Adaptive thumbnail grid, size adjustable with slider
- Click or Space to toggle winner
- `←/→` arrow keys navigate with focus ring
- "Winners Only" filter in toolbar
- Same green checkmark overlay as filmstrip

---

## Optional Features (user-toggleable via toolbar/settings)
- **Time-based grouping** — collapses burst shots into groups by capture time proximity (gap threshold configurable); works in both views
- **Visual similarity sub-grouping** — within time groups, clusters visually similar shots using Apple Vision (toggleable)
- **Histogram overlay** — RGB + luminosity histogram per photo; mini-bar in carousel/grid, full chart in filmstrip detail area

---

## Tech Stack
- **Language**: Swift
- **UI**: SwiftUI (macOS 14+ Sonoma target)
- **Image decoding**: `ImageIO` — handles RAW (CR2, CR3, NEF, ARW, DNG), JPEG, HEIC; extracts embedded JPEG previews for fast thumbnails
- **EXIF / metadata**: `ImageIO` (`CGImageSourceCopyPropertiesAtIndex`) — reads `DateTimeOriginal` for time grouping
- **Visual similarity**: Apple `Vision` — `VNGenerateImageFeaturePrintRequest` feature vectors + cosine distance
- **Histogram**: `Accelerate` framework — `vImageHistogramCalculation` on decoded pixel buffer; renders RGB + luminosity curves
- **File ops**: `Foundation.FileManager` for scanning and copying

---

## Architecture

```
PhotoOrganizer.app
├── Models/
│   ├── Photo.swift            — single photo (path, format, optional JPEG pair, thumbnail cache)
│   ├── PhotoGroup.swift       — optional time/visual cluster (used only when grouping is enabled)
│   ├── SelectionRound.swift   — one round: source pool → selected winners         ✅ done
│   └── AppState.swift         — top-level observable state (source folder, rounds, view mode, features)  ✅ done
│
├── Services/
│   ├── FolderScanner.swift    — recursive scan; detects RAW+JPEG pairs by matching base filename  ✅ done
│   ├── ThumbnailService.swift — async thumbnail generation via ImageIO embedded JPEG previews     ✅ done
│   ├── GroupingService.swift  — optional: clusters by EXIF capture time (default gap: 5s)
│   ├── VisionService.swift    — optional: VNFeaturePrint per image; cosine distance sub-clustering
│   ├── HistogramService.swift — optional: vImageHistogramCalculation on decoded image buffer
│   ├── EXIFService.swift      — reads DateTimeOriginal, camera model, ISO, shutter, aperture
│   └── CopyService.swift      — copies winners to destination; async stream progress reporting    ✅ done
│
└── Views/
    ├── WelcomeView.swift       — app launch: "Open Folder" button + drag-and-drop zone            ✅ done
    ├── LibraryView.swift       — main container: toolbar, sidebar (round history), view switcher  ✅ done
    ├── FilmstripView.swift     — PRIMARY: large photo + bottom carousel; K/←/→ shortcuts         ← next
    ├── CarouselCell.swift      — one thumbnail in the filmstrip carousel; winner overlay
    ├── FlatGridView.swift      — SECONDARY: all photos in adaptive scrollable grid                ✅ done
    ├── GroupedGridView.swift   — optional: photos nested under collapsible time/visual groups
    ├── ThumbnailCell.swift     — grid cell: thumbnail, winner checkmark overlay                   ✅ done
    ├── ExportView.swift        — destination picker, progress bar, flatten option                 ✅ done
    └── HistogramView.swift     — full RGB + luminosity chart (shown in filmstrip detail area)
```

---

## Key Implementation Notes

### Folder Picker (Entry Point)
- `WelcomeView` shown on launch if no source folder loaded
- Uses `NSOpenPanel` (folder selection); drag-and-drop also supported
- After loading: immediately switches to `LibraryView` → `FilmstripView` and begins async thumbnail generation

### RAW + JPEG Pair Detection
- Bucket files by base filename (strip extension, case-insensitive)
- If base has both a RAW ext (cr2, cr3, nef, arw, dng) AND a JPEG ext (jpg, jpeg) → treat as a pair
- **Preview/thumbnail**: use JPEG (fast decode); fall back to embedded RAW preview via `kCGImageSourceThumbnailMaxPixelSize`
- **Copy on export**: always copy RAW; copy JPEG sidecar alongside it

### Filmstrip View
- Large photo occupies ~80% of the window height; rendered full-quality via ImageIO (not just the embedded thumbnail)
- Carousel at the bottom: horizontally scrollable, fixed height ~90px, shows all photos
- Active photo in carousel is highlighted and kept centred as you navigate
- Navigation and selection is mirrored: marking a photo in filmstrip marks it in grid and vice versa

### Winner Selection
- `K` or `Space` → toggle winner on current photo
- `←` / `→` → navigate (filmstrip scrolls carousel to follow)
- Winner state lives in `AppState.selectedIDs` — shared between both views
- Green checkmark + tint overlay on both carousel and grid thumbnails

### Multi-Round Workflow
```
Round 1: Source folder (1000 photos) → cull to 200 winners
Round 2: 200 winners become new pool → cull to 50
Export: Copy 50 RAW files (+ JPEG sidecars) to /destination/
```
- Round history in sidebar (collapsible)
- "New Round from Winners" — confirms, saves round, resets pool

### View Switching
- Toolbar toggle: filmstrip icon ↔ grid icon (like Finder's view buttons)
- `AppState.viewMode: ViewMode` (.filmstrip / .grid) persists within a session
- Filmstrip is the default on first launch

### Optional: Grouping
- Toggle in toolbar: "Group by Time"
- `GroupingService` clusters photos within N seconds of each other (default 5s, configurable)
- In filmstrip: groups shown as section breaks in the carousel with a label ("Burst — 12 photos")
- In grid: collapsible group headers

### Optional: Histogram
- Toggle in toolbar: "Histogram"
- In filmstrip: compact histogram chart below the large photo
- In grid: small luminosity mini-bar beneath each thumbnail
- Overexposure / underexposure warning markers at extremes

### Export
- `NSOpenPanel` for destination OR auto-create `Winners_[YYYYMMDD_HHMMSS]/` next to source folder
- `CopyService`: copies files, reports progress via `AsyncStream`
- Option: preserve original subfolder structure vs. flatten all into one folder

---

## Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Blank app skeleton, Xcode project | ✅ Complete |
| 1 | WelcomeView, FolderScanner, ThumbnailService, FlatGridView | ✅ Complete |
| 2 | Winner selection, multi-round, CopyService, ExportView | ✅ Complete |
| 3 | **FilmstripView** — large preview + carousel, K/←/→ shortcuts | ← next |
| 4 | Optional: Time-based grouping (GroupingService, GroupedGridView) | Pending |
| 5 | Optional: Histogram (HistogramService, chart in filmstrip + mini-bar in grid) | Pending |
| 6 | Optional: Visual similarity (VisionService sub-clustering) | Pending |
| 7 | Polish: recent folders, persisted sessions, configurable thresholds, app icon | Pending |

---

## Verification
- Load 500+ mixed RAW+JPEG files → filmstrip opens immediately, carousel thumbnails load as you scroll
- RAW+JPEG pairs show as one entry in carousel and grid (not two)
- Press K → green checkmark appears on carousel thumbnail; navigate away and back → still marked
- Press → rapidly through 50 photos → no lag, carousel stays in sync
- Switch to grid view → same winners are marked there
- Export → RAW files + JPEG sidecars land in destination folder
- Start new round → only previous winners are in the pool; round appears in sidebar history
