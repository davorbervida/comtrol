import Quickshell
import Quickshell.Io
import QtQuick

// Power menu — mirrors Omarchy menu "System" actions/icons/conditions.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  readonly property string itemId: "power"
  readonly property string label: "Power"
  readonly property string icon: ""
  readonly property string title: "Power"

  property bool suspendAvailable: true
  property bool hibernateAvailable: false

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property var menu: {
    var rows = [
      {
        itemId: "power.screensaver",
        label: "Screensaver",
        icon: "󱄄",
        kind: "power",
        command: "omarchy-launch-screensaver force"
      },
      {
        itemId: "power.lock",
        label: "Lock",
        icon: "",
        kind: "power",
        command: "omarchy-system-lock"
      }
    ]
    if (root.suspendAvailable) {
      rows.push({
        itemId: "power.suspend",
        label: "Suspend",
        icon: "󰒲",
        kind: "power",
        command: "systemctl suspend"
      })
    }
    if (root.hibernateAvailable) {
      rows.push({
        itemId: "power.hibernate",
        label: "Hibernate",
        icon: "󰤁",
        kind: "power",
        command: "systemctl hibernate"
      })
    }
    rows.push(
      {
        itemId: "power.logout",
        label: "Logout",
        icon: "󰍃",
        kind: "power",
        command: "omarchy-system-logout"
      },
      {
        itemId: "power.reboot",
        label: "Reboot",
        icon: "󰜉",
        kind: "power",
        command: "omarchy-system-reboot"
      },
      {
        itemId: "power.shutdown",
        label: "Shutdown",
        icon: "󰐥",
        kind: "power",
        command: "omarchy-system-shutdown"
      }
    )
    return { title: root.title, rows: rows }
  }

  signal changed()

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
    // Same `when` checks as omarchy-menu.jsonc System entries.
    command: [
      "bash", "-lc",
      "suspend=0; hibernate=0; "
        + "if ! omarchy-toggle-enabled suspend-off >/dev/null 2>&1; then suspend=1; fi; "
        + "if omarchy-hibernation-available >/dev/null 2>&1; then hibernate=1; fi; "
        + "printf '%s\\t%s\\n' \"$suspend\" \"$hibernate\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split("\t")
        root.suspendAvailable = String(parts[0] || "0") === "1"
        root.hibernateAvailable = String(parts[1] || "0") === "1"
        root.changed()
      }
    }
  }
}
