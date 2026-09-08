import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

// Omarchy-style skewed coverflow for local theme previews (mirrors omarchy.image-picker).
Item {
  id: root

  // [{ name, preview, path, source }]
  property var themes: []
  property string mode: "local" // "local" | "web"
  property string filterText: ""
  property int selectedIndex: 0
  property bool layoutSettled: false

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
  // Same vertical budget as the name under the carousel (display + margins).
  readonly property int topChromeHeight: mode === "local" ? 74 : Style.space(30)
  readonly property int bottomChromeHeight: filterText ? 104 : 74

  signal backRequested()
  signal themeActivated(var theme)
  signal themeRemoveRequested(var theme)
  signal filterChanged(string text)
  signal indexChanged(int index)

  readonly property var imageArray: {
    var out = []
    var list = root.themes || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i] || {}
      var preview = t.preview || t["preview"] || ""
      if (!preview)
        continue
      var name = t.name || t["name"] || ""
      out.push({
        name: name,
        preview: preview,
        path: t.path || t["path"] || "",
        source: t.source || t["source"] || "",
        filePath: preview,
        fileName: name,
        thumbnailPath: preview,
        theme: t
      })
    }
    return out
  }

  onThemesChanged: {
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

  function labelForName(name) {
    var n = String(name || "")
    // Web catalog names look like omarchy-foo-theme — show "Foo".
    n = n.replace(/^omarchy-/i, "").replace(/-theme$/i, "")
    return n
      .replace(/[-_]+/g, " ")
      .replace(/\b\w/g, function(m) { return m.toUpperCase() })
  }

  // Title-only substring match (case-insensitive). "ma" matches "Matte", not letter-by-letter fuzz.
  function itemMatches(index) {
    if (index < 0 || index >= imageArray.length)
      return false
    var needle = String(root.filterText || "").trim().toLowerCase().replace(/[-_]+/g, " ")
    if (!needle)
      return true
    var title = labelForName(imageArray[index].name || "").toLowerCase()
    return title.indexOf(needle) !== -1
  }

  function firstMatchingIndex() {
    for (var i = 0; i < imageArray.length; i++) {
      if (itemMatches(i))
        return i
    }
    return -1
  }

  function filteredPosition(index) {
    if (!root.filterText)
      return index
    var position = 0
    for (var i = 0; i < index; i++) {
      if (itemMatches(i))
        position++
    }
    return position
  }

  function selectedFilteredPosition() {
    if (!root.filterText)
      return root.selectedIndex
    return itemMatches(root.selectedIndex)
      ? filteredPosition(root.selectedIndex)
      : 0
  }

  function currentLabel() {
    if (imageArray.length === 0 || !itemMatches(root.selectedIndex))
      return root.filterText ? "No matches" : ""
    return labelForName(imageArray[root.selectedIndex].name)
  }

  function currentSourceLabel() {
    if (root.mode !== "local")
      return ""
    if (imageArray.length === 0 || !itemMatches(root.selectedIndex))
      return ""
    var src = String(imageArray[root.selectedIndex].source || "").toLowerCase()
    if (src === "user")
      return "User"
    if (src === "first_party")
      return "System"
    return ""
  }

  function select(index) {
    if (imageArray.length === 0)
      return
    if (index < 0)
      index = 0
    else if (index >= imageArray.length)
      index = imageArray.length - 1
    if (!itemMatches(index))
      return
    if (index === root.selectedIndex)
      return
    root.selectedIndex = index
    root.indexChanged(index)
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0)
      return
    var index = root.selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        root.select(index)
        return
      }
    }
  }

  function updateFilter(text) {
    root.filterText = text
    root.filterChanged(text)
    if (!itemMatches(root.selectedIndex)) {
      var next = firstMatchingIndex()
      if (next >= 0)
        root.select(next)
    }
  }

  function activateSelected() {
    if (!itemMatches(root.selectedIndex))
      return
    var item = imageArray[root.selectedIndex]
    if (item)
      root.themeActivated(item.theme || item)
  }

  function removeSelected() {
    if (root.mode !== "local")
      return
    if (!itemMatches(root.selectedIndex))
      return
    var item = imageArray[root.selectedIndex]
    if (item)
      root.themeRemoveRequested(item.theme || item)
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      if (root.visible && imageArray.length > 0) {
        root.layoutSettled = true
        carousel.forceActiveFocus()
      }
    })
  }

  function focusCarousel() {
    if (root.visible && root.layoutSettled)
      carousel.forceActiveFocus()
  }

  Component.onCompleted: revealWhenSettled()
  onVisibleChanged: if (visible) revealWhenSettled()

  Item {
    id: card
    visible: root.layoutSettled && imageArray.length > 0
    width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
    height: root.expandedHeight + root.topChromeHeight + root.bottomChromeHeight
    anchors.centerIn: parent

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: carousel
      anchors.top: parent.top
      anchors.topMargin: root.topChromeHeight
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
          if (root.filterText)
            root.updateFilter("")
          else
            root.backRequested()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
          root.removeSelected()
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.updateFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
          root.selectAdjacent(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
          root.selectAdjacent(1)
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.updateFilter(root.filterText + event.text)
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

          readonly property bool matched: root.itemMatches(index)
          readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
          readonly property bool selected: matched && index === root.selectedIndex
          readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16
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
      visible: root.mode === "local" && text.length > 0
      anchors.bottom: carousel.top
      anchors.bottomMargin: Style.space(16)
      anchors.horizontalCenter: carousel.horizontalCenter
      width: root.expandedWidth
      text: root.currentSourceLabel()
      color: root.foreground
      style: Text.Outline
      styleColor: Util.alpha(root.dimColor, 0.7)
      font.pixelSize: Style.font.display
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
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

    Text {
      textFormat: Text.PlainText
      visible: root.filterText.length > 0
      anchors.top: carousel.bottom
      anchors.topMargin: Style.space(16) + Style.font.display + Style.space(8)
      anchors.horizontalCenter: carousel.horizontalCenter
      width: root.expandedWidth
      text: root.filterText
      color: root.foreground
      opacity: 0.85
      style: Text.Outline
      styleColor: Util.alpha(root.dimColor, 0.7)
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.layoutSettled && imageArray.length === 0
    text: "No theme previews"
    color: root.foreground
    opacity: 0.5
    font.pixelSize: Style.font.body
  }
}
