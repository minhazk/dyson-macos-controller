#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ "${1:-}" != "--leased" ]]; then
  # Woodpecker isolates HOME. Locate the host's resource queue through the
  # account database, then restore the isolated HOME for the build itself.
  runner_home="$(/usr/bin/python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
  resource_run="$runner_home/.local/bin/resource-run"
  if [[ ! -x "$resource_run" ]]; then
    echo "The native CI host needs the workstation resource queue installed." >&2
    exit 1
  fi
  exec env HOME="$runner_home" "$resource_run" --kind build -- \
    env HOME="$HOME" /bin/bash "$repo_root/script/ci_test.sh" --leased
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build/clang-module-cache"
jobs="${WORKSTATION_WORKERS:-2}"

xcodebuild -version
swift test -j "$jobs"
