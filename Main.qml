import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "layouts" as Layouts
import "functions"

// Plugin entry: host lifecycle + layout routing + QML domain helpers.
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
  property int localPluginsSerial: 0
  property int localThemesSerial: 0
  property int webThemesSerial: 0
  property int backgroundsSerial: 0
  property int localPackagesSerial: 0
  property int webPackagesSerial: 0
  property int localAursSerial: 0
  property int webAursSerial: 0
  property int localWebAppsSerial: 0
  property int searchSerial: 0
  property int youtubeSerial: 0
  property int redditSerial: 0
  property int googleSerial: 0
  property int duckduckgoSerial: 0
  property int xSerial: 0
  property int wikipediaSerial: 0
  property int pendingPackageRemoveSerial: -1
  property int pendingWebAppRemoveSerial: -1
  property int pendingPluginRemoveSerial: -1
  property int pendingPluginToggleSerial: -1
  property bool refreshPackagesAfterRemove: false
  property bool refreshWebAppsAfterRemove: false
  property bool refreshPluginsAfterRemove: false
  property bool refreshPluginsAfterToggle: false
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

    if (root.pendingDomain === "search")
      return root.jsonField(item, "path")

    if (root.pendingDomain === "youtube")
      return root.jsonField(item, "detail") || root.jsonField(item, "channel") || root.jsonField(item, "url")

    if (root.pendingDomain === "reddit")
      return root.jsonField(item, "detail") || root.jsonField(item, "subreddit") || root.jsonField(item, "url")

    if (root.pendingDomain === "google")
      return root.jsonField(item, "detail") || root.jsonField(item, "url")

    if (root.pendingDomain === "duckduckgo")
      return root.jsonField(item, "detail") || root.jsonField(item, "url")

    if (root.pendingDomain === "x")
      return root.jsonField(item, "detail") || root.jsonField(item, "user") || root.jsonField(item, "url")

    if (root.pendingDomain === "wikipedia")
      return root.jsonField(item, "detail") || root.jsonField(item, "url")

    if (root.pendingDomain === "webapps") {
      var url = root.jsonField(item, "url")
      var source = root.jsonField(item, "source")
      var parts = []
      if (url)
        parts.push(url)
      if (source === "first_party")
        parts.push("system")
      return parts.join("  ")
    }

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

    root.opened = true
    root.showingResults = false
    root.loading = false
    root.resultRows = []
    root.clearLayoutResults()
    cardMenu.open(payload)
    Qt.callLater(function() { cardMenu.focusMenu() })
  }

  function close() {
    WebBrowser.cool()
    root.opened = false
  }

  function dismiss() {
    WebBrowser.cool()
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
      liveSearchTimer.stop()
      Plugins.cancel()
      Themes.cancel()
      Backgrounds.cancel()
      Packages.cancel()
      Aurs.cancel()
      WebApps.cancel()
      Files.cancel()
      YouTube.cancel()
      Reddit.cancel()
      Google.cancel()
      DuckDuckGo.cancel()
      X.cancel()
      Wikipedia.cancel()
      Files.resetHidden()
      root.pendingPackageRemoveSerial = -1
      root.pendingWebAppRemoveSerial = -1
      root.pendingPluginRemoveSerial = -1
      root.pendingPluginToggleSerial = -1
      root.refreshPackagesAfterRemove = false
      root.refreshWebAppsAfterRemove = false
      root.refreshPluginsAfterRemove = false
      root.refreshPluginsAfterToggle = false
      root.showingResults = false
      root.loading = false
      root.resultRows = []
      root.clearLayoutResults()
      cardMenu.resetAfterResults()
      return
    }
    if (root.loading && !root.usesFullscreenResults(root.pendingDomain, root.pendingMode)) {
      liveSearchTimer.stop()
      root.localPluginsSerial += 1
      root.localThemesSerial += 1
      root.webThemesSerial += 1
      root.backgroundsSerial += 1
      root.localPackagesSerial += 1
      root.webPackagesSerial += 1
      root.localAursSerial += 1
      root.webAursSerial += 1
      root.localWebAppsSerial += 1
      root.searchSerial += 1
      root.youtubeSerial += 1
      root.redditSerial += 1
      root.googleSerial += 1
      root.duckduckgoSerial += 1
      root.xSerial += 1
      root.wikipediaSerial += 1
      Plugins.cancel()
      Themes.cancel()
      Backgrounds.cancel()
      Packages.cancel()
      Aurs.cancel()
      WebApps.cancel()
      Files.cancel()
      YouTube.cancel()
      Reddit.cancel()
      Google.cancel()
      DuckDuckGo.cancel()
      X.cancel()
      Wikipedia.cancel()
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
    liveSearchTimer.stop()
    root.clearLayoutResults()

    if (domain === "boot") {
      root.showingResults = true
      root.loading = false
      root.resultRows = []
      cardMenu.prepareForResults()
      previewBoot.loadUnlocks()
      Qt.callLater(function() { previewBoot.focusCarousel() })
      return
    }

    if (domain === "plugins" && mode === "web") {
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      browsePlugins.loadCatalog()
      return
    }

    if (domain === "plugins" && mode === "local") {
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
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      root.localThemesSerial = Themes.installedSerial + 1
      Themes.listInstalled()
      return
    }

    if (domain === "themes" && mode === "web") {
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      root.webThemesSerial = Themes.webSerial + 1
      Themes.loadWeb("")
      return
    }

    if (domain === "background") {
      root.showingResults = true
      root.loading = true
      root.resultRows = []
      cardMenu.prepareForResults()
      root.backgroundsSerial = Backgrounds.listSerial + 1
      Backgrounds.list(mode || "current")
      return
    }

    if (domain === "packages" && mode === "local") {
      root.showingResults = false
      root.loading = true
      root.resultRows = []
      cardMenu.markActionLoading(domain, mode)
      root.localPackagesSerial = Packages.installedSerial + 1
      Packages.listInstalled()
      return
    }

    if (domain === "packages" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.webPackagesSerial = Packages.webSerial + 1
      Packages.searchWeb("")
      return
    }

    if (domain === "aurs" && mode === "local") {
      root.showingResults = false
      root.loading = true
      root.resultRows = []
      cardMenu.markActionLoading(domain, mode)
      root.localAursSerial = Aurs.installedSerial + 1
      Aurs.listInstalled()
      return
    }

    if (domain === "aurs" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.webAursSerial = Aurs.webSerial + 1
      Aurs.searchWeb("")
      return
    }

    if (domain === "webapps" && mode === "local") {
      root.showingResults = false
      root.loading = true
      root.resultRows = []
      cardMenu.markActionLoading(domain, mode)
      root.localWebAppsSerial = WebApps.installedSerial + 1
      WebApps.listInstalled()
      return
    }

    if (domain === "search") {
      root.showingResults = false
      root.loading = true
      root.resultRows = []
      cardMenu.markActionLoading(domain, mode)
      root.searchSerial = Files.list(mode || "files")
      return
    }

    if (domain === "youtube" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.youtubeSerial = YouTube.webSerial + 1
      YouTube.searchWeb("")
      return
    }

    if (domain === "reddit" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.redditSerial = Reddit.webSerial + 1
      Reddit.searchWeb("")
      return
    }

    if (domain === "google" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.googleSerial = Google.webSerial + 1
      Google.searchWeb("")
      return
    }

    if (domain === "duckduckgo" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.duckduckgoSerial = DuckDuckGo.webSerial + 1
      DuckDuckGo.searchWeb("")
      return
    }

    if (domain === "x" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.xSerial = X.webSerial + 1
      X.searchWeb("")
      return
    }

    if (domain === "wikipedia" && mode === "web") {
      if (root.showingResults) {
        root.loading = true
      } else {
        root.showingResults = false
        root.loading = true
        root.resultRows = []
        cardMenu.markActionLoading(domain, mode)
      }
      root.wikipediaSerial = Wikipedia.webSerial + 1
      Wikipedia.searchWeb("")
      return
    }

    console.warn("comtrol: unknown domain/mode", domain, mode)
    root.loading = false
  }

  function toggleSearchHidden() {
    if (root.pendingDomain !== "search")
      return
    Files.toggleHidden()
    root.loading = true
    root.resultRows = []
    if (!root.showingResults)
      cardMenu.markActionLoading("search", root.pendingMode)
    else
      cardMenu.rebuildDisplay()
    root.searchSerial = Files.list(root.pendingMode || "files")
  }


  function finishSearch() {
    if (!root.showingResults)
      root.showingResults = true
    root.loading = false
    cardMenu.clearPendingAction()
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
        mode: root.pendingMode || "local",
        pluginEnabled: item.enabled !== false && item.enabled !== "false" && item.enabled !== 0,
        pluginCanDisable: item.canDisable !== false && item.canDisable !== "false" && item.canDisable !== 0
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

  function packagesToResultRows(packages) {
    var rows = []
    var list = packages || []
    var prevDomain = root.pendingDomain
    root.pendingDomain = "packages"
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      rows.push({
        itemId: root.resultItemId(item, i),
        label: root.resultLabel(item),
        detail: root.resultDetail(item),
        icon: "󰏖",
        kind: "result",
        domain: "packages",
        mode: root.pendingMode || "local"
      })
    }
    root.pendingDomain = prevDomain
    return rows
  }

  function applyLocalPackagesList(packages) {
    if (root.pendingDomain !== "packages" || root.pendingMode !== "local")
      return
    if (Packages.installedSerial !== root.localPackagesSerial)
      return
    root.resultRows = root.packagesToResultRows(packages)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function applyWebPackagesList(packages) {
    if (root.pendingDomain !== "packages" || root.pendingMode !== "web")
      return
    if (Packages.webSerial !== root.webPackagesSerial)
      return
    root.resultRows = root.packagesToResultRows(packages)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function aursToResultRows(packages) {
    var rows = []
    var list = packages || []
    var prevDomain = root.pendingDomain
    root.pendingDomain = "aurs"
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      rows.push({
        itemId: root.resultItemId(item, i),
        label: root.resultLabel(item),
        detail: root.resultDetail(item),
        icon: "󰣇",
        kind: "result",
        domain: "aurs",
        mode: root.pendingMode || "local"
      })
    }
    root.pendingDomain = prevDomain
    return rows
  }

  function applyLocalAursList(packages) {
    if (root.pendingDomain !== "aurs" || root.pendingMode !== "local")
      return
    if (Aurs.installedSerial !== root.localAursSerial)
      return
    root.resultRows = root.aursToResultRows(packages)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function applyWebAursList(packages) {
    if (root.pendingDomain !== "aurs" || root.pendingMode !== "web")
      return
    if (Aurs.webSerial !== root.webAursSerial)
      return
    root.resultRows = root.aursToResultRows(packages)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function webAppsToResultRows(apps) {
    var rows = []
    var list = apps || []
    var prevDomain = root.pendingDomain
    root.pendingDomain = "webapps"
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var iconName = root.jsonField(item, "icon")
      rows.push({
        itemId: root.resultItemId(item, i),
        label: root.resultLabel(item),
        detail: root.resultDetail(item),
        icon: "󰈔",
        appIcon: iconName,
        path: root.jsonField(item, "path"),
        kind: "result",
        domain: "webapps",
        mode: root.pendingMode || "local"
      })
    }
    root.pendingDomain = prevDomain
    return rows
  }

  function applyLocalWebAppsList(apps) {
    if (root.pendingDomain !== "webapps" || root.pendingMode !== "local")
      return
    if (WebApps.installedSerial !== root.localWebAppsSerial)
      return
    root.resultRows = root.webAppsToResultRows(apps)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function searchToResultRows(items) {
    var rows = []
    var list = items || []
    var icon = Files.iconForMode(root.pendingMode)
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var name = root.jsonField(item, "name")
      var path = root.jsonField(item, "path")
      rows.push({
        itemId: path || ("search." + i),
        label: name || path || "?",
        detail: path,
        icon: icon,
        path: path,
        kind: "result",
        domain: "search",
        mode: root.pendingMode || "files"
      })
    }
    return rows
  }

  function applySearchList(items, mode) {
    if (root.pendingDomain !== "search")
      return
    if (mode && mode !== root.pendingMode)
      return
    if (Files.listSerial !== root.searchSerial)
      return
    root.resultRows = root.searchToResultRows(items)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function youtubeToResultRows(results) {
    var rows = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var type = root.jsonField(item, "type") || "video"
      var title = root.jsonField(item, "title")
      var url = root.jsonField(item, "url")
      var thumb = root.jsonField(item, "thumbnail")
      rows.push({
        itemId: url || root.jsonField(item, "id") || ("youtube." + i),
        label: title || url || "?",
        detail: root.jsonField(item, "detail") || root.jsonField(item, "channel"),
        icon: YouTube.iconForType(type),
        appIcon: thumb,
        path: url,
        kind: "result",
        domain: "youtube",
        mode: "web"
      })
    }
    return rows
  }

  function applyYouTubeList(results) {
    if (root.pendingDomain !== "youtube" || root.pendingMode !== "web")
      return
    if (YouTube.webSerial !== root.youtubeSerial)
      return
    root.resultRows = root.youtubeToResultRows(results)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function redditToResultRows(results) {
    var rows = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var type = root.jsonField(item, "type") || "post"
      var title = root.jsonField(item, "title")
      var url = root.jsonField(item, "url")
      var thumb = root.jsonField(item, "thumbnail")
      rows.push({
        itemId: url || root.jsonField(item, "id") || ("reddit." + i),
        label: title || url || "?",
        detail: root.jsonField(item, "detail") || root.jsonField(item, "subreddit"),
        icon: Reddit.iconForType(type),
        appIcon: thumb,
        path: url,
        kind: "result",
        domain: "reddit",
        mode: "web"
      })
    }
    return rows
  }

  function applyRedditList(results) {
    if (root.pendingDomain !== "reddit" || root.pendingMode !== "web")
      return
    if (Reddit.webSerial !== root.redditSerial)
      return
    root.resultRows = root.redditToResultRows(results)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function googleToResultRows(results) {
    var rows = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var type = root.jsonField(item, "type") || "web"
      var title = root.jsonField(item, "title")
      var url = root.jsonField(item, "url")
      var thumb = root.jsonField(item, "thumbnail")
      rows.push({
        itemId: url || root.jsonField(item, "id") || ("google." + i),
        label: title || url || "?",
        detail: root.jsonField(item, "detail") || url,
        icon: Google.iconForType(type),
        appIcon: thumb,
        path: url,
        kind: "result",
        domain: "google",
        mode: "web"
      })
    }
    return rows
  }

  function applyGoogleList(results) {
    if (root.pendingDomain !== "google" || root.pendingMode !== "web")
      return
    if (Google.webSerial !== root.googleSerial)
      return
    root.resultRows = root.googleToResultRows(results)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function duckduckgoToResultRows(results) {
    var rows = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var type = root.jsonField(item, "type") || "web"
      var title = root.jsonField(item, "title")
      var url = root.jsonField(item, "url")
      var thumb = root.jsonField(item, "thumbnail")
      rows.push({
        itemId: url || root.jsonField(item, "id") || ("duckduckgo." + i),
        label: title || url || "?",
        detail: root.jsonField(item, "detail") || url,
        icon: DuckDuckGo.iconForType(type),
        appIcon: thumb,
        path: url,
        kind: "result",
        domain: "duckduckgo",
        mode: "web"
      })
    }
    return rows
  }

  function applyDuckDuckGoList(results) {
    if (root.pendingDomain !== "duckduckgo" || root.pendingMode !== "web")
      return
    if (DuckDuckGo.webSerial !== root.duckduckgoSerial)
      return
    root.resultRows = root.duckduckgoToResultRows(results)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function xToResultRows(results) {
    var rows = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var type = root.jsonField(item, "type") || "tweet"
      var title = root.jsonField(item, "title")
      var url = root.jsonField(item, "url")
      var thumb = root.jsonField(item, "thumbnail")
      rows.push({
        itemId: url || root.jsonField(item, "id") || ("x." + i),
        label: title || url || "?",
        detail: root.jsonField(item, "detail") || root.jsonField(item, "user"),
        icon: X.iconForType(type),
        appIcon: thumb,
        path: url,
        kind: "result",
        domain: "x",
        mode: "web"
      })
    }
    return rows
  }

  function applyXList(results) {
    if (root.pendingDomain !== "x" || root.pendingMode !== "web")
      return
    if (X.webSerial !== root.xSerial)
      return
    root.resultRows = root.xToResultRows(results)
    if (root.loading) {
      root.finishSearch()
      Qt.callLater(root.focusActiveLayout)
    }
  }

  function wikipediaToResultRows(results) {
    var rows = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var type = root.jsonField(item, "type") || "article"
      var title = root.jsonField(item, "title")
      var url = root.jsonField(item, "url")
      var thumb = root.jsonField(item, "thumbnail")
      rows.push({
        itemId: url || root.jsonField(item, "id") || ("wikipedia." + i),
        label: title || url || "?",
        detail: root.jsonField(item, "detail") || url,
        icon: Wikipedia.iconForType(type),
        appIcon: thumb,
        path: url,
        kind: "result",
        domain: "wikipedia",
        mode: "web"
      })
    }
    return rows
  }

  function applyWikipediaList(results) {
    if (root.pendingDomain !== "wikipedia" || root.pendingMode !== "web")
      return
    if (Wikipedia.webSerial !== root.wikipediaSerial)
      return
    root.resultRows = root.wikipediaToResultRows(results)
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

    if (root.pendingDomain === "plugins" && root.pendingMode === "local") {
      root.refreshPluginsAfterRemove = true
      root.loading = true
      root.pendingPluginRemoveSerial = Plugins.remove(id)
      if (root.pendingPluginRemoveSerial < 0) {
        root.refreshPluginsAfterRemove = false
        root.loading = false
      }
      return
    }

    if (root.pendingDomain === "webapps" && root.pendingMode === "local") {
      root.refreshWebAppsAfterRemove = true
      root.loading = true
      root.pendingWebAppRemoveSerial = WebApps.remove(id)
      if (root.pendingWebAppRemoveSerial < 0) {
        root.refreshWebAppsAfterRemove = false
        root.loading = false
      }
      return
    }

    root.refreshPackagesAfterRemove = true
    root.loading = true
    root.pendingPackageRemoveSerial = Packages.remove(id)
    if (root.pendingPackageRemoveSerial < 0) {
      root.refreshPackagesAfterRemove = false
      root.loading = false
    }
  }

  function togglePlugin(name) {
    if (!name)
      return
    if (root.pendingDomain !== "plugins" || root.pendingMode !== "local")
      return
    var id = String(name)
    root.refreshPluginsAfterToggle = true
    root.pendingPluginToggleSerial = Plugins.toggleEnabled(id)
    if (root.pendingPluginToggleSerial < 0) {
      root.refreshPluginsAfterToggle = false
      return
    }
  }

  function runLiveWebSearch() {
    if (!cardMenu.usesLiveFilterSearch)
      return

    if (root.pendingDomain === "packages") {
      root.loading = true
      root.webPackagesSerial = Packages.webSerial + 1
      Packages.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "aurs") {
      root.loading = true
      root.webAursSerial = Aurs.webSerial + 1
      Aurs.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "youtube") {
      root.loading = true
      root.youtubeSerial = YouTube.webSerial + 1
      YouTube.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "reddit") {
      root.loading = true
      root.redditSerial = Reddit.webSerial + 1
      Reddit.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "google") {
      root.loading = true
      root.googleSerial = Google.webSerial + 1
      Google.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "duckduckgo") {
      root.loading = true
      root.duckduckgoSerial = DuckDuckGo.webSerial + 1
      DuckDuckGo.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "x") {
      root.loading = true
      root.xSerial = X.webSerial + 1
      X.searchWeb(String(cardMenu.filterText || ""))
      return
    }

    if (root.pendingDomain === "wikipedia") {
      root.loading = true
      root.wikipediaSerial = Wikipedia.webSerial + 1
      Wikipedia.searchWeb(String(cardMenu.filterText || ""))
    }
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

  Timer {
    id: liveSearchTimer
    interval: (root.pendingDomain === "youtube" || root.pendingDomain === "reddit"
               || root.pendingDomain === "google" || root.pendingDomain === "duckduckgo"
               || root.pendingDomain === "x"
               || root.pendingDomain === "wikipedia") ? 700 : 250
    repeat: false
    onTriggered: root.runLiveWebSearch()
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
      onLiveSearchRequested: liveSearchTimer.restart()
      onRemovePackageRequested: function(name) { root.removePackage(name) }
      onTogglePluginRequested: function(name) { root.togglePlugin(name) }
      onToggleSearchHiddenRequested: root.toggleSearchHidden()
    }

    Connections {
      target: Plugins
      function onInstalledListed(plugins) {
        root.applyLocalPluginsList(plugins)
      }
      function onRemoveFinished(exitCode, serial, payload) {
        if (serial !== root.pendingPluginRemoveSerial)
          return
        root.pendingPluginRemoveSerial = -1
        if (!root.refreshPluginsAfterRemove)
          return
        root.refreshPluginsAfterRemove = false
        Qt.callLater(function() {
          if (!root.opened)
            return
          root.runComtrol("plugins", "local", root.resultsTitle || "Plugins")
        })
      }
      function onSetEnabledFinished(exitCode, serial, pluginId, enabled) {
        if (serial !== root.pendingPluginToggleSerial)
          return
        root.pendingPluginToggleSerial = -1
        root.refreshPluginsAfterToggle = false
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

    Connections {
      target: Packages
      function onLocalListed(packages) {
        root.applyLocalPackagesList(packages)
      }
      function onWebListed(packages) {
        root.applyWebPackagesList(packages)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "packages" || root.pendingMode !== "web")
          return
        if (Packages.webSerial !== root.webPackagesSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "Package search failed"),
          detail: "",
          icon: "󰀦",
          kind: "result",
          domain: "",
          mode: ""
        }]
        root.finishSearch()
        Qt.callLater(root.focusActiveLayout)
      }
      function onRemoveFinished(exitCode, serial, payload) {
        if (serial !== root.pendingPackageRemoveSerial)
          return
        root.pendingPackageRemoveSerial = -1
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

    Connections {
      target: Aurs
      function onLocalListed(packages) {
        root.applyLocalAursList(packages)
      }
      function onWebListed(packages) {
        root.applyWebAursList(packages)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "aurs" || root.pendingMode !== "web")
          return
        if (Aurs.webSerial !== root.webAursSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "AUR search failed"),
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
      target: WebApps
      function onLocalListed(apps) {
        root.applyLocalWebAppsList(apps)
      }
      function onRemoveFinished(exitCode, serial, payload) {
        if (serial !== root.pendingWebAppRemoveSerial)
          return
        root.pendingWebAppRemoveSerial = -1
        if (!root.refreshWebAppsAfterRemove)
          return
        root.refreshWebAppsAfterRemove = false
        Qt.callLater(function() {
          if (!root.opened)
            return
          root.runComtrol("webapps", "local", root.resultsTitle || "Web Apps")
        })
      }
    }

    Connections {
      target: Files
      function onListed(items, mode) {
        root.applySearchList(items, mode)
      }
    }

    Connections {
      target: YouTube
      function onWebListed(results) {
        root.applyYouTubeList(results)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "youtube" || root.pendingMode !== "web")
          return
        if (YouTube.webSerial !== root.youtubeSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "YouTube search failed"),
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
      target: Reddit
      function onWebListed(results) {
        root.applyRedditList(results)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "reddit" || root.pendingMode !== "web")
          return
        if (Reddit.webSerial !== root.redditSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "Reddit search failed"),
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
      target: Google
      function onWebListed(results) {
        root.applyGoogleList(results)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "google" || root.pendingMode !== "web")
          return
        if (Google.webSerial !== root.googleSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "Google search failed"),
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
      target: DuckDuckGo
      function onWebListed(results) {
        root.applyDuckDuckGoList(results)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "duckduckgo" || root.pendingMode !== "web")
          return
        if (DuckDuckGo.webSerial !== root.duckduckgoSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "DuckDuckGo search failed"),
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
      target: X
      function onWebListed(results) {
        root.applyXList(results)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "x" || root.pendingMode !== "web")
          return
        if (X.webSerial !== root.xSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "X search failed"),
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
      target: Wikipedia
      function onWebListed(results) {
        root.applyWikipediaList(results)
      }
      function onWebFailed(message) {
        if (root.pendingDomain !== "wikipedia" || root.pendingMode !== "web")
          return
        if (Wikipedia.webSerial !== root.wikipediaSerial)
          return
        root.resultRows = [{
          itemId: "result.error",
          label: String(message || "Wikipedia search failed"),
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
  }
}
