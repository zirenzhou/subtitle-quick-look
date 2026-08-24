# Changelog

All notable user-facing changes are recorded here. GitHub tags use semantic versioning.

## Unreleased

### Added

- Plain-text `.txt` parsing and native translation in Finder workflows, including Shift-JIS, EUC-JP, Windows-1252, and other existing text encodings.
- A lightweight self-healing LaunchAgent that checks Quick Look registration after login and every 15 minutes, repairs stale state, and exits without remaining active in the background.
- Duplicate registrations from older installs are removed so macOS cannot randomly route previews to stale app copies.

### Fixed

- Restored interactive Quick Look previews after removing an incompatible data-based preview declaration that made Finder fall back to its generic file-information panel.

## [1.2.0](https://github.com/zirenzhou/subtitle-quick-look/releases/tag/v1.2.0) — 2026-08-02

### Added

- Quick Look support for ASS and SSA subtitles, including common Firecore/Infuse content types.
- Format-aware Save As conversion between WebVTT, SRT, LRC, and ASS/SSA while preserving subtitle timing and structure.
- Localized **Convert Subtitles…** and **Translate Files…** Finder Services for batch processing multiple files.
- Source and target language selection for Finder translation, with language-suffixed copies by default and explicit atomic replacement when requested.
- Local Simplified/Traditional Chinese conversion when Apple Translation does not expose the requested script pair.
- Shared Foundation-only subtitle parsing and conversion core with expanded reconstruction tests.

### Improved

- Compact format selection in the Save As panel.
- Larger, visible hover targets for close and save controls.
- Automatic Quick Look and Finder Services registration during Homebrew install and upgrade.
- English, Simplified Chinese, Traditional Chinese, Japanese, and Korean Finder Service localization.

## [1.1.0](https://github.com/zirenzhou/subtitle-quick-look/releases/tag/v1.1.0) — 2026-08-02

### Added

- Apple-native translation for VTT, LRC, and SRT previews.
- Automatic source-language detection and remembered primary and secondary target languages.
- SRT Quick Look routing for common content types.
- Native Save As flow for translated subtitle copies.

### Improved

- Translation changes subtitle text only; cue numbers, timestamps, tags, whitespace, and source structure remain intact.
- Compact controls adapt to narrow Quick Look windows.
- Language menus use autonyms, merge regional duplicates, and keep a contextual six-language shortlist.
- Files written in the device's primary language do not translate automatically; a manual request uses the remembered secondary target.
- Repeated translation sessions no longer remain stuck in the loading state.

## [1.0.0](https://github.com/zirenzhou/subtitle-quick-look/releases/tag/v1.0.0) — 2026-08-02

### Added

- First public release.
- Finder Quick Look plain-text previews for WebVTT and LRC files.
- UTF-8, UTF-16/32, GB18030, and Latin-1 decoding.
- Universal Apple Silicon and Intel builds.
- Homebrew source installation with automatic Quick Look registration.
- An 8 MiB preview limit to keep Quick Look responsive.
