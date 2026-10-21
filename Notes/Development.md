# Framed — development notes

Build, architecture, and regression-check notes. For the user guide, see [README](../README.md). Run shell commands below from the repository root.

A native SwiftUI macOS app for placing device screenshots inside your own transparent PNG mockups and exporting App Store-sized images. Built with NavigationSplitView, a compact native split settings pane, standard toolbar items, and native file dialogs.

## Use
1. Open `Framed.xcodeproj` in Xcode 27.1 and run the Framed scheme.
2. Add screenshots from your simulator or real device. Multiple images can be imported together.
3. Open the visual Frame Library in the inspector, import front-facing PNG mockups, and choose a thumbnail. The largest enclosed transparent screen opening is detected automatically; camera cutouts remain visible.
4. Choose an Export Canvas size, background, scale, and Fit or Fill. When a frame has a detected or manually calibrated screen, Use Suggested Canvas offers a supported size based on its screen proportions and pixel dimensions. Selecting a frame automatically matches the canvas to its device family; the user can override it afterward. The frame keeps its orientation. Check the preview and any aspect-ratio or enlargement warnings.
5. Click Export in the toolbar (⌘E) to open the export sheet. Review the preview, choose PNG or JPEG and the PNG transparency option, then export the selected screenshot or all screenshots. The final Export button opens a native destination picker; batch exports save directly in the user-selected folder using each screenshot’s own layout in sidebar order, with numeric suffixes to preserve existing files.

Exports use sRGB at the selected pixel dimensions. In Appearance, enable Transparent background to export a PNG with alpha; the preview shows a checkerboard that is not included in the file. JPEG always uses the selected background color. Transparency is saved with the project. App Store uploads require an opaque background, so turn transparency off for those exports. The app uses user-selected file access and processes images locally. Use File → Save Project (⌘S), Save Project As (⇧⌘S), and Open Project (⌘O) to continue work later. The `.framed` document package stores a small JSON manifest and original screenshot/frame files, so it can be moved without its source images. Canvas edits show the native dirty-window indicator. Closing a dirty window or quitting offers Save, Don’t Save, and Cancel; cancelling or failing a save preserves your work. Exporting images does not save the project.

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

See [the implementation plan](Implementation-plan.md) for the original project scope. Headlines, effects, saved projects, and individual layouts have since been implemented.

## Window startup regression check

This opens the real SwiftUI view at the reported launch-crash size and performs 12 resize passes. Run on a Mac with a graphical session:

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/ProjectWindowState.swift Framed/FrameSelection.swift Framed/FrameLibraryBrowser.swift Framed/FrameImportProgress.swift Framed/AboutView.swift Framed/SidebarFocusRecovery.swift Framed/ContentView.swift Tests/WindowLayoutChecks.swift -o /tmp/framed-window-checks
/tmp/framed-window-checks
```

The settings pane uses SwiftUI's native `HSplitView`. The previous `.inspector` container caused a repeating window-constraint update exception at narrow restored window sizes, including with empty inspector content.

## Project checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/ProjectChecks.swift -o /tmp/framed-project-checks
/tmp/framed-project-checks
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/ProjectWindowState.swift Tests/ProjectLifecycleChecks.swift -o /tmp/framed-lifecycle-checks
/tmp/framed-lifecycle-checks
```

The roundtrip checks use temporary projects and remove their source images before reopening. The lifecycle checks require a graphical Mac session and operate only on disposable test windows, verifying native dirty state and close/quit decisions.

## Reusable frame library

Imported frames are copied into `Framed/Frames` in the app's Application Support directory (inside its container when sandboxed). Original PNGs can be moved or removed after import. Each entry contains the original-resolution PNG, a bounded thumbnail, and metadata; matching image content is imported only once.

Click the frame preview in the inspector to open the visual picker. Search, inspect a larger preview, select No Frame, rename entries, or remove library copies using the Selection menu or contextual menu. Importing within the picker updates the shared library; Use Frame applies the choice to the canvas. Library changes do not dirty projects. Removing a library copy preserves the embedded copies in projects.

