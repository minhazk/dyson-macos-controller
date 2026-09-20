#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${DYSON_BUILD_CONFIGURATION:-release}"
jobs="${DYSON_BUILD_JOBS:-2}"

swift build -c "$configuration" -j "$jobs" --product DysonMenuBar
binary_path="$(swift build -c "$configuration" -j "$jobs" --show-bin-path)/DysonMenuBar"
app_dir="$repo_root/build/DysonMenuBar.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/DysonMenuBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"

# Sign the staged bundle so macOS can consistently associate Local Network
# permission with the app bundle during local development. Release builds
# should replace this ad-hoc signature with an Apple-issued identity.
codesign --force --deep --sign - "$app_dir" >/dev/null

echo "Built ad-hoc signed app at $app_dir"
