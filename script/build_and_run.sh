#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

configuration="${DYSON_BUILD_CONFIGURATION:-release}"
jobs="${DYSON_BUILD_JOBS:-${WORKSTATION_WORKERS:-2}}"
verify=0
logs=0
show_settings=0
refresh_credentials=0

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
    --settings)
      show_settings=1
      ;;
    --refresh-credentials)
      refresh_credentials=1
      show_settings=1
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

if (( verify )); then
  swift test -j "$jobs"
fi

"$repo_root/scripts/build-app.sh"
installed_app="/Applications/DysonMenuBar.app"
if (( show_settings )); then
  if (( refresh_credentials )); then
    /usr/bin/open "$installed_app" --args --settings --refresh-credentials
  else
    /usr/bin/open "$installed_app" --args --settings
  fi
else
  /usr/bin/open "$installed_app"
fi

if (( verify )); then
  expected_executable="$installed_app/Contents/MacOS/DysonMenuBar"
  launched=0
  for attempt in {1..20}; do
    while IFS= read -r process_id; do
      if [[ "$(ps -p "$process_id" -o comm=)" == "$expected_executable" ]]; then
        launched=1
        break
      fi
    done < <(pgrep -x DysonMenuBar || true)
    if (( launched )); then
      break
    fi
    sleep 0.5
  done
  if (( ! launched )); then
    echo "Launch verification failed: $expected_executable is not running." >&2
    exit 1
  fi
  echo "Verified running app: $expected_executable"
fi

if (( logs )); then
  echo "App launched. To follow redacted diagnostics: log stream --style compact --predicate 'process == \"DysonMenuBar\"'"
fi
