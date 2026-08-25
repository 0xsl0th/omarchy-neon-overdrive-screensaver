#!/usr/bin/env bash

# Add or remove Neon Overdrive's managed Omarchy menu entries without
# replacing the user's JSONC file or disturbing unrelated entries/comments.

set -euo pipefail

begin_marker="BEGIN neon-overdrive-screensaver (managed)"
end_marker="END neon-overdrive-screensaver (managed)"
menu_file="${NEON_OVERDRIVE_MENU_FILE:-${HOME:?HOME is not set}/.config/omarchy/extensions/omarchy-menu.jsonc}"
action="${1:-}"

fail() {
  printf 'menu-integration: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s <install|remove>\n' "${0##*/}"
}

case $action in
install | remove) ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

menu_dir=${menu_file%/*}
[[ $menu_dir != "$menu_file" ]] || menu_dir=.

if [[ -L $menu_file ]]; then
  fail "refusing to replace symlink: $menu_file"
fi
if [[ -e $menu_file && ! -f $menu_file ]]; then
  fail "menu path is not a regular file: $menu_file"
fi

if [[ $action == remove && ! -e $menu_file ]]; then
  printf 'Neon Overdrive menu integration is already absent.\n'
  exit 0
fi

mkdir -p -- "$menu_dir"
stripped=$(mktemp "$menu_dir/.neon-overdrive-menu.stripped.XXXXXX")
staged=$(mktemp "$menu_dir/.neon-overdrive-menu.staged.XXXXXX")
cleanup() {
  rm -f -- "$stripped" "$staged"
}
trap cleanup EXIT

if [[ -e $menu_file ]]; then
  begin_count=$(awk -v marker="$begin_marker" 'index($0, marker) { count++ } END { print count + 0 }' "$menu_file")
  end_count=$(awk -v marker="$end_marker" 'index($0, marker) { count++ } END { print count + 0 }' "$menu_file")

  if ((begin_count != end_count || begin_count > 1)); then
    fail "managed markers are malformed in $menu_file"
  fi

  if ((begin_count == 1)) && ! awk -v begin="$begin_marker" -v end="$end_marker" '
    index($0, begin) { begin_line = NR }
    index($0, end) { end_line = NR }
    END { exit !(begin_line > 0 && end_line > begin_line) }
  ' "$menu_file"; then
    fail "managed markers are out of order in $menu_file"
  fi

  awk -v begin="$begin_marker" -v end="$end_marker" '
    index($0, begin) { managed = 1; next }
    index($0, end) { managed = 0; next }
    !managed { print }
  ' "$menu_file" >"$stripped"
else
  printf '{\n}\n' >"$stripped"
  begin_count=0
fi

if [[ $action == remove ]]; then
  if ((begin_count == 0)); then
    printf 'Neon Overdrive menu integration is already absent.\n'
    exit 0
  fi

  chmod --reference="$menu_file" "$stripped"
  mv -f -- "$stripped" "$menu_file"
  printf 'Removed Neon Overdrive menu integration from %s\n' "$menu_file"
  exit 0
fi

open_line=$(awk '/^[[:space:]]*\{[[:space:]]*$/ { print NR; exit }' "$stripped")
[[ -n $open_line ]] || fail "could not find the menu object's opening brace in $menu_file"

{
  sed -n "1,${open_line}p" "$stripped"
  cat <<'MENU_BLOCK'
  // BEGIN neon-overdrive-screensaver (managed)
  "system.screensaver": {
    "label": "Neon Overdrive Screensaver",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force"
  },
  "system.screensaver-random": {
    "label": "Neon Overdrive: Random Effect",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force --effect random"
  },
  "system.screensaver-synthgrid": {
    "label": "Neon Overdrive: Synth Grid",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force --effect synthgrid"
  },
  "system.screensaver-laseretch": {
    "label": "Neon Overdrive: Laser Etch",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force --effect laseretch"
  },
  "system.screensaver-matrix": {
    "label": "Neon Overdrive: Matrix Rain",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force --effect matrix"
  },
  "system.screensaver-vhstape": {
    "label": "Neon Overdrive: VHS Distortion",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force --effect vhstape"
  },
  "system.screensaver-thunderstorm": {
    "label": "Neon Overdrive: Thunderstorm",
    "action": "\"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch\" force --effect thunderstorm"
  },
  // END neon-overdrive-screensaver (managed)
MENU_BLOCK
  tail -n "+$((open_line + 1))" "$stripped"
} >"$staged"

if [[ -e $menu_file ]] && cmp -s -- "$staged" "$menu_file"; then
  printf 'Neon Overdrive menu integration is already current.\n'
  exit 0
fi

if [[ -e $menu_file ]]; then
  backup="$menu_file.neon-overdrive.bak"
  if [[ ! -e $backup && ! -L $backup ]]; then
    cp -p -- "$menu_file" "$backup"
  fi
  chmod --reference="$menu_file" "$staged"
else
  chmod 0644 "$staged"
fi

mv -f -- "$staged" "$menu_file"
printf 'Installed Neon Overdrive menu integration in %s\n' "$menu_file"
