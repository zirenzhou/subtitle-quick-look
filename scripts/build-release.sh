#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/build/ManualRelease"
archive_dir="$project_root/dist"
app_name="Subtitle Quick Look"
extension_name="Subtitle Quick Look Preview"
app_path="$build_root/$app_name.app"
extension_path="$app_path/Contents/PlugIns/$extension_name.appex"
module_cache="$build_root/ModuleCache"
version="${VERSION:-1.1.0}"

rm -rf "$build_root"
mkdir -p \
  "$app_path/Contents/MacOS" \
  "$extension_path/Contents/MacOS" \
  "$module_cache" \
  "$archive_dir"

cp "$project_root/SubtitleQuickLook/App/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/SubtitleQuickLook/PreviewExtension/Info.plist" "$extension_path/Contents/Info.plist"

add_plist_value() {
  local plist="$1"
  local key="$2"
  local type="$3"
  local value="$4"
  /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$plist"
}

add_plist_value "$app_path/Contents/Info.plist" CFBundleExecutable string "$app_name"
add_plist_value "$app_path/Contents/Info.plist" CFBundleIdentifier string io.github.zirenzhou.subtitle-quick-look
add_plist_value "$app_path/Contents/Info.plist" CFBundleName string "$app_name"
add_plist_value "$app_path/Contents/Info.plist" CFBundleDisplayName string "$app_name"
add_plist_value "$app_path/Contents/Info.plist" CFBundlePackageType string APPL
add_plist_value "$app_path/Contents/Info.plist" CFBundleShortVersionString string "$version"
add_plist_value "$app_path/Contents/Info.plist" CFBundleVersion string 1
add_plist_value "$app_path/Contents/Info.plist" LSMinimumSystemVersion string 15.0
add_plist_value "$app_path/Contents/Info.plist" NSHighResolutionCapable bool true

add_plist_value "$extension_path/Contents/Info.plist" CFBundleExecutable string "$extension_name"
add_plist_value "$extension_path/Contents/Info.plist" CFBundleIdentifier string io.github.zirenzhou.subtitle-quick-look.preview
add_plist_value "$extension_path/Contents/Info.plist" CFBundleName string "$extension_name"
add_plist_value "$extension_path/Contents/Info.plist" CFBundleDisplayName string "$extension_name"
add_plist_value "$extension_path/Contents/Info.plist" CFBundlePackageType string XPC!
add_plist_value "$extension_path/Contents/Info.plist" CFBundleShortVersionString string "$version"
add_plist_value "$extension_path/Contents/Info.plist" CFBundleVersion string 1
add_plist_value "$extension_path/Contents/Info.plist" LSMinimumSystemVersion string 15.0
/usr/libexec/PlistBuddy -c \
  "Set :NSExtension:NSExtensionPrincipalClass SubtitleQuickLookPreview.PreviewProvider" \
  "$extension_path/Contents/Info.plist"

compile_app() {
  local arch="$1"
  xcrun swiftc \
    -module-cache-path "$module_cache" \
    -target "$arch-apple-macos15.0" \
    -O \
    "$project_root/SubtitleQuickLook/App/main.swift" \
    -o "$build_root/app-$arch"
}

compile_extension() {
  local arch="$1"
  xcrun swiftc \
    -module-cache-path "$module_cache" \
    -target "$arch-apple-macos15.0" \
    -O \
    -module-name SubtitleQuickLookPreview \
    -parse-as-library \
    -application-extension \
    -emit-executable \
    "$project_root/SubtitleQuickLook/PreviewExtension/PreviewProvider.swift" \
    -framework QuickLookUI \
    -framework Carbon \
    -framework NaturalLanguage \
    -framework UniformTypeIdentifiers \
    -framework AppKit \
    -framework SwiftUI \
    -framework Translation \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    -o "$build_root/extension-$arch"
}

for architecture in arm64 x86_64; do
  compile_app "$architecture"
  compile_extension "$architecture"
done

xcrun lipo -create \
  "$build_root/app-arm64" \
  "$build_root/app-x86_64" \
  -output "$app_path/Contents/MacOS/$app_name"

xcrun lipo -create \
  "$build_root/extension-arm64" \
  "$build_root/extension-x86_64" \
  -output "$extension_path/Contents/MacOS/$extension_name"

codesign --force --sign - \
  --entitlements "$project_root/SubtitleQuickLook/PreviewExtension/PreviewExtension.entitlements" \
  "$extension_path"

codesign --force --sign - \
  --entitlements "$project_root/SubtitleQuickLook/App/SubtitleQuickLook.entitlements" \
  "$app_path"

rm -f "$archive_dir/Subtitle-Quick-Look.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "$app_path" \
  "$archive_dir/Subtitle-Quick-Look.zip"

echo "Built: $app_path"
echo "Package: $archive_dir/Subtitle-Quick-Look.zip"
