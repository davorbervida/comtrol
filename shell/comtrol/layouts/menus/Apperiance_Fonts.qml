import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Appearance → Fonts: installed font list (Change) and 1px text-size slider.
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
  readonly property string changeItemId: "fonts.change"
  readonly property string sizeItemId: "fonts.size"
  readonly property string label: "Fonts"
  readonly property string icon: ""
  readonly property string title: "Fonts"

  readonly property int minSize: 9
  readonly property int maxSize: 20
  readonly property int sliderRowHeight: Math.max(
    Style.space(72),
    Style.font.caption + Style.spacing.controlGap + Math.max(Style.space(22), Math.round(Style.spacing.controlHeight * 0.38) + Style.spacing.md)
  )

  property var fontRows: []
  property string currentFont: ""
  property bool loadingFonts: false
  property bool fontsReady: false
  property bool awaitingList: false
  property int previewSize: -1
  property int pendingSize: -1
  property int appliedSize: -1

  readonly property int liveSize: Math.round(Number(Style.font.baseSize))
  readonly property int displayedSize: {
    if (root.previewSize >= 0)
      return root.previewSize
    return Math.max(root.minSize, Math.min(root.maxSize, root.liveSize))
  }
  readonly property int currentIndex: {
    var rows = root.fontRows || []
    for (var i = 0; i < rows.length; i++) {
      if (String((rows[i] && rows[i].label) || "") === root.currentFont)
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
      { itemId: root.changeItemId, label: root.awaitingList ? "Loading…" : "Change", icon: "", kind: "menu" },
      { itemId: root.sizeItemId, label: "Size", kind: "slider" }
    ]
  })

  readonly property var changeMenu: ({
    title: "Change",
    rows: root.fontRows
  })

  signal fontsChanged()

  onLiveSizeChanged: {
    if (root.previewSize >= 0 && root.liveSize === root.previewSize)
      root.previewSize = -1
  }

  function loadFonts() {
    if (listProc.running)
      return
    listProc.running = true
  }

  function applyFontList(text) {
    var current = ""
    var seen = ({})
    var rows = []
    var rawLines = String(text || "").split("\n")
    for (var i = 0; i < rawLines.length; i++) {
      var raw = String(rawLines[i] || "").trim()
      if (!raw)
        continue
      var tab = raw.indexOf("\t")
      var name = (tab >= 0 ? raw.substring(0, tab) : raw).trim()
      if (!name || seen[name])
        continue
      seen[name] = true
      if (tab >= 0 && !current)
        current = raw.substring(tab + 1).trim()
      rows.push({
        itemId: name,
        label: name,
        icon: "",
        kind: "font",
        detail: "",
        domain: "",
        mode: ""
      })
    }
    if (current)
      root.currentFont = current
    for (var j = 0; j < rows.length; j++)
      rows[j].icon = (rows[j].label === root.currentFont) ? "✓" : ""
    root.fontRows = rows
    root.loadingFonts = false
    root.fontsReady = true
    root.fontsChanged()
  }

  function setFont(name) {
    var fontName = String(name || "").trim()
    if (!fontName)
      return
    setFontProc.command = ["omarchy-font-set", fontName]
    if (setFontProc.running)
      setFontProc.running = false
    setFontProc.running = true
  }

  function setSize(px) {
    var next = Math.round(Number(px))
    if (!isFinite(next))
      return
    next = Math.max(root.minSize, Math.min(root.maxSize, next))
    root.previewSize = next
    if (next === root.liveSize && !sizeProc.running) {
      root.pendingSize = -1
      return
    }
    root.pendingSize = next
    root.flushSize()
  }

  function adjustSize(delta) {
    root.setSize(root.displayedSize + delta)
  }

  function flushSize() {
    if (sizeProc.running)
      return
    if (root.pendingSize < 0 || root.pendingSize === root.appliedSize)
      return
    root.appliedSize = root.pendingSize
    sizeProc.command = ["omarchy-display-text-size", String(root.pendingSize)]
    sizeProc.running = true
  }

  Component.onCompleted: root.loadFonts()

  Process {
    id: listProc
    command: ["bash", "-c",
      "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while IFS= read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\n' \"$f\" \"$current\"; done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFontList(text)
    }
    onStarted: root.loadingFonts = true
    onExited: {
      if (!root.fontsReady)
        root.applyFontList("")
    }
  }

  Process {
    id: setFontProc
  }

  Process {
    id: sizeProc
    onExited: {
      if (root.pendingSize >= 0 && root.pendingSize !== root.appliedSize)
        root.flushSize()
      else if (root.pendingSize === root.appliedSize)
        root.pendingSize = -1
    }
  }

  Component {
    id: sliderRowComponent

    Item {
      id: sliderRow
      property bool hasCursor: false

      readonly property color ink: sliderRow.hasCursor ? root.selectedText : root.foreground

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
            text: "TEXT SIZE"
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
            text: (sizeSlider.dragging ? Math.round(sizeSlider.liveValue) : root.displayedSize) + "px"
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
          value: root.displayedSize
          fillColor: sliderRow.ink
          knobColor: sliderRow.ink
          trackColor: Qt.rgba(sliderRow.ink.r, sliderRow.ink.g, sliderRow.ink.b, 0.22)
          tickColor: root.background
          onReleased: function(v) { root.setSize(Math.round(v)) }
        }
      }
    }
  }

  readonly property Component sliderDelegate: sliderRowComponent
}