For projects created before the library, select Save this frame to library in the inspector or Save Current Frame to Library in the picker. Opening a project matches existing library entries but does not resurrect removed ones.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/FrameLibraryChecks.swift -o /tmp/framed-library-checks
/tmp/framed-library-checks
```

These checks use an isolated temporary directory and cover persistence after deleting the source image, bounded previews, deduplication, rename/removal, project portability and dirty-state isolation, calibration, asset repair, and import failure. `Tests/FramePickerPreview.swift` provides a separate visual QA fixture; set `FRAMED_PREVIEW_FRAMES` to a folder of PNG frames. It always copies into a temporary directory rather than the user's library.

## Background frame imports

Frame imports decode images, encode PNGs, hash contents, write files, generate thumbnails, on a background executor. A native modal progress dialog reports the filename and processed count. Cancel stops the remaining work; completed frames stay available, and unfinished staging folders are removed. A non-interruptible image operation may need to finish before cancellation completes. Adding a project-embedded frame to the library and loading a saved frame also perform their image work off the main actor.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/FrameImportChecks.swift -o /tmp/framed-import-checks
/tmp/framed-import-checks /path/to/device-frames
```

The checks measure a main-actor heartbeat during real imports and exercise cancellation/retry, partial failures, staging cleanup, progress, library-only import semantics, and explicit frame application. Set `FRAMED_PREVIEW_IMPORT=1` with `FRAMED_PREVIEW_FRAMES` when running the visual picker fixture to inspect and cancel an import into a temporary library.

## Bulk frame management

Use Command-click to toggle frames and Shift-click to select a range. The Selection menu contains Select All Shown, Deselect All, Remove Selected Frames, and Remove All Frames (including frames hidden by search). Removal asks for confirmation, runs off the main actor, and preserves project-embedded copies. Use Frame is available when exactly one frame (or No Frame) is selected.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/FrameSelection.swift Tests/FrameBulkChecks.swift -o /tmp/framed-bulk-checks
/tmp/framed-bulk-checks
```

Checks cover toggle/range/filter selection, stale selections, bulk deletion, Remove All, persistence, and preservation of the current project's frame.

Frame import is always a global-library operation, including the inspector plus button. It never adds images to the project, changes its selected frame, or changes its dirty state. Only choosing Use Frame applies a library frame to the canvas. New library entries are saved immediately in Application Support; saving a `.framed` project is not required to keep them.

## Canvas suggestion checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Tests/CanvasSuggestionChecks.swift -o /tmp/framed-canvas-checks
/tmp/framed-canvas-checks
```

Checks approximate screen measurements, portrait and landscape, devices with multiple accepted resolutions, and unsupported proportions. Suggestions constrain known device families before comparing screen geometry. Choosing a frame applies the matched canvas in the same undo step. A first screenshot import inherits that canvas when a frame is already selected.

## Transparency checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Tests/TransparencyChecks.swift -o /tmp/framed-transparency-checks
/tmp/framed-transparency-checks
```

## Calibration checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/CalibrationChecks.swift -o /tmp/framed-calibration-checks
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
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Tests/EffectsChecks.swift -o /tmp/framed-effects-checks
/tmp/framed-effects-checks
```

## Headlines

Enable Show headline in the inspector to add up to two centered lines. Each field supplies one line; long lines use an ellipsis instead of adding more lines. Choose any installed font family, weight, size in export pixels, and color. Drag the headline in the preview or use the horizontal/vertical position sliders; Reset Position restores its starting location. The selection outline is a preview guide and is excluded from exports. Reduce device scale if you need more room above the frame. Text is rendered above device effects and remains sharp rather than fading with the device.

