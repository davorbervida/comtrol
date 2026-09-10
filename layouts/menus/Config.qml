import Quickshell
import Quickshell.Io
import QtQuick

// Root → Config — Channel, password, timezone, plugins, default apps, and related settings.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  readonly property string itemId: "config"
  readonly property string label: "Config"
  readonly property string icon: ""
  readonly property string title: "Config"

  property string currentChannel: ""

  readonly property string channelItemId: "config.channel"
  readonly property string passwordItemId: "config.password"

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
        itemId: root.channelItemId,
        label: "Channel",
        icon: "󰔫",
        kind: "menu",
        status: root.channelStatus()
      },
      {
        itemId: root.passwordItemId,
        label: "Password",
        icon: "",
        kind: "menu"
      },
      {
        itemId: "config.timezone",
        label: "Timezone",
        icon: "",
        kind: "config",
        command: "omarchy-menu-timezone"
      },
      {
        itemId: "config.plugins",
        label: "Plugins",
        icon: "󰐱",
        kind: "action",
        domain: "plugins",
        mode: "local"
      }
    ]
  })

  readonly property var channelMenu: ({
    title: "Channel",
    rows: [
      {
        itemId: "config.channel.stable",
        label: "Stable",
        icon: "🟢",
        kind: "config",
        command: "omarchy-launch-floating-terminal-with-presentation 'omarchy-channel-set stable'",
        status: root.currentChannel === "stable" ? "✓" : ""
      },
      {
        itemId: "config.channel.rc",
        label: "RC",
        icon: "🟡",
        kind: "config",
        command: "omarchy-launch-floating-terminal-with-presentation 'omarchy-channel-set rc'",
        status: root.currentChannel === "rc" ? "✓" : ""
      },
      {
        itemId: "config.channel.edge",
        label: "Edge",
        icon: "🟠",
        kind: "config",
        command: "omarchy-launch-floating-terminal-with-presentation 'omarchy-channel-set edge'",
        status: root.currentChannel === "edge" ? "✓" : ""
      },
      {
        itemId: "config.channel.dev",
        label: "Dev",
        icon: "🔴",
        kind: "config",
        command: "omarchy-launch-floating-terminal-with-presentation 'omarchy-channel-set dev'",
        status: root.currentChannel === "dev" ? "✓" : ""
      }
    ]
  })

  readonly property var passwordMenu: ({
    title: "Password",
    rows: [
      {
        itemId: "config.password.drive",
        label: "Drive Encryption",
        icon: "",
        kind: "config",
        command: "omarchy-launch-floating-terminal-with-presentation omarchy-drive-password"
      },
      {
        itemId: "config.password.user",
        label: "User",
        icon: "",
        kind: "config",
        command: "omarchy-launch-floating-terminal-with-presentation passwd"
      }
    ]
  })

  signal changed()

  function channelStatus() {
    var cur = String(root.currentChannel || "").trim()
    if (!cur)
      return ""
    if (cur === "stable")
      return "Stable"
    if (cur === "rc")
      return "RC"
    if (cur === "edge")
      return "Edge"
    if (cur === "dev")
      return "Dev"
    return cur
  }

  function isConfigMenu(menuId) {
    var id = String(menuId || "")
    return id === root.itemId
      || id === root.channelItemId
      || id === root.passwordItemId
  }

  function load() {
    if (!channelProc.running)
      channelProc.running = true
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
    id: channelProc
    command: [
      "bash", "-lc",
      "printf '%s\\n' \"$(omarchy-channel-current 2>/dev/null | tr -d '\\n')\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.currentChannel = String(text || "").replace(/\r?\n$/, "").trim()
        root.changed()
      }
    }
  }
}
