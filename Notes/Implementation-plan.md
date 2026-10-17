# Framed — first version

Original planning notes, kept for reference. For the current user guide, see [README](../README.md); for implementation details and checks, see [Development](Development.md).

A local macOS utility: import screenshot images and front-facing transparent PNG device frames, compose on an App Store-sized canvas, and export opaque sRGB PNG or JPEG.

## First version
- Screenshot library with multi-file import, selection, removal, and batch export.
- User-supplied mockup library; automatically locate the largest enclosed transparent screen opening and use it as an exact clipping mask, preserving bezels and camera cutouts.
- Manual normalized screen bounds and corner radius for frames without a detectable opening. Perspective mockups are outside the first version.
- Live preview, solid background, device scale, fit/fill, portrait/landscape, accepted output dimensions, and crop/upscale warnings.
- PNG/JPEG export at exact pixels without an alpha channel. Native save dialogs and sandbox file access.
- A dated, local preset catalog linked to Apple's official requirements. Presets specify accepted output dimensions, not a guarantee of App Review acceptance.

## Next
Saved projects and reusable mockup calibration; optional headline/subtitle; gradients; ordering and per-screenshot layouts; multi-size export; localization sets. Keep App Store upload and complex perspective transforms out of the initial scope.

## Verification
Build with Xcode. Exercise detection against supplied mockups and render the sample screenshot through the production renderer. Check exported dimensions, RGB/no-alpha encoding, orientation, clipping, PNG/JPEG, and manual fallback.

Source: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications (checked 2026-10-16).
