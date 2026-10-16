# Framed

A native SwiftUI macOS app for placing device screenshots inside your own transparent PNG mockups and exporting App Store-sized images. Built with NavigationSplitView, a compact native split settings pane, standard toolbar items, and native file dialogs.

## Use
1. Open `Framed.xcodeproj` in Xcode 27.1 and run the Framed scheme.
2. Add screenshots from your simulator or real device. Multiple images can be imported together.
3. Import front-facing PNG mockups and choose a frame in the inspector. The largest enclosed transparent screen opening is detected automatically; camera cutouts remain visible.
4. Choose an output size, background, scale, and Fit or Fill. Check the preview and any aspect-ratio or enlargement warnings.
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
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/EditorModel.swift Framed/ProjectWindowState.swift Framed/ContentView.swift Tests/WindowLayoutChecks.swift -o /tmp/framed-window-checks
/tmp/framed-window-checks
```

The settings pane uses SwiftUI's native `HSplitView`. The previous `.inspector` container caused a repeating window-constraint update exception at narrow restored window sizes, including with empty inspector content.

## Project checks

```sh
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/EditorModel.swift Tests/ProjectChecks.swift -o /tmp/framed-project-checks
/tmp/framed-project-checks
xcrun swiftc -default-isolation MainActor -swift-version 5 Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Framed/FramedProject.swift Framed/EditorModel.swift Framed/ProjectWindowState.swift Tests/ProjectLifecycleChecks.swift -o /tmp/framed-lifecycle-checks
/tmp/framed-lifecycle-checks
```

The roundtrip checks use temporary projects and remove their source images before reopening. The lifecycle checks require a graphical Mac session and operate only on disposable test windows, verifying native dirty state and close/quit decisions.
