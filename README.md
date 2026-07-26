# HoldToTranslate

A macOS menu bar translation app built with SwiftUI.

Select text in other apps, hold a configured mouse button, and it will read the selection and show translation in a floating panel near your cursor.

## Features

- Long-press trigger to translate selected text from other apps.
- Selection reading via Accessibility APIs, with clipboard fallback when needed.
- Floating translation panel near cursor for quick copy/edit/submit flow.
- Configurable translation service settings (Endpoint, API Key, Region, target language).
- Built-in safety thresholds for long text (warn and hard limit).
- Local persistence for settings and API key (Keychain).

## Requirements

- macOS 14+
- Swift 6.3 toolchain

## Project Structure

- `Sources/hold-to-translate/hold_to_translate.swift`: main app logic and UI
- `scripts/build_app.sh`: build, app bundle packaging, optional signing, install to `/Applications`
- `assets/app-icon.svg`: source icon for `.icns` generation

## Quick Start

### 1) Build (debug)

```bash
swift build
```

### 2) Build app bundle and install

```bash
./scripts/build_app.sh
```

By default this script:

- Builds release binary
- Packages `dist/HoldToTranslate.app`
- Installs to `/Applications/HoldToTranslate.app`
- Tries to generate Dock icon from `assets/app-icon.svg`

### 3) Launch

```bash
open -n /Applications/HoldToTranslate.app
```

## Configuration

Open the main panel and set:

- Endpoint
- API Key
- Region
- Target language
- Trigger button
- Long-press duration
- Warn threshold / Hard threshold

## Accessibility Permission

The app needs Accessibility permission to read selected text from other apps.

- In app, use the Accessibility section to request permission or open system settings.
- System path: Privacy & Security > Accessibility
- If reading fails after system prompts, refocus the target app and try again.

## Build Script Options

You can control signing/installation with environment variables:

- `SIGN_IDENTITY`: Code-signing certificate SHA-1.
- `INSTALL_TO_APPLICATIONS`: `1` (default) to install into `/Applications`, `0` to skip install.
- `FAIL_ON_UNSIGNED`: `1` to fail when no signing identity is available, `0` (default) to allow unsigned build.

Examples:

```bash
SIGN_IDENTITY=<SHA1> ./scripts/build_app.sh
```

```bash
INSTALL_TO_APPLICATIONS=0 ./scripts/build_app.sh
```

```bash
FAIL_ON_UNSIGNED=1 ./scripts/build_app.sh
```

## Run Tests

```bash
swift test
```

## GitHub CI

This repository includes a GitHub Actions workflow at `.github/workflows/release-build.yml`.

It runs automatically when:

- code is pushed to a `release/*` branch such as `release/v1.8.0`
- a `release/*` branch is created on GitHub
- the workflow is started manually from the Actions tab

The workflow:

- builds `dist/HoldToTranslate.app` with `INSTALL_TO_APPLICATIONS=0`
- uploads both the `.app` bundle and a zipped artifact for download

## Troubleshooting

### Cannot read selected text

- Ensure Accessibility permission is granted.
- Ensure focus is in the target app, not in HoldToTranslate panel.
- Some apps expose limited Accessibility attributes; clipboard fallback is used when possible.

### Permission or trust seems reset after rebuild

- Unsigned builds may trigger trust instability after updates.
- Prefer stable code signing (`SIGN_IDENTITY`) for consistent behavior.

### Translation fails

- Check Endpoint / Region / API Key.
- Verify network connectivity.
- Check status message in app panel for failure details.

## Notes

This project currently keeps core implementation in a single Swift source file for fast iteration.
