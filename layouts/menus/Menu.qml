import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "../../functions"

// Card menu: navigation tree, desktop apps, and list results (packages/AUR/etc.).
Item {
  id: root

  property var shell
  property bool showingResults: false
  property bool loading: false
  property string resultsTitle: "Results"
  property var resultRows: []
  property string pendingDomain: ""
  property string pendingMode: ""

  property string activeMenu: "root"
  property var navStack: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  // After keyboard navigation, ignore hover until the pointer actually moves.
  // Prevents ListView rebuilds from stealing selection via HoverHandler recreate.
  property bool suppressPointerSelect: false
  property real pointerArmX: -1
  property real pointerArmY: -1
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property string pendingActionDomain: ""
  property string pendingActionMode: ""

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  // Slightly larger type than the shared shell scale for menu readability.
  readonly property real menuFontScale: 1.25
  readonly property int menuFontCaption: Math.max(1, Math.round(Style.font.caption * menuFontScale))
  readonly property int menuFontBody: Math.max(1, Math.round(Style.font.body * menuFontScale))
  readonly property int menuFontHeading: Math.max(1, Math.round(Style.font.heading * menuFontScale))
  readonly property int menuFontIcon: Math.max(1, Math.round(Style.font.iconLarge * menuFontScale))
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(40), menuFontHeading + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(42), menuFontBody + Style.spacing.controlPaddingY * 2)
  property int detailRowHeight: Math.max(Style.space(60), menuFontBody + menuFontCaption + Style.spacing.controlPaddingY * 2)
  property int rowSpacing: Style.spacing.xs
  property int cardWidth: Math.min(Style.space(560), parent.width - Style.gapsOut * 2)
  readonly property bool resultsHaveDetail: showingResults
    && (pendingDomain === "packages" || pendingDomain === "aurs" || pendingDomain === "search"
        || pendingDomain === "youtube" || pendingDomain === "reddit"
        || pendingDomain === "google" || pendingDomain === "duckduckgo" || pendingDomain === "x"
        || pendingDomain === "wikipedia")
  readonly property bool menuSearchActive: !showingResults && filterText.trim().length > 0
  readonly property bool applicationsMenuActive: !showingResults && activeMenu === "applications"
  readonly property int activeRowHeight: (resultsHaveDetail || menuSearchActive || applicationsMenuActive) ? detailRowHeight : rowHeight
  readonly property bool fontsMenuActive: !showingResults && filterText.trim().length === 0 && activeMenu === "fonts"
  readonly property bool desktopMenuActive: !showingResults && filterText.trim().length === 0 && activeMenu === appearanceDesktop.itemId
  readonly property bool desktopOpacityGroupActive: !showingResults && filterText.trim().length === 0
    && appearanceDesktop.isOpacityGroupMenu(activeMenu)
  readonly property int visibleRowsHeight: {
    var available = Math.max(activeRowHeight, parent.height - Style.gapsOut * 2 - headerHeight - contentSpacing - contentMargin * 2)
    var h
    if (root.fontsMenuActive)
      h = rowHeight + rowSpacing + appearanceFonts.sliderRowHeight
    else if (root.desktopMenuActive)
      h = 4 * rowHeight + 5 * appearanceDesktop.sliderRowHeight + 8 * rowSpacing
    else if (root.desktopOpacityGroupActive)
      h = 2 * appearanceDesktop.sliderRowHeight + rowSpacing
    else
      h = Math.max(displayModel.count, 1) * (activeRowHeight + rowSpacing) - rowSpacing
    return Math.min(h, available)
  }
  readonly property int cardHeight: headerHeight + contentSpacing + visibleRowsHeight + contentMargin * 2
  readonly property bool usesLiveFilterSearch: showingResults
    && pendingMode === "web"
    && (pendingDomain === "packages" || pendingDomain === "aurs"
        || pendingDomain === "youtube" || pendingDomain === "reddit"
        || pendingDomain === "google" || pendingDomain === "duckduckgo" || pendingDomain === "x"
        || pendingDomain === "wikipedia")

  signal backRequested()
  signal dismissRequested()
  signal actionRequested(string domain, string mode, string title)
  signal liveSearchRequested(string query)
  signal removePackageRequested(string name)
  signal togglePluginRequested(string name)
  signal toggleSearchHiddenRequested()

  Install {
    id: installMenu
  }

  Update {
    id: updateMenu
    onChanged: {
      if (updateMenu.isUpdateMenu(root.activeMenu))
        root.rebuildDisplay()
    }
  }

  Config {
    id: configMenu
    onChanged: {
      if (configMenu.isConfigMenu(root.activeMenu))
        root.rebuildDisplay()
    }
  }

  Reset {
    id: resetMenu
  }

  Search {
    id: searchMenu
  }

  Power {
    id: powerMenu
    onChanged: {
      if (root.activeMenu === powerMenu.itemId)
        root.rebuildDisplay()
    }
  }

  Defaults {
    id: defaultsMenu
    onChanged: {
      if (defaultsMenu.isDefaultsMenu(root.activeMenu))
        root.rebuildDisplay()
    }
  }

  Apperiance_Fonts {
    id: appearanceFonts
    background: root.background
    foreground: root.foreground
    selectedText: root.selectedText
    fontFamily: root.fontFamily
    onFontsChanged: {
      if (appearanceFonts.awaitingList) {
        root.enterFontChange()
        return
      }
      if (root.activeMenu === appearanceFonts.changeItemId) {
        root.rebuildDisplay()
        root.selectedIndex = appearanceFonts.currentIndex
        return
      }
      if (root.activeMenu === appearanceFonts.itemId)
        root.rebuildDisplay()
    }
  }

  Apperiance_Desktop {
    id: appearanceDesktop
    background: root.background
    foreground: root.foreground
    selectedText: root.selectedText
    fontFamily: root.fontFamily
    onChanged: {
      if (root.activeMenu === appearanceDesktop.itemId
          || root.activeMenu === appearanceDesktop.positionItemId
          || root.activeMenu === appearanceDesktop.opacityItemId
          || appearanceDesktop.isOpacityGroupMenu(root.activeMenu))
        root.rebuildDisplay()
    }
  }

  readonly property var menus: {
    var tree = {
      "root": {
        title: "Control",
        rows: [
          { itemId: "appearance", label: "Appearance", icon: "", kind: "menu" },
          { itemId: "apps", label: "Apps", icon: "󰀻", kind: "menu" },
          searchMenu.rootRow,
          installMenu.rootRow,
          configMenu.rootRow,
          resetMenu.rootRow,
          powerMenu.rootRow
        ]
      },
      "appearance": {
        title: "Appearance",
        rows: [
          { itemId: "themes", label: "Themes", icon: "󰏘", kind: "action", domain: "themes", mode: "local" },
          { itemId: "background", label: "Backgrounds", icon: "󰸉", kind: "menu" },
          { itemId: "boot", label: "Unlock", icon: "󰟵", kind: "action", domain: "boot", mode: "local" },
          appearanceFonts.rootRow,
          appearanceDesktop.rootRow
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
          { itemId: "applications", label: "Desktop", icon: "󰀻", kind: "menu" },
          { itemId: "packages", label: "Packages", icon: "󰏖", kind: "action", domain: "packages", mode: "local" },
          { itemId: "aurs", label: "AUR", icon: "󰣇", kind: "action", domain: "aurs", mode: "local" },
          { itemId: "webapps", label: "Web Apps", icon: "󰖟", kind: "action", domain: "webapps", mode: "local" }
        ]
      },
      "applications": {
        title: "Desktop",
        rows: []
      },
    }
    tree[installMenu.itemId] = {
      title: installMenu.menu.title,
      rows: (installMenu.menu.rows || []).concat([updateMenu.rootRow])
    }
    tree[updateMenu.itemId] = updateMenu.menu
    tree[configMenu.itemId] = {
      title: configMenu.menu.title,
      rows: (configMenu.menu.rows || []).concat([defaultsMenu.rootRow])
    }
    tree[configMenu.channelItemId] = configMenu.channelMenu
    tree[configMenu.passwordItemId] = configMenu.passwordMenu
    tree[resetMenu.itemId] = resetMenu.menu
    tree[resetMenu.configItemId] = resetMenu.configMenu
    tree[resetMenu.processItemId] = resetMenu.processMenu
    tree[resetMenu.hardwareItemId] = resetMenu.hardwareMenu
    // Web search needs Node.js; hide the entry until we know it's available.
    var nodeOk = WebBrowser.nodeAvailable
    var searchRows = []
    var rawSearchRows = (searchMenu.menu && searchMenu.menu.rows) || []
    for (var si = 0; si < rawSearchRows.length; si++) {
      var srow = rawSearchRows[si] || {}
      if (String(srow.itemId || "") === searchMenu.webItemId && !nodeOk)
        continue
      searchRows.push(srow)
    }
    tree[searchMenu.itemId] = {
      title: searchMenu.menu.title,
      rows: searchRows
    }
    if (nodeOk)
      tree[searchMenu.webItemId] = searchMenu.webMenu
    tree[powerMenu.itemId] = powerMenu.menu
    tree[defaultsMenu.itemId] = defaultsMenu.menu
    tree[defaultsMenu.browserItemId] = defaultsMenu.browserMenu
    tree[defaultsMenu.terminalItemId] = defaultsMenu.terminalMenu
    tree[defaultsMenu.editorItemId] = defaultsMenu.editorMenu
    tree[defaultsMenu.agentItemId] = defaultsMenu.agentMenu
    tree[appearanceFonts.itemId] = appearanceFonts.menu
    tree[appearanceFonts.changeItemId] = appearanceFonts.changeMenu
    tree[appearanceDesktop.itemId] = appearanceDesktop.menu
    tree[appearanceDesktop.positionItemId] = appearanceDesktop.positionMenu
    var opacityMenus = appearanceDesktop.opacityGroupMenus()
    for (var opacityKey in opacityMenus)
      tree[opacityKey] = opacityMenus[opacityKey]
    return tree
  }

  onShellChanged: {
    if (root.applicationsMenuActive)
      root.rebuildDisplay()
    if (root.appLibrary)
      root.appLibrary.refreshIcons()
  }
  onShowingResultsChanged: root.rebuildDisplay()
  onResultRowsChanged: root.rebuildDisplay()
  onLoadingChanged: root.rebuildDisplay()

  function open(payload) {
    var data = payload || ({})
    root.navStack = []
    root.activeMenu = data.initialMenu || data.menu || "root"
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.pendingActionDomain = ""
    root.pendingActionMode = ""
    root.rebuildDisplay()
    root.refreshLocalIcons()
    if (root.appLibrary)
      root.appLibrary.refreshIcons()
  }

  function focusMenu() {
    keyCatcher.forceActiveFocus()
  }

  function resetAfterResults() {
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    root.focusMenu()
    root.syncWebBrowser()
  }

  function prepareForResults() {
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.pendingActionDomain = ""
    root.pendingActionMode = ""
    root.rebuildDisplay()
    root.syncWebBrowser()
  }

  function markActionLoading(domain, mode) {
    root.pendingActionDomain = String(domain || "")
    root.pendingActionMode = String(mode || "")
    root.rebuildDisplay()
    root.syncWebBrowser()
  }

  function clearPendingAction() {
    if (!root.pendingActionDomain && !root.pendingActionMode)
      return
    root.pendingActionDomain = ""
    root.pendingActionMode = ""
    if (!root.showingResults)
      root.rebuildDisplay()
  }

  function isWebMenuContext() {
    if (root.activeMenu === searchMenu.webItemId)
      return true
    // Keep browser warm during web search loading/results even if menu id drifted.
    if (!(root.showingResults || root.pendingActionDomain))
      return false
    var d = String(root.pendingDomain || root.pendingActionDomain || "")
    return d === "youtube" || d === "reddit" || d === "google"
      || d === "duckduckgo" || d === "x" || d === "wikipedia"
  }

  function syncWebBrowser() {
    if (root.isWebMenuContext())
      WebBrowser.warm()
    else
      WebBrowser.cool()
  }

  // Pop one menu level. Returns false when already at root (caller should dismiss).
  function navigateBack() {
    if (root.navStack.length === 0)
      return false
    root.activeMenu = root.navStack.pop()
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    root.syncWebBrowser()
    return true
  }

  function currentMenu() {
    if (root.showingResults)
      return { title: root.loading ? "Loading" : root.resultsTitle, rows: root.resultRows }
    return root.menus[root.activeMenu] || root.menus.root
  }

  function rowHeightForKind(kind) {
    if (kind === "slider")
      return appearanceFonts.sliderRowHeight
    return root.activeRowHeight
  }

  function isSliderSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count)
      return false
    return String(displayModel.get(root.selectedIndex).kind || "") === "slider"
  }

  function selectedItemId() {
    if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count)
      return ""
    return String(displayModel.get(root.selectedIndex).itemId || "")
  }

  function adjustSelectedSlider(delta) {
    root.noteKeyboardSelection()
    var id = root.selectedItemId()
    if (id === appearanceDesktop.blurItemId
        || appearanceDesktop.isLookSlider(id)
        || appearanceDesktop.groupIdFromSlider(id))
      appearanceDesktop.adjustSlider(id, delta)
    else
      appearanceFonts.adjustSize(delta)
  }

  function noteKeyboardSelection() {
    root.suppressPointerSelect = true
    root.pointerArmX = -1
    root.pointerArmY = -1
    root.cursorActive = true
    pointerSuppressTimer.restart()
  }

  function pointerSelect(index) {
    if (root.suppressPointerSelect)
      return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function considerPointerMove(x, y) {
    if (!root.suppressPointerSelect)
      return
    if (root.pointerArmX < 0) {
      root.pointerArmX = x
      root.pointerArmY = y
      return
    }
    if (Math.abs(x - root.pointerArmX) >= 2 || Math.abs(y - root.pointerArmY) >= 2) {
      root.suppressPointerSelect = false
      pointerSuppressTimer.stop()
    }
  }

  Timer {
    id: pointerSuppressTimer
    interval: 750
    repeat: false
    onTriggered: root.suppressPointerSelect = false
  }

  function enterFontChange() {
    appearanceFonts.awaitingList = false
    root.navStack = root.ancestorsOf(appearanceFonts.changeItemId)
    root.activeMenu = appearanceFonts.changeItemId
    root.filterText = ""
    root.cursorActive = true
    root.rebuildDisplay()
    root.selectedIndex = appearanceFonts.currentIndex
    if (displayModel.count > 0)
      resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function openFontChange() {
    if (appearanceFonts.fontsReady) {
      root.enterFontChange()
      return
    }
    appearanceFonts.awaitingList = true
    if (root.activeMenu === appearanceFonts.itemId)
      root.rebuildDisplay()
    appearanceFonts.loadFonts()
  }

  function headerText() {
    if (root.filterText)
      return root.filterText
    var title = root.currentMenu().title || "Control"
    if (root.showingResults && root.pendingDomain === "search" && Files.showHidden)
      return title + " · hidden…"
    if (WebBrowser.installing && root.isWebMenuContext())
      return title + " · installing…"
    if (WebBrowser.lastError && root.isWebMenuContext())
      return title + " · " + WebBrowser.lastError
    return title + "…"
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
        if (kind === "slider")
          continue
        out.push({
          itemId: itemId,
          kind: kind,
          icon: String(row.icon || ""),
          label: label,
          detail: pathLabels.join(" › "),
          domain: String(row.domain || ""),
          mode: String(row.mode || ""),
          status: String(row.status || ""),
          command: String(row.command || "")
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
    // File search: filter by basename only — full path in detail/itemId
    // would match directory segments (e.g. "ba" → .../backup/.../favicon.ico).
    if (String(row.domain || root.pendingDomain || "") === "search")
      return label.indexOf(q) >= 0
    var itemId = String(row.itemId || "").toLowerCase()
    var detail = String(row.detail || "").toLowerCase()
    return label.indexOf(q) >= 0 || itemId.indexOf(q) >= 0 || detail.indexOf(q) >= 0
  }

  function fileUrl(path) {
    if (!path)
      return ""
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (!value)
      return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  function refreshLocalIcons() {
    if (!iconIndexScan.running)
      iconIndexScan.running = true
  }

  function resolveAppIcon(icon) {
    var value = String(icon || "").trim()
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value
    if (value.indexOf("http://") === 0 || value.indexOf("https://") === 0)
      return value
    if (value.charAt(0) === "/")
      return root.fileUrl(value)

    var themed = Quickshell.iconPath(value.length > 0 ? value : "application-x-executable", true)
    if (themed && String(themed).length > 0)
      return themed

    var indexed = root.iconIndex[value]
    if (indexed)
      return root.fileUrl(indexed)

    if (root.appLibrary) {
      try {
        var fromLib = root.appLibrary.iconSource(value)
        if (fromLib && String(fromLib).length > 0)
          return String(fromLib)
      } catch (e) {
      }
    }

    return Quickshell.iconPath("application-x-executable", true)
  }

  function collectApplicationRows(query, limit) {
    var out = []
    var q = String(query || "").trim()
    var maxRows = limit > 0 ? limit : (q ? 40 : 5000)

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
      var capped = Math.min(count, maxRows)
      for (var i = 0; i < capped; i++) {
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

    try {
      var values = DesktopEntries.applications.values || []
      var ql = q.toLowerCase()
      var max = Math.min(values.length, 5000)
      for (var j = 0; j < max && out.length < maxRows; j++) {
        var e = values[j]
        if (!e || e.noDisplay)
          continue
        var name = String(e.name || "")
        var id = String(e.id || "")
        if (!name && !id)
          continue
        if (ql) {
          var hay = (name + " " + String(e.genericName || "") + " " + id).toLowerCase()
          if (hay.indexOf(ql) < 0)
            continue
        }
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
      out.sort(function(a, b) {
        return String(a.label).localeCompare(String(b.label), undefined, { sensitivity: "base" })
      })
    } catch (e3) {
      console.warn("comtrol DesktopEntries fallback failed:", e3)
    }
    return out
  }

  function collectAppSearchRows(query) {
    var q = String(query || "").trim()
    if (!q)
      return []
    return root.collectApplicationRows(q, 40)
  }

  function rebuildDisplay() {
    var q = root.usesLiveFilterSearch ? "" : root.filterText.trim().toLowerCase()
    var rows = []

    if (root.showingResults) {
      rows = (root.currentMenu().rows || []).slice()
    } else if (root.activeMenu === "applications") {
      rows = root.collectApplicationRows(root.filterText.trim(), 0)
    } else if (q) {
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
      if (q && (String(row.kind || "") === "slider" || (String(row.kind || "") !== "app" && !root.rowMatchesQuery(row, q))))
        continue
      var label = String(row.label || "")
      if (root.pendingActionDomain
          && String(row.kind || "") === "action"
          && String(row.domain || "") === root.pendingActionDomain
          && String(row.mode || "") === root.pendingActionMode)
        label = "Loading…"
      displayModel.append({
        itemId: String(row.itemId || row.id || ""),
        kind: String(row.kind || ""),
        icon: String(row.icon || ""),
        appIcon: String(row.appIcon || ""),
        path: String(row.path || ""),
        label: label,
        detail: String(row.detail || ""),
        domain: String(row.domain || ""),
        mode: String(row.mode || ""),
        status: String(row.status || ""),
        command: String(row.command || ""),
        pluginEnabled: (row.pluginEnabled === true || row.pluginEnabled === "true" || row.pluginEnabled === 1 || row.pluginEnabled === "1") ? "1" : "0",
        pluginCanDisable: (row.pluginCanDisable === false || row.pluginCanDisable === "false" || row.pluginCanDisable === 0 || row.pluginCanDisable === "0") ? "0" : "1"
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

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    if (root.usesLiveFilterSearch) {
      root.liveSearchRequested(text)
      return
    }
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    var wasActive = root.cursorActive
    root.noteKeyboardSelection()
    if (!wasActive) {
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.kind === "menu") {
      if (row.itemId === appearanceFonts.changeItemId) {
        root.openFontChange()
        return
      }
      root.navStack = root.ancestorsOf(row.itemId)
      root.activeMenu = row.itemId
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = true
      if (row.itemId === "applications") {
        root.refreshLocalIcons()
        if (root.appLibrary)
          root.appLibrary.refreshIcons()
      }
      if (row.itemId === powerMenu.itemId)
        powerMenu.load()
      if (updateMenu.isUpdateMenu(row.itemId))
        updateMenu.load()
      if (configMenu.isConfigMenu(row.itemId))
        configMenu.load()
      if (defaultsMenu.isDefaultsMenu(row.itemId))
        defaultsMenu.load()
      if (row.itemId === appearanceDesktop.itemId)
        appearanceDesktop.loadDesktop()
      if (row.itemId === appearanceDesktop.opacityItemId)
        appearanceDesktop.loadOpacityGroups()
      root.rebuildDisplay()
      root.syncWebBrowser()
      return
    }
    if (row.kind === "slider")
      return
    if (row.kind === "font") {
      appearanceFonts.setFont(row.label || row.itemId)
      return
    }
    if (row.kind === "bar-transparency") {
      appearanceDesktop.toggleTransparency()
      return
    }
    if (row.kind === "look-shadow") {
      appearanceDesktop.toggleShadow()
      return
    }
    if (row.kind === "opacity-reset") {
      appearanceDesktop.resetOpacityDefaults()
      return
    }
    if (row.kind === "bar-position") {
      appearanceDesktop.setPosition(row.itemId)
      return
    }
    if (row.kind === "power") {
      if (powerMenu.run(row.command || ""))
        root.dismissRequested()
      return
    }
    if (row.kind === "update") {
      if (updateMenu.run(row.command || ""))
        root.dismissRequested()
      return
    }
    if (row.kind === "reset") {
      if (resetMenu.run(row.command || ""))
        root.dismissRequested()
      return
    }
    if (row.kind === "config") {
      if (configMenu.run(row.command || ""))
        root.dismissRequested()
      return
    }
    if (row.kind === "default") {
      defaultsMenu.setDefault(row.command || "")
      return
    }
    if (row.kind === "action" && row.domain && row.mode) {
      if (root.pendingActionDomain === row.domain && root.pendingActionMode === row.mode)
        return
      root.actionRequested(row.domain, row.mode, row.label)
      return
    }
    if (row.kind === "app") {
      if (root.appLibrary) {
        root.appLibrary.launch(row.itemId, row.label)
      } else {
        var desktopId = String(row.itemId || "")
        if (desktopId) {
          if (desktopId.slice(-8) !== ".desktop")
            desktopId += ".desktop"
          Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", desktopId])
        }
      }
      root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "webapps") {
      var desktopPath = String(row.path || "")
      if (!desktopPath) {
        var hits = WebApps.findByName(String(row.itemId || row.label || ""))
        if (hits && hits.length > 0)
          desktopPath = String(hits[0].path || "")
      }
      if (desktopPath && WebApps.launch(desktopPath))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "search") {
      var filePath = String(row.path || row.itemId || "")
      if (filePath && Files.open(filePath))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "youtube") {
      var ytUrl = String(row.path || row.itemId || "")
      if (ytUrl && YouTube.open(ytUrl))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "reddit") {
      var rdUrl = String(row.path || row.itemId || "")
      if (rdUrl && Reddit.open(rdUrl))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "google") {
      var gUrl = String(row.path || row.itemId || "")
      if (gUrl && Google.open(gUrl))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "duckduckgo") {
      var ddgUrl = String(row.path || row.itemId || "")
      if (ddgUrl && DuckDuckGo.open(ddgUrl))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "x") {
      var xUrl = String(row.path || row.itemId || "")
      if (xUrl && X.open(xUrl))
        root.dismissRequested()
      return
    }
    if (row.kind === "result"
        && String(row.domain || root.pendingDomain || "") === "wikipedia") {
      var wikiUrl = String(row.path || row.itemId || "")
      if (wikiUrl && Wikipedia.open(wikiUrl))
        root.dismissRequested()
    }
  }

  ListModel { id: displayModel }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.menuSearchActive || root.applicationsMenuActive)
        root.rebuildDisplay()
    }
  }

  Connections {
    target: WebBrowser
    function onNodeAvailableChanged() {
      // If Web was open and Node disappeared, step back to Search.
      if (!WebBrowser.nodeAvailable && root.activeMenu === searchMenu.webItemId) {
        root.activeMenu = searchMenu.itemId
        root.navStack = root.ancestorsOf(searchMenu.itemId)
      }
      root.rebuildDisplay()
    }
    function onInstallingChanged() {
      // Refresh header (“installing…”) while deps install.
      if (root.activeMenu === searchMenu.webItemId || root.isWebMenuContext())
        root.rebuildDisplay()
    }
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(" ")]
    stdout: SplitParser {
      onRead: function(line) { root.indexIconLine(line) }
    }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Component.onCompleted: root.refreshLocalIcons()

  BorderSurface {
    id: card
    width: root.cardWidth
    height: Math.min(root.cardHeight, parent.height - Style.gapsOut * 2)
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
          root.dismissRequested()
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Left && !root.filterText && root.isSliderSelected()) {
          root.adjustSelectedSlider(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right && root.isSliderSelected()) {
          root.adjustSelectedSlider(1)
          event.accepted = true
        } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
          if (root.showingResults || root.pendingActionDomain || !root.navigateBack())
            root.backRequested()
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
        } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
          if (root.showingResults
              && ((root.pendingDomain === "packages" && root.pendingMode === "local")
                  || (root.pendingDomain === "webapps" && root.pendingMode === "local")
                  || (root.pendingDomain === "plugins" && root.pendingMode === "local"))
              && root.cursorActive
              && root.selectedIndex >= 0
              && root.selectedIndex < displayModel.count) {
            var row = displayModel.get(root.selectedIndex)
            if (row && row.kind === "result" && row.itemId)
              root.removePackageRequested(row.itemId)
          }
          event.accepted = true
        } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
          if (root.showingResults
              && root.pendingDomain === "plugins"
              && root.pendingMode === "local"
              && root.cursorActive
              && root.selectedIndex >= 0
              && root.selectedIndex < displayModel.count) {
            var toggleRow = displayModel.get(root.selectedIndex)
            if (toggleRow && toggleRow.kind === "result" && toggleRow.itemId && toggleRow.pluginCanDisable === "1")
              root.togglePluginRequested(toggleRow.itemId)
          }
          event.accepted = true
        } else if (event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
          if (root.pendingDomain === "search"
              && (root.showingResults || root.pendingActionDomain === "search"))
            root.toggleSearchHiddenRequested()
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
          text: {
            // Explicit deps so “installing…” updates without rebuildDisplay.
            void root.filterText
            void root.showingResults
            void root.pendingDomain
            void root.activeMenu
            void WebBrowser.installing
            void WebBrowser.lastError
            return root.headerText()
          }
          color: root.foreground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: root.menuFontHeading
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
          interactive: !root.isSliderSelected() && !root.fontsMenuActive && !root.desktopMenuActive && !root.desktopOpacityGroupActive

          delegate: BorderSurface {
            id: row
            required property int index
            required property string itemId
            required property string kind
            required property string icon
            required property string appIcon
            required property string path
            required property string label
            required property string detail
            required property string domain
            required property string mode
            required property string status
            required property string command
            required property string pluginEnabled
            required property string pluginCanDisable

            readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
            readonly property bool hasDetail: detail.length > 0
            readonly property bool isApp: row.kind === "app"
            readonly property bool showPackageRemove: row.kind === "result"
              && ((root.pendingDomain === "packages" && root.pendingMode === "local")
                  || (root.pendingDomain === "webapps" && root.pendingMode === "local")
                  || (root.pendingDomain === "plugins" && root.pendingMode === "local"))
            readonly property bool showPluginToggle: row.kind === "result"
              && root.pendingDomain === "plugins"
              && root.pendingMode === "local"
              && row.pluginCanDisable === "1"
            readonly property bool pluginIsEnabled: row.pluginEnabled === "1"
            readonly property bool showResultIconImage: row.kind === "result" && String(row.appIcon || "").length > 0
            readonly property bool isSlider: row.kind === "slider"
            readonly property bool hasStatus: row.status.length > 0
            readonly property int toggleWidth: Style.space(84)
            readonly property int removeWidth: Style.space(84)
            readonly property int trailingWidth: {
              if (showPluginToggle && showPackageRemove)
                return row.toggleWidth + Style.space(12) + row.removeWidth
              if (showPackageRemove)
                return row.removeWidth
              if (hasStatus)
                return Style.space(128)
              return Style.space(16)
            }

            width: ListView.view.width
            height: root.rowHeightForKind(row.kind)
            radius: root.cornerRadius
            color: hasCursor ? root.selectedBackground : "transparent"
            borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

            Row {
              visible: !row.isSlider
              enabled: !row.isSlider
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(12)

              Item {
                width: ((root.pendingDomain === "youtube" || root.pendingDomain === "reddit"
                        || root.pendingDomain === "google" || root.pendingDomain === "duckduckgo" || root.pendingDomain === "x"
                        || root.pendingDomain === "wikipedia") && row.showResultIconImage) ? Style.space(56) : Style.space(36)
                height: parent.height

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: !row.isApp && !row.showResultIconImage
                  text: row.icon
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.menuFontIcon
                }

                Image {
                  id: appIconImage
                  anchors.centerIn: parent
                  visible: (row.isApp || row.showResultIconImage) && status !== Image.Error
                  width: (root.pendingDomain === "youtube" || root.pendingDomain === "reddit"
                          || root.pendingDomain === "google" || root.pendingDomain === "duckduckgo" || root.pendingDomain === "x"
                          || root.pendingDomain === "wikipedia") ? Style.space(48) : root.menuFontIcon
                  height: (root.pendingDomain === "youtube" || root.pendingDomain === "reddit"
                           || root.pendingDomain === "google" || root.pendingDomain === "duckduckgo" || root.pendingDomain === "x"
                           || root.pendingDomain === "wikipedia") ? Style.space(36) : root.menuFontIcon
                  fillMode: Image.PreserveAspectCrop
                  sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                  sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                  source: (row.isApp || row.showResultIconImage) ? root.resolveAppIcon(row.appIcon) : ""
                  asynchronous: true
                  smooth: true
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: (row.isApp || row.showResultIconImage) && appIconImage.status !== Image.Ready
                  text: row.label ? String(row.label).charAt(0).toUpperCase() : "?"
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.menuFontBody
                  font.bold: true
                }
              }

              Column {
                width: Math.max(
                  Style.space(40),
                  parent.width - Style.space(36) - Style.space(12) - row.trailingWidth - Style.space(24)
                )
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.menuFontBody
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
                  font.pixelSize: root.menuFontCaption
                  elide: Text.ElideMiddle
                }
              }

              Item {
                width: row.trailingWidth
                height: parent.height

                Text {
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  visible: !row.showPackageRemove && !row.showPluginToggle && !row.hasStatus
                  text: (row.kind === "menu" || row.kind === "action") ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: (row.kind === "menu" || row.kind === "action") ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: root.menuFontBody
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignRight
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  visible: !row.showPackageRemove && !row.showPluginToggle && row.hasStatus
                  text: row.status
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.72
                  font.family: root.fontFamily
                  font.pixelSize: root.menuFontCaption
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignRight
                }

                Row {
                  anchors.fill: parent
                  spacing: Style.space(12)
                  layoutDirection: Qt.RightToLeft
                  visible: row.showPackageRemove || row.showPluginToggle

                  Text {
                    textFormat: Text.PlainText
                    visible: row.showPackageRemove
                    width: row.removeWidth
                    height: parent.height
                    text: "Remove"
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.72
                    font.family: root.fontFamily
                    font.pixelSize: root.menuFontCaption
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: row.showPluginToggle
                    width: row.toggleWidth
                    height: parent.height
                    text: row.pluginIsEnabled ? "Disable" : "Enable"
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.72
                    font.family: root.fontFamily
                    font.pixelSize: root.menuFontCaption
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }
            }

            Loader {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              active: row.isSlider
              sourceComponent: appearanceDesktop.isDesktopSlider(row.itemId)
                ? appearanceDesktop.sliderDelegate
                : appearanceFonts.sliderDelegate
              onLoaded: {
                if (!item)
                  return
                item.hasCursor = Qt.binding(function() { return row.hasCursor })
                if (appearanceDesktop.isDesktopSlider(row.itemId)) {
                  item.role = appearanceDesktop.sliderRoleFor(row.itemId)
                  item.groupId = appearanceDesktop.sliderGroupFor(row.itemId)
                }
              }
            }

            HoverHandler {
              enabled: row.isSlider
              onHoveredChanged: if (hovered) root.pointerSelect(index)
            }

            MouseArea {
              anchors.fill: parent
              visible: !row.isSlider
              enabled: !row.isSlider
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.considerPointerMove(mouse.x, mouse.y)
              onContainsMouseChanged: if (containsMouse) root.pointerSelect(index)
              onClicked: {
                root.suppressPointerSelect = false
                root.cursorActive = true
                root.selectedIndex = index
                root.activateIndex(index)
              }
            }

            MouseArea {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12) + row.removeWidth + Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: row.toggleWidth
              height: parent.height
              visible: row.showPluginToggle
              enabled: row.showPluginToggle
              z: 2
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.considerPointerMove(mouse.x, mouse.y)
              onContainsMouseChanged: if (containsMouse) root.pointerSelect(index)
              onClicked: {
                root.suppressPointerSelect = false
                root.cursorActive = true
                root.selectedIndex = index
                root.togglePluginRequested(row.itemId)
              }
            }

            MouseArea {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              width: row.removeWidth
              height: parent.height
              visible: row.showPackageRemove
              enabled: row.showPackageRemove
              z: 2
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.considerPointerMove(mouse.x, mouse.y)
              onContainsMouseChanged: if (containsMouse) root.pointerSelect(index)
              onClicked: {
                root.suppressPointerSelect = false
                root.cursorActive = true
                root.selectedIndex = index
                root.removePackageRequested(row.itemId)
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: displayModel.count === 0
          text: (root.loading || appearanceFonts.loadingFonts) ? "Loading…" : "No matches"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: root.menuFontBody
        }
      }
    }
  }
}
