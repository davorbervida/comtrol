pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Pacman package list / search / remove — pure QML (no run.sh / cOMtrol).
// Process only for pacman / pkexec / zstd|tar (same binaries Rust used).
Item {
  id: root

  readonly property string pacmanLocalDir: "/var/lib/pacman/local"
  readonly property string omarchyDbPath: "/var/lib/pacman/sync/omarchy.db"

  property int installedSerial: 0
  property int webSerial: 0
  property int removeSerial: 0

  property var cachedInstalled: []
  property var nativeNameSet: ({})

  // Local scan after pacman -Qnq
  property int scanSerial: 0
  property var scanAcc: []
  property string scanMode: "" // "" | "listing" | "desc"
  property string scanListingPath: ""
  property string scanDescPath: ""
  property var scanDescQueue: []

  // Web / omarchy pipeline
  property var installedNameSet: ({})
  property string webQuery: ""
  property string webStep: "" // qnq | qq | omarchy | ss

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
    root.webStep = ""
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

  function matchesTokens(name, description, tokens) {
    if (!tokens || tokens.length === 0)
      return true
    var hay = root.normalizePkgText(name) + " " + root.normalizePkgText(description)
    for (var i = 0; i < tokens.length; i++) {
      if (hay.indexOf(root.normalizePkgText(tokens[i])) < 0)
        return false
    }
    return true
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

  // --- Local list (mirrors system/packages.rs) ---

  function listInstalled() {
    root.installedSerial += 1
    root.scanSerial = root.installedSerial
    root.scanAcc = []
    root.scanDescQueue = []
    root.scanMode = ""
    root.nativeNameSet = ({})

    var stale = root.cachedInstalled || []
    if (stale.length > 0)
      root.localListed(stale.slice())

    pacmanProc.serial = root.installedSerial
    pacmanProc.purpose = "qnq"
    root.startProc(pacmanProc, ["pacman", "-Qnq"])
    return root.installedSerial
  }

  function beginLocalScan(nativeText) {
    if (root.scanSerial !== root.installedSerial)
      return
    root.nativeNameSet = root.nameSetFromLines(nativeText)
    root.scanAcc = []
    root.scanDescQueue = []
    root.scanListingPath = root.pacmanLocalDir
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
    root.scanDescPath = descPath
    var src = root.readTextFile(descPath)
    var name = root.descField(src, "NAME")
    if (name && root.nativeNameSet[name]) {
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

  // --- Web search (mirrors search/packages.rs) ---

  function searchWeb(query) {
    root.webSerial += 1
    root.webQuery = String(query || "")
    root.installedNameSet = ({})
    var q = root.webQuery.trim()
    if (!q) {
      pacmanProc.serial = root.webSerial
      pacmanProc.purpose = "qq"
      root.webStep = "qq"
      root.startProc(pacmanProc, ["pacman", "-Qq"])
      return root.webSerial
    }
    var tokens = root.queryTokens(q)
    if (tokens.length === 0) {
      root.webListed([])
      return root.webSerial
    }
    var argv = ["pacman", "-Ss", "--"]
    for (var i = 0; i < tokens.length; i++)
      argv.push(tokens[i])
    pacmanProc.serial = root.webSerial
    pacmanProc.purpose = "ss"
    root.webStep = "ss"
    root.startProc(pacmanProc, argv)
    return root.webSerial
  }

  function onQqFinished(text, exitCode) {
    if (pacmanProc.serial !== root.webSerial)
      return
    root.installedNameSet = root.nameSetFromLines(text)
    // Same pipeline Rust used for empty web catalog.
    pacmanProc.serial = root.webSerial
    pacmanProc.purpose = "omarchy"
    root.webStep = "omarchy"
    root.startProc(pacmanProc, [
      "sh", "-c",
      "zstd -d -c " + root.omarchyDbPath + " | tar -xO --wildcards '*/desc'"
    ])
  }

  function onOmarchyFinished(text, exitCode) {
    if (pacmanProc.serial !== root.webSerial)
      return
    if (exitCode !== 0) {
      root.webFailed("Failed to read omarchy package database")
      return
    }
    var packages = root.parseOmarchyDescs(text)
    packages.sort(function(a, b) {
      return String(a.name || "").localeCompare(String(b.name || ""))
    })
    root.webListed(packages)
  }

  function parseOmarchyDescs(text) {
    var out = []
    var chunks = String(text || "").split("%FILENAME%\n")
    for (var i = 0; i < chunks.length; i++) {
      var chunk = chunks[i]
      if (!chunk)
        continue
      var name = root.descField(chunk, "NAME")
      var version = root.descField(chunk, "VERSION")
      if (!name || !version)
        continue
      out.push({
        name: name,
        version: version,
        description: root.descField(chunk, "DESC"),
        repo: "omarchy",
        installed: !!root.installedNameSet[name]
      })
    }
    return out
  }

  function onSsFinished(text, exitCode) {
    if (pacmanProc.serial !== root.webSerial)
      return
    var tokens = root.queryTokens(root.webQuery)
    var packages = root.parseSsOutput(text)
    var filtered = []
    for (var i = 0; i < packages.length; i++) {
      var p = packages[i]
      if (root.matchesTokens(p.name, p.description, tokens))
        filtered.push(p)
    }
    filtered.sort(function(a, b) {
      return String(a.name || "").localeCompare(String(b.name || ""))
    })
    root.webListed(filtered)
  }

  function parseSsOutput(stdout) {
    var packages = []
    var lines = String(stdout || "").split("\n")
    var i = 0
    while (i < lines.length) {
      var line = lines[i]
      i += 1
      if (!line || line.charAt(0) === " " || line.charAt(0) === "\t")
        continue
      var sp = line.indexOf(" ")
      if (sp < 0)
        continue
      var repoName = line.substring(0, sp)
      var rest = line.substring(sp + 1).trim()
      var slash = repoName.indexOf("/")
      if (slash < 0)
        continue
      var repo = repoName.substring(0, slash)
      var name = repoName.substring(slash + 1)
      var installed = rest.indexOf("[installed") >= 0
      var version = rest.split(/\s+/)[0] || ""
      var description = ""
      if (i < lines.length) {
        var next = lines[i]
        if (next && (next.charAt(0) === " " || next.charAt(0) === "\t")) {
          description = next.trim()
          i += 1
        }
      }
      packages.push({
        name: name,
        version: version,
        description: description,
        repo: repo,
        installed: installed
      })
    }
    return packages
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

    if (purpose === "qnq") {
      if (serial !== root.installedSerial)
        return
      root.beginLocalScan(text)
      return
    }
    if (purpose === "qq") {
      root.onQqFinished(text, exitCode)
      return
    }
    if (purpose === "omarchy") {
      root.onOmarchyFinished(text, exitCode)
      return
    }
    if (purpose === "ss") {
      root.onSsFinished(text, exitCode)
      return
    }
  }

  // --- Remove (mirrors remove/packages.rs) ---

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

    // Prefer cached native list; if empty, still attempt pacman -R (pacman validates).
    var known = root.findCached(name)
    if (!known && root.cachedInstalled && root.cachedInstalled.length > 0) {
      root.removeFinished(1, serial, {
        ok: false,
        error: "No pacman packages to remove.",
        removed: [],
        skipped: [name]
      })
      return serial
    }

    removeProc.serial = serial
    removeProc.packageName = name
    // --noconfirm: Process has no TTY for pacman prompts (GUI path).
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
