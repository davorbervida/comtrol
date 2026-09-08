import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "layouts" as Layouts

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string activeMenu: "root"
  property var navStack: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  property bool showingResults: false
  property bool loading: false
  property string resultsTitle: "Results"
  property var resultRows: []
  property var themeResults: []
  property var pluginResults: []
  property string pendingDomain: ""
  property string pendingMode: ""
  property int searchSerial: 0

  readonly property bool usePreviewTheme: showingResults
    && !loading
    && pendingDomain === "themes"
    && (pendingMode === "local" || pendingMode === "web")
  readonly property bool useBrowsePlugins: showingResults
    && !loading
    && pendingDomain === "plugins"
    && pendingMode === "web"
  readonly property bool useFullscreenLayout: usePreviewTheme || useBrowsePlugins

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  property color scrim: useFullscreenLayout ? Color.imagePicker.scrim : Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(36), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int detailRowHeight: Math.max(Style.space(52), Style.font.body + Style.font.caption + Style.spacing.controlPaddingY * 2)
  property int rowSpacing: Style.spacing.xs
  property int cardWidth: Math.min(Style.space(360), panel.width - Style.gapsOut * 2)
  readonly property bool resultsHaveDetail: false
  readonly property int activeRowHeight: resultsHaveDetail ? detailRowHeight : rowHeight
  readonly property int visibleRowsHeight: Math.min(
    Math.max(displayModel.count, 1) * (activeRowHeight + rowSpacing) - rowSpacing,
    Math.max(activeRowHeight, panel.height - Style.gapsOut * 2 - headerHeight - contentSpacing - contentMargin * 2)
  )
  readonly property int cardHeight: headerHeight + contentSpacing + visibleRowsHeight + contentMargin * 2

  readonly property var menus: ({
    "root": {
      title: "Control",
      rows: [
        { itemId: "appearance", label: "Appearance", icon: "", kind: "menu" },
        { itemId: "apps", label: "Apps", icon: "󰀻", kind: "menu" },
        { itemId: "plugins", label: "Plugins", icon: "󰐱", kind: "menu" }
      ]
    },
    "appearance": {
      title: "Appearance",
      rows: [
        { itemId: "themes", label: "Themes", icon: "󰏘", kind: "menu" }
      ]
    },
    "themes": {
      title: "Themes",
      rows: [
        { itemId: "themes.web", label: "Add", icon: "󰐕", kind: "action", domain: "themes", mode: "web" },
        { itemId: "themes.local", label: "Installed", icon: "󰉋", kind: "action", domain: "themes", mode: "local" }
      ]
    },
    "apps": {
      title: "Apps",
      rows: [
        { itemId: "packages", label: "Packages", icon: "󰏖", kind: "menu" },
        { itemId: "aurs", label: "AUR", icon: "󰣇", kind: "menu" }
      ]
    },
    "plugins": {
      title: "Plugins",
      rows: [
        { itemId: "plugins.web", label: "Add", icon: "󰐕", kind: "action", domain: "plugins", mode: "web" },
        { itemId: "plugins.local", label: "Installed", icon: "󰉋", kind: "action", domain: "plugins", mode: "local" }
      ]
    },
    "packages": {
      title: "Packages",
      rows: [
        { itemId: "packages.web", label: "Add", icon: "󰐕", kind: "action", domain: "packages", mode: "web" },
        { itemId: "packages.local", label: "Installed", icon: "󰉋", kind: "action", domain: "packages", mode: "local" }
      ]
    },
    "aurs": {
      title: "AUR",
      rows: [
        { itemId: "aurs.web", label: "Add", icon: "󰐕", kind: "action", domain: "aurs", mode: "web" },
        { itemId: "aurs.local", label: "Installed", icon: "󰉋", kind: "action", domain: "aurs", mode: "local" }
      ]
    }
  })

  function pluginDir() {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0)
      url = url.substring(7)
    while (url.length > 1 && url.charAt(url.length - 1) === "/")
      url = url.substring(0, url.length - 1)
    return url
  }

  function runScript() {
    return root.pluginDir() + "/run.sh"
  }

  function domainFlag(domain) {
    switch (domain) {
      case "themes": return "-theme"
      case "plugins": return "-plugin"
      case "packages": return "-package"
      case "aurs": return "-aur"
      case "bindings": return "-binding"
      case "webapps": return "-webapp"
      default: return "-" + String(domain || "").replace(/s$/, "")
    }
  }

  function jsonField(obj, key) {
    if (!obj)
      return ""
    var value = obj[key]
    if (value === undefined || value === null)
      return ""
    return String(value)
  }

  function resultLabel(item) {
    if (!item || typeof item !== "object")
      return "?"

    var name = root.jsonField(item, "name")
    var itemId = root.jsonField(item, "id")
    var fullName = root.jsonField(item, "full_name")
    var repo = root.jsonField(item, "repo")
    var source = root.jsonField(item, "source")

    // Plugin catalog: prefer display name (repo is a URL, not a pacman repo).
    if (root.pendingDomain === "plugins") {
      if (name)
        return name
      if (itemId)
        return itemId
      return "?"
    }

    // pacman web results: repo/name
    if (repo && name && !fullName && !source)
      return repo + "/" + name
    if (name)
      return name
    if (itemId)
      return itemId
    if (fullName)
      return fullName
    return "?"
  }

  function resultDetail(item) {
    if (!item || typeof item !== "object")
      return ""
    if (root.pendingDomain !== "plugins" || root.pendingMode !== "web")
      return ""

    var version = root.jsonField(item, "version")
    var repo = root.jsonField(item, "repo")
    var parts = []
    if (version)
      parts.push(version)
    if (repo)
      parts.push(repo)
    return parts.join("  ")
  }

  function resultItemId(item, index) {
    return root.jsonField(item, "id")
      || root.jsonField(item, "name")
      || root.jsonField(item, "full_name")
      || ("result." + index)
  }

  function extractJsonArray(text) {
    var raw = String(text || "").trim()
    if (!raw)
      return []

    // Prefer a top-level array; tolerate leading/trailing noise around [...].
    var start = raw.indexOf("[")
    var end = raw.lastIndexOf("]")
    var candidate = (start >= 0 && end > start) ? raw.substring(start, end + 1) : raw

    var data = JSON.parse(candidate)
    // QML/JSON may yield array-like objects where Array.isArray is false.
    if (data && data.length !== undefined) {
      var out = []
      for (var i = 0; i < data.length; i++)
        out.push(data[i])
      return out
    }
    if (data && typeof data === "object")
      return [data]
    return []
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (searchProcess.running)
      searchProcess.running = false

    root.opened = true
    root.navStack = []
    root.activeMenu = payload.initialMenu || payload.menu || "root"
    root.showingResults = false
    root.loading = false
    root.resultRows = []
    root.themeResults = []
    root.pluginResults = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (searchProcess.running)
      searchProcess.running = false
    root.opened = false
  }

  function dismiss() {
    if (searchProcess.running)
      searchProcess.running = false
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "comtrol")
  }

  function currentMenu() {
    if (root.showingResults)
      return { title: root.loading ? "Loading" : root.resultsTitle, rows: root.resultRows }
    return root.menus[root.activeMenu] || root.menus.root
  }

  function headerText() {
    if (root.filterText)
      return root.filterText
    return (root.currentMenu().title || "Control") + "…"
  }

  function rebuildDisplay() {
    var menu = root.currentMenu()
    var rows = menu.rows || []
    // Packages → Add / AUR → Add use Rust search; don't re-filter client-side.
    var q = root.usesRustFilterSearch() ? "" : root.filterText.trim().toLowerCase()

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var itemId = String(row.itemId || row.id || "")
      var label = String(row.label || "")
      var detail = String(row.detail || "")
      if (q && label.toLowerCase().indexOf(q) < 0 && itemId.toLowerCase().indexOf(q) < 0
          && detail.toLowerCase().indexOf(q) < 0)
        continue
      displayModel.append({
        itemId: itemId,
        kind: String(row.kind || ""),
        icon: String(row.icon || ""),
        label: label,
        detail: detail,
        domain: String(row.domain || ""),
        mode: String(row.mode || "")
      })
    }

    if (displayModel.count === 0) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count) {
      root.selectedIndex = displayModel.count - 1
    }
    if (displayModel.count > 0 && !root.cursorActive)
      root.cursorActive = true
  }

  function usesRustFilterSearch() {
    return root.showingResults
      && root.pendingMode === "web"
      && (root.pendingDomain === "packages" || root.pendingDomain === "aurs")
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    if (root.usesRustFilterSearch()) {
      rustSearchTimer.restart()
      return
    }
    root.rebuildDisplay()
  }

  function runLiveRustSearch() {
    if (!root.usesRustFilterSearch())
      return

    if (searchProcess.running)
      searchProcess.running = false

    root.searchSerial += 1
    searchProcess.serial = root.searchSerial
    root.loading = true

    var argv = [root.runScript(), "-s", root.domainFlag(root.pendingDomain), "-w"]
    var q = root.filterText.trim()
    if (q)
      argv.push(q)
    searchProcess.command = argv
    searchProcess.running = true
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function goBack() {
    if (root.showingResults) {
      rustSearchTimer.stop()
      if (searchProcess.running)
        searchProcess.running = false
      if (themeApplyProc.running)
        themeApplyProc.running = false
      if (themeRemoveProc.running)
        themeRemoveProc.running = false
      root.showingResults = false
      root.loading = false
      root.resultRows = []
      root.themeResults = []
      root.pluginResults = []
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = true
      root.rebuildDisplay()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    if (root.navStack.length === 0) {
      root.dismiss()
      return
    }
    root.activeMenu = root.navStack.pop()
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.kind === "menu") {
      root.navStack.push(root.activeMenu)
      root.activeMenu = row.itemId
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = true
      root.rebuildDisplay()
      return
    }
    if (row.kind === "action" && row.domain && row.mode) {
      root.runComtrol(row.domain, row.mode, row.label)
      return
    }
  }

  function runComtrol(domain, mode, title) {
    root.pendingDomain = domain
    root.pendingMode = mode
    root.resultsTitle = title || (domain + " " + mode)
    root.showingResults = true
    root.loading = true
    root.resultRows = []
    root.themeResults = []
    root.pluginResults = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    rustSearchTimer.stop()
    root.rebuildDisplay()

    // Installed → system view (-v); Add → search web (-s -w)
    root.searchSerial += 1
    searchProcess.serial = root.searchSerial
    var argv
    if (mode === "local")
      argv = [root.runScript(), "-v", root.domainFlag(domain)]
    else
      argv = [root.runScript(), "-s", root.domainFlag(domain), "-w"]
    searchProcess.command = argv
    searchProcess.running = true
  }

  // Parse JSON array from cOMtrol stdout into menu rows.
  function parseResults(text) {
    var rows = []
    var raw = String(text || "").trim()
    if (!raw)
      return rows

    try {
      var data = root.extractJsonArray(raw)

      if (root.pendingDomain === "themes" && (root.pendingMode === "local" || root.pendingMode === "web")) {
        var themes = []
        for (var t = 0; t < data.length; t++) {
          var theme = data[t] || {}
          var preview = root.jsonField(theme, "preview")
          if (!preview)
            preview = root.jsonField(theme, "preview_image")
          themes.push({
            name: root.jsonField(theme, "name"),
            full_name: root.jsonField(theme, "full_name"),
            path: root.jsonField(theme, "path"),
            preview: preview,
            source: root.jsonField(theme, "source"),
            repo: root.jsonField(theme, "repo"),
            stars: theme.stars || theme["stars"] || 0,
            author: root.jsonField(theme, "author"),
            description: root.jsonField(theme, "description"),
            ansi_colors: theme.ansi_colors || theme["ansi_colors"] || [],
            mode: root.pendingMode
          })
        }
        root.themeResults = themes
        root.pluginResults = []
        return rows
      }

      if (root.pendingDomain === "plugins" && root.pendingMode === "web") {
        var plugins = []
        for (var p = 0; p < data.length; p++) {
          var plugin = data[p] || {}
          plugins.push({
            id: root.jsonField(plugin, "id"),
            name: root.jsonField(plugin, "name"),
            version: root.jsonField(plugin, "version"),
            author: root.jsonField(plugin, "author"),
            repo: root.jsonField(plugin, "repo"),
            description: root.jsonField(plugin, "description"),
            preview: root.jsonField(plugin, "preview_image"),
            install_command: root.jsonField(plugin, "install_command"),
            install_available: !!(plugin.install_available || plugin["install_available"]),
            mode: "web"
          })
        }
        root.pluginResults = plugins
        root.themeResults = []
        return rows
      }

      root.themeResults = []
      root.pluginResults = []
      for (var i = 0; i < data.length; i++) {
        var item = data[i] || {}
        rows.push({
          itemId: root.resultItemId(item, i),
          label: root.resultLabel(item),
          detail: root.resultDetail(item),
          icon: root.pendingDomain === "plugins" ? "󰐱" : "󰈔",
          kind: "result",
          domain: root.pendingDomain || "",
          mode: root.pendingMode || ""
        })
      }
    } catch (e) {
      root.themeResults = []
      root.pluginResults = []
      rows.push({
        itemId: "result.error",
        label: "Invalid JSON from cOMtrol",
        detail: "",
        icon: "󰀦",
        kind: "result",
        domain: "",
        mode: ""
      })
    }
    return rows
  }

  function applyTheme(theme) {
    if (!theme)
      return
    if (themeApplyProc.running)
      themeApplyProc.running = false

    // Local: apply installed theme. Web: install from git (also applies).
    if (root.pendingMode === "web" || theme.mode === "web") {
      var repo = theme.repo || ""
      if (!repo)
        return
      themeApplyProc.command = ["omarchy-theme-install", String(repo)]
      themeApplyProc.running = true
      return
    }

    if (!theme.name)
      return
    themeApplyProc.command = ["omarchy-theme-set", String(theme.name)]
    themeApplyProc.running = true
  }

  function applyPlugin(plugin) {
    if (!plugin)
      return
    var cmd = String(plugin.install_command || "")
    if (!cmd)
      return
    if (themeApplyProc.running)
      themeApplyProc.running = false
    themeApplyProc.command = ["bash", "-lc", cmd]
    themeApplyProc.running = true
  }

  function removeTheme(theme) {
    if (!theme || !theme.name)
      return
    if (root.pendingMode !== "local" && theme.mode !== "local")
      return
    if (themeRemoveProc.running)
      themeRemoveProc.running = false
    themeRemoveProc.command = [root.runScript(), "-r", "-theme", String(theme.name)]
    themeRemoveProc.running = true
  }

  ListModel { id: displayModel }

  Process {
    id: themeApplyProc
  }

  Process {
    id: themeRemoveProc
    onExited: function(exitCode) {
      // Refresh local theme list after Rust remove (success or partial).
      if (root.pendingDomain === "themes" && root.pendingMode === "local")
        root.runComtrol("themes", "local", "Installed")
    }
  }

  Process {
    id: searchProcess
    property int serial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (searchProcess.serial !== root.searchSerial)
          return
        root.resultRows = root.parseResults(text)
        root.loading = false
        root.selectedIndex = 0
        root.cursorActive = root.resultRows.length > 0
        root.rebuildDisplay()
        if (root.usePreviewTheme)
          Qt.callLater(function() { previewTheme.focusCarousel() })
        else if (root.useBrowsePlugins)
          Qt.callLater(function() { browsePlugins.focusGrid() })
        else
          Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (searchProcess.serial !== root.searchSerial)
          return
        if (!text || !String(text).trim())
          return
        if (root.loading && root.resultRows.length === 0
            && root.themeResults.length === 0 && root.pluginResults.length === 0) {
          root.resultRows = [{
            itemId: "result.error",
            label: String(text).trim().split("\n")[0],
            detail: "",
            icon: "󰀦",
            kind: "result",
            domain: "",
            mode: ""
          }]
          root.loading = false
          root.rebuildDisplay()
        }
      }
    }
    onExited: function(exitCode) {
      if (searchProcess.serial !== root.searchSerial)
        return
      if (!root.loading)
        return
      if (exitCode !== 0 && root.resultRows.length === 0
          && root.themeResults.length === 0 && root.pluginResults.length === 0) {
        root.resultRows = [{
          itemId: "result.error",
          label: "cOMtrol failed (exit " + exitCode + ")",
          detail: "",
          icon: "󰀦",
          kind: "result",
          domain: "",
          mode: ""
        }]
      }
      root.loading = false
      root.rebuildDisplay()
      if (root.usePreviewTheme)
        Qt.callLater(function() { previewTheme.focusCarousel() })
      else if (root.useBrowsePlugins)
        Qt.callLater(function() { browsePlugins.focusGrid() })
    }
  }

  Timer {
    id: rustSearchTimer
    interval: 250
    repeat: false
    onTriggered: root.runLiveRustSearch()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "comtrol-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.useFullscreenLayout ? root.goBack() : root.dismiss()
    }

    Layouts.PreviewTheme {
      id: previewTheme
      anchors.fill: parent
      visible: root.usePreviewTheme
      themes: root.themeResults
      mode: root.pendingMode
      onBackRequested: root.goBack()
      onThemeActivated: function(theme) { root.applyTheme(theme) }
      onThemeRemoveRequested: function(theme) { root.removeTheme(theme) }
    }

    Layouts.BrowsePlugins {
      id: browsePlugins
      anchors.fill: parent
      visible: root.useBrowsePlugins
      plugins: root.pluginResults
      onBackRequested: root.goBack()
      onPluginActivated: function(plugin) { root.applyPlugin(plugin) }
    }

    BorderSurface {
      id: card
      visible: !root.useFullscreenLayout
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.goBack()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerText()
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string label
              required property string detail
              required property string domain
              required property string mode

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool hasDetail: detail.length > 0

              width: ListView.view.width
              height: hasDetail ? root.detailRowHeight : root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"
              borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(12)

                Text {
                  textFormat: Text.PlainText
                  text: row.icon
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(24)
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  width: Math.max(
                    Style.space(40),
                    parent.width - Style.space(24) - Style.space(12) - Style.space(16) - Style.space(24)
                  )
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.label
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: row.hasDetail
                    text: row.detail
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.62
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(16)
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = index
                  root.activateIndex(index)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: displayModel.count === 0
            text: root.loading ? "Loading…" : "No matches"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