Headline size and position scale proportionally when you change the canvas dimensions. All headline settings save with the project and participate in dirty-window tracking. Fonts are referenced by family rather than embedded; unavailable fonts fall back to the system font. Older projects open with headlines disabled. Batch export uses each screenshot’s own headline.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Tests/HeadlineChecks.swift -o /tmp/framed-headline-checks
/tmp/framed-headline-checks
```

## Device placement

Drag the phone or screenshot in the preview to move them together. Appearance → Device position provides horizontal and vertical sliders and Reset Device Position. The screen mask, manual calibration guide, and device fade move with the device; the headline remains independent. Device edges may extend outside the canvas and are cropped on export.

Enabling the headline shifts a centered device down by 4% of the canvas height, without changing its scale. Existing custom positions are preserved. Disabling the headline reverses this default shift if the device has not been repositioned. Reset Device Position restores the center, including the default headroom when a headline is enabled. Position saves with the project and participates in dirty-window tracking; older projects retain centered placement.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Tests/DevicePositionChecks.swift -o /tmp/framed-position-checks
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

Select a screenshot in the sidebar to edit its own frame, canvas, background, device placement, headline, calibration, and effects. Newly imported screenshots start with the active device section’s default layout. Browsing between screenshots does not mark the project as changed.

Right-click a screenshot for Duplicate, Move Up/Down, Move to Device, Use as Device Default Layout, Copy Style, and Paste Style. Apply Default Layout to Screenshots is available on each device section’s context menu. Duplicate copies the image and full layout; Paste Style and Apply Style to All preserve each destination’s headline text. The copied style is available within the current open project. The sidebar also supports native list reordering; its order determines numbered batch export filenames. PNG batch exports retain each layout’s transparency choice; JPEG uses each layout’s background color.

Project format version 3 adds device sections, default layouts, screenshot membership, and selected default-layout state. Version 1 and 2 projects infer sections from their saved canvas family while retaining every screenshot layout. Version 1 shared layouts are copied to every screenshot. Saving a grouped project upgrades it to version 3; older app versions reject that newer format.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/PerScreenshotChecks.swift -o /tmp/framed-layout-checks
/tmp/framed-layout-checks
```

Checks cover independent settings and frames, duplicate isolation, preserved headline text, ordering, clean selection changes, project roundtrips, version 1 migration, and invalid layout rejection.

## Responsive project opening

Open Project and Finder opens read and decode the document, eagerly decode embedded images, validate layouts, detect frame masks, and hash frame assets on a background executor. Library matching uses those retained asset hashes rather than re-encoding full-resolution frames. A native Opening Project sheet shows the current stage and offers Cancel. Cancellation is checked between image operations; the current canvas stays intact until preparation succeeds. Broken projects leave the current project and its dirty state unchanged.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/ProjectOpenChecks.swift -o /tmp/framed-open-checks
/tmp/framed-open-checks /path/to/project-with-frames.framed
```

The checks measure main-actor responsiveness during opening and verify cancellation, layout preservation, library matching, concurrent-open rejection, source-file preservation, and atomic failure for corrupt JSON and embedded images. They use an isolated temporary frame library.

## Undo and redo

Use Edit → Undo (⌘Z) and Redo (⇧⌘Z) for the last 20 project edits. Device/headline drags and slider adjustments each count as one step; rapid headline typing and color adjustments are coalesced. Screenshot imports, duplication, removal, reordering, frame selection, calibration, and style application are included. Image data is shared in memory rather than re-encoded for history. Global frame-library operations and guide preferences are excluded.

Saving preserves history. Undoing back to the saved composition clears the dirty indicator; undoing past it marks the project as changed. Opening a project starts a fresh history. History belongs to each window and is not stored in the project file.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/UndoChecks.swift -o /tmp/framed-undo-checks
/tmp/framed-undo-checks
```

## Fast frame selection

Selecting a single library frame starts background preparation after a short browsing debounce. Use Frame shares that job if it is still running, and reuses the result once ready. Frames already embedded in the current project switch without loading the library PNG or detecting the screen again. Prefetch does not change the canvas, dirty state, or undo history.

