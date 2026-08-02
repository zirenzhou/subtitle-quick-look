# Subtitle Quick Look

[![Build](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml/badge.svg)](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[中文说明](README.zh-CN.md)

A lightweight macOS Quick Look extension for WebVTT (`.vtt`), LRC (`.lrc`), and SubRip (`.srt`) files, with optional translation powered by Apple's native Translation framework.

Select a supported file in Finder and press <kbd>Space</kbd> to see its original text. Click the small translation button in the corner when you want a translated, text-only preview.

## Features

- Finder Quick Look previews for `.vtt`, `.lrc`, and `.srt`
- Native Apple Translation with automatic source-language detection
- Target language defaults to the macOS preferred language
- Files already written in the device's primary language never auto-translate; a manual request uses a separately remembered secondary target language
- Matching source and target languages close translation cleanly with a brief “No translation needed” notice
- Compact, responsive translation controls that stay usable in narrow Quick Look windows
- Contextual language menus keep up to six system and recently used languages visible; regional duplicates are merged, every language is shown by its autonym, and the rest are folded under **More**
- Remembers whether translation is enabled and the selected languages
- Sends only subtitle text for translation; timestamps and subtitle structure stay intact
- Native Save As panel with a target-language filename suggestion
- UTF-8, UTF-16/32, GB18030, and Latin-1 decoding
- Apple Silicon and Intel support
- No separate window, Dock icon, background process, or custom network service
- Preview size limited to 8 MiB to keep Quick Look responsive

## Requirements

- macOS 15 Sequoia or later
- Xcode 16 or later for the Homebrew source build

## Install with Homebrew

This repository doubles as a third-party Homebrew tap:

```bash
brew tap zirenzhou/subtitle-quick-look https://github.com/zirenzhou/subtitle-quick-look.git
brew trust --formula zirenzhou/subtitle-quick-look/subtitle-quick-look
brew install zirenzhou/subtitle-quick-look/subtitle-quick-look
```

`brew trust --formula` is required by Homebrew 6 for third-party taps. It trusts only this formula, not every formula that may later appear in the tap. Skip that line if your Homebrew version does not provide `brew trust`.

After installation, select a `.vtt`, `.lrc`, or `.srt` file in Finder and press <kbd>Space</kbd>.

To upgrade an existing installation to the latest release:

```bash
brew update
brew upgrade subtitle-quick-look
subtitle-quick-look register
```

## Manage the extension

The formula registers the Quick Look extension automatically.

```bash
subtitle-quick-look status       # Check registration
subtitle-quick-look register     # Register again and refresh Quick Look
subtitle-quick-look unregister   # Unregister before uninstalling
```

To uninstall:

```bash
subtitle-quick-look unregister
brew uninstall subtitle-quick-look
brew untap zirenzhou/subtitle-quick-look
```

If Finder still shows a stale preview, run:

```bash
subtitle-quick-look register
killall Finder
```

Also check **System Settings → General → Login Items & Extensions → Quick Look** and make sure **Subtitle Quick Look Preview** is enabled.

## Why is there an `.app` bundle?

Modern macOS requires Quick Look preview extensions to live inside an app bundle. The bundled host is only a technical container:

- it has no user interface;
- it has no Dock icon;
- it never stays running;
- it exits immediately if launched; and
- it does not become the default application for VTT, LRC, or SRT files.

You manage the extension entirely through Homebrew and never need to open the host.

## Privacy and limits

Preview parsing and Apple Translation run locally. The extension does not add its own network service. It requests write access only to the destination you explicitly choose in the macOS Save As panel. Files larger than 8 MiB are truncated in the preview and cannot be saved from Quick Look.

## Build from source

```bash
./scripts/build-release.sh
```

Outputs:

- `build/ManualRelease/Subtitle Quick Look.app`
- `dist/Subtitle-Quick-Look.zip`

The build creates universal arm64/x86_64 binaries and applies a local ad-hoc signature. The Homebrew formula builds the extension locally, so installation does not depend on downloading and opening an unnotarized app bundle.

## License

[MIT](LICENSE)
