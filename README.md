# Subtitle Quick Look

[![Build](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml/badge.svg)](https://github.com/zirenzhou/subtitle-quick-look/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black.svg)](#requirements)

[中文说明](README.zh-CN.md) · [Changelog](CHANGELOG.md)

**A lightweight macOS Quick Look extension, native subtitle translator, and format converter for VTT, SRT, LRC, ASS, and SSA files.**

Select a subtitle or lyrics file in Finder and press <kbd>Space</kbd>. Subtitle Quick Look adds readable previews, optional translation through Apple's native Translation framework, and one-click conversion without an AI API, API key, account, background service, or uploaded subtitle data.

## Why Subtitle Quick Look?

- **Preview more subtitle and lyrics formats:** WebVTT (`.vtt`), SubRip (`.srt`), LRC lyrics (`.lrc`), and SubStation Alpha (`.ass`, `.ssa`), with shared plain-text (`.txt`) parsing for Finder workflows.
- **Translate with macOS:** automatic language detection, native Apple Translation, remembered language choices, and local Simplified/Traditional Chinese conversion.
- **Convert and batch-process files:** preserve subtitle timing and structure, save to another format, or use localized Finder Services on multiple files.
- **Stay lightweight and private:** no AI API, API key, sign-in, custom network service, Dock icon, or persistent background process.

## Quick start

1. Install with Homebrew using the commands below.
2. Select a supported file in Finder and press <kbd>Space</kbd>.
3. Use the corner translation button only when you need it, or open **Finder → Services** for batch translation and conversion.

## Features

- Finder Quick Look previews for `.vtt`, `.lrc`, `.srt`, `.ass`, and `.ssa`
- Plain-text `.txt` parsing and translation in Finder Services, including legacy encodings such as Shift-JIS
- Native Apple Translation with automatic source-language detection
- Target language defaults to the macOS preferred language
- Files already written in the device's primary language never auto-translate; a manual request uses a separately remembered secondary target language
- Matching source and target languages close translation cleanly with a brief “No translation needed” notice
- Compact, responsive translation controls that stay usable in narrow Quick Look windows
- Contextual language menus keep up to six system and recently used languages visible; regional duplicates are merged, every language is shown by its autonym, and the rest are folded under **More**
- Remembers whether translation is enabled and the selected languages
- Sends only subtitle text for translation; timestamps and subtitle structure stay intact
- Native Save As panel with a target-language filename suggestion
- Save As keeps the original format by default and can convert the result to WebVTT, SRT, LRC, or ASS/SSA
- Localized Finder Services can convert or translate multiple selected subtitles at once
- **Convert Subtitles…** creates new sibling files and never overwrites the source
- **Translate Files…** asks for source/target languages and saves language-suffixed copies by default; replacing the selected originals is an explicit option
- Traditional/Simplified Chinese conversion uses the local macOS system transform when Apple Translation does not expose that language pair
- UTF-8, UTF-16/32, Shift-JIS, EUC-JP, GB18030, Windows-1252, and Latin-1 decoding
- Apple Silicon and Intel support
- No separate window, Dock icon, persistent background process, or custom network service
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

This is currently a third-party tap. Because the installed product is a native macOS app bundle containing a Quick Look extension, the correct official Homebrew destination is `homebrew/cask`, not `homebrew/core`. See the [official Homebrew distribution roadmap](docs/HOMEBREW.md) for the signing, notarization, packaging, and public-interest requirements that must be completed before submission.

After installation, select a supported subtitle in Finder and press <kbd>Space</kbd>. Registration is automatic; no extra command is normally required.

To upgrade an existing installation to the latest release:

```bash
brew update
brew upgrade subtitle-quick-look
```

If macOS does not refresh Quick Look or Finder Services immediately after an install or upgrade, run the fallback command printed by Homebrew:

```bash
subtitle-quick-look register
```

## Finder Services

Select one or more subtitle files, then open **Finder → Services**:

- **Convert Subtitles…** asks for one compact output format and creates new files next to the originals. It changes the subtitle format, not the language.
- **Translate Files…** asks for source and target languages. It saves language-suffixed copies by default, or atomically replaces the selected originals when **Replace original files** is enabled.

The service menus and dialogs follow the device language in English, Simplified Chinese, Traditional Chinese, Japanese, or Korean. Language choices use autonyms and are shared with Quick Look. The Services host launches only for the requested operation and exits afterward.

These commands appear under **Services** because v1.2 uses macOS `NSServices`, which supports multi-file Finder input and lightweight Homebrew registration. Finder **Quick Actions** are a separate extension type with their own sandbox, signing, activation, and enablement lifecycle; moving the same commands there requires a separately embedded Action extension rather than a menu relocation.

## Manage the extension

The formula automatically registers the Quick Look extension and refreshes Finder Services during install and upgrade.
It also installs a lightweight LaunchAgent that verifies registration after login and every 15 minutes. The helper repairs missing or stale registration, removes older duplicate registrations, and exits immediately; it is not a persistent background process.

```bash
subtitle-quick-look status       # Check registration
subtitle-quick-look register     # Register again and refresh Quick Look
subtitle-quick-look install-autostart # Restore login registration if needed
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

Modern macOS requires Quick Look preview extensions and Services to live inside an app bundle. The bundled host is only a technical container:

- it has no user interface;
- it has no Dock icon;
- it runs only while a Finder Service is handling selected files;
- it exits automatically after the operation; and
- it does not become the default application for VTT, LRC, or SRT files.

You manage the extension entirely through Homebrew and never need to open the host.

macOS assigns `public.plain-text` to its built-in text previewer. A third-party Preview Extension may declare `.txt` support, but current macOS releases do not guarantee that Space-bar preview requests are routed to it. Shift-JIS and other legacy-encoded TXT files are therefore handled reliably through the **Translate Files…** Finder Service rather than by replacing Apple's TXT previewer.

## iOS note

The subtitle parsing and conversion core is Foundation-only so it can be reused by a future iOS Action/Share extension. Homebrew cannot install or sign iOS extensions, so an iOS Files/Share Sheet action must ship later as a separately signed iOS companion app; it is not included in this macOS Homebrew package.

## Privacy and limits

Preview parsing, Chinese script conversion, and Apple Translation run locally. The extension does not add its own network service. Quick Look writes only to a destination you explicitly choose in the Save As panel. **Translate Files…** preserves originals by default; replacement happens only when you explicitly enable **Replace original files**. Files larger than 8 MiB are truncated in the preview and cannot be saved from Quick Look.

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
