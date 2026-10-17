# Framed

A native SwiftUI macOS app for placing device screenshots inside your own transparent PNG mockups and exporting App Store-sized images. Built with NavigationSplitView, a compact native split settings pane, standard toolbar items, and native file dialogs.

## Use
1. Open `Framed.xcodeproj` in Xcode 27.1 and run the Framed scheme.
2. Add screenshots from your simulator or real device. Multiple images can be imported together.
3. Open the visual Frame Library in the inspector, import front-facing PNG mockups, and choose a thumbnail. The largest enclosed transparent screen opening is detected automatically; camera cutouts remain visible.
4. Choose an Export Canvas size, background, scale, and Fit or Fill. When a frame has a detected or manually calibrated screen, Use Suggested Canvas offers a supported size based on its screen proportions and pixel dimensions. Applying it is optional; selecting a frame keeps your existing canvas. The frame keeps its orientation. Check the preview and any aspect-ratio or enlargement warnings.
5. Export one screenshot or export the entire list into a new folder using the same layout.

PNG and JPEG exports are opaque sRGB at the selected pixel dimensions. The app uses user-selected file access and processes images locally. Use File → Save Project (⌘S), Save Project As (⇧⌘S), and Open Project (⌘O) to continue work later. The `.framed` project embeds screenshots and mockups along with the canvas settings, so it can be moved without its source images. Canvas edits show the native dirty-window indicator. Closing a dirty window or quitting offers Save, Don’t Save, and Cancel; cancelling or failing a save preserves your work. Exporting images does not save the project.

## Mockup requirements
The screen and exterior background should be transparent. Use manual screen bounds if automatic detection needs correction. An opaque screen placeholder must be removed in an image editor first. Perspective/angled device transformations are not supported. Start with a frame that matches the screenshot's device and orientation; Fit preserves the screenshot with letterboxing, while Fill may crop.

The local catalog contains common accepted sizes for iPhone, iPhone Duo, iPad, Mac, Apple TV, Vision Pro, and Apple Watch. It is dated October 16, 2026, and links to [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). It does not enumerate every legacy size or guarantee App Review acceptance. Apple allows up to 10 screenshots per device size; select the required sets for the platforms your app supports.

## Renderer checks
The standalone checks compile the production renderer and verify sample mockup detection, exact pixel dimensions, PNG/JPEG opacity, portrait/landscape, asymmetric screen geometry and image orientation, clipping, and manual calibration.

```sh
swiftc Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Tests/RendererChecks.swift -o /tmp/framed-checks
/tmp/framed-checks /path/to/mockups /path/to/screenshot.png
```

The supplied sample suite expects the mockup directory to include `Outer Closed Portrait` frames. It writes `/tmp/framed-sample.png` and `/tmp/framed-sample.jpg` for visual inspection.

See [the implementation plan](Notes/Implementation-plan.md) for the next steps: optional headlines and multi-size export. Projects already retain frame calibration.

## Window startup regression check

This opens the real SwiftUI view at the reported launch-crash size and performs 12 resize passes. Run on a Mac with a graphical session:

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/ProjectWindowState.swift Framed/FrameSelection.swift Framed/FrameLibraryBrowser.swift Framed/FrameImportProgress.swift Framed/ContentView.swift Tests/WindowLayoutChecks.swift -o /tmp/framed-window-checks
/tmp/framed-window-checks
```

The settings pane uses SwiftUI's native `HSplitView`. The previous `.inspector` container caused a repeating window-constraint update exception at narrow restored window sizes, including with empty inspector content.

## Project checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/ProjectChecks.swift -o /tmp/framed-project-checks
/tmp/framed-project-checks
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/ProjectWindowState.swift Tests/ProjectLifecycleChecks.swift -o /tmp/framed-lifecycle-checks
/tmp/framed-lifecycle-checks
```

The roundtrip checks use temporary projects and remove their source images before reopening. The lifecycle checks require a graphical Mac session and operate only on disposable test windows, verifying native dirty state and close/quit decisions.

## Reusable frame library

Imported frames are copied into `Framed/Frames` in the app's Application Support directory (inside its container when sandboxed). Original PNGs can be moved or removed after import. Each entry contains the original-resolution PNG, a bounded thumbnail, and metadata; matching image content is imported only once.

Click the frame preview in the inspector to open the visual picker. Search, inspect a larger preview, select No Frame, rename entries, or remove library copies using the details pane or contextual menu. Importing within the picker updates the shared library; Use Frame applies the choice to the canvas. Library changes do not dirty projects. Removing a library copy preserves the embedded copies in projects.

For projects created before the library, select Save this frame to library in the inspector or Add Current Project Frame in the picker. Opening a project matches existing library entries but does not resurrect removed ones.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/FrameLibraryChecks.swift -o /tmp/framed-library-checks
/tmp/framed-library-checks
```

These checks use an isolated temporary directory and cover persistence after deleting the source image, bounded previews, deduplication, rename/removal, project portability and dirty-state isolation, calibration, asset repair, and import failure. `Tests/FramePickerPreview.swift` provides a separate visual QA fixture; set `FRAMED_PREVIEW_FRAMES` to a folder of PNG frames. It always copies into a temporary directory rather than the user's library.

## Background frame imports

Frame imports decode images, encode PNGs, hash contents, write files, generate thumbnails, on a background executor. A native modal progress dialog reports the filename and processed count. Cancel stops the remaining work; completed frames stay available, and unfinished staging folders are removed. A non-interruptible image operation may need to finish before cancellation completes. Adding a project-embedded frame to the library and loading a saved frame also perform their image work off the main actor.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/FrameImportChecks.swift -o /tmp/framed-import-checks
/tmp/framed-import-checks /path/to/device-frames
```

The checks measure a main-actor heartbeat during real imports and exercise cancellation/retry, partial failures, staging cleanup, progress, library-only import semantics, and explicit frame application. Set `FRAMED_PREVIEW_IMPORT=1` with `FRAMED_PREVIEW_FRAMES` when running the visual picker fixture to inspect and cancel an import into a temporary library.

## Bulk frame management

Enable Select Multiple to toggle frames by clicking, or use Command-click to toggle and Shift-click to select a range. Select All Shown selects the current search results; Deselect clears the selection. Remove Selected removes the chosen reusable copies. The More (ellipsis) menu offers Remove All Frames, including frames hidden by search. Both actions ask for confirmation, run file removal off the main actor, and preserve project-embedded copies. Use Frame is available when exactly one frame (or No Frame) is selected.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/FrameSelection.swift Tests/FrameBulkChecks.swift -o /tmp/framed-bulk-checks
/tmp/framed-bulk-checks
```

Checks cover toggle/range/filter selection, stale selections, bulk deletion, Remove All, persistence, and preservation of the current project's frame.

Frame import is always a global-library operation, including the main toolbar and inspector plus button. It never adds images to the project, changes its selected frame, or changes its dirty state. Only choosing Use Frame applies a library frame to the canvas. New library entries are saved immediately in Application Support; saving a `.framed` project is not required to keep them.

## Canvas suggestion checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Tests/CanvasSuggestionChecks.swift -o /tmp/framed-canvas-checks
/tmp/framed-canvas-checks
```

Checks approximate screen measurements, portrait and landscape, devices with multiple accepted resolutions, and unsupported proportions. Suggestions compare screen geometry; they do not identify the device model or change the project until applied.
