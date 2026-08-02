#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="${TMPDIR:-/tmp}/subtitle-quick-look-tests"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/ModuleCache"

xcrun swiftc \
  -module-cache-path "$test_root/ModuleCache" \
  -target "$(uname -m)-apple-macos15.0" \
  -parse-as-library \
  "$project_root/SubtitleQuickLook/Shared/SubtitleCore.swift" \
  "$project_root/Tests/SubtitleCoreTests.swift" \
  -framework NaturalLanguage \
  -o "$test_root/subtitle-parser-tests"

"$test_root/subtitle-parser-tests" \
  "$project_root/Tests/Fixtures/translation-zh-Hant.srt"
