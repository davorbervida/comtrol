import Quickshell
import Quickshell.Io
import QtQuick

// Install → Update — Omarchy update / firmware / time actions.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  readonly property string itemId: "update"
  readonly property string label: "Update"
  readonly property string icon: ""
  readonly property string title: "Update"

  property bool themesExtrasAvailable: false

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property var menu: {
    var rows = [
      {
        itemId: "update.omarchy",
        label: "Omarchy",
        icon: "",
        kind: "update",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-update"
      }
    ]
    if (root.themesExtrasAvailable) {
      rows.push({
        itemId: "update.themes",
        label: "Extra Themes",
        icon: "󰸌",
        kind: "update",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-theme-update"
      })
    }
    rows.push(
      {
        itemId: "update.firmware",
        label: "Firmware",
        icon: "",
        kind: "update",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-update-firmware"
      },
      {
        itemId: "update.time",
        label: "Time",
        icon: "",
        kind: "update",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-update-time"
      }
    )
    return { title: root.title, rows: rows }
  }

  signal changed()

  function isUpdateMenu(menuId) {
    return String(menuId || "") === root.itemId
  }

  function load() {
    if (!whenProc.running)
      whenProc.running = true
  }

  function run(command) {
    var cmd = String(command || "").trim()
    if (!cmd)
      return false
    Quickshell.execDetached(["bash", "-lc", cmd])
    return true
  }

  Component.onCompleted: root.load()

  Process {
    id: whenProc
    // Same `when` checks as omarchy-menu.jsonc Update entries.
    command: [
      "bash", "-lc",
      "themes=0; "
        + "if omarchy-theme-extras >/dev/null 2>&1; then themes=1; fi; "
        + "printf '%s\\n' \"$themes\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.themesExtrasAvailable = String(text || "").replace(/\r?\n$/, "").trim() === "1"
        root.changed()
      }
    }
  }
}
