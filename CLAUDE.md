# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- **Install dependencies**: `flutter pub get`
- **Run the app**: `flutter run` (requires an emulator or device)
- **Run all tests**: `flutter test`
- **Run a specific test**: `flutter test test/widget_test.dart`
- **Static analysis**: `flutter analyze`
- **Fix lint issues**: `dart fix --apply`
- **Build APK**: `flutter build apk`
- **Build iOS**: `flutter build ios`

## Architecture & Code Structure

This is a Flutter application designed for barcode scanning with text-to-speech feedback and preset configurations.

### State Management
- **Provider**: Uses the `provider` package for state management.
- **ScannerProvider**: Centralizes scanning logic, counts, and configuration state (`lib/providers/scanner_provider.dart`).

### Directory Structure
- `lib/models/`: Data classes (e.g., `ScanConfig` for preset scanning modes).
- `lib/providers/`: State management classes using the Provider pattern.
- `lib/screens/`: UI components organized by screen. Includes setup, admin, and scanning interfaces.
- `lib/services/`: Heavy lifting and utility logic:
    - `PrefsService`: Manages local persistence via `shared_preferences`.
    - `TtsService`: Handles text-to-speech feedback using `flutter_tts`.
    - `ScannerUtils`: Utility functions for processing barcode data.

### Key Workflows
- **Setup**: Users configure scan presets in `SetupScreen`.
- **Scanning**: The `ScannerScreen` or `PresetScanScreen` uses `mobile_scanner` to detect barcodes, which are then processed and counted.
- **Feedback**: Immediate audio feedback is provided via `TtsService` based on scan results.
