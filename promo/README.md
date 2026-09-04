# Neon Overdrive community promo

`neon-overdrive-promo.mp4` is the finished 32-second, 1080p community video.
It opens by visibly selecting Synth Grid, then uses live captures of all five
effects, a second Laser Etch reprise, and the real Cava-driven music-reactive
view.

The current cut uses the opening 32 seconds of **Blade Runner (End Titles)**.
That mastered excerpt is included as a lossless, 24-bit/48 kHz FLAC at
`promo/audio/blade-runner-end-titles-32s.flac`; the full recording is not
distributed. See [`NOTICE.md`](../NOTICE.md) for its licensing status.

## Rebuild

To substitute another rights-cleared soundtrack, prepare a 32-second master
and pass its path and credit to both capture and build commands:

```bash
PROMO_MUSIC=/path/to/music.wav \
PROMO_MUSIC_CREDIT='Track title — Artist' \
promo/capture-effect.sh audio 9

PROMO_MUSIC=/path/to/music.wav \
PROMO_MUSIC_CREDIT='Track title — Artist' \
promo/build-promo.sh
```

`promo/generate-music.py` remains available for rebuilding the project's
original, sample-free **Night City Link** score.

Capture source takes from a live Omarchy/Hyprland session. Each command opens
the screensaver briefly on the focused display:

```bash
promo/capture-effect.sh synthgrid 18
promo/capture-effect.sh laseretch 18
promo/capture-effect.sh matrix 18
promo/capture-effect.sh vhstape 18
promo/capture-effect.sh thunderstorm 18
promo/capture-effect.sh audio 9
```

The capture helper requires `wf-recorder` and `mpv`. `capture-env.sh` suppresses
automated focus/input wake events only inside ordinary-effect promo takes; it
does not alter the production renderer.

Build the full-quality edit and its sub-10 MB GitHub preview:

```bash
promo/build-promo.sh
```

Raw takes and intermediate WAV masters are ignored by Git because they are
reproducible and large. The rights-cleared 32-second FLAC excerpt, finished
MP4s, title script, music generator, and production scripts are kept with the
project.
