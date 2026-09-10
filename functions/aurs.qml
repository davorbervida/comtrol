pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// AUR package list / search / remove — pure QML (no run.sh / cOMtrol).
// Local: pacman -Qmq + /var/lib/pacman/local. Web: AUR RPC via XMLHttpRequest.
// Remove: pkexec pacman -R (same as Rust).
Item {
  id: root

  readonly property string pacmanLocalDir: "/var/lib/pacman/local"
  readonly property string aurRpcBase: "https://aur.archlinux.org/rpc/v5/search/"

  property int installedSerial: 0
  property int webSerial: 0
  property int removeSerial: 0

  property var cachedInstalled: []
  property var foreignNameSet: ({})
  property var installedForeignSet: ({})

  // Local scan after pacman -Qmq
  property int scanSerial: 0
  property var scanAcc: []
  property string scanMode: "" // "" | "listing" | "desc"
  property var scanDescQueue: []

  property string webQuery: ""

  signal localListed(var packages)
  signal webListed(var packages)
  signal webFailed(string message)
  signal removeFinished(int exitCode, int serial, var payload)

  function cancel() {
    root.installedSerial += 1
    root.webSerial += 1
    root.scanSerial += 1
    root.scanMode = ""
    root.scanDescQueue = []
    if (pacmanProc.running)
      pacmanProc.running = false
    if (removeProc.running)
      removeProc.running = false
  }

  function startProc(proc, argv) {
    if (proc.running)
      proc.running = false
    if (typeof proc.exec === "function") {
      proc.exec(argv)
      return
    }
    proc.command = argv
    proc.running = false
    proc.running = true
  }

  function queryTokens(query) {
    var parts = String(query || "").trim().toLowerCase().split(/\s+/)
    var out = []
    for (var i = 0; i < parts.length; i++) {
      if (parts[i])
        out.push(parts[i])
    }
    return out
  }

  function normalizePkgText(s) {
    return String(s || "").toLowerCase().replace(/[-_]/g, " ")
  }

  function packageMatches(pkg, token) {
    var needle = root.normalizePkgText(token)
    if (!needle)
      return true
    var hay = root.normalizePkgText(pkg.name) + " " + root.normalizePkgText(pkg.description)
    return hay.indexOf(needle) >= 0
  }

  function descField(src, key) {
    var header = "%" + key + "%\n"
    var text = String(src || "")
    var i = text.indexOf(header)
    if (i < 0)
      return ""
    var rest = text.substring(i + header.length)
    var end = rest.indexOf("\n")
    var value = (end < 0 ? rest : rest.substring(0, end)).trim()
    return value
  }

  function readTextFile(path) {
    fileView.path = ""
    fileView.path = "file://" + String(path || "")
    try {
      return String(fileView.text() || "")
    } catch (e) {
      return ""
    }
  }

  function nameSetFromLines(text) {
    var out = ({})
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var n = String(lines[i] || "").trim()
      if (n)
        out[n] = true
    }
    return out
  }

  function encodePathSegment(s) {
    var str = String(s || "")
    var out = ""
    for (var i = 0; i < str.length; i++) {
      var c = str.charAt(i)
      var code = str.charCodeAt(i)
      if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90)
          || (code >= 97 && code <= 122) || c === "-" || c === "_" || c === "." || c === "~") {
        out += c
      } else {
        var hex = code.toString(16).toUpperCase()
        if (hex.length < 2)
          hex = "0" + hex
        out += "%" + hex
      }
    }
    return out
  }

  // --- Local list (mirrors system/aurs.rs) ---

  function listInstalled() {
    root.installedSerial += 1
    root.scanSerial = root.installedSerial
    root.scanAcc = []
    root.scanDescQueue = []
    root.scanMode = ""
    root.foreignNameSet = ({})

    var stale = root.cachedInstalled || []
    if (stale.length > 0)
      root.localListed(stale.slice())

    pacmanProc.serial = root.installedSerial
    pacmanProc.purpose = "qmq"
    root.startProc(pacmanProc, ["pacman", "-Qmq"])
    return root.installedSerial
  }

  function beginLocalScan(foreignText) {
    if (root.scanSerial !== root.installedSerial)
      return
    root.foreignNameSet = root.nameSetFromLines(foreignText)
    root.scanAcc = []
    root.scanDescQueue = []
    root.scanMode = "listing"
    dirModel.folder = ""
    Qt.callLater(root.applyLocalDirModel)
  }

  function applyLocalDirModel() {
    if (root.scanSerial !== root.installedSerial)
      return
    if (root.scanMode !== "listing")
      return
    dirModel.folder = "file://" + root.pacmanLocalDir
  }

  function onLocalDirReady() {
    if (root.scanSerial !== root.installedSerial)
      return
    if (root.scanMode !== "listing")
      return
    if (dirModel.status !== FolderListModel.Ready)
      return
    var listed = String(dirModel.folder || "")
    var want = "file://" + root.pacmanLocalDir
    if (listed !== want && listed !== want + "/")
      return

    var count = dirModel.count
    for (var i = 0; i < count; i++) {
      if (!dirModel.isFolder(i))
        continue
      var path = String(dirModel.get(i, "filePath") || "")
      if (!path)
        continue
      root.scanDescQueue.push(path + "/desc")
    }
    root.scanMode = "desc"
    root.drainDescQueue()
  }

  function drainDescQueue() {
    if (root.scanSerial !== root.installedSerial)
      return
    if (root.scanMode !== "desc")
      return
    if (!root.scanDescQueue || root.scanDescQueue.length === 0) {
      root.finishLocalScan()
      return
    }
    var descPath = root.scanDescQueue[0]
    root.scanDescQueue = root.scanDescQueue.slice(1)
    var src = root.readTextFile(descPath)
    var name = root.descField(src, "NAME")
    if (name && root.foreignNameSet[name]) {
      var version = root.descField(src, "VERSION")
      if (version) {
        var reasonRaw = root.descField(src, "REASON")
        root.scanAcc.push({
          name: name,
          version: version,
          description: root.descField(src, "DESC"),
          reason: reasonRaw === "1" ? "dependency" : "explicit"
        })
      }
    }
    Qt.callLater(root.drainDescQueue)
  }

  function finishLocalScan() {
    if (root.scanSerial !== root.installedSerial)
      return
    var items = root.scanAcc.slice()
    items.sort(function(a, b) {
      return String(a.name || "").localeCompare(String(b.name || ""))
    })
    root.cachedInstalled = items
    root.scanMode = ""
    root.localListed(items)
  }

  // --- Web search (mirrors search/aurs.rs, XMLHttpRequest instead of curl) ---

  function searchWeb(query) {
    root.webSerial += 1
    var raw = String(query || "").trim()
    if (!raw)
      raw = "omarchy"
    root.webQuery = raw

    pacmanProc.serial = root.webSerial
    pacmanProc.purpose = "qmq_web"
    root.startProc(pacmanProc, ["pacman", "-Qmq"])
    return root.webSerial
  }

  function startAurRpc(serial) {
    if (serial !== root.webSerial)
      return
    var tokens = root.queryTokens(root.webQuery)
    if (tokens.length === 0) {
      root.webListed([])
      return
    }

    var searchArg = tokens.join("-")
    root.fetchAurSearch(serial, searchArg, tokens, true)
  }

  function fetchAurSearch(serial, searchArg, tokens, allowFallback) {
    if (serial !== root.webSerial)
      return
    if (String(searchArg || "").length < 2) {
      if (allowFallback && tokens.length > 1)
        root.tryLongestTokenFallback(serial, tokens, [])
      else
        root.webListed([])
      return
    }

    var url = root.aurRpcBase + root.encodePathSegment(searchArg) + "?by=name-desc"
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.setRequestHeader("User-Agent", "cOMtrol")
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return
      if (serial !== root.webSerial)
        return
      if (xhr.status < 200 || xhr.status >= 300) {
        root.webFailed("AUR search failed (HTTP " + xhr.status + ")")
        return
      }
      var results = []
      try {
        var data = JSON.parse(String(xhr.responseText || ""))
        results = (data && data.results) || []
      } catch (e) {
        root.webFailed("Invalid AUR JSON")
        return
      }
      if ((!results || results.length === 0) && allowFallback && tokens.length > 1) {
        root.tryLongestTokenFallback(serial, tokens, results)
        return
      }
      root.finishAurSearch(serial, tokens, results)
    }
    try {
      xhr.send()
    } catch (e) {
      if (serial === root.webSerial)
        root.webFailed(String(e))
    }
  }

  function tryLongestTokenFallback(serial, tokens, _empty) {
    if (serial !== root.webSerial)
      return
    var searchArg = tokens.join("-")
    var fallback = ""
    var bestLen = 0
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].length > bestLen) {
        bestLen = tokens[i].length
        fallback = tokens[i]
      }
    }
    if (!fallback || fallback === searchArg) {
      root.finishAurSearch(serial, tokens, [])
      return
    }
    root.fetchAurSearch(serial, fallback, tokens, false)
  }

  function finishAurSearch(serial, tokens, results) {
    if (serial !== root.webSerial)
      return
    var packages = []
    var list = results || []
    for (var i = 0; i < list.length; i++) {
      var parsed = root.parseAurHit(list[i])
      if (!parsed)
        continue
      var ok = true
      for (var t = 0; t < tokens.length; t++) {
        if (!root.packageMatches(parsed, tokens[t])) {
          ok = false
          break
        }
      }
      if (ok)
        packages.push(parsed)
    }
    packages.sort(function(a, b) {
      return String(a.name || "").localeCompare(String(b.name || ""))
    })
    root.webListed(packages)
  }

  function parseAurHit(pkg) {
    if (!pkg || typeof pkg !== "object")
      return null
    var name = String(pkg.Name || "")
    if (!name)
      return null
    var maintainer = pkg.Maintainer
    return {
      name: name,
      version: String(pkg.Version || ""),
      description: String(pkg.Description || ""),
      votes: Number(pkg.NumVotes || 0),
      popularity: Number(pkg.Popularity || 0),
      maintainer: (maintainer === undefined || maintainer === null) ? null : String(maintainer),
      url: String(pkg.URL || ""),
      installed: !!root.installedForeignSet[name]
    }
  }

  function onPacmanStdout(text) {
    pacmanProc._stdout = String(text || "")
  }

  function onPacmanExited(exitCode) {
    var purpose = pacmanProc.purpose
    var serial = pacmanProc.serial
    var text = String(pacmanProc._stdout || "")
    pacmanProc._stdout = ""
    pacmanProc.purpose = ""

    if (purpose === "qmq") {
      if (serial !== root.installedSerial)
        return
      root.beginLocalScan(text)
      return
    }
    if (purpose === "qmq_web") {
      if (serial !== root.webSerial)
        return
      root.installedForeignSet = root.nameSetFromLines(text)
      root.startAurRpc(serial)
      return
    }
  }

  // --- Remove (mirrors remove/aurs.rs) ---

  function findCached(name) {
    var n = String(name || "")
    var list = root.cachedInstalled || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || "") === n)
        return list[i]
    }
    return null
  }

  function remove(packageName) {
    var name = String(packageName || "").trim()
    if (!name)
      return -1

    root.removeSerial += 1
    var serial = root.removeSerial

    var known = root.findCached(name)
    if (!known && root.cachedInstalled && root.cachedInstalled.length > 0) {
      root.removeFinished(1, serial, {
        ok: false,
        error: "No AUR packages to remove.",
        removed: [],
        skipped: [name]
      })
      return serial
    }

    removeProc.serial = serial
    removeProc.packageName = name
    root.startProc(removeProc, ["pkexec", "pacman", "-R", "--noconfirm", "--", name])
    return serial
  }

  function onRemoveExited(exitCode) {
    var serial = removeProc.serial
    var name = removeProc.packageName
    removeProc.serial = -1
    removeProc.packageName = ""
    var payload = ({
      ok: exitCode === 0,
      removed: exitCode === 0 ? [name] : [],
      skipped: exitCode === 0 ? [] : [name]
    })
    if (exitCode === 0)
      root.cachedInstalled = []
    root.removeFinished(exitCode, serial, payload)
  }

  FolderListModel {
    id: dirModel
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
    showHidden: false
    sortField: FolderListModel.Unsorted
    onStatusChanged: {
      if (root.scanMode !== "listing")
        return
      if (status === FolderListModel.Ready)
        Qt.callLater(root.onLocalDirReady)
    }
  }

  FileView {
    id: fileView
    blockLoading: true
    printErrors: false
  }

  Process {
    id: pacmanProc
    property int serial: 0
    property string purpose: ""
    property string _stdout: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onPacmanStdout(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.onPacmanExited(exitCode)
    }
  }

  Process {
    id: removeProc
    property int serial: -1
    property string packageName: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.onRemoveExited(exitCode)
    }
  }
}
