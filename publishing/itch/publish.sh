#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="1.0.0"
readonly EXPECTED_SHA256="83e641639354336680c57ef50d3129f08e7487e56e8c8efb0ef2bf5eae070323"
readonly ITCH_USER="daksh-mor"
readonly ITCH_PROJECT="valu"
readonly ITCH_TARGET="$ITCH_USER/$ITCH_PROJECT:android"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly APK_RELATIVE="builds/Valu-1.0.0.apk"
readonly APK="$REPO_ROOT/$APK_RELATIVE"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ "$ITCH_USER" =~ ^[A-Za-z0-9_-]+$ ]] || fail "ITCH_USER may contain only letters, numbers, underscores, and hyphens"
[[ -f "$APK" ]] || fail "signed APK not found at $APK"
[[ -s "$APK" ]] || fail "APK is empty: $APK"

command -v shasum >/dev/null 2>&1 || fail "shasum is required"
command -v butler >/dev/null 2>&1 || fail "butler is not installed or is not on PATH"

actual_sha256="$(shasum -a 256 "$APK" | awk '{print $1}')"
[[ "$actual_sha256" == "$EXPECTED_SHA256" ]] || fail \
  "APK SHA-256 mismatch (expected $EXPECTED_SHA256, got $actual_sha256)"

apksigner_bin="${APKSIGNER:-}"
if [[ -z "$apksigner_bin" ]]; then
  if command -v apksigner >/dev/null 2>&1; then
    apksigner_bin="$(command -v apksigner)"
  elif [[ -x "${ANDROID_HOME:-}/build-tools/35.0.0/apksigner" ]]; then
    apksigner_bin="$ANDROID_HOME/build-tools/35.0.0/apksigner"
  elif [[ -x "$HOME/Library/Android/sdk/build-tools/35.0.0/apksigner" ]]; then
    apksigner_bin="$HOME/Library/Android/sdk/build-tools/35.0.0/apksigner"
  else
    fail "apksigner is required; set APKSIGNER to its full path"
  fi
fi

if [[ -z "${JAVA_HOME:-}" && -d "/opt/homebrew/opt/openjdk@17" ]]; then
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
  export PATH="$JAVA_HOME/bin:$PATH"
elif [[ -z "${JAVA_HOME:-}" && -d "/usr/local/opt/openjdk@17" ]]; then
  export JAVA_HOME="/usr/local/opt/openjdk@17"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

"$apksigner_bin" verify "$APK" || fail "APK signature verification failed"

printf 'Verified %s\n' "$APK_RELATIVE"
printf 'SHA-256: %s\n' "$actual_sha256"
printf 'Uploading to %s as version %s\n' "$ITCH_TARGET" "$VERSION"

cd "$REPO_ROOT"
butler push builds/Valu-1.0.0.apk "$ITCH_TARGET" --userversion 1.0.0
