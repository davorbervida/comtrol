import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons

// Appearance → Shell: bar position/transparency and shell font.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property string itemId: "shell"
  readonly property string positionItemId: "shell.bar.position"
  readonly property string transparencyItemId: "shell.bar.transparency"
  readonly property string label: "Shell"
  readonly property string icon: "󰨇"
  readonly property string title: "Shell"

  property string position: "top"
  property bool transparent: false

  readonly property string positionLabel: {
    var p = String(root.position || "top").toLowerCase()
    if (p === "bottom")
      return "Bottom"
    if (p === "left")
      return "Left"
    if (p === "right")
      return "Right"
    return "Top"
  }
  readonly property string transparencyLabel: root.transparent ? "On" : "Off"

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
        itemId: root.positionItemId,
        label: "Bar position",
        icon: "",
        kind: "menu",
        status: root.positionLabel
      },
      {
        itemId: root.transparencyItemId,
        label: "Bar transparency",
        icon: "󰂵",
        kind: "bar-transparency",
        status: root.transparencyLabel
      }
    ]
  })

  readonly property var positionMenu: ({
    title: "Bar position",
    rows: [
      root.positionRow("top", "Top", "󰁝"),
      root.positionRow("bottom", "Bottom", "󰁅"),
      root.positionRow("left", "Left", "󰁍"),
      root.positionRow("right", "Right", "󰁔")
    ]
  })

  signal changed()

  function positionRow(id, name, icon) {
    return {
      itemId: id,
      label: name,
      icon: root.position === id ? "✓" : icon,
      kind: "bar-position"
    }
  }

  function applyShellJson(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      var bar = (data && data.bar) || {}
      var nextPos = String(bar.position || "top").toLowerCase()
      if (nextPos !== "top" && nextPos !== "bottom" && nextPos !== "left" && nextPos !== "right")
        nextPos = "top"
      var nextTrans = bar.transparent === true
      if (nextPos === root.position && nextTrans === root.transparent)
        return
      root.position = nextPos
      root.transparent = nextTrans
      root.changed()
    } catch (e) {
    }
  }

  function setPosition(name) {
    var p = String(name || "").toLowerCase()
    if (p !== "top" && p !== "bottom" && p !== "left" && p !== "right")
      return
    if (p === root.position)
      return
    root.position = p
    root.changed()
    Quickshell.execDetached(["omarchy-bar", "position", p])
  }

  function toggleTransparency() {
    root.transparent = !root.transparent
    root.changed()
    Quickshell.execDetached(["omarchy-bar", "transparent", "toggle"])
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellJson(text())
    onFileChanged: reload()
  }
}
