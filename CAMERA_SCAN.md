# Camera scanning update

## What changed

**Flutter**
- `lib/screens/camera_scan_screen.dart` (new): live in-app scanner. Draws an A4 guide, tracks the sheet
  in real time, coaches the user ("Move closer", "Hold the phone parallel to the sheet", "Too dark",
  "Glare", "Focusing...", "Turn the sheet upright"), auto-captures once the sheet is found, sharp and
  steady, and always keeps a manual shutter. Torch, tap-to-focus, portrait lock, camera-permission
  handling, and a "Use system camera" fallback if the camera cannot start.
- `lib/utils/omr_frame_analyzer.dart` (new): pure-Dart detector used by the screen (no Flutter imports).
- `lib/utils/image_optimizer.dart` (new): downsizes big gallery photos (> 2.5 MB) to 2400 px / JPEG 88
  in a background isolate before upload; in-app captures pass through untouched.
- `lib/screens/scan_omr_screen.dart`: "Scan with camera" opens the live scanner and scans automatically
  after capture. A failed scan now shows a plain-language reason and a "Retake with camera" button
  instead of a snackbar.
- `lib/services/omr_service.dart`: 90 s timeout, safe handling of non-JSON responses, uploads the
  optimized image and cleans up the temp file.
- `pubspec.yaml`: adds `camera: ^0.12.0+2` and `image: ^4.8.0`.
- `AndroidManifest.xml`: adds `CAMERA` permission. `Info.plist`: adds `NSCameraUsageDescription`
  (missing before: iOS "Take Photo" would have crashed) and `NSPhotoLibraryUsageDescription`.

**Backend** (`backend/omr/omr_engine/detect.py`, diff in `patches/detect_py.diff`)
- Fallback corner-marker search now scores every set of four by geometry instead of picking the blobs
  furthest into each corner (which dark clutter beat).
- If the timing marks do not lock, it retries alternate marker sets and both 90 degree orientations, so
  sideways photos are read.

## Verification (what was and was not tested)

Tested in a sandbox with Python/OpenCV against the engine and a Python reference of the analyzer:
- Sheets rotated +-90 degrees: 0/24 read before, 24/24 after (answers and roll exact).
- Corner selection with dark clutter: 0/8 correct before, 8/8 after (about 1 px error).
- Upright and 180 degree sheets: unchanged (100% answers, roll exact); bundled synthetic images unchanged.
- Capture width vs accuracy (synthetic phone photos): 100% correct at 640, 800, 1080 and 1440 px wide.
- Frame analyzer reference: detects the sheet in every frame where it fits (about 1.5 px corner error),
  0 false positives in 60 sheet-less clutter frames (max timing lock 0.20 vs 0.55 threshold), and
  recognises the real photos including the two sideways ones.

**Not tested: the Dart code has never been compiled or run** (no Flutter SDK was available). Please run
`flutter pub get`, `flutter analyze`, `flutter test test/omr_frame_analyzer_test.dart`, then try on a
real Android and iOS device. The Dart analyzer is a line-by-line port of the validated Python reference
(`tools/omr_reference/`), and the unit test's expectations were cross-checked against it, but a port can
still contain mistakes.

## Things to tune on real devices (`AnalyzerConfig` in omr_frame_analyzer.dart)
- `minFocus` (0.03): calibrated on synthetic blur only. If auto-capture never fires because it says
  "Focusing...", lower it; the manual shutter always works.
- `_preset` in camera_scan_screen.dart: `veryHigh` (1080p). Use `ResolutionPreset.high` on slow devices.
- `SheetProfile`: fiducial and timing-track positions come from `sample_template.json`. If you print
  sheets from a different template, update these to match (the timing match tolerates ~4 mm).

## Known limitation you still need to fix: template mismatch
The photographed "Test Examination CSE-001" sheets were not printed from `sample_template.json`
(timing marks about 2-3 mm off, bubble grid about half a bubble off). The backend always scans with the
sample template, so those sheets still fail or read unreliably, even though the camera now finds them.
Pass the matching template (the `/api/omr/scan` route already accepts a `template` upload) or reprint
sheets from `sample_template.json`. The engine's strict check was deliberately not loosened.

## Security notes (not changed)
`backend/.env` and `.git` are inside the archive you shared; rotate secrets if it has left your control.
`192.168.0.103` is hard-coded in `omr_service.dart` and `api_service.dart` (use `--dart-define=API_BASE_URL`).
`/api/omr/scan` has no auth middleware.
