pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Web app list / remove — pure QML (no run.sh / cOMtrol).
// FS scan: FolderListModel + FileView (.desktop). Process: rm / pkexec / update-desktop-database.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string userAppsDir: root.home + "/.local/share/applications"
  readonly property string firstPartyAppsDir: root.omarchyPath + "/applications"
  readonly property string iconDir: root.home + "/.local/share/icons/hicolor/256x256/apps"
  readonly property string oldIconDir: root.home + "/.local/share/applications/icons"

  property int installedSerial: 0
  property int removeSerial: 0
  property var cachedInstalled: []

  // Directory scan
  property int scanSerial: 0
  property var scanAcc: []
  property var scanQueue: []
  property string scanMode: "" // "" | "listing"
  property string scanSource: ""
  property bool scanRecursive: false
  property string scanListingPath: ""

  // Remove pipeline: user rm (+ icons) then optional pkexec for first-party, then update-desktop-database
  property int removePipeSerial: -1
  property var removePipeApps: []
  property var removePipeUserPaths: []
  property var removePipeFirstParty: []
  property var removePipeIconPaths: []
  property string removePipeStep: "" // rm_user | pkexec | update_db
  property var removePipePayload: ({})

  signal localListed(var apps)
  signal removeFinished(int exitCode, int serial, var payload)

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
    root.scanSerial += 1
    root.removePipeSerial = -1
    root.scanMode = ""
    root.scanQueue = []
    root.removePipeApps = []
    root.removePipeUserPaths = []
    root.removePipeFirstParty = []
    root.removePipeIconPaths = []
    root.removePipeStep = ""
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

  function readTextFile(path) {
    fileView.path = ""
    fileView.path = root.toFileUrl(path)
    try {
      return String(fileView.text() || "")
    } catch (e) {
      return ""
    }
  }

  function desktopField(src, key) {
    var lines = String(src || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = String(lines[i] || "").trim()
      if (!line || line.charAt(0) === "#")
        continue
      var eq = line.indexOf("=")
      if (eq < 0)
        continue
      if (line.substring(0, eq) !== key)
        continue
      return line.substring(eq + 1).trim()
    }
    return ""
  }

  function parseUrlFromExec(exec) {
    var e = String(exec || "")
    var prefix = "omarchy-launch-webapp"
    if (e.indexOf(prefix) !== 0)
      return ""
    var rest = e.substring(prefix.length).trim()
    if (!rest)
      return ""
    if (rest.charAt(0) === "\"") {
      var end = rest.indexOf("\"", 1)
      if (end > 1)
        return rest.substring(1, end)
      return rest.substring(1)
    }
    var sp = rest.indexOf(" ")
    return sp < 0 ? rest : rest.substring(0, sp)
  }

  function parseDesktopApp(path, source) {
    var src = root.readTextFile(path)
    if (!src)
      return null
    var exec = root.desktopField(src, "Exec")
    if (!exec)
      return null
    if (exec.indexOf("omarchy-launch-webapp") < 0 && exec.indexOf("omarchy-webapp-handler") < 0)
      return null

    var name = root.desktopField(src, "Name")
    if (!name) {
      var base = String(path || "")
      var slash = base.lastIndexOf("/")
      var file = slash >= 0 ? base.substring(slash + 1) : base
      var dot = file.lastIndexOf(".")
      name = dot > 0 ? file.substring(0, dot) : file
      if (!name)
        name = "unknown"
    }

    var icon = root.desktopField(src, "Icon")
    var url = root.parseUrlFromExec(exec)
    var app = {
      name: name,
      icon: icon,
      path: path,
      source: source
    }
    if (url)
      app.url = url
    return app
  }

  function isDesktopName(name) {
    var n = String(name || "").toLowerCase()
    return n.length > 8 && n.substring(n.length - 8) === ".desktop"
  }

  // --- Local list (mirrors system/web_apps.rs) ---

  function listInstalled() {
    root.installedSerial += 1
    root.scanSerial = root.installedSerial
    root.scanAcc = []
    root.scanQueue = [
      { path: root.userAppsDir, source: "user", recursive: true },
      { path: root.firstPartyAppsDir, source: "first_party", recursive: false }
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
    root.scanRecursive = !!job.recursive
    root.scanListingPath = String(job.path || "")
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

    var count = dirModel.count
    for (var i = 0; i < count; i++) {
      var name = String(dirModel.get(i, "fileName") || "")
      var path = String(dirModel.get(i, "filePath") || "")
      if (!name || !path)
        continue
      if (name === "." || name === "..")
        continue

      if (dirModel.isFolder(i)) {
        if (root.scanRecursive) {
          root.scanQueue.push({
            path: path,
            source: root.scanSource,
            recursive: true
          })
        }
        continue
      }

      if (!root.isDesktopName(name))
        continue

      var app = root.parseDesktopApp(path, root.scanSource)
      if (app)
        root.scanAcc.push(app)
    }

    root.scanMode = ""
    root.drainScanQueue()
  }

  function finishScan() {
    if (root.scanSerial !== root.installedSerial)
      return
    root.cachedInstalled = root.scanAcc.slice()
    root.localListed(root.cachedInstalled)
  }

  function filterLocal(query) {
    var q = String(query || "").trim().toLowerCase()
    var list = root.cachedInstalled || []
    if (!q)
      return list.slice()
    var out = []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var hay = (String(item.name || "") + " " + String(item.url || "")).toLowerCase()
      if (hay.indexOf(q) >= 0)
        out.push(item)
    }
    return out
  }

  function findByName(appName) {
    var n = String(appName || "")
    var list = root.cachedInstalled || []
    var hits = []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name || "") === n)
        hits.push(list[i])
    }
    return hits
  }

  // Same sanitizing as omarchy-webapp-remove / Rust remove/web_apps.rs
  function sanitizeIconName(name) {
    var out = ""
    var prevDash = false
    var s = String(name || "")
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i)
      var lower = c.toLowerCase()
      if ((lower >= "a" && lower <= "z") || (c >= "0" && c <= "9")) {
        out += lower
        prevDash = false
      } else if (!prevDash) {
        out += "-"
        prevDash = true
      }
    }
    while (out.length > 0 && out.charAt(0) === "-")
      out = out.substring(1)
    while (out.length > 0 && out.charAt(out.length - 1) === "-")
      out = out.substring(0, out.length - 1)
    return out
  }

  function iconPathsForApp(app) {
    var paths = []
    var name = String(app.name || "")
    var icon = String(app.icon || "")
    var sanitized = root.sanitizeIconName(name)
    if (sanitized)
      paths.push(root.iconDir + "/" + sanitized + ".png")
    if (name)
      paths.push(root.iconDir + "/" + name + ".png")
    if (name)
      paths.push(root.oldIconDir + "/" + name + ".png")
    if (icon && icon !== sanitized && icon !== name)
      paths.push(root.iconDir + "/" + icon + ".png")
    return paths
  }

  // Launch via the .desktop Exec line (omarchy-launch-webapp / handler).
  function launch(desktopPath) {
    var path = String(desktopPath || "").trim()
    if (!path)
      return false
    // Prefer absolute path so user + first-party apps both resolve.
    Quickshell.execDetached(["uwsm-app", "--", "gio", "launch", path])
    return true
  }

  // --- Remove (mirrors remove/web_apps.rs; skips bindings related cleanup) ---

  function remove(appName) {
    var name = String(appName || "").trim()
    if (!name)
      return -1

    root.removeSerial += 1
    var serial = root.removeSerial
    var apps = root.findByName(name)

    if (!apps || apps.length === 0) {
      root.removeFinished(1, serial, {
        ok: false,
        error: "No web apps to remove.",
        removed: [],
        skipped: [name]
      })
      return serial
    }

    var userPaths = []
    var firstParty = []
    var iconPaths = []
    for (var i = 0; i < apps.length; i++) {
      var app = apps[i]
      if (String(app.source || "") === "first_party") {
        firstParty.push(String(app.path || ""))
      } else {
        userPaths.push(String(app.path || ""))
        var icons = root.iconPathsForApp(app)
        for (var j = 0; j < icons.length; j++)
          iconPaths.push(icons[j])
      }
    }

    root.removePipeSerial = serial
    root.removePipeApps = apps
    root.removePipeUserPaths = userPaths
    root.removePipeFirstParty = firstParty
    root.removePipeIconPaths = iconPaths
    root.removePipePayload = {
      ok: true,
      removed: [name],
      skipped: []
    }

    if (userPaths.length > 0 || iconPaths.length > 0) {
      root.removePipeStep = "rm_user"
      var argv = ["rm", "-f"]
      for (var u = 0; u < userPaths.length; u++)
        argv.push(userPaths[u])
      for (var ic = 0; ic < iconPaths.length; ic++)
        argv.push(iconPaths[ic])
      root.startProc(removeProc, argv)
      return serial
    }

    if (firstParty.length > 0) {
      root.removePipeStep = "pkexec"
      var pk = ["pkexec", "rm", "-f"]
      for (var f = 0; f < firstParty.length; f++)
        pk.push(firstParty[f])
      root.startProc(removeProc, pk)
      return serial
    }

    root.removePipeSerial = -1
    root.removeFinished(1, serial, {
      ok: false,
      error: "No web apps to remove.",
      removed: [],
      skipped: [name]
    })
    return serial
  }

  function onRemoveProcExited(exitCode) {
    var serial = root.removePipeSerial
    if (serial < 0)
      return

    var step = root.removePipeStep
    if (step === "rm_user") {
      if (exitCode !== 0) {
        root.finishRemove(exitCode)
        return
      }
      if (root.removePipeFirstParty && root.removePipeFirstParty.length > 0) {
        root.removePipeStep = "pkexec"
        var pk = ["pkexec", "rm", "-f"]
        for (var f = 0; f < root.removePipeFirstParty.length; f++)
          pk.push(root.removePipeFirstParty[f])
        root.startProc(removeProc, pk)
        return
      }
      root.removePipeStep = "update_db"
      root.startProc(removeProc, ["update-desktop-database", root.userAppsDir])
      return
    }

    if (step === "pkexec") {
      if (exitCode !== 0) {
        root.finishRemove(exitCode)
        return
      }
      if (root.removePipeUserPaths && root.removePipeUserPaths.length > 0) {
        root.removePipeStep = "update_db"
        root.startProc(removeProc, ["update-desktop-database", root.userAppsDir])
        return
      }
      root.finishRemove(0)
      return
    }

    if (step === "update_db") {
      // Non-fatal if update-desktop-database fails
      root.finishRemove(0)
      return
    }

    root.finishRemove(exitCode)
  }

  function finishRemove(exitCode) {
    var serial = root.removePipeSerial
    var payload = root.removePipePayload || ({})
    payload.ok = exitCode === 0
    if (exitCode === 0)
      root.cachedInstalled = []
    root.removePipeSerial = -1
    root.removePipeStep = ""
    root.removePipeApps = []
    root.removePipeUserPaths = []
    root.removePipeFirstParty = []
    root.removePipeIconPaths = []
    root.removeFinished(exitCode, serial, payload)
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

  Process {
    id: removeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.onRemoveProcExited(exitCode)
    }
  }
}
