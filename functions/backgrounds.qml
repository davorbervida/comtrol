pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Background list / remove — pure QML (no run.sh / cOMtrol / helper scripts).
// FS scan: FolderListModel. Process only for rm / pkexec (mirrors remove/backgrounds.rs).
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string currentBackgroundsDir: root.home + "/.local/state/omarchy/current/theme/backgrounds"
  readonly property string userThemesDir: root.home + "/.config/omarchy/themes"
  readonly property string firstPartyThemesDir: root.omarchyPath + "/themes"
  readonly property string wallpapersDir: root.home + "/Pictures/Wallpapers"

  property int listSerial: 0
  property int removeSerial: 0
  property var cachedListed: []
  property string cachedMode: ""

  // Directory scan
  property int scanSerial: 0
  property var scanAcc: []
  property var scanQueue: []
  property string scanMode: "" // "" | "listing"
  property string scanRole: "" // themes_root | images
  property string scanListingPath: ""
  property string listMode: "" // current | themes | wallpapers | all

  // Remove pipeline: try rm, optionally escalate to pkexec
  property int removePipeSerial: -1
  property string removePipePath: ""
  property string removePipeStep: "" // rm | pkexec
  property var removePipePayload: ({})

  signal listed(var backgrounds, string mode)
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
    root.listSerial += 1
    root.scanSerial += 1
    root.removePipeSerial = -1
    root.scanMode = ""
    root.scanQueue = []
    if (removeProc.running)
      removeProc.running = false
  }

  function isImageName(name) {
    var n = String(name || "").toLowerCase()
    var dot = n.lastIndexOf(".")
    if (dot < 0)
      return false
    var ext = n.substring(dot + 1)
    return ext === "jpg" || ext === "jpeg" || ext === "png"
      || ext === "gif" || ext === "bmp" || ext === "webp"
  }

  function isUnderUsrShare(path) {
    var p = String(path || "")
    return p === "/usr/share" || p.indexOf("/usr/share/") === 0
  }

  function isAbsolutePath(path) {
    return String(path || "").charAt(0) === "/"
  }

  // --- List (mirrors system/backgrounds.rs) ---

  function list(mode) {
    var m = String(mode || "current").trim().toLowerCase()
    if (m !== "current" && m !== "themes" && m !== "wallpapers" && m !== "all")
      m = "current"

    root.listSerial += 1
    root.scanSerial = root.listSerial
    root.listMode = m
    root.scanAcc = []
    root.scanQueue = root.buildScanQueue(m)
    root.scanMode = ""

    if (root.cachedMode === m && root.cachedListed && root.cachedListed.length > 0)
      root.listed(root.cachedListed.slice(), m)

    root.drainScanQueue()
    return root.listSerial
  }

  function buildScanQueue(mode) {
    if (mode === "current")
      return [{ path: root.currentBackgroundsDir, role: "images" }]
    if (mode === "wallpapers")
      return [{ path: root.wallpapersDir, role: "images" }]
    if (mode === "themes") {
      return [
        { path: root.userThemesDir, role: "themes_root" },
        { path: root.firstPartyThemesDir, role: "themes_root" }
      ]
    }
    // all = theme backgrounds then wallpapers
    return [
      { path: root.userThemesDir, role: "themes_root" },
      { path: root.firstPartyThemesDir, role: "themes_root" },
      { path: root.wallpapersDir, role: "images" }
    ]
  }

  function drainScanQueue() {
    if (root.scanSerial !== root.listSerial)
      return
    if (!root.scanQueue || root.scanQueue.length === 0) {
      root.finishScan()
      return
    }
    var job = root.scanQueue[0]
    root.scanQueue = root.scanQueue.slice(1)
    root.scanRole = String(job.role || "")
    root.scanListingPath = String(job.path || "")
    root.scanMode = "listing"
    // Clear first so FolderListModel re-reads the directory (same-path
    // assignment keeps a stale listing after deletes).
    dirModel.folder = ""
    Qt.callLater(root.applyDirModelFolder)
  }

  function applyDirModelFolder() {
    if (root.scanSerial !== root.listSerial)
      return
    if (root.scanMode !== "listing")
      return
    dirModel.folder = root.toFileUrl(root.scanListingPath)
  }

  function onDirListingReady() {
    if (root.scanSerial !== root.listSerial)
      return
    if (root.scanMode !== "listing")
      return
    if (dirModel.status !== FolderListModel.Ready)
      return
    var listedUrl = String(dirModel.folder || "")
    var want = root.toFileUrl(root.scanListingPath)
    if (listedUrl !== want && root.fromFileUrl(listedUrl) !== root.scanListingPath)
      return

    var role = root.scanRole
    var count = dirModel.count

    if (role === "themes_root") {
      for (var i = 0; i < count; i++) {
        if (!dirModel.isFolder(i))
          continue
        var name = String(dirModel.get(i, "fileName") || "")
        var path = String(dirModel.get(i, "filePath") || "")
        if (!name || !path || name === "." || name === "..")
          continue
        root.scanQueue.push({ path: path + "/backgrounds", role: "images" })
      }
      root.scanMode = ""
      root.drainScanQueue()
      return
    }

    if (role === "images") {
      for (var j = 0; j < count; j++) {
        if (dirModel.isFolder(j))
          continue
        var fname = String(dirModel.get(j, "fileName") || "")
        var fpath = String(dirModel.get(j, "filePath") || "")
        if (!fpath || !root.isImageName(fname))
          continue
        root.scanAcc.push({ path: fpath })
      }
      root.scanMode = ""
      root.drainScanQueue()
      return
    }

    root.scanMode = ""
    root.drainScanQueue()
  }

  function finishScan() {
    if (root.scanSerial !== root.listSerial)
      return
    var items = root.scanAcc.slice()
    items.sort(function(a, b) {
      return String(a.path || "").localeCompare(String(b.path || ""))
    })
    root.cachedListed = items
    root.cachedMode = root.listMode
    root.listed(items, root.listMode)
  }

  // --- Remove (mirrors remove/backgrounds.rs) ---

  function remove(path) {
    var p = String(path || "").trim()
    if (!p || !root.isAbsolutePath(p))
      return -1

    root.removeSerial += 1
    var serial = root.removeSerial
    root.removePipeSerial = serial
    root.removePipePath = p
    root.removePipePayload = ({
      ok: false,
      removed: [],
      skipped: [],
      path: p
    })

    if (root.isUnderUsrShare(p)) {
      root.removePipeStep = "pkexec"
      root.startRemoveProc(["pkexec", "rm", "-f", "--", p])
    } else {
      root.removePipeStep = "rm"
      root.startRemoveProc(["rm", "-f", "--", p])
    }
    return serial
  }

  function startRemoveProc(argv) {
    if (removeProc.running)
      removeProc.running = false
    if (typeof removeProc.exec === "function") {
      removeProc.exec(argv)
      return
    }
    removeProc.command = argv
    removeProc.running = false
    removeProc.running = true
  }

  function onRemoveProcExited(exitCode) {
    var serial = root.removePipeSerial
    if (serial < 0)
      return

    if (root.removePipeStep === "rm" && exitCode !== 0) {
      // Permission denied or similar — escalate like Rust.
      root.removePipeStep = "pkexec"
      Qt.callLater(function() {
        if (root.removePipeSerial !== serial)
          return
        root.startRemoveProc(["pkexec", "rm", "-f", "--", root.removePipePath])
      })
      return
    }

    var payload = root.removePipePayload
    if (exitCode === 0) {
      payload.ok = true
      payload.removed = [root.removePipePath]
      root.cachedListed = []
      root.cachedMode = ""
    } else {
      payload.ok = false
      payload.error = "Failed to remove " + root.removePipePath
    }
    root.removePipeSerial = -1
    root.removePipeStep = ""
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

  Process {
    id: removeProc
    onExited: function(exitCode) {
      root.onRemoveProcExited(exitCode)
    }
  }
}
