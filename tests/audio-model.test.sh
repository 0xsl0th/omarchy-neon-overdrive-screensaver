#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/audio-model.sh
source "$project_root/lib/audio-model.sh"

fail() {
  printf 'audio-model test failed: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected=$1 actual=$2 label=$3
  [[ $actual == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

zeros='0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;'
neon_audio_parse_frame "$zeros" || fail 'valid silence frame was rejected'
assert_equal 18 "${#NEON_AUDIO_LEVELS[@]}" 'bar count'
assert_equal 0 "$NEON_AUDIO_ENERGY" 'silence energy'
assert_equal 0 "$NEON_AUDIO_ACTIVE" 'silence activity'

full='100;100;100;100;100;100;100;100;100;100;100;100;100;100;100;100;100;100;'
neon_audio_parse_frame "$full" || fail 'valid full-scale frame was rejected'
assert_equal 100 "$NEON_AUDIO_PEAK" 'full-scale peak'
assert_equal 100 "$NEON_AUDIO_ENERGY" 'clamped full-scale energy'
assert_equal 100 "$NEON_AUDIO_BASS" 'full-scale bass'
assert_equal 1 "$NEON_AUDIO_ACTIVE" 'full-scale activity'

osc_frame=$'\033]0;cava\a010;020;030;040;050;060;070;080;090;100;999;0;0;0;0;0;0;0;'
neon_audio_parse_frame "$osc_frame" || fail 'OSC-prefixed frame was rejected'
assert_equal 10 "${NEON_AUDIO_LEVELS[0]}" 'base-10 leading zero parsing'
assert_equal 100 "${NEON_AUDIO_LEVELS[10]}" 'upper clamp'

neon_audio_parse_frame "${zeros%;}" || fail 'frame without a trailing delimiter was rejected'
neon_audio_parse_frame "$zeros"$'\r' || fail 'CR-terminated frame was rejected'

before=$(IFS=,; printf '%s' "${NEON_AUDIO_LEVELS[*]}")
before_state="$NEON_AUDIO_MEAN,$NEON_AUDIO_PEAK,$NEON_AUDIO_ENERGY,$NEON_AUDIO_BASS,$NEON_AUDIO_MID,$NEON_AUDIO_HIGH,$NEON_AUDIO_BASS_EMA,$NEON_AUDIO_ACTIVE,$NEON_AUDIO_BEAT"
invalid_frames=(
  ''
  '1;2;3;'
  '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;'
  '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;-1;'
  '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;$((1));'
  '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;999999;'
  '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;;'
)
for frame in "${invalid_frames[@]}"; do
  if neon_audio_parse_frame "$frame"; then
    fail "invalid frame was accepted: $frame"
  fi
done
after=$(IFS=,; printf '%s' "${NEON_AUDIO_LEVELS[*]}")
after_state="$NEON_AUDIO_MEAN,$NEON_AUDIO_PEAK,$NEON_AUDIO_ENERGY,$NEON_AUDIO_BASS,$NEON_AUDIO_MID,$NEON_AUDIO_HIGH,$NEON_AUDIO_BASS_EMA,$NEON_AUDIO_ACTIVE,$NEON_AUDIO_BEAT"
assert_equal "$before" "$after" 'invalid frames must not mutate state'
assert_equal "$before_state" "$after_state" 'invalid frames must not mutate derived state'

neon_audio_reset
bass_hit='60;60;60;60;60;60;0;0;0;0;0;0;0;0;0;0;0;0;'
neon_audio_parse_frame "$bass_hit" || fail 'bass frame was rejected'
assert_equal 1 "$NEON_AUDIO_BEAT" 'bass attack detection'
assert_equal 60 "$NEON_AUDIO_BASS" 'bass band average'
assert_equal 0 "$NEON_AUDIO_MID" 'mid band average'
assert_equal 0 "$NEON_AUDIO_HIGH" 'high band average'

neon_audio_decay 50
assert_equal 30 "${NEON_AUDIO_LEVELS[0]}" 'level decay'
if neon_audio_decay 101; then
  fail 'invalid decay percentage was accepted'
fi

neon_audio_glyph 0
assert_equal '▁' "$REPLY" 'zero glyph'
neon_audio_glyph 100
assert_equal '█' "$REPLY" 'peak glyph'

coproc FAKE_CAVA {
  printf '%s\n' "$zeros" "$bass_hit" "$full"
  sleep 0.1
}
fake_cava_pid=${FAKE_CAVA_PID:-}
fake_cava_fd=${FAKE_CAVA[0]:-}
[[ -n $fake_cava_pid && -n $fake_cava_fd ]] || fail 'fake Cava coprocess did not start'
sleep 0.02
neon_audio_read_fd "$fake_cava_fd" 8 || fail 'fake Cava frames were not consumed'
assert_equal 3 "$NEON_AUDIO_FRAMES_READ" 'consumed frame count'
assert_equal 100 "$NEON_AUDIO_ENERGY" 'latest consumed frame'
exec {fake_cava_fd}<&- 2>/dev/null || true
kill "$fake_cava_pid" 2>/dev/null || true
wait "$fake_cava_pid" 2>/dev/null || true

coproc FLOOD_CAVA {
  for ((frame_index = 0; frame_index < 40; frame_index++)); do
    printf '%s\n' "$full"
  done
  sleep 0.1
}
flood_cava_pid=${FLOOD_CAVA_PID:-}
flood_cava_fd=${FLOOD_CAVA[0]:-}
[[ -n $flood_cava_pid && -n $flood_cava_fd ]] || fail 'flood Cava coprocess did not start'
sleep 0.02
neon_audio_read_fd "$flood_cava_fd" 5 || fail 'flood Cava frames were not consumed'
assert_equal 5 "$NEON_AUDIO_FRAMES_READ" 'per-tick frame cap'
exec {flood_cava_fd}<&- 2>/dev/null || true
kill "$flood_cava_pid" 2>/dev/null || true
wait "$flood_cava_pid" 2>/dev/null || true

coproc STALLED_CAVA {
  sleep 0.1
}
stalled_cava_pid=${STALLED_CAVA_PID:-}
stalled_cava_fd=${STALLED_CAVA[0]:-}
[[ -n $stalled_cava_pid && -n $stalled_cava_fd ]] || fail 'stalled Cava coprocess did not start'
if neon_audio_read_fd "$stalled_cava_fd" 8; then
  fail 'stalled Cava unexpectedly produced a valid frame'
fi
((NEON_AUDIO_READ_STATUS > 128)) || fail "stalled read did not report a timeout: $NEON_AUDIO_READ_STATUS"
exec {stalled_cava_fd}<&- 2>/dev/null || true
kill "$stalled_cava_pid" 2>/dev/null || true
wait "$stalled_cava_pid" 2>/dev/null || true

printf 'Audio model tests passed.\n'
