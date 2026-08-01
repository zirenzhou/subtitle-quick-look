# Subtitle Quick Look

[![Build](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml/badge.svg)](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[中文说明](README.zh-CN.md)

A tiny macOS Quick Look extension that adds plain-text previews for WebVTT (`.vtt`) subtitle files and LRC (`.lrc`) lyrics files.

Select a supported file in Finder and press <kbd>Space</kbd> to see its original text. The extension does not render subtitles or lyrics; it deliberately presents the source as readable plain text.

## Features

- Finder Quick Look previews for `.vtt` and `.lrc`
- UTF-8, UTF-16/32, GB18030, and Latin-1 decoding
- Apple Silicon and Intel support
- No window, Dock icon, background process, or network access
- Preview size limited to 8 MiB to keep Quick Look responsive

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later for the Homebrew source build

## Install with Homebrew

This repository doubles as a third-party Homebrew tap:

```bash
brew tap zirenzhou/subtitle-quick-look https://github.com/zirenzhou/subtitle-quick-look.git
brew trust --formula zirenzhou/subtitle-quick-look/subtitle-quick-look
brew install zirenzhou/subtitle-quick-look/subtitle-quick-look
```

`brew trust --formula` is required by Homebrew 6 for third-party taps. It trusts only this formula, not every formula that may later appear in the tap. Skip that line if your Homebrew version does not provide `brew trust`.

After installation, select a `.vtt` or `.lrc` file in Finder and press <kbd>Space</kbd>.

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
- it does not become the default application for VTT or LRC files.

You manage the extension entirely through Homebrew and never need to open the host.

## Privacy and limits

Preview generation is fully local. The extension has no network capability and receives read-only access only to the file being previewed. Files larger than 8 MiB are truncated in the preview with a visible notice.

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
