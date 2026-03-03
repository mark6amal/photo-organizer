# Photo Organizer

Photo Organizer is a macOS SwiftUI app for reviewing large photo sets, grouping burst shots by capture time, clustering visually similar frames, and marking keepers for later export.

## Requirements

- macOS 14 or newer
- Xcode 15 or newer
- Apple command line developer tools installed via Xcode

This project uses an Xcode app target, not a Swift Package. A full Xcode install is required for building and running the app. The standalone Command Line Tools package is not enough for `xcodebuild`.

## Install Xcode

1. Open the App Store and install Xcode, or download it from Apple Developer.
2. Launch Xcode once and accept the license/install any required components.
3. Make sure the active developer directory points at the full Xcode app:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

4. Verify the setup:

```bash
xcodebuild -version
```

If this prints an error saying the active developer directory is `/Library/Developer/CommandLineTools`, step 3 has not been applied yet.

## Open In Xcode

1. Open [PhotoOrganizer.xcodeproj](/Users/marcusamalachandran/Claude/Projects/photo-organizer/PhotoOrganizer.xcodeproj).
2. Select the `PhotoOrganizer` scheme.
3. Choose `My Mac` as the run destination.
4. Press `Run`.

## Build From Terminal

The repo includes a helper script:

```bash
./build.sh
```

This runs `xcodebuild`, writes derived data into `.build/`, and launches the built app if the build succeeds.

You can also run the build command directly:

```bash
xcodebuild \
  -project PhotoOrganizer.xcodeproj \
  -scheme PhotoOrganizer \
  -configuration Debug \
  -derivedDataPath .build \
  build
```

## First Run

1. Launch the app.
2. Choose a folder containing RAW and/or JPEG files.
3. Use filmstrip or grid view to review images.
4. Enable `Group by Time` to split burst sequences.
5. Enable `Similarity` to create visual sub-clusters inside each time group.
6. Mark keepers and export them when ready.

## Project Layout

- `PhotoOrganizer/`: application source files
- `PhotoOrganizer.xcodeproj/`: Xcode project
- `TestPhotos/`: sample images for local testing
- `build.sh`: convenience script for build + launch

## Notes

- Session state is restored on launch using Application Support storage.
- RAW files can be paired with matching JPEGs and displayed together in metadata/export flows.
- The visual similarity workflow is optimized for burst-style comparisons rather than semantic scene matching.
