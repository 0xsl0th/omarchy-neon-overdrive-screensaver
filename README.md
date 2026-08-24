# Neon Overdrive Screensaver for Omarchy

Neon Overdrive is a multi-monitor terminal screensaver and idle-service clone
for Omarchy. It cycles through a synth grid, matrix rain, VHS distortion, and a
thunderstorm in a cyan/magenta night-city palette. Keyboard input, mouse input,
or focus loss wakes every saver window; Omarchy retains responsibility for idle
timing and locking.

This plugin runs as unsandboxed code inside the long-lived Omarchy shell. Review
the repository before enabling it.

## Requirements

- Omarchy with its Quickshell plugin manager and Hyprland session
- `ttfx` 0.3.2 or newer
- `bash`, `jq`, `socat`, `procps-ng`, and `xdg-terminal-exec`
- Alacritty, Foot, Ghostty, or Kitty as the selected terminal

The tested baseline is Omarchy 4.0.0-1, Hyprland 0.56.2, and TTFX 0.3.2.
Older releases have not been validated.

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
bin/neon-overdrive-launch     Multi-monitor terminal launcher
bin/neon-overdrive-render     TTFX renderer and wake handling
assets/screensaver.txt        Original terminal artwork
scripts/menu-integration.sh   Managed JSONC menu integration
scripts/validate.sh           Offline-safe validation suite
install.sh / uninstall.sh     Installation lifecycle
```

## Provenance and license

The artwork and effect choreography are original to this project. The idle
service is derived from Omarchy's built-in `omarchy.idle` plugin. Both projects
are distributed under the MIT License; see [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md).
