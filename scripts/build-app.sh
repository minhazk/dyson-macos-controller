#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${DYSON_BUILD_CONFIGURATION:-release}"
jobs="${DYSON_BUILD_JOBS:-${WORKSTATION_WORKERS:-2}}"

swift build -c "$configuration" -j "$jobs" --product DysonMenuBar
binary_path="$(swift build -c "$configuration" -j "$jobs" --show-bin-path)/DysonMenuBar"
installed_app="/Applications/DysonMenuBar.app"
staging_dir="$(mktemp -d /Applications/.dyson-install.XXXXXX)"
app_dir="$staging_dir/DysonMenuBar.app"

cleanup() {
  # Restore the previous installation if replacing it failed.
  if [[ -d "$staging_dir/previous.app" && ! -e "$installed_app" ]]; then
    mv "$staging_dir/previous.app" "$installed_app"
  fi
  rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_path" "$app_dir/Contents/MacOS/DysonMenuBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"

# Sign the staged bundle so macOS can consistently associate permissions and
# Keychain access with the app bundle during local development. An explicit
# identifier requirement is important here: a plain ad-hoc signature gets a
# new cdhash after every rebuild, which makes macOS ask for Keychain access
# again after each refresh.
codesign --force --deep --sign - \
  --identifier community.dyson.macos-controller \
  --requirements='=designated => identifier "community.dyson.macos-controller"' \
  "$app_dir" >/dev/null

codesign --verify --deep --strict "$app_dir"

# Build and validate before stopping the running app. Every checkout installs
# to this same location so login items never depend on a build-folder copy.
killall DysonMenuBar 2>/dev/null || true
for attempt in {1..20}; do
  if ! pgrep -x DysonMenuBar >/dev/null; then
    break
  fi
  sleep 0.5
done
if pgrep -x DysonMenuBar >/dev/null; then
  echo "Could not stop DysonMenuBar; keeping the previous installation." >&2
  exit 1
fi
if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$staging_dir/previous.app"
fi
mv "$app_dir" "$installed_app"

echo "Installed ad-hoc signed app at $installed_app"
