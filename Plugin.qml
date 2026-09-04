import QtQuick
import Quickshell

Item {
  id: root

  // Injected by omarchy-shell for third-party overlay entry points.
  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "io.github.0xsl0th.neon-overdrive"

  function effectFromPayload(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (error) { payload = ({}) }

    var effect = String(payload.effect || "rotate")
    var effects = ["rotate", "random", "synthgrid", "laseretch", "matrix", "vhstape", "thunderstorm"]
    return effects.indexOf(effect) >= 0 ? effect : "rotate"
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function open(payloadJson) {
    root.opened = true

    if (!root.service || typeof root.service.startPreview !== "function") {
      console.warn("Neon Overdrive service is unavailable; preview was not started")
      Qt.callLater(root.dismiss)
      return
    }

    if (!root.service.startPreview(effectFromPayload(payloadJson)))
      console.warn("Neon Overdrive preview is already starting")

    // The terminal windows own the fullscreen experience after launch. Clear
    // the shell's transient overlay state without dismissing those windows.
    Qt.callLater(root.dismiss)
  }

  function close() {
    root.opened = false
  }
}
