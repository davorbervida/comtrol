pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Shared plugin catalog / install / remove helpers for cOMtrol.
// Everything is QML: catalog via XMLHttpRequest + FileView cache,
// installed scan via FolderListModel + FileView, remove via argv Process.
// Item (not QtObject): needs a default property for FileView/Process/FolderListModel children.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string userPluginsDir: root.home + "/.config/omarchy/plugins"
  readonly property string firstPartyPluginsDir: root.omarchyPath + "/shell/plugins"

  readonly property string pluginRoot: {
    var url = Qt.resolvedUrl("..").toString()
    if (url.indexOf("file://") === 0)
      url = url.substring(7)
    while (url.length > 1 && url.charAt(url.length - 1) === "/")
      url = url.substring(0, url.length - 1)
    return url
  }
  readonly property string catalogDataDir: root.pluginRoot + "/data"
  readonly property string catalogUrl: "https://plugins.omarchy.org/catalog.json"
  readonly property string statsUrl: "https://api.omarchyplugins.com/v1/stats"
  readonly property string catalogCachePath: root.catalogDataDir + "/catalog.json"
  readonly property string statsCachePath: root.catalogDataDir + "/stats.json"
  readonly property string pluginsCachePath: root.catalogDataDir + "/plugins.json"
  readonly property string metaCachePath: root.catalogDataDir + "/catalog-meta.json"

  property bool catalogLoading: false
  property bool catalogShownFromCache: false
  property int catalogSerial: 0
  property int installedSerial: 0
  property int addSerial: 0
  property int removeSerial: 0
  property int setEnabledSerial: 0
  property int stateSerial: 0

  property var cachedInstalled: []
  property var _pendingRemoteCatalog: null
  property var _pendingRemoteStats: null
  property bool _catalogFetchDone: false
  property bool _statsFetchDone: false
  property string _catalogFetchError: ""
  property string _stateRaw: ""
  property string _setEnabledId: ""
  property bool _setEnabledValue: false

  // Directory scan state (pure QML).
  property int scanSerial: 0
  property var scanAcc: []
  property var scanQueue: []
  property string scanMode: "" // "" | "listing"
  property string scanSource: ""
  property string scanRole: ""
  property int scanDepth: 0
  property string scanListingPath: ""

  // Remove pipeline: disable → delete → rescan
  property int removePipeSerial: -1
  property string removePipeId: ""
  property string removePipePath: ""
  property string removePipeSource: ""
  property string removePipeStep: "" // disable | delete | rescan
  property var removePipePayload: ({})

  signal catalogFinished()
  signal catalogFailed(string message)
  signal catalogPayload(var payload, bool fromCache)
  signal installedListed(var plugins)
  signal addFinished(int exitCode, int serial)
  signal removeFinished(int exitCode, int serial, var payload)
  signal setEnabledFinished(int exitCode, int serial, string pluginId, bool enabled)

  function toFileUrl(path) {
    var p = String(path || "")
    if (!p)
      return ""
    if (p.indexOf("file://") === 0)
      return p
    return "file://" + p
  }

  function fromFileUrl(url) {
    var u = String(url || "")
    if (u.indexOf("file://") === 0)
      u = u.substring(7)
    try {
      return decodeURIComponent(u)
    } catch (e) {
      return u
    }
  }

  function cancel() {
    root.catalogSerial += 1
    root.installedSerial += 1
    root.scanSerial += 1
    root.stateSerial += 1
    root.setEnabledSerial += 1
    root.removePipeSerial = -1
    root.catalogLoading = false
    root.catalogShownFromCache = false
    root.scanMode = ""
    root.scanQueue = []
    root._pendingRemoteCatalog = null
    root._pendingRemoteStats = null
    root._catalogFetchDone = false
    root._statsFetchDone = false
    root._catalogFetchError = ""
    root._stateRaw = ""
    if (addProc.running)
      addProc.running = false
    if (removeProc.running)
      removeProc.running = false
    if (mkdirProc.running)
      mkdirProc.running = false
    if (stateProc.running)
      stateProc.running = false
    if (setEnabledProc.running)
      setEnabledProc.running = false
  }

  function loadCatalog() {
    root.catalogSerial += 1
    root.catalogLoading = true
    root.catalogShownFromCache = false
    root._pendingRemoteCatalog = null
    root._pendingRemoteStats = null
    root._catalogFetchDone = false
    root._statsFetchDone = false
    root._catalogFetchError = ""

    root.readCatalogCache()
    root.ensureDataDirThenSync()
    root.listInstalled()
  }

  function readCatalogCache() {
    var plugins = root.readJsonFile(root.pluginsCachePath)
    if (!plugins || plugins.length === undefined)
      return
    root.applyCatalogPayload({ ok: true, cached: true, plugins: plugins }, true)
  }

  function ensureDataDirThenSync() {
    if (mkdirProc.running)
      mkdirProc.running = false
    mkdirProc.serial = root.catalogSerial
    mkdirProc.command = ["mkdir", "-p", root.catalogDataDir]
    mkdirProc.running = true
  }

  function startCatalogSync() {
    var serial = root.catalogSerial
    root.fetchJson(root.catalogUrl, function(ok, data, error) {
      if (serial !== root.catalogSerial)
        return
      root._catalogFetchDone = true
      if (!ok || !data || typeof data !== "object" || data.length !== undefined) {
        root._catalogFetchError = String(error || "catalog fetch failed")
        root._pendingRemoteCatalog = null
      } else {
        root._pendingRemoteCatalog = data
      }
      root.maybeFinishCatalogSync(serial)
    })
    root.fetchJson(root.statsUrl, function(ok, data, error) {
      if (serial !== root.catalogSerial)
        return
      root._statsFetchDone = true
      if (ok && data && typeof data === "object" && data.length === undefined)
        root._pendingRemoteStats = data
      else
        root._pendingRemoteStats = root.readJsonFile(root.statsCachePath) || ({})
      root.maybeFinishCatalogSync(serial)
    })
  }

  function maybeFinishCatalogSync(serial) {
    if (serial !== root.catalogSerial)
      return
    if (!root._catalogFetchDone || !root._statsFetchDone)
      return

    if (!root._pendingRemoteCatalog) {
      if (!root.catalogShownFromCache) {
        root.catalogLoading = false
        root.catalogFailed(root._catalogFetchError || "Plugin catalog failed")
      } else if (root.catalogLoading) {
        root.catalogLoading = false
        root.catalogFinished()
      }
      return
    }

    var remoteCatalog = root._pendingRemoteCatalog
    var remoteStats = root._pendingRemoteStats || ({})
    var localCatalog = root.readJsonFile(root.catalogCachePath) || ({})
    if (typeof localCatalog !== "object" || localCatalog.length !== undefined)
      localCatalog = ({})

    var remoteIds = root.catalogIdSet(remoteCatalog)
    var localIds = root.catalogIdSet(localCatalog)
    var remoteVersions = root.catalogVersions(remoteCatalog)
    var localVersions = root.catalogVersions(localCatalog)

    var newIds = []
    for (var rid in remoteIds) {
      if (!localIds[rid])
        newIds.push(rid)
    }
    newIds.sort()

    var changedIds = []
    for (var cid in remoteIds) {
      if (localIds[cid] && remoteVersions[cid] !== localVersions[cid])
        changedIds.push(cid)
    }
    changedIds.sort()

    var localPlugins = root.readJsonFile(root.pluginsCachePath)
    var hasLocalPlugins = !!(localPlugins && localPlugins.length !== undefined && localPlugins.length > 0)
    var catalogChanged = newIds.length > 0 || changedIds.length > 0 || !hasLocalPlugins

    var plugins = root.mergeCatalog(remoteCatalog, remoteStats)
    root.writeJsonFile(root.catalogCachePath, remoteCatalog)
    root.writeJsonFile(root.statsCachePath, remoteStats)
    root.writeJsonFile(root.pluginsCachePath, plugins)
    root.writeJsonFile(root.metaCachePath, {
      count: plugins.length,
      new_count: newIds.length,
      changed_count: changedIds.length,
      new_ids: newIds.slice(0, 50)
    })

    root.finishCatalogSync({
      ok: true,
      updated: catalogChanged,
      new_count: newIds.length,
      changed_count: changedIds.length,
      new_ids: newIds.slice(0, 50),
      plugins: plugins
    })
  }

  function catalogIdSet(catalog) {
    var out = ({})
    var list = (catalog && catalog.plugins) || []
    for (var i = 0; i < list.length; i++) {
      var plugin = list[i] || {}
      var pid = String(plugin.id || "")
      if (pid)
        out[pid] = true
    }
    return out
  }

  function catalogVersions(catalog) {
    var out = ({})
    var list = (catalog && catalog.plugins) || []
    for (var i = 0; i < list.length; i++) {
      var plugin = list[i] || {}
      var pid = String(plugin.id || "")
      if (pid)
        out[pid] = String(plugin.version || "")
    }
    return out
  }

  function mergeCatalog(catalog, stats) {
    var statsPlugins = (stats && stats.plugins) || ({})
    if (typeof statsPlugins !== "object" || statsPlugins.length !== undefined)
      statsPlugins = ({})
    var out = []
    var list = (catalog && catalog.plugins) || []
    for (var i = 0; i < list.length; i++) {
      var plugin = list[i] || {}
      if (typeof plugin !== "object")
        continue
      var pid = String(plugin.id || "")
      var st = statsPlugins[pid]
      if (!st || typeof st !== "object")
        st = ({})
      var preview = plugin.previewImage || ""
      if (preview && String(preview).indexOf("http://") !== 0 && String(preview).indexOf("https://") !== 0)
        preview = "https://plugins.omarchy.org/" + String(preview).replace(/^\//, "")
      var tags = plugin.tags || []
      var tagList = []
      if (tags && tags.length !== undefined) {
        for (var ti = 0; ti < tags.length; ti++)
          tagList.push(String(tags[ti]))
      }
      out.push({
        id: pid,
        name: String(plugin.name || ""),
        description: String(plugin.description || ""),
        author: String(plugin.author || ""),
        version: String(plugin.version || ""),
        category: String(plugin.category || ""),
        tags: tagList,
        repo: String(plugin.repo || ""),
        source_type: String(plugin.sourceType || ""),
        stars: Number(plugin.stars || 0),
        views: Number(st.views || 0),
        copies: Number(st.copies || 0),
        hearts: Number(st.hearts || 0),
        install_available: !!plugin.installAvailable,
        install_command: String(plugin.installCommand || ""),
        preview_image: preview ? String(preview) : null
      })
    }
    return out
  }

  function fetchJson(url, callback) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.setRequestHeader("User-Agent", "cOMtrol-plugin-catalog")
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return
      if (xhr.status < 200 || xhr.status >= 300) {
        callback(false, null, "HTTP " + xhr.status)
        return
      }
      try {
        callback(true, JSON.parse(String(xhr.responseText || "")), "")
      } catch (e) {
        callback(false, null, "Invalid JSON")
      }
    }
    try {
      xhr.send()
    } catch (e) {
      callback(false, null, String(e))
    }
  }

  function writeJsonFile(path, value) {
    cacheWriteView.path = ""
    cacheWriteView.path = root.toFileUrl(path)
    try {
      cacheWriteView.setText(JSON.stringify(value))
    } catch (e) {
    }
  }

  function applyCatalogPayload(payload, fromCache) {
    root.catalogPayload(payload, fromCache)
    if (fromCache) {
      var list = []
      if (payload && payload.plugins && payload.plugins.length !== undefined)
        list = payload.plugins
      else if (payload && payload.length !== undefined)
        list = payload
      if (list.length > 0) {
        root.catalogShownFromCache = true
        root.catalogLoading = false
        root.catalogFinished()
      }
    }
  }

  function finishCatalogSync(payload) {
    if (payload && payload.ok === false && !root.catalogShownFromCache) {
      root.catalogLoading = false
      root.catalogFailed(String(payload.error || "Plugin catalog failed"))
      return
    }
    if (payload && payload.plugins)
      root.applyCatalogPayload(payload, false)
    if (root.catalogLoading) {
      root.catalogLoading = false
      root.catalogFinished()
    }
  }

  function listInstalled() {
    root.installedSerial += 1
    root.scanSerial = root.installedSerial
    root.scanAcc = []
    root.scanQueue = [
      { path: root.userPluginsDir, depth: 0, source: "user", role: "user_root" },
      { path: root.firstPartyPluginsDir, depth: 0, source: "first_party", role: "fp_root" }
    ]
    root.scanMode = ""
    var stale = root.cachedInstalled || []
    if (stale.length > 0)
      root.installedListed(stale.slice())
    root.drainScanQueue()
    return root.installedSerial
  }

  function drainScanQueue() {
    if (root.scanSerial !== root.installedSerial)
      return
    if (!root.scanQueue || root.scanQueue.length === 0) {
      root.finishScan()
      return
    }
    var job = root.scanQueue[0]
    root.scanQueue = root.scanQueue.slice(1)
    root.scanSource = String(job.source || "")
    root.scanDepth = Number(job.depth || 0)
    root.scanRole = String(job.role || "")
    root.scanListingPath = String(job.path || "")
    root.scanMode = "listing"
    var url = "file://" + root.scanListingPath
    if (String(dirModel.folder) === url && dirModel.status === FolderListModel.Ready) {
      Qt.callLater(root.onDirListingReady)
      return
    }
    dirModel.folder = url
  }

  function onDirListingReady() {
    if (root.scanSerial !== root.installedSerial)
      return
    if (root.scanMode !== "listing")
      return
    if (dirModel.status !== FolderListModel.Ready)
      return
    var listed = String(dirModel.folder || "")
    var want = "file://" + root.scanListingPath
    if (listed !== want && root.fromFileUrl(listed) !== root.scanListingPath)
      return

    var role = root.scanRole
    var count = dirModel.count
    for (var i = 0; i < count; i++) {
      var isDir = dirModel.isFolder(i)
      var name = String(dirModel.get(i, "fileName") || "")
      var path = String(dirModel.get(i, "filePath") || "")
      if (!path)
        continue

      if (role === "user_root") {
        if (!isDir)
          continue
        root.tryAddManifest(path + "/manifest.json", "user", path)
        continue
      }

      if (role === "fp_root") {
        if (isDir)
          root.scanQueue.push({ path: path, depth: 1, source: "first_party", role: "fp_dir" })
        continue
      }

      if (role === "fp_dir") {
        var childDepth = root.scanDepth + 1
        if (isDir) {
          if (childDepth < 3)
            root.scanQueue.push({ path: path, depth: childDepth, source: "first_party", role: "fp_dir" })
        } else if (root.isManifestName(name) && childDepth >= 2 && childDepth <= 3) {
          root.tryAddManifest(path, "first_party", root.parentDir(path))
        }
      }
    }

    root.scanMode = ""
    root.drainScanQueue()
  }

  function isManifestName(name) {
    return name === "manifest.json" || (name.length > 14 && name.substring(name.length - 14) === ".manifest.json")
  }

  function parentDir(path) {
    var p = String(path || "")
    var idx = p.lastIndexOf("/")
    if (idx <= 0)
      return p
    return p.substring(0, idx)
  }

  function tryAddManifest(manifestPath, source, pluginDir) {
    var data = root.readJsonFile(manifestPath)
    if (!data || typeof data !== "object")
      return
    var id = String(data.id || "").trim()
    if (!id)
      return
    var previewPath = String(pluginDir || "") + "/preview.png"
    var kinds = data.kinds || []
    var kindList = []
    if (kinds && kinds.length !== undefined) {
      for (var i = 0; i < kinds.length; i++)
        kindList.push(String(kinds[i]))
    }
    root.scanAcc.push({
      id: id,
      name: String(data.name || id),
      version: String(data.version || ""),
      description: String(data.description || ""),
      path: String(pluginDir || ""),
      preview: previewPath,
      kinds: kindList,
      source: source,
      enabled: true,
      canDisable: true
    })
  }

  function readJsonFile(path) {
    var url = root.toFileUrl(path)
    manifestView.path = ""
    manifestView.path = url
    var text = ""
    try {
      text = String(manifestView.text() || "")
    } catch (e) {
      return null
    }
    if (!text)
      return null
    try {
      return JSON.parse(text)
    } catch (e) {
      return null
    }
  }

  function finishScan() {
    if (root.scanSerial !== root.installedSerial)
      return
    root.cachedInstalled = root.scanAcc.slice()
    root.maybeContinueRemoveAfterScan()
    root.beginStateEnrichment()
  }

  function beginStateEnrichment() {
    root.stateSerial = root.installedSerial
    root._stateRaw = ""
    if (stateProc.running)
      stateProc.running = false
    stateProc.command = ["omarchy-plugin-list", "--json"]
    stateProc.running = true
  }

  function mergePluginStates(raw) {
    var states = ({})
    try {
      var arr = JSON.parse(String(raw || "[]"))
      if (!arr || arr.length === undefined)
        arr = []
      for (var i = 0; i < arr.length; i++) {
        var p = arr[i] || {}
        var sid = String(p.id || "").trim()
        if (!sid)
          continue
        states[sid] = {
          enabled: !(p.enabled === false || p.enabled === "false" || p.enabled === 0),
          canDisable: !(p.canDisable === false || p.canDisable === "false" || p.canDisable === 0)
        }
      }
    } catch (e) {
      return
    }
    var list = root.cachedInstalled || []
    var next = []
    for (var j = 0; j < list.length; j++) {
      var item = list[j] || {}
      var id = String(item.id || "")
      var st = states[id]
      next.push({
        id: item.id,
        name: item.name,
        version: item.version,
        description: item.description,
        path: item.path,
        preview: item.preview,
        kinds: item.kinds,
        source: item.source,
        enabled: st ? st.enabled : (item.enabled !== false),
        canDisable: st ? st.canDisable : (item.canDisable !== false)
      })
    }
    root.cachedInstalled = next
  }

  function publishInstalled() {
    root.installedListed(root.cachedInstalled || [])
  }

  function updateCachedEnabled(pluginId, enabled) {
    var id = String(pluginId || "")
    var list = root.cachedInstalled || []
    var next = []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      if (String(item.id || "") === id) {
        next.push({
          id: item.id,
          name: item.name,
          version: item.version,
          description: item.description,
          path: item.path,
          preview: item.preview,
          kinds: item.kinds,
          source: item.source,
          enabled: !!enabled,
          canDisable: item.canDisable !== false
        })
      } else {
        next.push(item)
      }
    }
    root.cachedInstalled = next
  }

  function setEnabled(pluginId, enabled) {
    var id = String(pluginId || "").trim()
    if (!id)
      return -1
    root.setEnabledSerial += 1
    var serial = root.setEnabledSerial
    root._setEnabledId = id
    root._setEnabledValue = !!enabled
    if (setEnabledProc.running)
      setEnabledProc.running = false
    if (enabled)
      setEnabledProc.command = ["omarchy-plugin-enable", id]
    else
      setEnabledProc.command = ["omarchy-plugin-disable", id]
    setEnabledProc.serial = serial
    setEnabledProc.running = true
    return serial
  }

  function toggleEnabled(pluginId) {
    var id = String(pluginId || "").trim()
    if (!id)
      return -1
    var plugin = root.findCached(id)
    var currently = !plugin || plugin.enabled !== false
    return root.setEnabled(id, !currently)
  }

  function maybeContinueRemoveAfterScan() {
    if (root._removeAfterScanSerial < 0)
      return
    var serial = root._removeAfterScanSerial
    var id = root._removeAfterScanId
    root._removeAfterScanSerial = -1
    root._removeAfterScanId = ""
    var plugin = root.findCached(id)
    if (!plugin || !plugin.path) {
      root.removeFinished(1, serial, {
        ok: false,
        error: "No plugins to remove.",
        removed: [],
        skipped: [id]
      })
      return
    }
    root.startRemovePipeline(serial, plugin)
  }

  function findCached(pluginId) {
    var id = String(pluginId || "")
    var list = root.cachedInstalled || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id || "") === id)
        return list[i]
    }
    return null
  }

  function splitArgv(commandLine) {
    var s = String(commandLine || "").trim()
    var out = []
    var cur = ""
    var quote = ""
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i)
      if (quote) {
        if (c === "\\" && i + 1 < s.length) {
          cur += s.charAt(i + 1)
          i += 1
          continue
        }
        if (c === quote) {
          quote = ""
          continue
        }
        cur += c
        continue
      }
      if (c === "\"" || c === "'") {
        quote = c
        continue
      }
      if (c === " " || c === "\t" || c === "\n") {
        if (cur.length > 0) {
          out.push(cur)
          cur = ""
        }
        continue
      }
      cur += c
    }
    if (cur.length > 0)
      out.push(cur)
    return out
  }

  function add(installCommand) {
    var cmd = String(installCommand || "").trim()
    if (!cmd)
      return -1
    var argv = root.splitArgv(cmd)
    if (!argv.length)
      return -1
    var hasYes = false
    for (var i = 0; i < argv.length; i++) {
      if (argv[i] === "--yes" || argv[i] === "-y") {
        hasYes = true
        break
      }
    }
    if (!hasYes)
      argv.push("--yes")
    root.addSerial += 1
    addProc.serial = root.addSerial
    if (addProc.running)
      addProc.running = false
    // Catalog install_command as argv — no shell wrapper.
    addProc.command = argv
    addProc.running = true
    return addProc.serial
  }

  function remove(pluginId) {
    var id = String(pluginId || "").trim()
    if (!id)
      return -1

    root.removeSerial += 1
    var serial = root.removeSerial
    var plugin = root.findCached(id)
    if (!plugin || !plugin.path) {
      root._removeAfterScanId = id
      root._removeAfterScanSerial = serial
      root.listInstalled()
      return serial
    }
    root.startRemovePipeline(serial, plugin)
    return serial
  }

  property string _removeAfterScanId: ""
  property int _removeAfterScanSerial: -1

  function startRemovePipeline(serial, plugin) {
    root.removePipeSerial = serial
    root.removePipeId = String(plugin.id || "")
    root.removePipePath = String(plugin.path || "")
    root.removePipeSource = String(plugin.source || "user")
    root.removePipePayload = ({
      ok: false,
      removed: [],
      skipped: [],
      first_party: root.removePipeSource === "first_party" ? [root.removePipeId] : []
    })
    root.removePipeStep = "disable"
    root.runRemoveStep()
  }

  function runRemoveStep() {
    if (root.removePipeSerial < 0)
      return
    if (removeProc.running)
      removeProc.running = false

    if (root.removePipeStep === "disable") {
      removeProc.command = ["omarchy-shell", "shell", "setPluginEnabled", root.removePipeId, "false"]
      removeProc.running = true
      return
    }
    if (root.removePipeStep === "delete") {
      if (root.removePipeSource === "first_party")
        removeProc.command = ["pkexec", "rm", "-rf", root.removePipePath]
      else
        removeProc.command = ["rm", "-rf", root.removePipePath]
      removeProc.running = true
      return
    }
    if (root.removePipeStep === "rescan") {
      removeProc.command = ["omarchy-shell", "shell", "rescanPlugins"]
      removeProc.running = true
      return
    }
  }

  function onRemoveProcExited(exitCode) {
    var serial = root.removePipeSerial
    if (serial < 0)
      return

    if (root.removePipeStep === "disable") {
      root.removePipeStep = "delete"
      root.runRemoveStep()
      return
    }

    if (root.removePipeStep === "delete") {
      if (exitCode === 0) {
        root.removePipePayload.ok = true
        root.removePipePayload.removed = [root.removePipeId]
      } else {
        root.removePipePayload.ok = false
      }
      root.removePipeStep = "rescan"
      root.runRemoveStep()
      return
    }

    if (root.removePipeStep === "rescan") {
      var payload = root.removePipePayload
      root.removePipeSerial = -1
      root.removePipeStep = ""
      root.listInstalled()
      root.removeFinished(payload.ok ? 0 : 1, serial, payload)
    }
  }

  FolderListModel {
    id: dirModel
    showDirs: true
    showFiles: true
    showDotAndDotDot: false
    showHidden: false
    sortField: FolderListModel.Unsorted
    onStatusChanged: {
      if (root.scanMode !== "listing")
        return
      if (status === FolderListModel.Ready)
        Qt.callLater(root.onDirListingReady)
    }
  }

  FileView {
    id: manifestView
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: cacheWriteView
    blockLoading: true
    printErrors: false
  }

  Process {
    id: mkdirProc
    property int serial: 0
    onExited: function() {
      if (mkdirProc.serial !== root.catalogSerial)
        return
      root.startCatalogSync()
    }
  }

  Process {
    id: addProc
    property int serial: 0
    onExited: function(exitCode) {
      root.addFinished(exitCode, addProc.serial)
    }
  }

  Process {
    id: removeProc
    onExited: function(exitCode) {
      root.onRemoveProcExited(exitCode)
    }
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._stateRaw = String(text || "")
      }
    }
    onExited: function() {
      if (root.stateSerial !== root.installedSerial)
        return
      root.mergePluginStates(root._stateRaw)
      root._stateRaw = ""
      root.publishInstalled()
    }
  }

  Process {
    id: setEnabledProc
    property int serial: 0
    onExited: function(exitCode) {
      var serial = setEnabledProc.serial
      var id = root._setEnabledId
      var enabled = root._setEnabledValue
      if (exitCode === 0)
        root.updateCachedEnabled(id, enabled)
      root.setEnabledFinished(exitCode, serial, id, enabled)
      if (exitCode === 0)
        root.publishInstalled()
    }
  }
}
