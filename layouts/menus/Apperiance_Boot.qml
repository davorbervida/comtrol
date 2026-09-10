import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Io
import qs.Commons

// Appearance → Unlock: Omarchy plymouth coverflow (preview-unlock.png) with apply.
Item {
  id: root

  property var unlocks: []
  property int selectedIndex: 0
  property int pendingSelectedIndex: 0
  property int listSerial: 0
  property bool layoutSettled: false
  property bool loading: false

  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder

  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  readonly property int bottomChromeHeight: 74

  signal backRequested()
  signal dismissRequested()
  signal indexChanged(int index)

  function clear() {
    root.listSerial += 1
    root.unlocks = []
    root.selectedIndex = 0
    root.pendingSelectedIndex = 0
    root.loading = false
    if (listProc.running)
      listProc.running = false
  }

  function loadUnlocks() {
    root.listSerial += 1
    listProc.serial = root.listSerial
    if (listProc.running)
      listProc.running = false
    root.loading = true
    listProc.running = true
  }

  function applyUnlockList(text, serial) {
    if (serial !== undefined && serial !== root.listSerial)
      return
    var current = ""
    var next = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var raw = String(lines[i] || "").trim()
      if (!raw)
        continue
      var parts = raw.split("\t")
      var name = String(parts[0] || "").trim()
      var preview = String(parts[1] || "").trim()
      if (!current && parts.length > 2)
        current = String(parts[2] || "").trim()
      if (!name || !preview)
        continue
      next.push({ name: name, preview: preview, path: preview })
    }
    var selected = 0
    if (current) {
      for (var j = 0; j < next.length; j++) {
        if (next[j].name === current) {
          selected = j
          break
        }
      }
    }
    root.pendingSelectedIndex = selected
    root.unlocks = next
    root.loading = false
  }

  function applyUnlock(item) {
    if (!item)
      return
    var name = String(item.name || item["name"] || "").trim()
    if (!name)
      return
    var cmd = name === "default"
      ? "omarchy-plymouth-reset"
      : ("omarchy-plymouth-set-by-theme " + Util.shellQuote(name))
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", cmd])
    root.dismissRequested()
  }

  readonly property var imageArray: {
    var out = []
    var list = root.unlocks || []
    for (var i = 0; i < list.length; i++) {
      var u = list[i] || {}
      var preview = u.preview || u["preview"] || u.path || u["path"] || ""
      if (!preview)
        continue
      var name = u.name || u["name"] || ""
      out.push({
        name: name,
        path: preview,
        thumbnailPath: preview
      })
    }
    return out
  }

  onUnlocksChanged: {
    root.layoutSettled = false
    root.selectedIndex = root.pendingSelectedIndex
    root.revealWhenSettled()
  }

  function imageSource(path) {
    var p = String(path || "")
    if (!p)
      return ""
    if (p.indexOf("http://") === 0 || p.indexOf("https://") === 0 || p.indexOf("file://") === 0)
      return p
    return Util.fileUrl(p)
  }

  function labelForName(name) {
    var n = String(name || "")
    return n
      .replace(/[-_]+/g, " ")
      .replace(/\b\w/g, function(m) { return m.toUpperCase() })
  }

  function currentLabel() {
    if (imageArray.length === 0)
      return ""
    if (root.selectedIndex < 0 || root.selectedIndex >= imageArray.length)
      return ""
    return root.labelForName(imageArray[root.selectedIndex].name)
  }

  function select(index) {
    if (imageArray.length === 0)
      return
    if (index < 0)
      index = 0
    else if (index >= imageArray.length)
      index = imageArray.length - 1
    if (index === root.selectedIndex)
      return
    root.selectedIndex = index
    root.indexChanged(index)
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0)
      return
    root.select((root.selectedIndex + direction + count) % count)
  }

  function activateSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= imageArray.length)
      return
    var item = imageArray[root.selectedIndex]
    if (item && item.name)
      root.applyUnlock(item)
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      root.layoutSettled = true
      root.focusCarousel()
    })
  }

  function focusCarousel() {
    if (!root.visible)
      return
    if (imageArray.length > 0)
      carousel.forceActiveFocus()
    else
      emptyCatcher.forceActiveFocus()
  }

  Component.onCompleted: root.revealWhenSettled()
  onVisibleChanged: if (visible) {
    root.revealWhenSettled()
    root.focusCarousel()
  }

  Process {
    id: listProc
    property int serial: 0
    command: ["bash", "-c",
      "current=$(omarchy-plymouth-current 2>/dev/null); " +
      "omarchy_path=\"${OMARCHY_PATH:-/usr/share/omarchy}\"; " +
      "default_preview=\"$omarchy_path/default/plymouth/preview-unlock.png\"; " +
      "[[ -f $default_preview ]] && printf 'default\\t%s\\t%s\\n' \"$default_preview\" \"$current\"; " +
      "omarchy-plymouth-list 2>/dev/null | while IFS= read -r name; do " +
      "[[ -z $name ]] && continue; " +
      "dir=$(omarchy-theme-dir \"$name\" 2>/dev/null) || continue; " +
      "preview=\"$dir/preview-unlock.png\"; " +
      "[[ -f $preview ]] || continue; " +
      "printf '%s\\t%s\\t%s\\n' \"$name\" \"$preview\" \"$current\"; " +
      "done"
    ]
    stdout: StdioCollector {
      id: listCollector
      waitForEnd: true
      onStreamFinished: root.applyUnlockList(text, listProc.serial)
    }
    onStarted: root.loading = true
    onExited: {
      if (listProc.serial !== root.listSerial)
        return
      if (root.loading)
        root.applyUnlockList(listCollector.text, listProc.serial)
    }
  }

  Item {
    id: card
    visible: root.layoutSettled && imageArray.length > 0
    width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
    height: root.expandedHeight + root.bottomChromeHeight
    anchors.centerIn: parent

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: carousel
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.bottomChromeHeight
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
      clip: false
      focus: true

      readonly property real itemStep: root.sliceWidth + root.sliceSpacing
      readonly property real previewX: (width - root.expandedWidth) / 2

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismissRequested()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          root.backRequested()
          event.accepted = true
        } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
          root.selectAdjacent(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
          root.selectAdjacent(1)
          event.accepted = true
        }
      }

      Component.onCompleted: forceActiveFocus()

      Repeater {
        model: root.imageArray.length

        delegate: Item {
          id: item
          required property int index

          readonly property var imageData: root.imageArray[index]
          readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""
          readonly property int relativeIndex: index - root.selectedIndex
          readonly property bool selected: index === root.selectedIndex
          readonly property bool nearby: Math.abs(relativeIndex) <= 16
          property bool sourceActivated: nearby
          onNearbyChanged: if (nearby) sourceActivated = true

          visible: nearby
          x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
          width: selected ? root.expandedWidth : root.sliceWidth
          height: selected ? root.expandedHeight : root.sliceHeight
          y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
          z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

          readonly property real skAbs: Math.abs(root.skewOffset)
          readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
          readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
          readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
          readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

          Item {
            id: maskShape
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "white"
                strokeColor: "transparent"
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }
          }

          Item {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: maskShape
              maskThresholdMin: 0.3
              maskSpreadAtMin: 0.3
            }

            Image {
              anchors.fill: parent
              source: item.sourceActivated && item.thumbnailPath ? root.imageSource(item.thumbnailPath) : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              smooth: true
            }

            Rectangle {
              anchors.fill: parent
              color: Util.alpha(root.dimColor, item.selected ? 0 : 0.42)
            }
          }

          Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "transparent"
              strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
              strokeWidth: item.selected ? 3 : 1
              startX: item.topLeft; startY: 0
              PathLine { x: item.topRight; y: 0 }
              PathLine { x: item.bottomRight; y: item.height }
              PathLine { x: item.bottomLeft; y: item.height }
              PathLine { x: item.topLeft; y: 0 }
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: item.selected ? root.activateSelected() : root.select(index)
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.top: carousel.bottom
      anchors.topMargin: Style.space(16)
      anchors.horizontalCenter: carousel.horizontalCenter
      width: root.expandedWidth
      text: root.currentLabel()
      color: root.foreground
      style: Text.Outline
      styleColor: Util.alpha(root.dimColor, 0.7)
      font.pixelSize: Style.font.display
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  Item {
    id: emptyCatcher
    anchors.fill: parent
    visible: root.layoutSettled && imageArray.length === 0
    focus: visible

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.dismissRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_Backspace) {
        root.backRequested()
        event.accepted = true
      }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.loading ? "Loading…" : "No unlock previews"
      color: root.foreground
      opacity: 0.5
      font.pixelSize: Style.font.body
    }
  }
}
