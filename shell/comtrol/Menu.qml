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
  property var backgroundResults: []
  property var selectedPlugin: null
  property var installedPluginIds: ({})
  property string pendingDomain: ""
  property string pendingMode: ""
  property int searchSerial: 0
  property int installedPluginsSerial: 0

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property bool usePreviewTheme: showingResults
    && !loading
    && pendingDomain === "themes"
    && (pendingMode === "local" || pendingMode === "web")
  readonly property bool usePreviewBackground: showingResults
    && !loading
    && pendingDomain === "background"
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
  readonly property bool useFullscreenLayout: usePreviewTheme || useBrowsePlugins || usePluginDetail || usePreviewBackground

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
  readonly property bool menuSearchActive: !showingResults && filterText.trim().length > 0
  readonly property int activeRowHeight: (resultsHaveDetail || menuSearchActive) ? detailRowHeight : rowHeight
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
        { itemId: "themes", label: "Themes", icon: "󰏘", kind: "menu" },
        { itemId: "background", label: "Backgrounds", icon: "󰸉", kind: "menu" }
      ]
    },
    "themes": {
      title: "Themes",
      rows: [
        { itemId: "themes.web", label: "Install", icon: "󰐕", kind: "action", domain: "themes", mode: "web" },
        { itemId: "themes.local", label: "Installed", icon: "󰉋", kind: "action", domain: "themes", mode: "local" }
      ]
    },
    "background": {
      title: "Backgrounds",
      rows: [
        { itemId: "background.theme", label: "Theme", icon: "󰏘", kind: "action", domain: "background", mode: "current" },
        { itemId: "background.themes", label: "All themes", icon: "󰕰", kind: "action", domain: "background", mode: "themes" },
        { itemId: "background.wallpapers", label: "My wallpapers", icon: "󰋩", kind: "action", domain: "background", mode: "wallpapers" },
        { itemId: "background.all", label: "All wallpapers", icon: "󰸉", kind: "action", domain: "background", mode: "all" }
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
        { itemId: "plugins.web", label: "Install", icon: "󰐕", kind: "action", domain: "plugins", mode: "web" },
        { itemId: "plugins.local", label: "Installed", icon: "󰉋", kind: "action", domain: "plugins", mode: "local" }
      ]
    },
    "packages": {
      title: "Packages",
      rows: [
        { itemId: "packages.web", label: "Install", icon: "󰐕", kind: "action", domain: "packages", mode: "web" },
        { itemId: "packages.local", label: "Installed", icon: "󰉋", kind: "action", domain: "packages", mode: "local" }
      ]
    },
    "aurs": {
      title: "AUR",
      rows: [
        { itemId: "aurs.web", label: "Install", icon: "󰐕", kind: "action", domain: "aurs", mode: "web" },
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
    root.backgroundResults = []
    root.selectedPlugin = null
    root.installedPluginIds = ({})
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    if (root.appLibrary)
      root.appLibrary.refreshIcons()
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

  function parentMenuOf(menuId) {
    var id = String(menuId || "")
    if (!id)
      return ""
    for (var key in root.menus) {
      var rows = (root.menus[key] && root.menus[key].rows) || []
      for (var i = 0; i < rows.length; i++) {
        var row = rows[i] || {}
        if (String(row.kind || "") === "menu" && String(row.itemId || "") === id)
          return key
      }
    }
    return ""
  }

  function ancestorsOf(menuId) {
    var chain = []
    var cur = root.parentMenuOf(menuId)
    while (cur) {
      chain.unshift(cur)
      if (cur === "root")
        break
      cur = root.parentMenuOf(cur)
    }
    return chain
  }

  // Flatten actionable rows under menuId (and nested menus), with breadcrumb detail.
  function collectDescendantRows(menuId) {
    var out = []
    function walk(id, pathLabels) {
      var menu = root.menus[id]
      if (!menu)
        return
      var rows = menu.rows || []
      for (var i = 0; i < rows.length; i++) {
        var row = rows[i] || {}
        var itemId = String(row.itemId || "")
        var label = String(row.label || "")
        var kind = String(row.kind || "")
        out.push({
          itemId: itemId,
          kind: kind,
          icon: String(row.icon || ""),
          label: label,
          detail: pathLabels.join(" › "),
          domain: String(row.domain || ""),
          mode: String(row.mode || "")
        })
        if (kind === "menu" && itemId)
          walk(itemId, pathLabels.concat([label]))
      }
    }
    walk(String(menuId || "root"), [])
    return out
  }

  function rowMatchesQuery(row, query) {
    if (!query)
      return true
    var q = String(query).toLowerCase()
    var label = String(row.label || "").toLowerCase()
    var itemId = String(row.itemId || "").toLowerCase()
    var detail = String(row.detail || "").toLowerCase()
    return label.indexOf(q) >= 0 || itemId.indexOf(q) >= 0 || detail.indexOf(q) >= 0
  }

  // Desktop apps via Omarchy AppLibrary (same source as omarchy.menu Apps),
  // with a DesktopEntries fallback if the shell proxy is unavailable.
  function collectAppSearchRows(query) {
    var out = []
    var q = String(query || "").trim()
    if (!q)
      return out

    var rows = []
    if (root.appLibrary) {
      try {
        rows = root.appLibrary.sortedEntries(q) || []
      } catch (e) {
        console.warn("comtrol appLibrary.sortedEntries failed:", e)
        rows = []
      }
    }

    var count = rows && rows.length !== undefined ? rows.length : 0
    if (count > 0) {
      var limit = Math.min(count, 40)
      for (var i = 0; i < limit; i++) {
        var hit = rows[i] || {}
        var entry = hit.entry || hit
        if (!entry)
          continue
        var appId = String(entry.id || "")
        if (!appId)
          continue
        var label = appId
        var subtext = ""
        var iconName = ""
        try {
          if (root.appLibrary) {
            label = root.appLibrary.entryName(entry) || appId
            subtext = root.appLibrary.entrySubtext(entry) || ""
          } else {
            label = String(entry.name || appId)
            subtext = String(entry.genericName || "")
          }
          iconName = String(entry.icon || "")
        } catch (e2) {
          label = appId
        }
        out.push({
          itemId: appId,
          kind: "app",
          icon: "",
          appIcon: iconName,
          label: label,
          detail: subtext || "Application",
          domain: "",
          mode: ""
        })
      }
      return out
    }

    // Fallback: scan DesktopEntries directly (same underlying catalog).
    try {
      var values = DesktopEntries.applications.values || []
      var ql = q.toLowerCase()
      var max = Math.min(values.length, 5000)
      for (var j = 0; j < max && out.length < 40; j++) {
        var e = values[j]
        if (!e || e.noDisplay)
          continue
        var name = String(e.name || "")
        var id = String(e.id || "")
        if (!name && !id)
          continue
        var hay = (name + " " + String(e.genericName || "") + " " + id).toLowerCase()
        if (hay.indexOf(ql) < 0)
          continue
        out.push({
          itemId: id || name,
          kind: "app",
          icon: "",
          appIcon: String(e.icon || ""),
          label: name || id,
          detail: String(e.genericName || "Application"),
          domain: "",
          mode: ""
        })
      }
    } catch (e3) {
      console.warn("comtrol DesktopEntries fallback failed:", e3)
    }
    return out
  }

  function rebuildDisplay() {
    var q = root.usesRustFilterSearch() ? "" : root.filterText.trim().toLowerCase()
    var rows = []

    if (root.showingResults) {
      rows = (root.currentMenu().rows || []).slice()
    } else if (q) {
      // Search current menu + nested submenus, then desktop apps (AppLibrary).
      rows = root.collectDescendantRows(root.activeMenu)
      var appHits = root.collectAppSearchRows(root.filterText.trim())
      for (var h = 0; h < appHits.length; h++)
        rows.push(appHits[h])
    } else {
      rows = ((root.menus[root.activeMenu] || root.menus.root).rows || []).slice()
    }

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] || {}
      // App hits are already filtered/scored by AppLibrary.
      if (q && String(row.kind || "") !== "app" && !root.rowMatchesQuery(row, q))
        continue
      displayModel.append({
        itemId: String(row.itemId || row.id || ""),
        kind: String(row.kind || ""),
        icon: String(row.icon || ""),
        appIcon: String(row.appIcon || ""),
        label: String(row.label || ""),
        detail: String(row.detail || ""),
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
      if (themeApplyProc.running)
        themeApplyProc.running = false
      if (themeRemoveProc.running)
        themeRemoveProc.running = false
      root.showingResults = false
      root.loading = false
      root.resultRows = []
      root.themeResults = []
      root.pluginResults = []
      root.backgroundResults = []
      root.selectedPlugin = null
      root.installedPluginIds = ({})
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
      // From search hits, rebuild the back stack so Back walks the real parents.
      root.navStack = root.ancestorsOf(row.itemId)
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
    if (row.kind === "app") {
      if (root.appLibrary)
        root.appLibrary.launch(row.itemId, row.label)
      root.dismiss()
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
    root.backgroundResults = []
    root.selectedPlugin = null
    root.installedPluginIds = ({})
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    rustSearchTimer.stop()
    root.rebuildDisplay()

    // Installed → system view (-v); Install → search web (-s -w);
    // Background → system view with source (-v -background -current|…)
    root.searchSerial += 1
    searchProcess.serial = root.searchSerial
    var argv
    if (domain === "background")
      argv = [root.runScript(), "-v", "-background", "-" + String(mode || "current")]
    else if (mode === "local")
      argv = [root.runScript(), "-v", root.domainFlag(domain)]
    else
      argv = [root.runScript(), "-s", root.domainFlag(domain), "-w"]
    searchProcess.command = argv
    searchProcess.running = true

    if (domain === "plugins" && mode === "web")
      root.refreshInstalledPlugins()
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
        root.backgroundResults = []
        return rows
      }

      if (root.pendingDomain === "background") {
        var backgrounds = []
        for (var b = 0; b < data.length; b++) {
          var bg = data[b] || {}
          var path = root.jsonField(bg, "path")
          if (!path)
            continue
          backgrounds.push({ path: path })
        }
        root.backgroundResults = backgrounds
        root.themeResults = []
        root.pluginResults = []
        return rows
      }

      if (root.pendingDomain === "plugins" && root.pendingMode === "web") {
        var plugins = []
        for (var p = 0; p < data.length; p++) {
          var plugin = data[p] || {}
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
          plugins.push({
            id: root.jsonField(plugin, "id"),
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
            installed: !!root.installedPluginIds[root.jsonField(plugin, "id")],
            mode: "web"
          })
        }
        root.pluginResults = plugins
        root.themeResults = []
        root.backgroundResults = []
        return rows
      }

      root.themeResults = []
      root.pluginResults = []
      root.backgroundResults = []
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
      root.backgroundResults = []
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

  function applyBackground(background) {
    if (!background)
      return
    var path = String(background.path || background["path"] || "")
    if (!path)
      return
    // Same end-step as omarchy-menu: switcher returns a path, then bg-set applies it.
    if (themeApplyProc.running)
      themeApplyProc.running = false
    themeApplyProc.command = ["omarchy-theme-bg-set", path]
    themeApplyProc.running = true
  }

  function applyPlugin(plugin) {
    if (!plugin)
      return
    // Catalog install_command is typically: "omarchy plugin add <git-url> --enable"
    var cmd = String(plugin.install_command || "").trim()
    if (!cmd)
      return
    // Quickshell Process has no TTY — omarchy-plugin-add refuses without --yes.
    if (cmd.indexOf("--yes") < 0 && !/(^|\s)-y(\s|$)/.test(cmd))
      cmd += " --yes"
    if (themeApplyProc.running)
      themeApplyProc.running = false
    themeApplyProc.command = ["bash", "-lc", cmd]
    themeApplyProc.running = true
  }

  function removePlugin(plugin) {
    if (!plugin)
      return
    var id = String(plugin.id || plugin["id"] || "")
    if (!id)
      return
    // Rust: cOMtrol -r -plugin <id>
    if (themeRemoveProc.running)
      themeRemoveProc.running = false
    themeRemoveProc.command = [root.runScript(), "-r", "-plugin", id]
    themeRemoveProc.running = true
  }

  function refreshInstalledPlugins() {
    root.installedPluginsSerial += 1
    installedPluginsProc.serial = root.installedPluginsSerial
    if (installedPluginsProc.running)
      installedPluginsProc.running = false
    installedPluginsProc.command = [root.runScript(), "-v", "-plugin"]
    installedPluginsProc.running = true
  }

  function applyInstalledFlags() {
    var ids = root.installedPluginIds || ({})
    var list = root.pluginResults || []
    var next = []
    for (var i = 0; i < list.length; i++) {
      var p = list[i] || {}
      var copy = ({})
      for (var k in p)
        copy[k] = p[k]
      copy.installed = !!ids[String(p.id || "")]
      next.push(copy)
    }
    root.pluginResults = next
    if (root.selectedPlugin) {
      var sel = ({})
      for (var sk in root.selectedPlugin)
        sel[sk] = root.selectedPlugin[sk]
      sel.installed = !!ids[String(sel.id || "")]
      root.selectedPlugin = sel
    }
  }

  function openPluginDetail(plugin) {
    if (!plugin)
      return
    var next = ({})
    for (var k in plugin)
      next[k] = plugin[k]
    next.installed = !!root.installedPluginIds[String(plugin.id || "")]
    root.selectedPlugin = next
    Qt.callLater(function() {
      if (root.usePluginDetail)
        pluginDetail.focusDetail()
    })
  }

  function bumpPluginHearts(pluginId) {
    var id = String(pluginId || "")
    if (!id)
      return
    var list = root.pluginResults || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id || "") === id) {
        list[i].hearts = Number(list[i].hearts || 0) + 1
        break
      }
    }
    root.pluginResults = list.slice()
    if (root.selectedPlugin && String(root.selectedPlugin.id || "") === id) {
      var next = ({})
      for (var k in root.selectedPlugin)
        next[k] = root.selectedPlugin[k]
      next.hearts = Number(next.hearts || 0) + 1
      // heartSent in detail already +1 visually; sync base count and reset flag via reassignment
      root.selectedPlugin = next
    }
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

  function removeBackground(background) {
    if (!background)
      return
    var path = String(background.path || background["path"] || "")
    if (!path)
      return
    // Rust: cOMtrol -r -background <absolute-path>
    if (themeRemoveProc.running)
      themeRemoveProc.running = false
    themeRemoveProc.command = [root.runScript(), "-r", "-background", path]
    themeRemoveProc.running = true
  }

  ListModel { id: displayModel }

  Process {
    id: themeApplyProc
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingDomain === "plugins" && root.pendingMode === "web")
        root.refreshInstalledPlugins()
    }
  }

  Process {
    id: themeRemoveProc
    onExited: function(exitCode) {
      // Refresh local theme list after Rust remove (success or partial).
      if (root.pendingDomain === "themes" && root.pendingMode === "local")
        root.runComtrol("themes", "local", "Installed")
      else if (root.pendingDomain === "plugins" && root.pendingMode === "web")
        root.refreshInstalledPlugins()
      else if (root.pendingDomain === "background")
        root.runComtrol("background", root.pendingMode, root.resultsTitle)
    }
  }

  Process {
    id: installedPluginsProc
    property int serial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (installedPluginsProc.serial !== root.installedPluginsSerial)
          return
        var ids = ({})
        try {
          var data = JSON.parse(String(text || "[]"))
          if (data && data.length !== undefined) {
            for (var i = 0; i < data.length; i++) {
              var id = root.jsonField(data[i] || {}, "id")
              if (id)
                ids[id] = true
            }
          }
        } catch (e) {
          ids = ({})
        }
        root.installedPluginIds = ids
        root.applyInstalledFlags()
      }
    }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.opened && root.menuSearchActive)
        root.rebuildDisplay()
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
        else if (root.usePreviewBackground)
          Qt.callLater(function() { previewBackground.focusCarousel() })
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
            && root.themeResults.length === 0 && root.pluginResults.length === 0
            && root.backgroundResults.length === 0) {
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
          && root.themeResults.length === 0 && root.pluginResults.length === 0
          && root.backgroundResults.length === 0) {
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
      else if (root.usePreviewBackground)
        Qt.callLater(function() { previewBackground.focusCarousel() })
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
      onDismissRequested: root.dismiss()
    }

    Layouts.BackgroundPreview {
      id: previewBackground
      anchors.fill: parent
      visible: root.usePreviewBackground
      backgrounds: root.backgroundResults
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
      onBackgroundActivated: function(background) { root.applyBackground(background) }
      onBackgroundRemoveRequested: function(background) { root.removeBackground(background) }
    }

    Layouts.BrowsePlugins {
      id: browsePlugins
      anchors.fill: parent
      visible: root.useBrowsePlugins
      plugins: root.pluginResults
      onBackRequested: root.goBack()
      onPluginActivated: function(plugin) { root.openPluginDetail(plugin) }
      onDismissRequested: root.dismiss()
    }

    Layouts.PluginDetail {
      id: pluginDetail
      anchors.fill: parent
      visible: root.usePluginDetail
      plugin: root.selectedPlugin || ({})
      onBackRequested: root.goBack()
      onDismissRequested: root.dismiss()
      onInstallRequested: function(plugin) { root.applyPlugin(plugin) }
      onRemoveRequested: function(plugin) { root.removePlugin(plugin) }
      onHeartSentFor: function(pluginId) { root.bumpPluginHearts(pluginId) }
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
            root.dismiss()
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
              required property string appIcon
              required property string label
              required property string detail
              required property string domain
              required property string mode

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool hasDetail: detail.length > 0
              readonly property bool isApp: kind === "app"

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

                Item {
                  width: Style.space(36)
                  height: parent.height

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: !row.isApp
                    text: row.icon
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                  }

                  Image {
                    anchors.centerIn: parent
                    visible: row.isApp
                    width: Style.font.iconLarge
                    height: Style.font.iconLarge
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: row.isApp && root.appLibrary
                      ? root.appLibrary.iconSource(row.appIcon)
                      : ""
                    asynchronous: true
                  }
                }

                Column {
                  width: Math.max(
                    Style.space(40),
                    parent.width - Style.space(36) - Style.space(12) - Style.space(16) - Style.space(24)
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
                  text: (row.kind === "menu" || row.kind === "action") ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: (row.kind === "menu" || row.kind === "action") ? 0.36 : 0
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
