pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Theme list / GitHub catalog / install / remove — pure QML (no run.sh / cOMtrol / helper scripts).
// Network: XMLHttpRequest. FS scan: FolderListModel + FileView.
// Process only for system binaries: mkdir, git, rm, pkexec — plus omarchy-theme-set to apply.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string userThemesDir: root.home + "/.config/omarchy/themes"
  readonly property string firstPartyThemesDir: root.omarchyPath + "/themes"
  readonly property string cacheDir: root.home + "/.cache/comtrol"
  readonly property string webCachePath: root.cacheDir + "/themes.json"
  readonly property int cacheTtlSecs: 24 * 60 * 60
  readonly property int searchPages: 3

  property bool webLoading: false
  property bool webShownFromCache: false
  property int installedSerial: 0
  property int webSerial: 0
  property int installSerial: 0
  property int removeSerial: 0
  property int applySerial: 0

  property var cachedInstalled: []
  property var cachedWeb: []

  // Directory scan (local themes)
  property int scanSerial: 0
  property var scanAcc: []
  property var scanQueue: []
  property string scanMode: "" // "" | "listing"
  property string scanSource: ""
  property string scanRole: ""
  property string scanListingPath: ""
  property string scanThemeName: ""
  property string scanThemePath: ""

  // Web catalog fetch
  property var webCandidates: []
  property int webPage: 0
  property int webPreviewIndex: 0
  property int webPreviewPending: 0
  property var webFetched: []
  property string webQuery: ""

  // Install pipeline: mkdir → rm existing → clone → set
  property int installPipeSerial: -1
  property string installPipeUrl: ""
  property string installPipeName: ""
  property string installPipePath: ""
  property string installPipeStep: "" // mkdir | rm_existing | clone | set

  // Remove
  property int removePipeSerial: -1
  property string removePipeName: ""
  property string removePipePath: ""
  property string removePipeSource: ""
  property var removePipePayload: ({})
  property string _removeAfterScanName: ""
  property int _removeAfterScanSerial: -1

  signal localListed(var themes)
  signal webListed(var themes, bool fromCache)
  signal webFailed(string message)
  signal webFinished()
  signal installFinished(int exitCode, int serial, string themeName)
  signal removeFinished(int exitCode, int serial, var payload)
  signal applyFinished(int exitCode, int serial)

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
    root.installedSerial += 1
    root.webSerial += 1
    root.scanSerial += 1
    root.installPipeSerial = -1
    root.removePipeSerial = -1
    root._removeAfterScanSerial = -1
    root._removeAfterScanName = ""
    root.webLoading = false
    root.webShownFromCache = false
    root.scanMode = ""
    root.scanQueue = []
    root.webCandidates = []
    root.webFetched = []
    root.webPreviewPending = 0
    if (mkdirProc.running)
      mkdirProc.running = false
    if (installProc.running)
      installProc.running = false
    if (removeProc.running)
      removeProc.running = false
    if (applyProc.running)
      applyProc.running = false
  }

  // --- Local list (mirrors system/themes.rs) ---

  function listInstalled() {
    root.installedSerial += 1
    root.scanSerial = root.installedSerial
    root.scanAcc = []
    root.scanQueue = [
      { path: root.userThemesDir, source: "user", role: "root" },
      { path: root.firstPartyThemesDir, source: "first_party", role: "root" }
    ]
    root.scanMode = ""
    var stale = root.cachedInstalled || []
    if (stale.length > 0)
      root.localListed(stale.slice())
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
    root.scanRole = String(job.role || "")
    root.scanListingPath = String(job.path || "")
    root.scanThemeName = String(job.name || "")
    root.scanThemePath = String(job.themePath || job.path || "")
    root.scanMode = "listing"
    var url = root.toFileUrl(root.scanListingPath)
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
    var want = root.toFileUrl(root.scanListingPath)
    if (listed !== want && root.fromFileUrl(listed) !== root.scanListingPath)
      return

    var role = root.scanRole
    var count = dirModel.count

    if (role === "root") {
      for (var i = 0; i < count; i++) {
        if (!dirModel.isFolder(i))
          continue
        var name = String(dirModel.get(i, "fileName") || "")
        var path = String(dirModel.get(i, "filePath") || "")
        if (!name || !path)
          continue
        if (name === "." || name === "..")
          continue
        root.scanQueue.push({
          path: path,
          source: root.scanSource,
          role: "theme",
          name: name,
          themePath: path
        })
      }
      root.scanMode = ""
      root.drainScanQueue()
      return
    }

    if (role === "theme") {
      var hasPreview = false
      for (var j = 0; j < count; j++) {
        var fname = String(dirModel.get(j, "fileName") || "")
        if (fname === "preview.png") {
          hasPreview = true
          break
        }
      }
      var ansi = root.parseColorsToml(root.scanThemePath + "/colors.toml")
      root.scanAcc.push({
        name: root.scanThemeName,
        path: root.scanThemePath,
        preview: hasPreview ? (root.scanThemePath + "/preview.png") : null,
        ansi_colors: ansi,
        source: root.scanSource
      })
      root.scanMode = ""
      root.drainScanQueue()
      return
    }

    root.scanMode = ""
    root.drainScanQueue()
  }

  function parseColorsToml(path) {
    var ansi = []
    for (var i = 0; i < 16; i++)
      ansi.push(null)

    var text = root.readTextFile(path)
    if (!text)
      return ansi

    var lines = String(text).split("\n")
    for (var li = 0; li < lines.length; li++) {
      var line = String(lines[li] || "").trim()
      if (!line || line.charAt(0) === "#")
        continue
      var eq = line.indexOf("=")
      if (eq < 0)
        continue
      var key = line.substring(0, eq).trim()
      var value = line.substring(eq + 1).trim()
      if (value.charAt(0) === "\"" && value.charAt(value.length - 1) === "\"")
        value = value.substring(1, value.length - 1)
      if (!value || value.charAt(0) !== "#")
        continue

      var index = -1
      if (key.indexOf("color") === 0) {
        var n = parseInt(key.substring(5), 10)
        if (!isNaN(n))
          index = n
      } else {
        switch (key) {
          case "black": index = 0; break
          case "red": index = 1; break
          case "green": index = 2; break
          case "yellow": index = 3; break
          case "blue": index = 4; break
          case "magenta":
          case "purple": index = 5; break
          case "cyan": index = 6; break
          case "white": index = 7; break
          case "bright_black": index = 8; break
          case "bright_red": index = 9; break
          case "bright_green": index = 10; break
          case "bright_yellow": index = 11; break
          case "bright_blue": index = 12; break
          case "bright_magenta":
          case "bright_purple": index = 13; break
          case "bright_cyan": index = 14; break
          case "bright_white": index = 15; break
        }
      }
      if (index < 0 || index > 15)
        continue
      if (key.indexOf("color") === 0 || ansi[index] === null)
        ansi[index] = value
    }
    return ansi
  }

  function readTextFile(path) {
    fileView.path = ""
    fileView.path = root.toFileUrl(path)
    try {
      return String(fileView.text() || "")
    } catch (e) {
      return ""
    }
  }

  function readJsonFile(path) {
    var text = root.readTextFile(path)
    if (!text)
      return null
    try {
      return JSON.parse(text)
    } catch (e) {
      return null
    }
  }

  function writeJsonFile(path, value) {
    cacheWriteView.path = ""
    cacheWriteView.path = root.toFileUrl(path)
    try {
      cacheWriteView.setText(JSON.stringify(value, null, 2))
    } catch (e) {
    }
  }

  function finishScan() {
    if (root.scanSerial !== root.installedSerial)
      return
    root.cachedInstalled = root.scanAcc.slice()
    root.localListed(root.cachedInstalled)
    root.maybeContinueRemoveAfterScan()
  }

  function findCached(themeName) {
    var name = String(themeName || "")
    var list = root.cachedInstalled || []
    var userHit = null
    var anyHit = null
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || "") !== name)
        continue
      if (String(list[i].source || "") === "user")
        userHit = list[i]
      if (!anyHit)
        anyHit = list[i]
    }
    return userHit || anyHit
  }

  function filterLocal(query) {
    var q = String(query || "").trim().toLowerCase()
    var list = root.cachedInstalled || []
    if (!q)
      return list.slice()
    var out = []
    for (var i = 0; i < list.length; i++) {
      var n = String(list[i].name || "").toLowerCase()
      if (n.indexOf(q) >= 0)
        out.push(list[i])
    }
    return out
  }

  // --- Web catalog (mirrors search/themes.rs) ---

  function loadWeb(query) {
    root.webSerial += 1
    root.webLoading = true
    root.webShownFromCache = false
    root.webQuery = String(query || "")
    root.webCandidates = []
    root.webFetched = []
    root.webPreviewIndex = 0
    root.webPreviewPending = 0
    root.webPage = 0

    if (root.tryEmitCachedWeb(root.webSerial, root.webQuery))
      return root.webSerial

    if (mkdirProc.running)
      mkdirProc.running = false
    mkdirProc.serial = root.webSerial
    mkdirProc.command = ["mkdir", "-p", root.cacheDir]
    mkdirProc.running = true
    return root.webSerial
  }

  function tryEmitCachedWeb(serial, query) {
    var cached = root.readWebCache()
    if (!cached)
      return false
    root.cachedWeb = cached
    var filtered = root.filterWeb(cached, query)
    root.webShownFromCache = true
    root.webListed(filtered, true)
    root.webLoading = false
    root.webFinished()
    return true
  }

  function readWebCache() {
    var value = root.readJsonFile(root.webCachePath)
    if (!value || typeof value !== "object" || value.length !== undefined)
      return null
    var fetchedAt = Number(value.fetched_at || 0)
    if (!fetchedAt)
      return null
    var now = Math.floor(Date.now() / 1000)
    if (now - fetchedAt > root.cacheTtlSecs)
      return null
    var arr = value.themes
    if (!arr || arr.length === undefined)
      return null
    var out = []
    for (var i = 0; i < arr.length; i++) {
      var item = arr[i] || {}
      var name = String(item.name || "")
      var fullName = String(item.full_name || "")
      var author = String(item.author || "")
      var repo = String(item.repo || "")
      var preview = String(item.preview_image || "")
      var stars = Number(item.stars || 0)
      if (!name || !fullName || !author || !repo || !preview)
        continue
      out.push({
        name: name,
        full_name: fullName,
        description: String(item.description || ""),
        author: author,
        repo: repo,
        stars: stars,
        preview_image: preview
      })
    }
    return out
  }

  function filterWeb(themes, query) {
    var q = String(query || "").trim().toLowerCase()
    var list = themes || []
    var sorted = list.slice()
    sorted.sort(function(a, b) {
      return Number(b.stars || 0) - Number(a.stars || 0)
    })
    if (!q)
      return sorted
    var out = []
    for (var i = 0; i < sorted.length; i++) {
      var t = sorted[i] || {}
      var hay = (String(t.name || "") + " " + String(t.full_name || "") + " "
        + String(t.description || "") + " " + String(t.author || "")).toLowerCase()
      if (hay.indexOf(q) >= 0)
        out.push(t)
    }
    return out
  }

  function startWebFetch(serial) {
    if (serial !== root.webSerial)
      return
    root.webCandidates = []
    root.webPage = 1
    root.fetchWebPage(serial)
  }

  function fetchWebPage(serial) {
    if (serial !== root.webSerial)
      return
    if (root.webPage < 1 || root.webPage > root.searchPages) {
      root.startPreviewChecks(serial)
      return
    }
    var url = "https://api.github.com/search/repositories?q=omarchy-theme+in:name+fork:false&sort=stars&order=desc&per_page=100&page="
      + root.webPage
    root.fetchJson(url, function(ok, data, error) {
      if (serial !== root.webSerial)
        return
      if (!ok || !data || typeof data !== "object") {
        if (root.webCandidates.length === 0 && !root.webShownFromCache) {
          root.webLoading = false
          root.webFailed(error || "GitHub theme search failed")
        } else {
          root.startPreviewChecks(serial)
        }
        return
      }
      var items = data.items
      if (!items || items.length === undefined || items.length === 0) {
        root.startPreviewChecks(serial)
        return
      }
      for (var i = 0; i < items.length; i++) {
        var item = items[i] || {}
        var fullName = String(item.full_name || "")
        if (!fullName)
          continue
        var owner = item.owner || {}
        root.webCandidates.push({
          name: String(item.name || fullName),
          full_name: fullName,
          description: String(item.description || ""),
          author: String(owner.login || ""),
          repo: String(item.clone_url || ""),
          stars: Number(item.stargazers_count || 0),
          preview_image: "",
          default_branch: String(item.default_branch || "main")
        })
      }
      root.webPage += 1
      if (root.webPage <= root.searchPages)
        root.fetchWebPage(serial)
      else
        root.startPreviewChecks(serial)
    })
  }

  function startPreviewChecks(serial) {
    if (serial !== root.webSerial)
      return
    root.webFetched = []
    root.webPreviewIndex = 0
    root.webPreviewPending = 0
    root.drainPreviewChecks(serial)
  }

  function drainPreviewChecks(serial) {
    if (serial !== root.webSerial)
      return
    var batch = 16
    while (root.webPreviewPending < batch && root.webPreviewIndex < root.webCandidates.length) {
      var idx = root.webPreviewIndex
      root.webPreviewIndex += 1
      root.webPreviewPending += 1
      root.checkPreviewFor(serial, root.webCandidates[idx])
    }
    if (root.webPreviewPending === 0 && root.webPreviewIndex >= root.webCandidates.length)
      root.finishWebFetch(serial)
  }

  function checkPreviewFor(serial, theme) {
    var branches = []
    var def = String(theme.default_branch || "main")
    branches.push(def)
    if (def !== "main")
      branches.push("main")
    if (def !== "master" && branches.indexOf("master") < 0)
      branches.push("master")
    root.tryPreviewBranch(serial, theme, branches, 0)
  }

  function tryPreviewBranch(serial, theme, branches, bi) {
    if (serial !== root.webSerial)
      return
    if (bi >= branches.length) {
      root.webPreviewPending -= 1
      root.drainPreviewChecks(serial)
      return
    }
    var url = "https://raw.githubusercontent.com/" + theme.full_name + "/" + branches[bi] + "/preview.png"
    root.headOk(url, function(ok) {
      if (serial !== root.webSerial)
        return
      if (ok) {
        root.webFetched.push({
          name: theme.name,
          full_name: theme.full_name,
          description: theme.description,
          author: theme.author,
          repo: theme.repo,
          stars: theme.stars,
          preview_image: url
        })
        root.webPreviewPending -= 1
        root.drainPreviewChecks(serial)
        return
      }
      root.tryPreviewBranch(serial, theme, branches, bi + 1)
    })
  }

  function finishWebFetch(serial) {
    if (serial !== root.webSerial)
      return
    var fetched = root.webFetched.slice()
    fetched.sort(function(a, b) {
      return Number(b.stars || 0) - Number(a.stars || 0)
    })
    root.writeJsonFile(root.webCachePath, {
      fetched_at: Math.floor(Date.now() / 1000),
      themes: fetched
    })
    root.cachedWeb = fetched
    var filtered = root.filterWeb(fetched, root.webQuery)
    root.webListed(filtered, false)
    root.webLoading = false
    root.webFinished()
  }

  function fetchJson(url, callback) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.setRequestHeader("User-Agent", "cOMtrol")
    xhr.setRequestHeader("Accept", "application/vnd.github+json")
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

  function headOk(url, callback) {
    var xhr = new XMLHttpRequest()
    xhr.open("HEAD", url)
    xhr.setRequestHeader("User-Agent", "cOMtrol")
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return
      callback(xhr.status >= 200 && xhr.status < 300)
    }
    try {
      xhr.send()
    } catch (e) {
      callback(false)
    }
  }

  // --- Install (git clone + omarchy-theme-set; no omarchy-theme-install script) ---

  function themeNameFromRepo(repoUrl) {
    var path = String(repoUrl || "").trim()
    if (!path)
      return ""
    if (path.indexOf("://") < 0) {
      var colon = path.indexOf(":")
      if (colon >= 0 && path.substring(0, colon).indexOf("/") < 0)
        path = path.substring(colon + 1)
    }
    while (path.length > 1 && path.charAt(path.length - 1) === "/")
      path = path.substring(0, path.length - 1)
    var slash = path.lastIndexOf("/")
    var base = slash >= 0 ? path.substring(slash + 1) : path
    if (base.length > 4 && base.substring(base.length - 4).toLowerCase() === ".git")
      base = base.substring(0, base.length - 4)
    base = base.toLowerCase()
    if (base.indexOf("omarchy-") === 0)
      base = base.substring(8)
    if (base.length > 6 && base.substring(base.length - 6) === "-theme")
      base = base.substring(0, base.length - 6)
    return base
  }

  function isValidThemeName(name) {
    var n = String(name || "")
    if (!n)
      return false
    return /^[a-z0-9_][a-z0-9._+-]*$/.test(n)
  }

  function install(repoUrl) {
    var url = String(repoUrl || "").trim()
    if (!url)
      return -1
    var name = root.themeNameFromRepo(url)
    if (!root.isValidThemeName(name))
      return -1

    root.installSerial += 1
    root.installPipeSerial = root.installSerial
    root.installPipeUrl = url
    root.installPipeName = name
    root.installPipePath = root.userThemesDir + "/" + name
    root.installPipeStep = "mkdir"
    root.runInstallStep()
    return root.installPipeSerial
  }

  function runInstallStep() {
    if (root.installPipeSerial < 0)
      return
    if (installProc.running)
      installProc.running = false

    if (root.installPipeStep === "mkdir") {
      installProc.command = ["mkdir", "-p", root.userThemesDir]
      installProc.running = true
      return
    }
    if (root.installPipeStep === "rm_existing") {
      installProc.command = ["rm", "-rf", "--", root.installPipePath]
      installProc.running = true
      return
    }
    if (root.installPipeStep === "clone") {
      installProc.command = ["git", "clone", "--", root.installPipeUrl, root.installPipePath]
      installProc.running = true
      return
    }
    if (root.installPipeStep === "set") {
      installProc.command = ["omarchy-theme-set", root.installPipeName]
      installProc.running = true
      return
    }
  }

  function onInstallProcExited(exitCode) {
    var serial = root.installPipeSerial
    if (serial < 0)
      return

    if (root.installPipeStep === "mkdir") {
      root.installPipeStep = "rm_existing"
      root.runInstallStep()
      return
    }
    if (root.installPipeStep === "rm_existing") {
      root.installPipeStep = "clone"
      root.runInstallStep()
      return
    }
    if (root.installPipeStep === "clone") {
      if (exitCode !== 0) {
        root.installPipeSerial = -1
        root.installPipeStep = ""
        root.installFinished(exitCode, serial, root.installPipeName)
        return
      }
      root.installPipeStep = "set"
      root.runInstallStep()
      return
    }
    if (root.installPipeStep === "set") {
      var name = root.installPipeName
      root.installPipeSerial = -1
      root.installPipeStep = ""
      root.listInstalled()
      root.installFinished(exitCode, serial, name)
    }
  }

  function apply(themeName) {
    var name = String(themeName || "").trim()
    if (!name)
      return -1
    root.applySerial += 1
    applyProc.serial = root.applySerial
    if (applyProc.running)
      applyProc.running = false
    applyProc.command = ["omarchy-theme-set", name]
    applyProc.running = true
    return applyProc.serial
  }

  // --- Remove (mirrors remove/themes.rs) ---

  function remove(themeName) {
    var name = String(themeName || "").trim()
    if (!name || name === "." || name === ".." || name.indexOf("/") >= 0)
      return -1

    root.removeSerial += 1
    var serial = root.removeSerial
    var theme = root.findCached(name)
    if (!theme || !theme.path) {
      root._removeAfterScanName = name
      root._removeAfterScanSerial = serial
      root.listInstalled()
      return serial
    }
    root.startRemovePipeline(serial, theme)
    return serial
  }

  function maybeContinueRemoveAfterScan() {
    if (root._removeAfterScanSerial < 0)
      return
    var serial = root._removeAfterScanSerial
    var name = root._removeAfterScanName
    root._removeAfterScanSerial = -1
    root._removeAfterScanName = ""
    var theme = root.findCached(name)
    if (!theme || !theme.path) {
      root.removeFinished(1, serial, {
        ok: false,
        error: "No themes to remove.",
        removed: [],
        skipped: [name]
      })
      return
    }
    root.startRemovePipeline(serial, theme)
  }

  function startRemovePipeline(serial, theme) {
    root.removePipeSerial = serial
    root.removePipeName = String(theme.name || "")
    root.removePipePath = String(theme.path || "")
    root.removePipeSource = String(theme.source || "user")
    root.removePipePayload = ({
      ok: false,
      removed: [],
      skipped: [],
      first_party: root.removePipeSource === "first_party" ? [root.removePipeName] : []
    })
    if (removeProc.running)
      removeProc.running = false
    if (root.removePipeSource === "first_party")
      removeProc.command = ["pkexec", "rm", "-rf", "--", root.removePipePath]
    else
      removeProc.command = ["rm", "-rf", "--", root.removePipePath]
    removeProc.running = true
  }

  function onRemoveProcExited(exitCode) {
    var serial = root.removePipeSerial
    if (serial < 0)
      return
    var payload = root.removePipePayload
    if (exitCode === 0) {
      payload.ok = true
      payload.removed = [root.removePipeName]
    } else {
      payload.ok = false
      payload.error = "Failed to remove " + root.removePipePath
    }
    root.removePipeSerial = -1
    root.listInstalled()
    root.removeFinished(payload.ok ? 0 : 1, serial, payload)
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
    id: fileView
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
      if (mkdirProc.serial !== root.webSerial)
        return
      root.startWebFetch(mkdirProc.serial)
    }
  }

  Process {
    id: installProc
    onExited: function(exitCode) {
      root.onInstallProcExited(exitCode)
    }
  }

  Process {
    id: removeProc
    onExited: function(exitCode) {
      root.onRemoveProcExited(exitCode)
    }
  }

  Process {
    id: applyProc
    property int serial: 0
    onExited: function(exitCode) {
      root.applyFinished(exitCode, applyProc.serial)
    }
  }
}
