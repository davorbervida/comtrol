import QtQuick
import qs.Commons

// Plugin catalog grid for Plugins → Add — fixed preview size, as many columns as fit.
Item {
  id: root

  // [{ id, name, version, author, repo, preview, description, install_command, ... }]
  property var plugins: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool layoutSettled: false

  property color dimColor: Color.background
  property color foreground: Color.menu.text
  property color cardBackground: Color.menu.background
  property color selectedBorder: Color.menu.selectedBorder
  property color unselectedBorder: Color.menu.border
  property color selectedBackground: Color.menu.selectedBackground

  property int gridGap: Style.space(14)
  property int cellPad: Style.space(12)
  property int previewWidth: 300
  property int previewHeight: 150
  property int authorBottomMargin: Style.space(12)
  property int columns: 3
  readonly property int textBlockHeight: Style.space(132) + authorBottomMargin
  readonly property int cardInnerWidth: previewWidth + cellPad * 2
  readonly property int cardInnerHeight: previewHeight + cellPad * 2 + textBlockHeight
  readonly property int bottomChromeHeight: filterText ? Style.space(96) : Style.space(64)
  readonly property int gridContentWidth: columns * (cardInnerWidth + gridGap)

  signal backRequested()
  signal pluginActivated(var plugin)
  signal filterChanged(string text)
  signal indexChanged(int index)
  signal dismissRequested()

  readonly property var filteredPlugins: {
    var out = []
    var list = root.plugins || []
    var needle = String(root.filterText || "").trim().toLowerCase()
    for (var i = 0; i < list.length; i++) {
      var p = list[i] || {}
      if (needle) {
        var tagStr = ""
        var tags = p.tags || []
        if (tags && tags.length !== undefined) {
          for (var ti = 0; ti < tags.length; ti++)
            tagStr += " " + tags[ti]
        }
        var hay = [
          p.name || "",
          p.id || "",
          p.author || "",
          p.repo || "",
          p.version || "",
          p.description || "",
          tagStr
        ].join(" ").toLowerCase()
        if (hay.indexOf(needle) < 0)
          continue
      }
      out.push(p)
    }
    return out
  }

  onPluginsChanged: {
    root.layoutSettled = false
    root.selectedIndex = 0
    root.revealWhenSettled()
  }

  onFilterTextChanged: {
    if (root.selectedIndex >= filteredPlugins.length)
      root.selectedIndex = Math.max(0, filteredPlugins.length - 1)
    if (filteredPlugins.length > 0 && root.selectedIndex < 0)
      root.selectedIndex = 0
  }

  function imageSource(path) {
    var p = String(path || "")
    if (!p)
      return ""
    if (p.indexOf("http://") === 0 || p.indexOf("https://") === 0 || p.indexOf("file://") === 0)
      return p
    return Util.fileUrl(p)
  }

  function updateFilter(text) {
    root.filterText = text
    root.filterChanged(text)
  }

  function select(index) {
    if (filteredPlugins.length === 0)
      return
    if (index < 0)
      index = 0
    else if (index >= filteredPlugins.length)
      index = filteredPlugins.length - 1
    if (index === root.selectedIndex)
      return
    root.selectedIndex = index
    root.indexChanged(index)
    grid.positionViewAtIndex(index, GridView.Contain)
  }

  function selectDelta(delta) {
    if (filteredPlugins.length === 0)
      return
    root.select(root.selectedIndex + delta)
  }

  function selectRow(direction) {
    root.selectDelta(direction * root.columns)
  }

  function activateSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= filteredPlugins.length)
      return
    var plugin = filteredPlugins[root.selectedIndex]
    if (plugin)
      root.pluginActivated(plugin)
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      if (root.visible) {
        root.layoutSettled = true
        grid.forceActiveFocus()
      }
    })
  }

  function focusGrid() {
    if (root.visible && root.layoutSettled)
      grid.forceActiveFocus()
  }

  Component.onCompleted: revealWhenSettled()
  onVisibleChanged: if (visible) revealWhenSettled()

  Item {
    id: frame
    visible: root.layoutSettled
    anchors.fill: parent
    anchors.margins: Style.gapsOut

    MouseArea { anchors.fill: parent; onClicked: {} }

    GridView {
      id: grid
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.bottomChromeHeight
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, root.gridContentWidth)
      clip: true
      focus: true
      cellWidth: root.cardInnerWidth + root.gridGap
      cellHeight: root.cardInnerHeight + root.gridGap
      model: root.filteredPlugins
      boundsBehavior: Flickable.StopAtBounds
      keyNavigationEnabled: false
      leftMargin: 0
      rightMargin: 0

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismissRequested()
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.selectDelta(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.selectDelta(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectRow(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.selectRow(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.updateFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
          root.backRequested()
          event.accepted = true
        } else if (event.text && event.text.length === 1
                   && event.text.charCodeAt(0) >= 32
                   && event.text.charCodeAt(0) !== 127
                   && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
          root.updateFilter(root.filterText + event.text)
          event.accepted = true
        }
      }

      delegate: Item {
        id: cell
        width: grid.cellWidth
        height: grid.cellHeight

        required property int index
        required property var modelData

        readonly property var plugin: modelData || ({})
        readonly property bool selected: root.selectedIndex === index
        readonly property string preview: String(plugin.preview || plugin.preview_image || "")
        readonly property string tagsText: {
          var tags = plugin.tags || []
          var parts = []
          if (tags && tags.length !== undefined) {
            for (var i = 0; i < tags.length; i++)
              parts.push(String(tags[i]))
          }
          return parts.join(" · ")
        }
        readonly property string statsText: {
          var hearts = Number(plugin.hearts || 0)
          var stars = Number(plugin.stars || 0)
          return "♥ " + hearts + "   ★ " + stars
        }

        Rectangle {
          width: root.cardInnerWidth
          height: root.cardInnerHeight
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: root.gridGap / 2
          radius: Style.cornerRadius
          color: cell.selected ? root.selectedBackground : root.cardBackground
          border.width: cell.selected ? Math.max(2, Style.space(2)) : 1
          border.color: cell.selected ? root.selectedBorder : root.unselectedBorder

          Column {
            anchors.fill: parent
            anchors.leftMargin: root.cellPad
            anchors.rightMargin: root.cellPad
            anchors.topMargin: root.cellPad
            anchors.bottomMargin: root.cellPad + root.authorBottomMargin
            spacing: Style.space(6)

            Item {
              width: root.previewWidth
              height: root.previewHeight
              anchors.horizontalCenter: parent.horizontalCenter

              Rectangle {
                anchors.fill: parent
                radius: Math.max(4, Style.cornerRadius - 2)
                color: Util.alpha(root.foreground, 0.06)
                visible: !cell.preview
              }

              Image {
                anchors.fill: parent
                visible: !!cell.preview
                source: cell.preview ? root.imageSource(cell.preview) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(cell.plugin.name || cell.plugin.id || "Plugin")
              color: root.foreground
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(cell.plugin.version || "")
              visible: text.length > 0
              color: root.foreground
              opacity: 0.72
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(cell.plugin.author || "")
              visible: text.length > 0
              color: root.foreground
              opacity: 0.72
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: cell.tagsText
              visible: text.length > 0
              color: root.foreground
              opacity: 0.62
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: cell.statsText
              color: root.foreground
              opacity: 0.72
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(cell.plugin.repo || "")
              visible: text.length > 0
              color: root.foreground
              opacity: 0.55
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
              bottomPadding: root.authorBottomMargin
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) root.select(index)
            onClicked: {
              root.select(index)
              root.activateSelected()
            }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.filterText ? Style.space(40) : Style.space(18)
      width: Math.min(parent.width * 0.6, Style.space(640))
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: filteredPlugins.length === 0
        ? (root.filterText ? "No matches" : "No plugins")
        : ""
      visible: text.length > 0
      color: root.foreground
      opacity: 0.5
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(14)
      width: Math.min(parent.width * 0.6, Style.space(640))
      horizontalAlignment: Text.AlignHCenter
      visible: root.filterText.length > 0
      textFormat: Text.PlainText
      text: root.filterText
      color: root.foreground
      opacity: 0.85
      font.pixelSize: Style.font.title
      style: Text.Outline
      styleColor: Util.alpha(root.dimColor, 0.7)
      elide: Text.ElideRight
    }
  }
}
