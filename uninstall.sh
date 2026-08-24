#!/usr/bin/env bash

# Remove only Neon Overdrive's managed menu entry and plugin checkout. Omarchy's
# plugin manager restores the built-in omarchy.idle service through clonedFrom.

set -euo pipefail

plugin_id="neon-overdrive.idle"
project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
plugin_dir="${HOME:?HOME is not set}/.config/omarchy/plugins/$plugin_id"
force=false

fail() {
  printf 'uninstall: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case $1 in
  --force)
    force=true
    shift
    ;;
  -h | --help)
    printf 'Usage: ./uninstall.sh [--force]\n'
    printf '  --force  remove a Git checkout even when it has local changes\n'
    exit 0
    ;;
  *)
    fail "unknown option: $1"
    ;;
  esac
done

if [[ -d $plugin_dir ]]; then
  installed_root=$(CDPATH= cd -- "$plugin_dir" && pwd -P)
  if [[ $installed_root != "$project_root" ]]; then
    [[ -x $installed_root/uninstall.sh ]] ||
      fail "an incompatible installation occupies $plugin_dir"
    if $force; then
      exec "$installed_root/uninstall.sh" --force
    else
      exec "$installed_root/uninstall.sh"
    fi
  fi

  command -v jq >/dev/null 2>&1 || fail "required command is missing: jq"
  command -v omarchy >/dev/null 2>&1 || fail "required command is missing: omarchy"
  command -v omarchy-shell >/dev/null 2>&1 || fail "required command is missing: omarchy-shell"
  jq -e --arg id "$plugin_id" '.id == $id' "$plugin_dir/manifest.json" >/dev/null ||
    fail "manifest identity does not match $plugin_id"

  if [[ -d $plugin_dir/.git ]] && ! $force; then
    command -v git >/dev/null 2>&1 || fail "required command is missing: git"
    dirty=$(git -C "$plugin_dir" status --porcelain --untracked-files=all)
    [[ -z $dirty ]] || fail "plugin checkout has local changes; inspect them or rerun with --force"
  fi

  if ! omarchy-shell shell ping >/dev/null 2>&1; then
    fail "omarchy-shell is not running; start it with: omarchy restart shell"
  fi

  "$project_root/scripts/menu-integration.sh" remove
  printf 'Removing %s; Omarchy will restore its built-in idle service.\n' "$plugin_id"
  cd -- "$HOME"
  exec omarchy plugin remove "$plugin_id" --yes
fi

"$project_root/scripts/menu-integration.sh" remove
printf '%s is already absent.\n' "$plugin_id"
