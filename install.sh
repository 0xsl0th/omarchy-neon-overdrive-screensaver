#!/usr/bin/env bash

# Install the Git checkout as an Omarchy plugin, enable it, and optionally add
# the managed menu preview entries.

set -euo pipefail

plugin_id="io.github.0xsl0th.neon-overdrive"
default_source="https://github.com/0xsl0th/omarchy-neon-overdrive-screensaver.git"
project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
plugin_dir="${HOME:?HOME is not set}/.config/omarchy/plugins/$plugin_id"
source_url=""
activate_only=false

fail() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: ./install.sh [--source <git-url>] [--activate-only]

Installs and enables $plugin_id. When run from the installed plugin directory,
the script only reconciles activation and optional menu integration.
USAGE
}

while (($# > 0)); do
  case $1 in
  --source)
    source_url="${2:-}"
    [[ -n $source_url ]] || fail "--source requires a Git URL"
    shift 2
    ;;
  --activate-only)
    activate_only=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    fail "unknown option: $1"
    ;;
  esac
done

required_commands=(
  bash date git hostname hyprctl jq mktemp omarchy omarchy-cmd-missing
  omarchy-hyprland-monitor-focused omarchy-notification-send omarchy-shell
  omarchy-toggle-enabled pgrep pkill sed socat stty ttfx xdg-terminal-exec
)
missing=()
for command in "${required_commands[@]}"; do
  command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done
((${#missing[@]} == 0)) || fail "missing required commands: ${missing[*]}"

omarchy plugin validate "$project_root" >/dev/null ||
  fail "plugin validation failed: $project_root"

if ! omarchy-shell shell ping >/dev/null 2>&1; then
  fail "omarchy-shell is not running; start it with: omarchy restart shell"
fi

activate() {
  "$project_root/scripts/menu-integration.sh" install
  omarchy-shell shell rescanPlugins >/dev/null

  omarchy plugin list --json | jq -e --arg id "$plugin_id" \
    'any(.[]; .id == $id)' >/dev/null || fail "plugin was not discovered: $plugin_id"

  omarchy plugin enable "$plugin_id" >/dev/null
  printf 'Installed and enabled %s.\n' "$plugin_id"
  printf 'Preview: "%s/bin/neon-overdrive-launch" force\n' "$plugin_dir"
}

if [[ -d $plugin_dir ]]; then
  installed_root=$(CDPATH= cd -- "$plugin_dir" && pwd -P)
  if [[ $installed_root != "$project_root" ]]; then
    [[ -x $installed_root/install.sh ]] ||
      fail "an incompatible installation already occupies $plugin_dir"
    exec "$installed_root/install.sh" --activate-only
  fi

  activate
  exit 0
fi

$activate_only && fail "installed plugin directory is missing: $plugin_dir"

if [[ -z $source_url ]]; then
  source_url=$(git -C "$project_root" remote get-url origin 2>/dev/null || true)
fi
[[ -n $source_url ]] || source_url=$default_source

omarchy plugin add "$source_url" --enable --yes
[[ -x $plugin_dir/install.sh ]] || fail "plugin install did not produce $plugin_dir"
exec "$plugin_dir/install.sh" --activate-only
