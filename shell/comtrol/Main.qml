import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "layouts" as Layouts
import "functions"

// Plugin entry: host lifecycle + layout routing + cOMtrol CLI gateway.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by omarchy-shell on Loader.onLoaded. Keep undeclared-default so
  // the host's `"shell" in item` check always sees the property.
  property var shell
  property var manifest: null

  property bool opened: false
  property bool showingResults: false
  property bool loading: false
  property string resultsTitle: "Results"
  property var resultRows: []
  property var selectedPlugin: null
  property string pendingDomain: ""
  property string pendingMode: ""
  property int searchSerial: 0
  property int localPluginsSerial: 0
  property int localThemesSerial: 0
  property int webThemesSerial: 0
  property int backgroundsSerial: 0
  property bool refreshPackagesAfterRemove: false
  property bool suppressDismissClick: false

  readonly property bool usePreviewTheme: showingResults
    && !loading
    && pendingDomain === "themes"
    && (pendingMode === "local" || pendingMode === "web")
  readonly property bool usePreviewBackground: showingResults
    && !loading
    && pendingDomain === "background"
  readonly property bool usePreviewBoot: showingResults
    && !loading
    && pendingDomain === "boot"
  readonly property bool usePluginDetail: showingResults
    && !loading
    && pendingDomain === "plugins"
    && pendingMode === "web"
    && selectedPlugin !== null
  readonly property bool useBrowsePlugins: showingResults
    && !loading
    && pendingDomain === "plugins"
    && pendingMode === "web"
    && selectedPlugin === null
  readonly property bool useFullscreenLayout: usePreviewTheme || useBrowsePlugins || usePluginDetail || usePreviewBackground || usePreviewBoot
  readonly property bool useCardMenu: !useFullscreenLayout

  function usesFullscreenResults(domain, mode) {
    if (domain === "themes")
      return true
    if (domain === "background")
      return true
    if (domain === "plugins" && mode === "web")
      return true
    if (domain === "boot")
      return true
    return false
  }

  property color scrim: useFullscreenLayout ? Color.imagePicker.scrim : Color.menu.scrim

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
      case "background":
      case "backgrounds": return "-background"
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
    var version = root.jsonField(item, "version")

    if (root.pendingDomain === "plugins") {
      if (name)
        return name
      if (itemId)
        return itemId
      return "?"
    }

    if (root.pendingDomain === "packages") {
      var pkgName = (repo && name) ? (repo + "/" + name) : (name || itemId || "?")
      if (pkgName !== "?" && version)
        return pkgName + "  " + version
      return pkgName
    }

    if (root.pendingDomain === "aurs") {
      var aurName = name || itemId || "?"
      if (aurName !== "?" && version)
        return aurName + "  " + version
      return aurName
    }

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

    if (root.pendingDomain === "packages" || root.pendingDomain === "aurs")
      return root.jsonField(item, "description")

    if (root.pendingDomain !== "plugins")
      return ""

    if (root.pendingMode === "local") {
      var version = root.jsonField(item, "version")
      var source = root.jsonField(item, "source")
      var parts = []
      if (version)
        parts.push(version)
      if (source === "first_party")
        parts.push("system")
      return parts.join("  ")
    }

    if (root.pendingMode !== "web")
      return ""

    var webVersion = root.jsonField(item, "version")
    var repo = root.jsonField(item, "repo")
    var webParts = []
    if (webVersion)
      webParts.push(webVersion)
    if (repo)
      webParts.push(repo)
    return webParts.join("  ")
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

    var start = raw.indexOf("[")
    var end = raw.lastIndexOf("]")
    var candidate = (start >= 0 && end > start) ? raw.substring(start, end + 1) : raw

    var data = JSON.parse(candidate)
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

  function clearLayoutResults() {
    previewTheme.clear()
    previewBackground.clear()
    previewBoot.clear()
    browsePlugins.clear()
    pluginDetail.clear()
    root.selectedPlugin = null
  }

  function syncSelectedPluginInstalled() {
    if (!root.selectedPlugin)
      return
    var next = browsePlugins.pluginWithInstalled(root.selectedPlugin)
    if (next)
      root.selectedPlugin = next
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (searchProcess.running)
      searchProcess.running = false
    root.searchSerial += 1

    root.opened = true
    root.showingResults = false
    root.loading = false
    root.resultRows = []
    root.clearLayoutResults()
    cardMenu.open(payload)
    Qt.callLater(function() { cardMenu.focusMenu() })
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

  function goBack() {
    if (root.selectedPlugin !== null) {
      root.selectedPlugin = null
      Qt.callLater(function() {
        if (root.useBrowsePlugins)
          browsePlugins.focusGrid()
      })
      return
    }
    if (root.showingResults) {
      rustSearchTimer.stop()
      if (searchProcess.running)
        searchProcess.running = false
      if (packageRemoveProc.running)
        packageRemoveProc.running = false
      root.showingResults = false
      root.loading = false
      root.resultRows = []
      root.clearLayoutResults()
      cardMenu.resetAfterResults()
      return
    }
    if (root.loading && !root.usesFullscreenResults(root.pendingDomain, root.pendingMode)) {
      rustSearchTimer.stop()
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.localPluginsSerial += 1
      root.loading = false
      cardMenu.clearPendingAction()
      return
    }
    if (!cardMenu.navigateBack())
      root.dismiss()
  }

  function runComtrol(domain, mode, title) {
    root.pendingDomain = domain
    root.pendingMode = mode
    root.resultsTitle = title || (domain + " " + mode)
    rustSearchTimer.stop()
    root.clearLayoutResults()

    if (domain === "boot") {
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.showingResults = true
      root.loading = false
      root.resultRows = []
      cardMenu.prepareForResults()
      previewBoot.loadUnlocks()
      Qt.callLater(function() { previewBoot.focusCarousel() })
      return
    }

    if (domain === "plugins" && mode === "web") {
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      browsePlugins.loadCatalog()
      return
    }

    if (domain === "plugins" && mode === "local") {
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.showingResults = false
      root.loading = true
      root.resultRows = []
      cardMenu.markActionLoading(domain, mode)
      // Align before listInstalled() — scan can finish quickly and emit
      // installedListed before this function returns.
      root.localPluginsSerial = Plugins.installedSerial + 1
      Plugins.listInstalled()
      return
    }

    if (domain === "themes" && mode === "local") {
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      root.localThemesSerial = Themes.installedSerial + 1
      Themes.listInstalled()
      return
    }

    if (domain === "themes" && mode === "web") {
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      root.webThemesSerial = Themes.webSerial + 1
      Themes.loadWeb("")
      return
    }

    if (domain === "background") {
      if (searchProcess.running)
        searchProcess.running = false
      root.searchSerial += 1
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      root.backgroundsSerial = Backgrounds.listSerial + 1
      Backgrounds.list(mode || "current")
      return
    }

    var fullscreen = root.usesFullscreenResults(domain, mode)
    if (fullscreen) {
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
    } else if (root.showingResults) {
      root.loading = true
    } else {
      root.showingResults = false
      root.loading = true
      root.resultRows = []
      cardMenu.markActionLoading(domain, mode)
    }

    root.searchSerial += 1
    searchProcess.serial = root.searchSerial
    var argv
    if (domain === "background")
      argv = [root.runScript(), "-v", "-background", "-" + String(mode || "current")]
    else if (mode === "local")
      argv = [root.runScript(), "-v", root.domainFlag(domain)]
    else
      argv = [root.runScript(), "-s", root.domainFlag(domain), "-w"]

    if (typeof searchProcess.exec === "function") {
      searchProcess.exec(argv)
    } else {
      if (searchProcess.running)
        searchProcess.running = false
      searchProcess.command = argv
      searchProcess.running = false
      searchProcess.running = true
    }
  }

  function finishSearch() {
    if (!root.showingResults)
      root.showingResults = true
    root.loading = false
    cardMenu.clearPendingAction()
  }

  function parseResults(text) {
    var rows = []
    var raw = String(text || "").trim()
    if (!raw)
      return rows

    try {
      var data = root.extractJsonArray(raw)

      if (root.pendingDomain === "themes" && (root.pendingMode === "local" || root.pendingMode === "web")) {
        previewTheme.loadFromData(data)
        return rows
      }

      if (root.pendingDomain === "background") {
        previewBackground.loadFromData(data)
        return rows
      }

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

  function pluginsToResultRows(plugins) {
    var rows = []
    var list = plugins || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      rows.push({
        itemId: root.resultItemId(item, i),
        label: root.resultLabel(item),
        detail: root.resultDetail(item),
        icon: "󰐱",
        kind: "result",
        domain: "plugins",
        mode: root.pendingMode || "local"
      })
    }
    return rows
  }

  function applyLocalPluginsList(plugins) {
    if (root.pendingDomain !== "plugins" || root.pendingMode !== "local")
      return
    if (Plugins.installedSerial !== root.localPluginsSerial)
      return
    root.resultRows = root.pluginsToResultRows(plugins)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function applyLocalThemesList(themes) {
    if (root.pendingDomain !== "themes" || root.pendingMode !== "local")
      return
    if (Themes.installedSerial !== root.localThemesSerial)
      return
    previewTheme.loadFromData(themes || [])
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function applyWebThemesList(themes) {
    if (root.pendingDomain !== "themes" || root.pendingMode !== "web")
      return
    if (Themes.webSerial !== root.webThemesSerial)
      return
    previewTheme.loadFromData(themes || [])
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function applyBackgroundsList(backgrounds, mode) {
    if (root.pendingDomain !== "background")
      return
    if (Backgrounds.listSerial !== root.backgroundsSerial)
      return
    if (mode && String(mode) !== String(root.pendingMode || "current"))
      return
    previewBackground.loadFromData(backgrounds || [])
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function openPluginDetail(plugin) {
    if (!plugin)
      return
    var next = browsePlugins.pluginWithInstalled(plugin)
    if (!next || !String(next.id || ""))
      return
    // Prevent the opening click from falling through to the scrim MouseArea.
    root.suppressDismissClick = true
    root.selectedPlugin = next
    Qt.callLater(function() {
      root.suppressDismissClick = false
      if (root.usePluginDetail)
        pluginDetail.focusDetail()
    })
  }

  function removePackage(name) {
    if (!name)
      return
    var id = String(name)

    root.refreshPackagesAfterRemove = true
    root.loading = true

    var argv = [root.runScript(), "-r", "-package", id]
    if (typeof packageRemoveProc.exec === "function") {
      packageRemoveProc.exec(argv)
    } else {
      if (packageRemoveProc.running)
        packageRemoveProc.running = false
      packageRemoveProc.command = argv
      packageRemoveProc.running = false
      packageRemoveProc.running = true
    }
  }

  function runLiveRustSearch() {
    if (!cardMenu.usesRustFilterSearch)
      return

    if (searchProcess.running)
      searchProcess.running = false

    root.searchSerial += 1
    searchProcess.serial = root.searchSerial
    root.loading = true

    var argv = [root.runScript(), "-s", root.domainFlag(root.pendingDomain), "-w"]
    var q = String(cardMenu.filterText || "").trim()
    if (q)
      argv.push(q)
    searchProcess.command = argv
    searchProcess.running = true
  }

  function focusActiveLayout() {
    if (root.usePreviewTheme)
      previewTheme.focusCarousel()
    else if (root.usePreviewBackground)
      previewBackground.focusCarousel()
    else if (root.usePreviewBoot)
      previewBoot.focusCarousel()
    else if (root.useBrowsePlugins)
      browsePlugins.focusGrid()
    else
      cardMenu.focusMenu()
  }

  Process {
    id: packageRemoveProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      if (!root.refreshPackagesAfterRemove)
        return
      root.refreshPackagesAfterRemove = false
      Qt.callLater(function() {
        if (!root.opened)
          return
        root.runComtrol("packages", "local", root.resultsTitle || "Packages")
      })
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
        root.finishSearch()
        Qt.callLater(root.focusActiveLayout)
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
            && previewTheme.themes.length === 0 && browsePlugins.plugins.length === 0
            && previewBackground.backgrounds.length === 0) {
          root.resultRows = [{
            itemId: "result.error",
            label: String(text).trim().split("\n")[0],
            detail: "",
            icon: "󰀦",
            kind: "result",
            domain: "",
            mode: ""
          }]
          root.finishSearch()
        }
      }
    }
    onExited: function(exitCode) {
      if (searchProcess.serial !== root.searchSerial)
        return
      if (!root.loading)
        return
      if (exitCode !== 0 && root.resultRows.length === 0
          && previewTheme.themes.length === 0 && browsePlugins.plugins.length === 0
          && previewBackground.backgrounds.length === 0) {
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
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
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
      onClicked: {
        if (root.suppressDismissClick)
          return
        if (root.useFullscreenLayout)
          root.goBack()
        else
          root.dismiss()
      }
    }

    Layouts.PreviewTheme {
      id: previewTheme
      anchors.fill: parent
      visible: root.usePreviewTheme
      mode: root.pendingMode
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
      onRefreshRequested: root.runComtrol("themes", "local", "Themes")
    }

    Layouts.BackgroundPreview {
      id: previewBackground
      anchors.fill: parent
      visible: root.usePreviewBackground
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
      onRefreshRequested: root.runComtrol("background", root.pendingMode, root.resultsTitle)
    }

    Layouts.ApperianceBoot {
      id: previewBoot
      anchors.fill: parent
      visible: root.usePreviewBoot
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
    }

    Layouts.BrowsePlugins {
      id: browsePlugins
      anchors.fill: parent
      visible: root.useBrowsePlugins
      onBackRequested: root.goBack()
      onPluginActivated: function(plugin) { root.openPluginDetail(plugin) }
      onDismissRequested: root.dismiss()
      onInstalledIdsChanged: root.syncSelectedPluginInstalled()
      onCatalogFinished: {
        root.finishSearch()
        Qt.callLater(root.focusActiveLayout)
      }
      onCatalogFailed: function(message) {
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "Plugin catalog failed"),
          detail: "",
          icon: "󰀦",
          kind: "result",
          domain: "",
          mode: ""
        }]
        root.finishSearch()
        Qt.callLater(root.focusActiveLayout)
      }
    }

    Layouts.PluginDetail {
      id: pluginDetail
      anchors.fill: parent
      visible: root.usePluginDetail
      // Keep this as a binding only — never assign pluginDetail.plugin from JS.
      plugin: root.selectedPlugin ? root.selectedPlugin : ({})
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
      onRefreshInstalledRequested: browsePlugins.refreshInstalled()
      onHeartSentFor: function(pluginId) {
        browsePlugins.bumpHearts(pluginId)
        if (root.selectedPlugin && String(root.selectedPlugin["id"] || root.selectedPlugin.id || "") === String(pluginId || "")) {
          var next = browsePlugins.pluginWithInstalled(root.selectedPlugin)
          if (next) {
            next.hearts = Number(next.hearts || 0) + 1
            root.selectedPlugin = next
          }
        }
      }
    }

    Layouts.Menu {
      id: cardMenu
      anchors.fill: parent
      visible: root.useCardMenu
      shell: root.shell
      showingResults: root.showingResults
      loading: root.loading
      resultsTitle: root.resultsTitle
      resultRows: root.resultRows
      pendingDomain: root.pendingDomain
      pendingMode: root.pendingMode
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
      onActionRequested: function(domain, mode, title) { root.runComtrol(domain, mode, title) }
      onLiveSearchRequested: rustSearchTimer.restart()
      onRemovePackageRequested: function(name) { root.removePackage(name) }
    }

    Connections {
      target: Plugins
      function onInstalledListed(plugins) {
        root.applyLocalPluginsList(plugins)
      }
    }

    Connections {
      target: Themes
      function onLocalListed(themes) {
        root.applyLocalThemesList(themes)
      }
      function onWebListed(themes, fromCache) {
        root.applyWebThemesList(themes)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "themes" || root.pendingMode !== "web")
          return
        if (Themes.webSerial !== root.webThemesSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "Theme catalog failed"),
          detail: "",
          icon: "󰀦",
          kind: "result",
          domain: "",
          mode: ""
        }]
        root.finishSearch()
        Qt.callLater(root.focusActiveLayout)
      }
    }

    Connections {
      target: Backgrounds
      function onListed(backgrounds, mode) {
        root.applyBackgroundsList(backgrounds, mode)
      }
    }
  }
}
