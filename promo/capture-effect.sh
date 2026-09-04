#!/usr/bin/env bash

# Capture one live Neon Overdrive effect from the focused Hyprland output.
# The resulting Matroska file is intentionally high-bitrate production media;
# build-promo.sh performs the delivery encode.

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
raw_dir="$script_dir/raw"
effect=${1:-}
duration=${2:-${CAPTURE_DURATION:-12}}
recorder_pid=""
player_pid=""

case $effect in
synthgrid | laseretch | matrix | vhstape | thunderstorm | audio) ;;
*)
  printf 'Usage: %s <synthgrid|laseretch|matrix|vhstape|thunderstorm|audio> [seconds]\n' "${0##*/}" >&2
  exit 2
  ;;
esac
[[ $duration =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  printf 'Capture duration must be a positive number.\n' >&2
  exit 2
}

mkdir -p "$raw_dir"
output="$raw_dir/$effect.mkv"

stop_screensaver() {
  pkill -u "$UID" -f '[o]rg.omarchy.screensaver' 2>/dev/null || true
}

cleanup() {
  trap - EXIT INT TERM HUP
  if [[ -n $recorder_pid ]] && kill -0 "$recorder_pid" 2>/dev/null; then
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true
  fi
  if [[ -n $player_pid ]] && kill -0 "$player_pid" 2>/dev/null; then
    kill "$player_pid" 2>/dev/null || true
    wait "$player_pid" 2>/dev/null || true
  fi
  stop_screensaver
}
trap cleanup EXIT INT TERM HUP

stop_screensaver

wf-recorder \
  --no-dmabuf \
  --output Virtual-1 \
  --framerate 30 \
  --codec libx264 \
  --codec-param preset=ultrafast \
  --codec-param crf=14 \
  --no-damage \
  --file "$output" \
  --overwrite \
  >/dev/null 2>"$raw_dir/$effect.capture.log" &
recorder_pid=$!

# Preserve a short preroll before the terminal maps; it makes it possible to
# choose the cleanest opening point during the edit.
sleep 0.75

renderer_effect=$effect
audio_mode=off

if [[ $effect == audio ]]; then
  music_file=${PROMO_MUSIC:-"$script_dir/audio/blade-runner-end-titles-32s.flac"}
  [[ -r $music_file ]] || {
    printf 'Music bed is missing: %s\n' "$music_file" >&2
    exit 1
  }
  renderer_effect=synthgrid
  audio_mode=auto
  # Begin just before the promo's reactive section; after terminal mapping,
  # the displayed spectrum follows the same passage used in the final mix.
  mpv --no-video --audio-display=no --really-quiet --start=21.5 "$music_file" &
  player_pid=$!
  sleep 0.35
fi

if [[ $effect == audio ]]; then
  # The live spectrum takes over before ordinary wake handling is armed, so
  # use the exact production launcher for the reactive shot.
  "$project_dir/bin/neon-overdrive-launch" force --effect "$renderer_effect"
else
  terminal=$(xdg-terminal-exec --print-id)
  renderer="$project_dir/bin/neon-overdrive-render"
  omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}

  case $terminal in
  *Alacritty*)
    terminal_command=(alacritty --class=org.omarchy.screensaver
      --config-file "$omarchy_path/default/alacritty/screensaver.toml" -e)
    ;;
  *ghostty*)
    terminal_command=(ghostty --class=org.omarchy.screensaver
      --config-file="$omarchy_path/default/ghostty/screensaver" --font-size=18 -e)
    ;;
  *foot*)
    terminal_command=(foot --app-id=org.omarchy.screensaver
      --config="$omarchy_path/default/foot/screensaver.ini" -e)
    ;;
  *kitty*)
    terminal_command=(kitty --class=org.omarchy.screensaver
      --override font_size=18 --override window_padding_width=0 -e)
    ;;
  *)
    printf 'Unsupported terminal: %s\n' "$terminal" >&2
    exit 1
    ;;
  esac

  printf -v launch_command '%q ' env "BASH_ENV=$script_dir/capture-env.sh" \
    "NEON_OVERDRIVE_AUDIO=$audio_mode" "${terminal_command[@]}" \
    "$renderer" --effect "$renderer_effect"
  hyprctl dispatch "hl.dsp.exec_cmd([[$launch_command]])" >/dev/null
fi

sleep "$duration"
cleanup
exit 0
