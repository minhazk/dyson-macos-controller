#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${DYSON_BUILD_CONFIGURATION:-release}"
jobs="${DYSON_BUILD_JOBS:-2}"
verify=0
logs=0

for argument in "$@"; do
  case "$argument" in
    --debug)
      configuration="debug"
      ;;
    --verify)
      verify=1
      ;;
    --logs)
      logs=1
      ;;
    --telemetry)
      export DYSON_TELEMETRY=1
      ;;
    run)
      ;;
    *)
      echo "Unknown option: $argument" >&2
      exit 2
      ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/dyson-clang-module-cache}"
export DYSON_BUILD_CONFIGURATION="$configuration"
export DYSON_BUILD_JOBS="$jobs"

killall DysonMenuBar 2>/dev/null || true

if (( verify )); then
  swift test -j "$jobs"
fi

"$repo_root/scripts/build-app.sh"
/usr/bin/open -n "$repo_root/build/DysonMenuBar.app"

if (( logs )); then
  echo "App launched. To follow redacted diagnostics: log stream --style compact --predicate 'process == \"DysonMenuBar\"'"
fi
