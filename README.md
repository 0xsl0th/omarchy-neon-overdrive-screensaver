# Neon Overdrive Screensaver for Omarchy

Neon Overdrive is a multi-monitor terminal screensaver and idle-service clone
for Omarchy. It cycles through a synth grid, matrix rain, VHS distortion, and a
thunderstorm in a cyan/magenta night-city palette. When music is playing, it
automatically switches to a live Cava spectrum that makes the skyline, glow,
and bass pulse together. Keyboard input, mouse input, or focus loss wakes every
saver window; Omarchy retains responsibility for idle timing and locking.

This plugin runs as unsandboxed code inside the long-lived Omarchy shell. Review
the repository before enabling it.

## Requirements

- Omarchy with its Quickshell plugin manager and Hyprland session
- `ttfx` 0.3.2 or newer
- `bash`, `jq`, `socat`, `procps-ng`, and `xdg-terminal-exec`
- Alacritty, Foot, Ghostty, or Kitty as the selected terminal
- Optional: Cava 0.10.7 or newer for music-reactive mode

The tested baseline is Omarchy 4.0.0-1, Hyprland 0.56.2, TTFX 0.3.2, and
Cava 0.10.7. Older releases have not been validated.

Install the optional visualizer through Omarchy:

```bash
omarchy pkg add cava
```

## Install

Authenticate Git for the private repository, clone it, then run:

```bash
git clone git@github.com:0xsl0th/omarchy-neon-overdrive-screensaver.git
cd omarchy-neon-overdrive-screensaver
./install.sh
```

The installer asks Omarchy to clone the repository into
`$HOME/.config/omarchy/plugins/neon-overdrive.idle`, validates and enables the
plugin, and adds one marker-delimited override to the existing Omarchy menu.
It never replaces `shell.json` or the full menu file. Rerunning the installed
script is idempotent:

```bash
"$HOME/.config/omarchy/plugins/neon-overdrive.idle/install.sh"
```

Alternatively, use Omarchy directly and then reconcile the menu:

```bash
omarchy plugin add git@github.com:0xsl0th/omarchy-neon-overdrive-screensaver.git --yes
"$HOME/.config/omarchy/plugins/neon-overdrive.idle/install.sh"
```

## Use

Preview immediately:

```bash
"$HOME/.config/omarchy/plugins/neon-overdrive.idle/bin/neon-overdrive-launch" force
```

Set idle timing in `$HOME/.config/omarchy/shell.json`; values are seconds:

```json
{
  "idle": {
    "screensaver": 150,
    "lock": 300
  }
}
```

Use Omarchy's Stay Awake control when the idle service should be temporarily
disabled. The plugin deliberately shares Omarchy's existing stay-awake state.

### Effect selection

The default screensaver rotates through every effect. Preview a specific effect,
choose a new random effect after each completed animation, or explicitly select
the rotation from the command line:

```bash
bin/neon-overdrive-launch force --effect laseretch
bin/neon-overdrive-launch force --effect random
bin/neon-overdrive-launch force --effect rotate
```

Available named effects are `synthgrid`, `laseretch`, `matrix`, `vhstape`, and
`thunderstorm`. The managed Omarchy menu includes shortcuts for every mode.

### Music-reactive mode

The renderer starts Cava as an optional child process with an isolated config.
It asks PipeWire for its automatic source, which Cava normally resolves to the
current default output. Three active frames move the screensaver into its neon
spectrum mode; about two seconds of silence, a stalled audio stream, or a Cava
failure returns it to the normal TTFX sequence. The owned Cava process is
terminated by its exact PID when the screensaver closes, so unrelated Cava
visualizers such as a bar widget are left alone.

The bundled config asks for PipeWire's automatic default-output source and does
not explicitly select a microphone. Cava analyzes that stream in memory; the
renderer receives only derived frequency magnitudes. Neither component saves or
transmits audio. Each monitor runs its own lightweight 18-bar, 24 FPS Cava
client. Set `NEON_OVERDRIVE_AUDIO=off` in the graphical session environment to
disable audio detection completely. An alternate isolated Cava configuration
can be selected with `NEON_OVERDRIVE_CAVA_CONFIG=/path/to/config`; review a
custom config because it can select a different input source.

## Update

```bash
omarchy plugin update neon-overdrive.idle --yes
"$HOME/.config/omarchy/plugins/neon-overdrive.idle/install.sh"
```

## Uninstall

```bash
"$HOME/.config/omarchy/plugins/neon-overdrive.idle/uninstall.sh"
```

Uninstall removes only the managed menu block and the plugin checkout. Omarchy
then restores its built-in `omarchy.idle` service. A dirty Git checkout is
preserved unless `--force` is explicitly supplied. Shared Stay Awake state and
unrelated user configuration are never deleted.

## Validate

The validation script is offline-safe and does not touch live configuration:

```bash
./scripts/validate.sh
```

It checks shell syntax, manifest validity, executable modes, symlinks,
machine-specific strings, IdleModel behavior, menu install idempotence, exact
menu removal, and whitespace errors.

## Layout

```text
manifest.json                 Omarchy plugin metadata
Service.qml                   Idle and lock lifecycle service
IdleModel.js                  Pure idle/event helpers
assets/cava-reactive.conf     Isolated PipeWire/raw Cava configuration
assets/screensaver.txt        Original terminal artwork
bin/neon-overdrive-launch     Multi-monitor terminal launcher
bin/neon-overdrive-render     TTFX/audio renderer and wake handling
lib/audio-model.sh            Strict audio parsing and signal calculations
scripts/menu-integration.sh   Managed JSONC menu integration
scripts/validate.sh           Offline-safe validation suite
tests/audio-model.test.sh     Offline audio parser and signal tests
tests/renderer-audio.test.py  PTY renderer handoff and cleanup test
install.sh / uninstall.sh     Installation lifecycle
```

## Provenance and license

The artwork and effect choreography are original to this project. The idle
service is derived from Omarchy's built-in `omarchy.idle` plugin. Both projects
are distributed under the MIT License; see [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md).