The library keeps a small memory cache of decoded originals and clipping masks, shared by project windows. Its count limit is three frames with a 128 MiB cost target; the system may evict cached data under memory pressure. Closing the picker or changing selection cancels abandoned preparation, while an active Use Frame request keeps its shared job alive. Library reload/removal invalidates cached results. A cold frame can still take time to prepare; the picker shows progress when Use Frame has to wait.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Tests/FramePreparationChecks.swift -o /tmp/framed-preparation-checks
/tmp/framed-preparation-checks /path/to/device-frame.png
```

Checks cover shared preparation and masks, cached reuse across windows, prompt cancellation, retries after failure, renaming, removal, undo, dirty-state isolation, and reusing an embedded frame when its library PNG is unavailable. All file mutations happen in a disposable library copy.

## Device-family filters

Frame Library offers native All, Watch, iPhone, iPad, and Mac filters alongside search. Search applies within the chosen family, and Select All Shown uses the matching results. Hidden frames are removed from the selection when filters change. Importing or adding a project frame clears the filters to reveal the imported selection.

Families are detected from Apple bezel filenames, including `Apple Watch …`, `AW Ultra …`, `iPhone …`, `iPad …`, `MacBook …`, `iMac …`, and `Mac …`. The imported family is kept when a frame is renamed. Existing library entries infer their family from their current names. Other names, including Apple TV, stay available under All. Filtering does not edit projects or enter undo history.

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/DeviceSections.swift Framed/FramedProject.swift Framed/ProjectPackage.swift Framed/FrameLibrary.swift Framed/EditorModel.swift Framed/FrameSelection.swift Tests/FrameFilterChecks.swift -o /tmp/framed-filter-checks
/tmp/framed-filter-checks /path/to/apple-bezel-pngs
```


## Recent editor and export behavior

- Desktop backdrop settings draw a two-color gradient behind transparent window captures, with window sizing, positioning, and an optional shadow. They live in each screenshot’s layout and project settings.
- Screen placement and clipping use the same refined detection region. Image content overlaps beneath the bezel to prevent thin uncovered seams.
- Export options provide JPEG quality, optional canvas overrides, and 25/50/75/100% scaling. PNG remains lossless. Export-only sizing does not modify the composition settings.
- Export rendering, encoding, and file writing use a background executor. Save and folder panels attach to the export settings sheet. Existing batch output files are not overwritten.
- Canvas zoom and hand-tool panning belong to the view, not the project or undo history. Fit uses a fixed centered view; other zoom levels use native scrolling. 100% maps image pixels to physical display pixels.
- Frame Library uses a native NSSearchField with recents and automatic completion disabled. Device segments share a row with search; Selection contains selection and removal actions. Apple’s resource link and import guidance live below the details preview.

Additional standalone checks: `Tests/DesktopChecks.swift`, `Tests/ExportChecks.swift`, `Tests/CanvasSelectionChecks.swift`, and `Tests/CanvasZoomChecks.swift`. Compile with the production dependencies used by the related checks above.

For the public website’s files and screenshot replacements, see [Website maintenance](Website.md).

## Device sections

The sidebar remains a single native SwiftUI List in NavigationSplitView, with collapsible native sections and no nested scroll views or custom toolbar backgrounds. Add Device creates a new iPhone, iPad, Mac, Apple Watch, or Apple TV section each time, including repeated device classes. Rename and Duplicate Device Layout are available on the header context menu; duplicated layouts start without screenshots. Optional section names preserve compatibility with older projects. Exports use distinct sanitized section names, adding numeric suffixes when folder names collide. The Default Layout row and section header select the template; edits affect future imports only. Applying the template to existing screenshots is explicit and keeps their headline text. Moving a screenshot between sections preserves its individual layout.

Device sections, membership, and defaults participate in the project fingerprint and 20-step undo history. Selection and disclosure expansion do not dirty the project. Removing a device confirms removal of its screenshots and can be undone. File drops on headers and insertion locations target that device; drops on the sidebar background target the active device. Screenshot imports into an explicit section preserve its canvas choice.

Export offers Selected Screenshot, Current Device, and Entire Project. Project exports create named device folders; device exports use the chosen folder directly. Both keep existing files and choose available filenames. Batch preview shows the first screenshot in the chosen scope.

`Tests/DeviceSectionChecks.swift` covers default inheritance, isolation, explicit apply with preserved text, section movement/reordering, export lists, clean browsing, version 3 roundtrips, migration, reference validation, and grouped removal undo. Compile it with the same source list as the undo checks above.

## Sidebar multi-selection

