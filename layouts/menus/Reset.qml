import Quickshell
import QtQuick

// Root → Reset — Hardware / Process / Config reset actions from Omarchy Update.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  readonly property string itemId: "reset"
  readonly property string label: "Reset"
  readonly property string icon: "󰑓"
  readonly property string title: "Reset"

  readonly property string configItemId: "reset.config"
  readonly property string processItemId: "reset.process"
  readonly property string hardwareItemId: "reset.hardware"

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property var menu: ({
    title: root.title,
    rows: [
      {
        itemId: root.configItemId,
        label: "Config",
        icon: "",
        kind: "menu"
      },
      {
        itemId: root.processItemId,
        label: "Process",
        icon: "",
        kind: "menu"
      },
      {
        itemId: root.hardwareItemId,
        label: "Hardware",
        icon: "󰇅",
        kind: "menu"
      }
    ]
  })

  readonly property var configMenu: ({
    title: "Reset to default",
    rows: [
      {
        itemId: "reset.config.hyprland",
        label: "Hyprland",
        icon: "",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-hyprland"
      },
      {
        itemId: "reset.config.hyprsunset",
        label: "Hyprsunset",
        icon: "",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-hyprsunset"
      },
      {
        itemId: "reset.config.plymouth",
        label: "Plymouth",
        icon: "󱣴",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-plymouth"
      },
      {
        itemId: "reset.config.tmux",
        label: "Tmux",
        icon: "",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-tmux"
      },
      {
        itemId: "reset.config.shell",
        label: "Shell",
        icon: "󰍜",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-shell"
      }
    ]
  })

  readonly property var processMenu: ({
    title: "Restart",
    rows: [
      {
        itemId: "reset.process.hyprsunset",
        label: "Hyprsunset",
        icon: "",
        kind: "reset",
        command: "omarchy-restart-hyprsunset"
      },
      {
        itemId: "reset.process.shell",
        label: "Shell",
        icon: "󰍜",
        kind: "reset",
        command: "omarchy-restart-shell"
      }
    ]
  })

  readonly property var hardwareMenu: ({
    title: "Restart",
    rows: [
      {
        itemId: "reset.hardware.audio",
        label: "Audio",
        icon: "",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-audio"
      },
      {
        itemId: "reset.hardware.wifi",
        label: "Wi-Fi",
        icon: "󱚾",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-wifi"
      },
      {
        itemId: "reset.hardware.bluetooth",
        label: "Bluetooth",
        icon: "󰂯",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-bluetooth"
      },
      {
        itemId: "reset.hardware.trackpad",
        label: "Trackpad",
        icon: "󰟸",
        kind: "reset",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-trackpad"
      }
    ]
  })

  function isResetMenu(menuId) {
    var id = String(menuId || "")
    return id === root.itemId
      || id === root.configItemId
      || id === root.processItemId
      || id === root.hardwareItemId
  }

  function run(command) {
    var cmd = String(command || "").trim()
    if (!cmd)
      return false
    Quickshell.execDetached(["bash", "-lc", cmd])
    return true
  }
}
