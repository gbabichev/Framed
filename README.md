# Framed

A native SwiftUI macOS app for placing device screenshots inside your own transparent PNG mockups and exporting App Store-sized images. Built with NavigationSplitView, a compact native split settings pane, standard toolbar items, and native file dialogs.

## Use
1. Open `Framed.xcodeproj` in Xcode 27.1 and run the Framed scheme.
2. Add screenshots from your simulator or real device. Multiple images can be imported together.
3. Open the visual Frame Library in the inspector, import front-facing PNG mockups, and choose a thumbnail. The largest enclosed transparent screen opening is detected automatically; camera cutouts remain visible.
4. Choose an Export Canvas size, background, scale, and Fit or Fill. When a frame has a detected or manually calibrated screen, Use Suggested Canvas offers a supported size based on its screen proportions and pixel dimensions. Applying it is optional; selecting a frame keeps your existing canvas. The frame keeps its orientation. Check the preview and any aspect-ratio or enlargement warnings.
5. Click Export in the toolbar (⌘E) to open the export sheet. Review the preview, choose PNG or JPEG and the PNG transparency option, then export the selected screenshot or all screenshots. The final Export button opens a native destination picker; batch exports create a new folder using each screenshot’s own layout in sidebar order.

Exports use sRGB at the selected pixel dimensions. In Appearance, enable Transparent background to export a PNG with alpha; the preview shows a checkerboard that is not included in the file. JPEG always uses the selected background color. Transparency is saved with the project. App Store uploads require an opaque background, so turn transparency off for those exports. The app uses user-selected file access and processes images locally. Use File → Save Project (⌘S), Save Project As (⇧⌘S), and Open Project (⌘O) to continue work later. The `.framed` project embeds screenshots and mockups along with the canvas settings, so it can be moved without its source images. Canvas edits show the native dirty-window indicator. Closing a dirty window or quitting offers Save, Don’t Save, and Cancel; cancelling or failing a save preserves your work. Exporting images does not save the project.

## Mockup requirements
The screen and exterior background should be transparent. Automatic screen detection is recommended. If it needs correction, enable Adjust screen edges manually. The preview shows a blue outline (excluded from exports). Left/right edges are measured across the frame image; top/bottom edges are measured down it. Edges keep the opposite edge fixed and cannot cross. Manual mode starts from the detected screen; Reset to Detected Screen returns to automatic detection and its camera-cutout mask. Manual calibration uses a rounded rectangle instead of that mask. Fit may leave black bars when the screen and screenshot proportions differ; Fill crops to cover the screen. An opaque screen placeholder must be removed in an image editor first. Perspective/angled device transformations are not supported. Start with a frame that matches the screenshot's device and orientation; Fit preserves the screenshot with letterboxing, while Fill may crop.

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

Frame import is always a global-library operation, including the inspector plus button. It never adds images to the project, changes its selected frame, or changes its dirty state. Only choosing Use Frame applies a library frame to the canvas. New library entries are saved immediately in Application Support; saving a `.framed` project is not required to keep them.

## Canvas suggestion checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Tests/CanvasSuggestionChecks.swift -o /tmp/framed-canvas-checks
/tmp/framed-canvas-checks
```

Checks approximate screen measurements, portrait and landscape, devices with multiple accepted resolutions, and unsupported proportions. Suggestions compare screen geometry; they do not identify the device model or change the project until applied.

## Transparency checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Tests/TransparencyChecks.swift -o /tmp/framed-transparency-checks
/tmp/framed-transparency-checks
```

## Calibration checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/CalibrationChecks.swift -o /tmp/framed-calibration-checks
/tmp/framed-calibration-checks
```

Checks independent edges, bounds and minimum sizes, saved settings, detected starting geometry, reset to automatic, and dirty state.

## Export edge checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Tests/MaskEdgeChecks.swift -o /tmp/framed-mask-checks
/tmp/framed-mask-checks
```

Detection uses a bounded analysis image, while clipping is refined from source alpha up to 4,096 pixels per side. Clipping extends beneath the opaque bezel so the source PNG supplies antialiased corners and camera cutouts. The pixel checks use a large synthetic frame to catch coarse-mask stair-stepping.

## Optional effects

