import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Io
import qs.Commons
import "../../functions"

// Skewed coverflow for background images (listing only — mirrors PreviewTheme visuals).
Item {
  id: root

  // [{ path }]
  property var backgrounds: []
  property string mode: "current"
  property int selectedIndex: 0
  property bool layoutSettled: false
  property int pendingRemoveSerial: -1

  property color dimColor: Color.background
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder

  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28

  signal backRequested()
  signal dismissRequested()
  signal indexChanged(int index)
  signal refreshRequested()

  function jsonField(obj, key) {
    if (!obj)
      return ""
    var value = obj[key]
    if (value === undefined || value === null)
      return ""
    return String(value)
  }

  function clear() {
    root.backgrounds = []
    root.selectedIndex = 0
    root.pendingRemoveSerial = -1
    if (applyProc.running)
      applyProc.running = false
  }

  function loadFromData(items) {
    var next = []
    var list = items || []
    for (var b = 0; b < list.length; b++) {
      var bg = list[b] || {}
      var path = root.jsonField(bg, "path")
      if (!path)
        continue
      next.push({ path: path })
    }
    root.backgrounds = next
  }

  function applyBackground(background) {
    if (!background)
      return
    var path = String(background.path || background["path"] || "")
    if (!path)
      return
    if (applyProc.running)
      applyProc.running = false
    applyProc.command = ["omarchy-theme-bg-set", path]
    applyProc.running = true
  }

  function removeBackground(background) {
    if (!background)
      return
    var path = String(background.path || background["path"] || "")
    if (!path)
      return
    root.pendingRemoveSerial = Backgrounds.remove(path)
    if (root.pendingRemoveSerial < 0)
      return
    // Drop from UI immediately; refresh reconciles after Process finishes.
    var next = []
    var list = root.backgrounds || []
    for (var i = 0; i < list.length; i++) {
      if (String((list[i] && list[i].path) || "") === path)
        continue
      next.push(list[i])
    }
    var prev = root.selectedIndex
    root.backgrounds = next
    if (next.length === 0)
      root.selectedIndex = 0
    else if (prev >= next.length)
      root.selectedIndex = next.length - 1
  }

  Connections {
    target: Backgrounds
    function onRemoveFinished(exitCode, serial, payload) {
      if (serial !== root.pendingRemoveSerial)
        return
      root.pendingRemoveSerial = -1
      root.refreshRequested()
    }
  }

  Process {
    id: applyProc
  }

  readonly property var imageArray: {
    var out = []
    var list = root.backgrounds || []
    for (var i = 0; i < list.length; i++) {
      var b = list[i] || {}
      var path = b.path || b["path"] || ""
      if (!path)
        continue
      out.push({
        path: path,
        thumbnailPath: path
      })
    }
    return out
  }

  onBackgroundsChanged: {
    root.layoutSettled = false
    root.selectedIndex = 0
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
    if (item && item.path)
      root.applyBackground(item)
  }

  function removeSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= imageArray.length)
      return
    var item = imageArray[root.selectedIndex]
    if (item && item.path)
      root.removeBackground(item)
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      root.layoutSettled = true
      if (root.visible && imageArray.length > 0)
        carousel.forceActiveFocus()
    })
  }

  function focusCarousel() {
    if (root.visible)
      carousel.forceActiveFocus()
  }

  Component.onCompleted: revealWhenSettled()
  onVisibleChanged: if (visible) {
    root.revealWhenSettled()
    root.focusCarousel()
  }

  Item {
    id: card
    visible: root.layoutSettled && imageArray.length > 0
    width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
    height: root.expandedHeight
    anchors.centerIn: parent

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: carousel
      anchors.centerIn: parent
      width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
      height: root.expandedHeight
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
        } else if (event.key === Qt.Key_R && ((event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.ShiftModifier))) {
          root.removeSelected()
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
  }
}
