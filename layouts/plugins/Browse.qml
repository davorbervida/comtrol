import QtQuick
import Quickshell.Io
import qs.Commons
import "../../functions"

// Plugin catalog grid for Plugins → Add — fixed preview size, as many columns as fit.
Item {
  id: root

  // [{ id, name, version, author, repo, preview, description, install_command, ... }]
  property var plugins: []
  property var installedPluginIds: ({})
  property string filterText: ""
  property int selectedIndex: 0
  property bool layoutSettled: false
  property int installedSerial: 0
  property int catalogSerial: 0

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
  signal installedIdsChanged()
  signal catalogFinished()
  signal catalogFailed(string message)

  property bool catalogLoading: false

  function jsonField(obj, key) {
    if (!obj)
      return ""
    var value = obj[key]
    if (value === undefined || value === null)
      return ""
    return String(value)
  }

  function clear() {
    root.plugins = []
    root.installedPluginIds = ({})
    root.filterText = ""
    root.selectedIndex = 0
    root.catalogLoading = false
    root.catalogSerial += 1
    root.installedSerial += 1
    Plugins.cancel()
  }

  function loadCatalog() {
    root.catalogLoading = true
    root.plugins = []
    // Plugins.loadCatalog() may finish synchronously from cache and emit
    // before this function returns — align serials first or we drop the result
    // and Main stays stuck on loading.
    root.catalogSerial = Plugins.catalogSerial + 1
    root.installedSerial = Plugins.installedSerial + 1
    Plugins.loadCatalog()
  }

  function applyCatalogPayload(payload, fromCache) {
    var list = []
    if (payload && payload.plugins && payload.plugins.length !== undefined)
      list = payload.plugins
    else if (payload && payload.length !== undefined)
      list = payload
    root.loadFromData(list)
  }

  function loadFromData(data) {
    var plugins = []
    var list = data || []
    var ids = root.installedPluginIds || ({})
    for (var p = 0; p < list.length; p++) {
      var plugin = list[p] || {}
      var installCmd = root.jsonField(plugin, "install_command")
      var installAvailable = !!(plugin.install_available || plugin["install_available"])
      // Catalog entries without an install path are not shown in BrowsePlugins.
      if (!installCmd && !installAvailable)
        continue
      var tags = plugin.tags || plugin["tags"] || []
      var tagList = []
      if (tags && tags.length !== undefined) {
        for (var ti = 0; ti < tags.length; ti++)
          tagList.push(String(tags[ti]))
      }
      var id = root.jsonField(plugin, "id")
      plugins.push({
        id: id,
        name: root.jsonField(plugin, "name"),
        version: root.jsonField(plugin, "version"),
        author: root.jsonField(plugin, "author"),
        repo: root.jsonField(plugin, "repo"),
        description: root.jsonField(plugin, "description"),
        category: root.jsonField(plugin, "category"),
        source_type: root.jsonField(plugin, "source_type"),
        preview: root.jsonField(plugin, "preview_image"),
        install_command: installCmd,
        install_available: installAvailable,
        tags: tagList,
        hearts: plugin.hearts || plugin["hearts"] || 0,
        stars: plugin.stars || plugin["stars"] || 0,
        views: plugin.views || plugin["views"] || 0,
        copies: plugin.copies || plugin["copies"] || 0,
        installed: !!ids[id],
        mode: "web"
      })
    }
    root.plugins = plugins
  }

  function refreshInstalled() {
    root.installedSerial = Plugins.listInstalled()
  }

  function applyInstalledFlags() {
    var ids = root.installedPluginIds || ({})
    var list = root.plugins || []
    var next = []
    for (var i = 0; i < list.length; i++) {
      var copy = root.clonePlugin(list[i])
      if (!copy)
        continue
      copy.installed = !!ids[String(copy.id || "")]
      next.push(copy)
    }
    root.plugins = next
    root.installedIdsChanged()
  }

  function bumpHearts(pluginId) {
    var id = String(pluginId || "")
    if (!id)
      return
    var list = root.plugins || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id || "") === id) {
        list[i].hearts = Number(list[i].hearts || 0) + 1
        break
      }
    }
    root.plugins = list.slice()
  }

  function clonePlugin(plugin) {
    if (!plugin)
      return null
    var tags = plugin.tags || plugin["tags"] || []
    var tagList = []
    if (tags && tags.length !== undefined) {
      for (var i = 0; i < tags.length; i++)
        tagList.push(String(tags[i]))
    }
    var preview = root.jsonField(plugin, "preview")
    if (!preview)
      preview = root.jsonField(plugin, "preview_image")
    var id = root.jsonField(plugin, "id")
    return {
      id: id,
      name: root.jsonField(plugin, "name"),
      version: root.jsonField(plugin, "version"),
      author: root.jsonField(plugin, "author"),
      repo: root.jsonField(plugin, "repo"),
      description: root.jsonField(plugin, "description"),
      category: root.jsonField(plugin, "category"),
      source_type: root.jsonField(plugin, "source_type") || root.jsonField(plugin, "sourceType"),
      preview: preview,
      preview_image: preview,
      install_command: root.jsonField(plugin, "install_command"),
      install_available: !!(plugin.install_available || plugin["install_available"]),
      tags: tagList,
      hearts: Number(plugin.hearts || plugin["hearts"] || 0),
      stars: Number(plugin.stars || plugin["stars"] || 0),
      views: Number(plugin.views || plugin["views"] || 0),
      copies: Number(plugin.copies || plugin["copies"] || 0),
      installed: !!(plugin.installed || plugin["installed"]),
      mode: String(plugin.mode || "web")
    }
  }

  function pluginWithInstalled(plugin) {
    var next = root.clonePlugin(plugin)
    if (!next)
      return null
    next.installed = !!root.installedPluginIds[String(next.id || "")]
    return next
  }

  Connections {
    target: Plugins
    function onCatalogPayload(payload, fromCache) {
      if (Plugins.catalogSerial !== root.catalogSerial)
        return
      root.applyCatalogPayload(payload, fromCache)
    }
    function onCatalogFinished() {
      if (Plugins.catalogSerial !== root.catalogSerial)
        return
      if (root.catalogLoading) {
        root.catalogLoading = false
        root.catalogFinished()
      }
    }
    function onCatalogFailed(message) {
      if (Plugins.catalogSerial !== root.catalogSerial)
        return
      root.catalogLoading = false
      root.catalogFailed(message)
    }
    function onInstalledListed(plugins) {
      if (Plugins.installedSerial !== root.installedSerial)
        return
      var ids = ({})
      var list = plugins || []
      for (var i = 0; i < list.length; i++) {
        var id = root.jsonField(list[i] || {}, "id")
        if (id)
          ids[id] = true
      }
      root.installedPluginIds = ids
      root.applyInstalledFlags()
    }
  }

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
    var filtered = root.filteredPlugins || []
    if (root.selectedIndex >= filtered.length)
      root.selectedIndex = Math.max(0, filtered.length - 1)
    if (filtered.length > 0 && root.selectedIndex < 0)
      root.selectedIndex = 0
    root.revealWhenSettled()
  }

  onFilterTextChanged: {
    var filtered = root.filteredPlugins || []
    if (root.selectedIndex >= filtered.length)
      root.selectedIndex = Math.max(0, filtered.length - 1)
    if (filtered.length > 0 && root.selectedIndex < 0)
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
    if (!plugin)
      return
    // Defer so the grid click finishes before Browse hides; otherwise the
    // release can hit Main's dismiss MouseArea and immediately goBack().
    var payload = root.clonePlugin(plugin)
    Qt.callLater(function() {
      if (payload)
        root.pluginActivated(payload)
    })
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      root.layoutSettled = true
      if (root.visible)
        grid.forceActiveFocus()
    })
  }

  function focusGrid() {
    if (root.visible)
      grid.forceActiveFocus()
  }

  Component.onCompleted: revealWhenSettled()
  onVisibleChanged: if (visible) {
    root.revealWhenSettled()
    root.focusGrid()
  }

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