The inspector’s Effects section offers Corner glow (color, corner, strength and size) and Device fade (top or bottom, depth and strength). Both default to off. The glow is drawn behind the device; the fade blends the screenshot and bezel together into the canvas background. With a transparent PNG, the fade reduces alpha and the glow remains translucent. JPEG composites the same effects onto the chosen background color. Effects are included in project files, dirty tracking, previews, and individual or batch exports. Older projects open with effects off.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Tests/EffectsChecks.swift -o /tmp/framed-effects-checks
/tmp/framed-effects-checks
```

## Headlines

Enable Show headline in the inspector to add up to two centered lines. Each field supplies one line; long lines use an ellipsis instead of adding more lines. Choose any installed font family, weight, size in export pixels, and color. Drag the headline in the preview or use the horizontal/vertical position sliders; Reset Position restores its starting location. The selection outline is a preview guide and is excluded from exports. Reduce device scale if you need more room above the frame. Text is rendered above device effects and remains sharp rather than fading with the device.

Headline size and position scale proportionally when you change the canvas dimensions. All headline settings save with the project and participate in dirty-window tracking. Fonts are referenced by family rather than embedded; unavailable fonts fall back to the system font. Older projects open with headlines disabled. Batch export uses each screenshot’s own headline.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Tests/HeadlineChecks.swift -o /tmp/framed-headline-checks
/tmp/framed-headline-checks
```

## Device placement

Drag the phone or screenshot in the preview to move them together. Appearance → Device position provides horizontal and vertical sliders and Reset Device Position. The screen mask, manual calibration guide, and device fade move with the device; the headline remains independent. Device edges may extend outside the canvas and are cropped on export.

Enabling the headline shifts a centered device down by 4% of the canvas height, without changing its scale. Existing custom positions are preserved. Disabling the headline reverses this default shift if the device has not been repositioned. Reset Device Position restores the center, including the default headroom when a headline is enabled. Position saves with the project and participates in dirty-window tracking; older projects retain centered placement.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Tests/DevicePositionChecks.swift -o /tmp/framed-position-checks
/tmp/framed-position-checks
```

The export sheet stays open after saving, shows completion or batch progress, and provides Done to close it. Canceling the destination picker returns to the settings. Frame import remains available in the Device frame card and Frame Library.

## Center guides and snapping

Appearance offers Show center guides and Snap to center. Guides draw the canvas’s horizontal and vertical center lines only in the editor. Device and headline dragging snap each axis independently when their center is within 8 preview points of the canvas center; dragging farther releases the snap. Disable snapping for fine positioning. These app preferences are remembered across sessions without marking projects dirty. Guides are excluded from the export preview and output files.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Tests/CenterSnappingChecks.swift -o /tmp/framed-snapping-checks
/tmp/framed-snapping-checks
```

## Individual screenshot layouts

Select a screenshot in the sidebar to edit its own frame, canvas, background, device placement, headline, calibration, and effects. Newly imported screenshots start with the selected screenshot’s style. Browsing between screenshots does not mark the project as changed.

Right-click a screenshot for Duplicate, Move Up/Down, Copy Style, Paste Style, and Apply Style to All. Duplicate copies the image and full layout; Paste Style and Apply Style to All preserve each destination’s headline text. The copied style is available within the current open project. The sidebar also supports native list reordering; its order determines numbered batch export filenames. PNG batch exports retain each layout’s transparency choice; JPEG uses each layout’s background color.

Project format version 2 saves all layouts and screenshot order. Version 1 projects open with their original shared layout copied to every screenshot; saving upgrades them to version 2.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/PerScreenshotChecks.swift -o /tmp/framed-layout-checks
/tmp/framed-layout-checks
```

Checks cover independent settings and frames, duplicate isolation, preserved headline text, ordering, clean selection changes, project roundtrips, version 1 migration, and invalid layout rejection.

## Responsive project opening

Open Project and Finder opens read and decode the document, eagerly decode embedded images, validate layouts, detect frame masks, and hash frame PNGs on a background executor. Library matching uses those embedded PNG hashes rather than re-encoding full-resolution frames. A native Opening Project sheet shows the current stage and offers Cancel. Cancellation is checked between image operations; the current canvas stays intact until preparation succeeds. Broken projects leave the current project and its dirty state unchanged.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/ProjectOpenChecks.swift -o /tmp/framed-open-checks
/tmp/framed-open-checks /path/to/project-with-frames.framed
```

The checks measure main-actor responsiveness during opening and verify cancellation, layout preservation, library matching, concurrent-open rejection, source-file preservation, and atomic failure for corrupt JSON and embedded images. They use an isolated temporary frame library.
