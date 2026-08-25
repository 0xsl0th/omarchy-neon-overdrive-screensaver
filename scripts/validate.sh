#!/usr/bin/env bash

# Offline-safe source validation. This never installs, enables, previews, or
# touches the live Omarchy configuration.

set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$project_root"

fail() {
  printf 'validate: %s\n' "$*" >&2
  exit 1
}

required_files=(
  manifest.json Service.qml IdleModel.js assets/screensaver.txt assets/cava-reactive.conf
  bin/neon-overdrive-launch bin/neon-overdrive-render
  lib/audio-model.sh tests/audio-model.test.sh tests/renderer-audio.test.py
  install.sh uninstall.sh scripts/menu-integration.sh scripts/validate.sh
  README.md LICENSE NOTICE.md .gitignore tests/idle-model.test.js
)
for file in "${required_files[@]}"; do
  [[ -f $file ]] || fail "missing required file: $file"
done

for script in install.sh uninstall.sh bin/neon-overdrive-launch \
  bin/neon-overdrive-render scripts/menu-integration.sh scripts/validate.sh; do
  [[ -x $script ]] || fail "script is not executable: $script"
done

bash -n install.sh uninstall.sh bin/neon-overdrive-launch \
  bin/neon-overdrive-render lib/audio-model.sh tests/audio-model.test.sh \
  scripts/menu-integration.sh scripts/validate.sh

jq -e '
  .schemaVersion == 1 and
  .id == "neon-overdrive.idle" and
  .version == "1.1.0" and
  .kinds == ["service"] and
  .entryPoints.service == "Service.qml" and
  .omarchy.clonedFrom == "omarchy.idle"
' manifest.json >/dev/null

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$project_root"
else
  printf 'validate: omarchy unavailable; skipped native plugin validation\n' >&2
fi

link=$(find . -path ./.git -prune -o -type l -print -quit)
[[ -z $link ]] || fail "symlinks are not allowed: $link"

if rg -n '(/home/[[:alnum:]_.-]+|omarchy-quattro|sloth\.idle)' \
  --glob '!scripts/validate.sh' .; then
  fail "machine-specific value found"
fi

if command -v node >/dev/null 2>&1; then
  node tests/idle-model.test.js
else
  printf 'validate: node unavailable; skipped IdleModel unit tests\n' >&2
fi

bash tests/audio-model.test.sh

if command -v python3 >/dev/null 2>&1; then
  python3 -B tests/renderer-audio.test.py
else
  printf 'validate: python3 unavailable; skipped renderer integration test\n' >&2
fi

for setting in \
  'bars = 18' 'framerate = 24' 'method = pipewire' 'source = auto' \
  'virtual = 1' 'method = raw' 'channels = mono' \
  'raw_target = /dev/stdout' 'data_format = ascii' \
  'ascii_max_range = 100' 'bar_delimiter = 59' 'frame_delimiter = 10'; do
  grep -Fqx "$setting" assets/cava-reactive.conf || fail "Cava config is missing: $setting"
done

if rg -n 'pkill.*cava' bin lib; then
  fail "Cava must be terminated by its tracked PID, never with pkill"
fi

fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/neon-overdrive-validation.XXXXXX")
cleanup() {
  rm -rf -- "$fixture_dir"
}
trap cleanup EXIT
fixture="$fixture_dir/omarchy-menu.jsonc"
original="$fixture_dir/original.jsonc"

cat >"$fixture" <<'JSONC'
{
  // Preserve this user-owned entry and comment byte-for-byte.
  "personal": {"label":"Personal"},
}
JSONC
cp -- "$fixture" "$original"

NEON_OVERDRIVE_MENU_FILE="$fixture" scripts/menu-integration.sh install >/dev/null
first_sum=$(sha256sum "$fixture" | awk '{ print $1 }')
NEON_OVERDRIVE_MENU_FILE="$fixture" scripts/menu-integration.sh install >/dev/null
second_sum=$(sha256sum "$fixture" | awk '{ print $1 }')
[[ $first_sum == "$second_sum" ]] || fail "menu installation is not idempotent"

begin_count=$(rg -c 'BEGIN neon-overdrive-screensaver' "$fixture")
[[ $begin_count == 1 ]] || fail "menu integration marker was duplicated"

NEON_OVERDRIVE_MENU_FILE="$fixture" scripts/menu-integration.sh remove >/dev/null
cmp -s -- "$fixture" "$original" || fail "menu removal did not preserve user content"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi

printf 'All Neon Overdrive source validations passed.\n'