The native List uses a Set selection binding for Shift-click ranges and Command-click toggling. Default Layout remains a single template selection; screenshot selections are temporary and do not enter the project fingerprint. The preview edits the lead screenshot. Dragging any selected screenshot includes the selected screenshots in visible sidebar order; dragging an unselected row starts a single-row selection. Drop handlers accept grouped JSON UUID payloads and native multi-provider UUID drags. Batch moves preserve layouts and register one undo action, including selection restoration. The Move to Device context menu also acts on the selected screenshots. `Tests/MultiSelectionChecks.swift` verifies these model and item-provider behaviors.

## Sidebar keyboard focus

`SidebarFocusRecovery` is a non-intercepting background NSView on the native List. A window-local mouse-down monitor queues responder recovery after normal selection and button handling, only for clicks inside the visible sidebar while its window is key and has no attached sheet. It finds the native table/outline under that point and makes it first responder. It does not update selection, observe model changes to steal focus, or replace the List’s scroll view. Monitor teardown occurs when detached or dismantled.

`Tests/SidebarFocusChecks.swift` uses an isolated hidden AppKit window to verify responder recovery from a text field, multi-selection preservation, inspector isolation, hidden-list rejection, and transparent hit testing:

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/SidebarFocusRecovery.swift Tests/SidebarFocusChecks.swift -o /tmp/framed-sidebar-focus-checks
/tmp/framed-sidebar-focus-checks
```

## Document package storage

New saves use a Finder document package with `project.json`, `Screenshots/`, and `Frames/`. The manifest has package format/version fields and project metadata (layout schema version 2 or 3). Image records store relative asset references and original filenames; they do not embed Base64 bytes. `ProjectImage.png` remains the in-memory/legacy JSON field name, but can contain original JPEG, PNG, HEIC, or TIFF data. Imported images retain immutable source bytes alongside their decoded CGImage; frame-library imports, prepared frames, screenshot duplication, and reopened projects retain those bytes and filenames. ImageIO applies source orientation consistently on both import and reopen.

Asset filenames include a content digest, a readable source stem, and the detected format extension. Duplicate content shares one asset per category. Reading validates paths, regular files, checksums, image dimensions, and project references. Legacy flat JSON versions 1–3 still open; their already-converted PNGs cannot recover the original JPEG bytes without reimporting the originals.

Package saves capture a lightweight snapshot and perform serialization and disk work through the background ProjectFileWorker. NSFileCoordinator wraps package access. Saving builds a complete staging package in Foundation’s item-replacement directory and atomically replaces the destination; this also supports replacing a legacy JSON file at the same `.framed` path. Unchanged assets are hard-linked from the previous package when possible, with a byte-write fallback, so they do not need re-encoding or rewriting. Failed staging leaves the previous project intact. Save completion establishes the clean fingerprint only after the write succeeds; close/quit waits for that completion. Open and save panels treat packages as documents, and Info.plist declares `com.apple.package` conformance and LSTypeIsPackage. Packages use the distinct `com.georgebabichev.framed.project-package` UTI; legacy JSON retains `com.georgebabichev.framed.project`. Both use `.framed`, with macOS distinguishing them by directory/data conformance. This avoids stale JSON declarations from older app builds overriding package recognition. Open panels accept both types; save panels use only the package type.

`Tests/ProjectPackageChecks.swift` covers original JPEG/PNG bytes and filenames, EXIF orientation, frame-library copies and renames, compact manifests, shared assets, unchanged-file reuse, replacement/Save As after deleting originals, legacy file-to-package conversion, failed replacement preservation, and malformed asset paths/checksums. Compile with the project-check source list above. ProjectOpenChecks accepts either legacy files or packages and verifies neither is modified by opening.

`Tests/ProjectTypeRegistrationChecks.swift` verifies macOS content-type resolution and Finder package recognition using temporary directory and JSON fixtures with the same `.framed` extension. Build Framed, register that app with Launch Services (`lsregister -f <Framed.app>`), then compile and run this standalone AppKit check.

Project opening reports ordered per-image progress for package asset reads, screenshot decoding, frame decoding, and screen detection. Counts apply to the named stage rather than an estimated overall percentage; the current asset name remains visible during long operations. A synchronous-worker/AsyncStream bridge publishes updates without moving image work onto the main actor. Cancellation retains the current project and stops between images. ProjectOpenChecks verifies stage counts, named assets, update order, responsiveness, and cancellation.
