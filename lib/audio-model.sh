#!/usr/bin/env bash

# Pure frame parsing and signal calculations for the Cava-backed renderer.
# This file is sourced by neon-overdrive-render and its offline unit tests.

NEON_AUDIO_BAR_COUNT=18
NEON_AUDIO_LEVELS=()
NEON_AUDIO_MEAN=0
NEON_AUDIO_PEAK=0
NEON_AUDIO_ENERGY=0
NEON_AUDIO_BASS=0
NEON_AUDIO_MID=0
NEON_AUDIO_HIGH=0
NEON_AUDIO_BASS_EMA=0
NEON_AUDIO_ACTIVE=0
NEON_AUDIO_BEAT=0
NEON_AUDIO_FRAMES_READ=0
NEON_AUDIO_READ_STATUS=0
NEON_AUDIO_FRAME_FOUND=0

_neon_audio_recalculate() {
  local index level sum=0 peak=0 bass_sum=0 mid_sum=0 high_sum=0

  for ((index = 0; index < NEON_AUDIO_BAR_COUNT; index++)); do
    level=${NEON_AUDIO_LEVELS[index]}
    sum=$((sum + level))
    ((level > peak)) && peak=$level

    if ((index < 6)); then
      bass_sum=$((bass_sum + level))
    elif ((index < 12)); then
      mid_sum=$((mid_sum + level))
    else
      high_sum=$((high_sum + level))
    fi
  done

  NEON_AUDIO_MEAN=$(((sum + NEON_AUDIO_BAR_COUNT / 2) / NEON_AUDIO_BAR_COUNT))
  NEON_AUDIO_PEAK=$peak
  NEON_AUDIO_ENERGY=$(((NEON_AUDIO_MEAN * 65 + peak * 55 + 50) / 100))
  ((NEON_AUDIO_ENERGY > 100)) && NEON_AUDIO_ENERGY=100
  NEON_AUDIO_BASS=$(((bass_sum + 3) / 6))
  NEON_AUDIO_MID=$(((mid_sum + 3) / 6))
  NEON_AUDIO_HIGH=$(((high_sum + 3) / 6))

  NEON_AUDIO_BEAT=0
  if ((NEON_AUDIO_BASS >= 18 && NEON_AUDIO_BASS > NEON_AUDIO_BASS_EMA + 10)); then
    NEON_AUDIO_BEAT=1
  fi
  NEON_AUDIO_BASS_EMA=$(((NEON_AUDIO_BASS_EMA * 7 + NEON_AUDIO_BASS * 3 + 5) / 10))

  NEON_AUDIO_ACTIVE=0
  if ((NEON_AUDIO_PEAK >= 8 || NEON_AUDIO_ENERGY >= 5)); then
    NEON_AUDIO_ACTIVE=1
  fi
  return 0
}

neon_audio_reset() {
  local index
  NEON_AUDIO_LEVELS=()
  for ((index = 0; index < NEON_AUDIO_BAR_COUNT; index++)); do
    NEON_AUDIO_LEVELS+=(0)
  done
  NEON_AUDIO_MEAN=0
  NEON_AUDIO_PEAK=0
  NEON_AUDIO_ENERGY=0
  NEON_AUDIO_BASS=0
  NEON_AUDIO_MID=0
  NEON_AUDIO_HIGH=0
  NEON_AUDIO_BASS_EMA=0
  NEON_AUDIO_ACTIVE=0
  NEON_AUDIO_BEAT=0
  return 0
}

neon_audio_parse_frame() {
  local raw=$1 token value
  local -a tokens=() levels=()

  raw=${raw//$'\r'/}
  # Cava may prefix its first raw frame with an OSC terminal-title sequence.
  [[ $raw == *$'\a'* ]] && raw=${raw##*$'\a'}
  [[ $raw == *';' ]] && raw=${raw%;}

  [[ -n $raw && $raw != ';'* && $raw != *';' && $raw != *';;'* ]] || return 1
  [[ $raw != *$'\033'* && $raw != *$'\a'* ]] || return 1

  IFS=';' read -r -a tokens <<<"$raw"
  ((${#tokens[@]} == NEON_AUDIO_BAR_COUNT)) || return 1

  for token in "${tokens[@]}"; do
    [[ $token =~ ^[0-9]{1,5}$ ]] || return 1
    value=$((10#$token))
    ((value > 100)) && value=100
    levels+=("$value")
  done

  NEON_AUDIO_LEVELS=("${levels[@]}")
  _neon_audio_recalculate
  return 0
}

neon_audio_decay() {
  local percent=${1:-80} index
  ((percent >= 0 && percent <= 100)) || return 1

  for ((index = 0; index < NEON_AUDIO_BAR_COUNT; index++)); do
    NEON_AUDIO_LEVELS[index]=$((NEON_AUDIO_LEVELS[index] * percent / 100))
  done
  _neon_audio_recalculate
  return 0
}

neon_audio_glyph() {
  local level=$1 index
  local -a glyphs=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')

  ((level < 0)) && level=0
  ((level > 100)) && level=100
  index=$(((level * 7 + 50) / 100))
  REPLY=${glyphs[index]}
}

neon_audio_read_fd() {
  local fd=$1 max_frames=${2:-32} raw

  [[ $fd =~ ^[0-9]+$ ]] || return 2
  [[ $max_frames =~ ^[0-9]+$ ]] && ((max_frames > 0)) || return 2

  NEON_AUDIO_FRAMES_READ=0
  NEON_AUDIO_READ_STATUS=0
  NEON_AUDIO_FRAME_FOUND=0

  # Keep wake/focus handling responsive even if a custom Cava config floods
  # stdout. A positive timeout consumes the line; `read -t 0` only polls it.
  while ((NEON_AUDIO_FRAMES_READ < max_frames)); do
    if IFS= read -r -t 0.001 -u "$fd" raw 2>/dev/null; then
      NEON_AUDIO_FRAMES_READ=$((NEON_AUDIO_FRAMES_READ + 1))
      if neon_audio_parse_frame "$raw"; then
        NEON_AUDIO_FRAME_FOUND=1
      fi
    else
      NEON_AUDIO_READ_STATUS=$?
      break
    fi
  done

  ((NEON_AUDIO_FRAME_FOUND == 1))
}

neon_audio_reset
