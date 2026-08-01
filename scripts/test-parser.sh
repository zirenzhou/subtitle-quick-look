#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="${TMPDIR:-/tmp}/subtitle-quick-look-tests"

mkdir -p "$test_root/ModuleCache"

xcrun swiftc \
  -module-cache-path "$test_root/ModuleCache" \
  -target "$(uname -m)-apple-macos15.0" \
  -D PARSER_TEST_MAIN \
  -parse-as-library \
  "$project_root/SubtitleQuickLook/PreviewExtension/PreviewProvider.swift" \
  -framework QuickLookUI \
  -framework Carbon \
  -framework NaturalLanguage \
  -framework UniformTypeIdentifiers \
  -framework AppKit \
  -framework SwiftUI \
  -framework Translation \
  -o "$test_root/subtitle-parser-tests"

"$test_root/subtitle-parser-tests"
