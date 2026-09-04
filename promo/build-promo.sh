#!/usr/bin/env bash

# Edit the captured live takes and soundtrack into the 32-second community
# promo. Source takes remain untouched in promo/raw.

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
raw_dir="$script_dir/raw"
work_dir="$script_dir/work"
music=${PROMO_MUSIC:-"$script_dir/audio/blade-runner-end-titles-32s.flac"}
music_credit=${PROMO_MUSIC_CREDIT:-Blade Runner (End Titles)}
output="$script_dir/neon-overdrive-promo.mp4"
github_output="$script_dir/neon-overdrive-promo-github.mp4"
github_passlog="$work_dir/neon-overdrive-github"

inputs=(synthgrid laseretch matrix vhstape thunderstorm audio)
for input in "${inputs[@]}"; do
  [[ -r $raw_dir/$input.mkv ]] || {
    printf 'Missing source take: %s\n' "$raw_dir/$input.mkv" >&2
    exit 1
  }
done
[[ -r $music ]] || {
  printf 'Missing music master: %s\n' "$music" >&2
  exit 1
}
[[ -r $script_dir/titles.ass ]] || {
  printf 'Missing title script: %s\n' "$script_dir/titles.ass" >&2
  exit 1
}

mkdir -p "$work_dir"

ffmpeg -hide_banner -y \
  -i "$raw_dir/synthgrid.mkv" \
  -i "$raw_dir/laseretch.mkv" \
  -i "$raw_dir/matrix.mkv" \
  -i "$raw_dir/vhstape.mkv" \
  -i "$raw_dir/thunderstorm.mkv" \
  -i "$raw_dir/audio.mkv" \
  -i "$music" \
  -filter_complex "
    [0:v]split=2[synth][endcard];
    [synth]trim=start=1.60:end=18.60,setpts=(PTS-STARTPTS)/2.6153846,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v0];
    [1:v]split=2[laser][laser_reprise];
    [laser]trim=start=1.60:end=18.60,setpts=(PTS-STARTPTS)/4.25,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v1];
    [2:v]trim=start=1.60:end=18.60,setpts=(PTS-STARTPTS)/4.25,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v2];
    [3:v]trim=start=1.60:end=18.50,setpts=(PTS-STARTPTS)/4.225,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v3];
    [4:v]trim=start=1.60:end=18.60,setpts=(PTS-STARTPTS)/4.25,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v4];
    [5:v]trim=start=2.10:end=6.85,setpts=PTS-STARTPTS,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v5];
    [laser_reprise]trim=start=9.50:end=12.00,setpts=(PTS-STARTPTS)/2,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30[v5b];
    [endcard]trim=start=15.60:end=18.60,setpts=(PTS-STARTPTS)*1.1666667,
      scale=1728:1080:flags=lanczos:in_range=full:out_range=tv,
      pad=1920:1080:96:0:color=0x080311,setsar=1,fps=30,
      eq=brightness=-0.16:saturation=0.72[v6];
    [v0][v1][v2][v3][v4][v5][v5b][v6]concat=n=8:v=1:a=0,
      drawbox=x=520:y=95:w=880:h=820:color=0x080311@0.90:t=fill:enable='between(t,0.05,1.68)',
      drawbox=x=520:y=95:w=880:h=820:color=0x00f5ff@0.85:t=3:enable='between(t,0.05,1.68)',
      drawbox=x=530:y=105:w=860:h=800:color=0xff2bd6@0.45:t=1:enable='between(t,0.05,1.68)',
      ass='$script_dir/titles.ass':fontsdir=/usr/share/fonts/TTF,
      fade=t=in:st=0:d=0.25,fade=t=out:st=31.50:d=0.50,
      setparams=range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709[v];
    [6:a]atrim=start=0:end=32,asetpts=PTS-STARTPTS,volume=-1.2dB,
      afade=t=in:st=0:d=0.25,afade=t=out:st=31.20:d=0.80[a]
  " \
  -map '[v]' -map '[a]' \
  -c:v libx264 -preset slow -crf 17 -profile:v high -level:v 4.2 \
  -pix_fmt yuv420p -r 30 -g 60 \
  -c:a aac -b:a 256k -ar 48000 \
  -movflags +faststart -metadata title='Neon Overdrive for Omarchy' \
  -metadata "comment=Original visuals by the Neon Overdrive project; music: $music_credit" \
  -shortest "$output"

# Keep the GitHub preview below 10 MB while retaining the same 32-second edit.
ffmpeg -hide_banner -y \
  -i "$output" -map 0:v:0 \
  -vf 'scale=-2:720:flags=lanczos' \
  -c:v libx264 -preset slow -tune animation \
  -b:v 1800k -maxrate 2200k -bufsize 4400k \
  -profile:v high -level:v 4.0 -pix_fmt yuv420p -r 30 \
  -pass 1 -passlogfile "$github_passlog" \
  -an -f null /dev/null

ffmpeg -hide_banner -y \
  -i "$output" -map 0:v:0 -map 0:a:0 \
  -vf 'scale=-2:720:flags=lanczos' \
  -c:v libx264 -preset slow -tune animation \
  -b:v 1800k -maxrate 2200k -bufsize 4400k \
  -profile:v high -level:v 4.0 -pix_fmt yuv420p -r 30 \
  -pass 2 -passlogfile "$github_passlog" \
  -c:a aac -b:a 128k -ar 48000 -movflags +faststart \
  -metadata title='Neon Overdrive for Omarchy — GitHub Preview' \
  -metadata "comment=Web preview; music: $music_credit; full-quality 1080p master also available" \
  "$github_output"

printf '%s\n%s\n' "$output" "$github_output"
