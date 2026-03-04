# Photo Organizer

Photo Organizer is a macOS SwiftUI app for fast culling: review large photo sets, move through moments quickly, use objective quality signals, and send keepers into editing.

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

## Package A Shareable DMG

To create a release build and wrap it in a DMG:

```bash
./make-dmg.sh
```

This writes the app bundle into `.build/`, creates a staging folder in `dist/`, and produces:

`dist/PhotoOrganizer.dmg`

You can also include a version suffix in the filename:

```bash
./make-dmg.sh v0.1.0
```

That produces:

`dist/PhotoOrganizer-macOS-v0.1.0.dmg`

Upload the generated DMG as a GitHub Release asset rather than committing it to the repository.

## First Run

1. Launch the app.
2. Choose a folder containing RAW and/or JPEG files.
3. Use the filmstrip culling workspace or grid view to review images.
4. Enable `Group by Time` to review scenes and bursts as moments.
5. Enable `Similarity` to create visual sub-clusters inside each moment.
6. Mark photos as keep or reject, then send keepers to editing when ready.

## Project Layout

- `PhotoOrganizer/`: application source files
- `PhotoOrganizer.xcodeproj/`: Xcode project
- `TestPhotos/`: sample images for local testing
- `build.sh`: convenience script for build + launch
- `make-dmg.sh`: convenience script for release DMG packaging

## Notes

- Session state is restored on launch using Application Support storage.
- RAW files can be paired with matching JPEGs and displayed together in metadata/export flows.
- The visual similarity workflow is optimized for burst-style comparisons rather than semantic scene matching.
