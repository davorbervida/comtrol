import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "../../functions/appearance"

// Appearance → Fonts: Shell, Terminal, and GTK family + size.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property string itemId: "fonts"
  readonly property string shellChangeId: "fonts.shell.change"
  readonly property string terminalChangeId: "fonts.terminal.change"
  readonly property string gtkChangeId: "fonts.gtk.change"
  readonly property string shellSizeId: "fonts.shell.size"
  readonly property string terminalSizeId: "fonts.terminal.size"
  readonly property string gtkSizeId: "fonts.gtk.size"
  readonly property string label: "Fonts"
  readonly property string icon: ""
  readonly property string title: "Fonts"

  readonly property int minSize: Fonts.minSize
  readonly property int maxSize: Fonts.maxSize
  readonly property int sliderRowHeight: Math.max(
    Style.space(72),
    Style.font.caption + Style.spacing.controlGap + Math.max(Style.space(22), Math.round(Style.spacing.controlHeight * 0.38) + Style.spacing.md)
  )
  readonly property int separatorRowHeight: Style.space(12)

  property var fontRows: []
  property string activeTarget: "shell"
  property bool awaitingList: false
  property int previewSize: -1
  property string previewTarget: ""

  readonly property bool loadingFonts: Fonts.loading
  readonly property bool fontsReady: root.listReadyFor(root.activeTarget)
  readonly property string currentFont: Fonts.familyOf(root.activeTarget)
  readonly property string activeChangeId: root.changeId(root.activeTarget)

  readonly property int liveShellSize: Math.round(Number(Style.font.baseSize))

  readonly property int currentIndex: {
    var rows = root.fontRows || []
    var current = String(Fonts.familyOf(root.activeTarget) || "")
    for (var i = 0; i < rows.length; i++) {
      if (String((rows[i] && rows[i].label) || "") === current)
        return i
    }
    return 0
  }

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
        itemId: root.shellChangeId,
        label: (root.awaitingList && root.activeTarget === "shell") ? "Loading…" : "Shell",
        icon: "󰨇",
        kind: "menu",
        status: Fonts.shellFamily || "—"
      },
      { itemId: root.shellSizeId, label: "Shell size", kind: "slider" },
      { itemId: "fonts.sep.terminal", kind: "separator" },
      {
        itemId: root.terminalChangeId,
        label: (root.awaitingList && root.activeTarget === "terminal") ? "Loading…" : "Terminal",
        icon: "",
        kind: "menu",
        status: Fonts.terminalFamily || "—"
      },
      { itemId: root.terminalSizeId, label: "Terminal size", kind: "slider" },
      { itemId: "fonts.sep.gtk", kind: "separator" },
      {
        itemId: root.gtkChangeId,
        label: (root.awaitingList && root.activeTarget === "gtk") ? "Loading…" : "GTK",
        icon: "󰏘",
        kind: "menu",
        status: Fonts.gtkFamily || "—"
      },
      { itemId: root.gtkSizeId, label: "GTK size", kind: "slider" }
    ]
  })

  readonly property var changeMenu: ({
    title: root.activeTarget === "terminal" ? "Terminal" : (root.activeTarget === "gtk" ? "GTK" : "Shell"),
    rows: root.fontRows
  })

  signal fontsChanged()

  onLiveShellSizeChanged: {
    if (root.previewTarget === "shell" && root.previewSize >= 0 && root.liveShellSize === root.previewSize)
      root.previewSize = -1
  }

  function targetFromId(itemId) {
    var id = String(itemId || "")
    if (id.indexOf("fonts.terminal") === 0)
      return "terminal"
    if (id.indexOf("fonts.gtk") === 0)
      return "gtk"
    return "shell"
  }

  function changeId(target) {
    if (target === "terminal")
      return root.terminalChangeId
    if (target === "gtk")
      return root.gtkChangeId
    return root.shellChangeId
  }

  function sizeId(target) {
    if (target === "terminal")
      return root.terminalSizeId
    if (target === "gtk")
      return root.gtkSizeId
    return root.shellSizeId
  }

  function isChangeItem(itemId) {
    var id = String(itemId || "")
    return id === root.shellChangeId || id === root.terminalChangeId || id === root.gtkChangeId
  }

  function isSizeSlider(itemId) {
    var id = String(itemId || "")
    return id === root.shellSizeId || id === root.terminalSizeId || id === root.gtkSizeId
  }

  function listReadyFor(target) {
    return Fonts.listKindFor(target) === "all" ? Fonts.allReady : Fonts.monoReady
  }

  function displayedSize(target) {
    var t = String(target || "shell")
    if (root.previewTarget === t && root.previewSize >= 0)
      return root.previewSize
    if (t === "shell")
      return Math.max(root.minSize, Math.min(root.maxSize, root.liveShellSize))
    return Math.max(root.minSize, Math.min(root.maxSize, Fonts.sizeOf(t)))
  }

  function rebuildRows() {
    var names = Fonts.names || []
    var current = String(Fonts.familyOf(root.activeTarget) || "")
    var rows = []
    for (var i = 0; i < names.length; i++) {
      var name = String(names[i] || "")
      if (!name)
        continue
      rows.push({
        itemId: name,
        label: name,
        icon: name === current ? "✓" : "",
        kind: "font",
        detail: "",
        domain: "",
        mode: ""
      })
    }
    root.fontRows = rows
    root.fontsChanged()
  }

  function load() {
    Fonts.load()
  }

  function openChange(changeId) {
    root.activeTarget = root.targetFromId(changeId)
    Fonts.scan(Fonts.listKindFor(root.activeTarget))
  }

  function setFont(name) {
    Fonts.setFamily(root.activeTarget, name)
  }

  function setSize(target, px) {
    var t = String(target || "shell")
    var next = Fonts.clamp(px)
    root.previewTarget = t
    root.previewSize = next
    Fonts.setSize(t, next)
    if (t !== "shell")
      root.previewSize = -1
  }

  function adjustSize(itemId, delta) {
    var t = root.targetFromId(itemId)
    root.setSize(t, root.displayedSize(t) + delta)
  }

  function groupMenus() {
    var out = ({})
    out[root.shellChangeId] = root.changeMenu
    out[root.terminalChangeId] = root.changeMenu
    out[root.gtkChangeId] = root.changeMenu
    return out
  }

  Component.onCompleted: root.load()

  Connections {
    target: Fonts
    function onListed() {
      root.rebuildRows()
    }
    function onChanged() {
      root.fontsChanged()
    }
  }

  Component {
    id: sliderRowComponent

    Item {
      id: sliderRow
      property bool hasCursor: false
      property string target: "shell"

      readonly property color ink: sliderRow.hasCursor ? root.selectedText : root.foreground
      readonly property int currentValue: root.displayedSize(sliderRow.target)

      Column {
        anchors.fill: parent
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Math.max(headerLabel.implicitHeight, sizeLabel.implicitHeight)

          Text {
            id: headerLabel
            textFormat: Text.PlainText
            text: {
              if (sliderRow.target === "terminal")
                return "TERMINAL"
              if (sliderRow.target === "gtk")
                return "GTK"
              return "SHELL"
            }
            color: sliderRow.ink
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: sizeLabel
            textFormat: Text.PlainText
            text: (sizeSlider.dragging ? Math.round(sizeSlider.liveValue) : sliderRow.currentValue)
              + (sliderRow.target === "gtk" ? "pt" : "px")
            color: sliderRow.ink
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSlider {
          id: sizeSlider
          width: parent.width
          minimum: root.minSize
          maximum: root.maxSize
          step: 1
          integer: true
          tickCount: root.maxSize - root.minSize + 1
          value: sliderRow.currentValue
          fillColor: sliderRow.ink
          knobColor: sliderRow.ink
          trackColor: Qt.rgba(sliderRow.ink.r, sliderRow.ink.g, sliderRow.ink.b, 0.22)
          tickColor: root.background
          onReleased: function(v) { root.setSize(sliderRow.target, Math.round(v)) }
        }
      }
    }
  }

  readonly property Component sliderDelegate: sliderRowComponent
}
