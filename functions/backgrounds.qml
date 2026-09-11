pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// Background list / remove — pure QML (no run.sh / cOMtrol / helper scripts).
// FS scan: FolderListModel. Process only for rm / pkexec (mirrors remove/backgrounds.rs).
// Thumbnails reuse ~/.cache/omarchy/image-selector (same as omarchy-menu-images).
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
  property int thumbSerial: 0
  property var thumbPending: []
  property var thumbMap: ({})

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
    if (thumbProc.running)
      thumbProc.running = false
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

    root.warmThumbRows()
    if (root.cachedMode === m && root.cachedListed && root.cachedListed.length > 0)
      root.listed(root.attachKnownThumbs(root.cachedListed), m)

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
    // Show the picker as soon as the file list exists. Thumbnails attach
    // from the in-memory Omarchy cache; missing ones resolve in the background.
    root.emitListed(root.attachKnownThumbs(items))
    root.resolveThumbs(items)
  }

  function attachKnownThumbs(items) {
    var map = root.thumbMap || {}
    var next = []
    var list = items || []
    for (var i = 0; i < list.length; i++) {
      var path = String((list[i] && list[i].path) || "")
      if (!path)
        continue
      next.push({
        path: path,
        thumbnail: map[path] || ""
      })
    }
    return next
  }

  function mergeThumbMap(text) {
    var map = {}
    var prev = root.thumbMap || {}
    for (var key in prev) {
      if (prev.hasOwnProperty(key))
        map[key] = prev[key]
    }
    var changed = false
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = String(lines[i] || "").trim()
      if (!line)
        continue
      var tab = line.indexOf("\t")
      if (tab < 0)
        continue
      var image = line.substring(0, tab)
      var thumb = line.substring(tab + 1)
      if (!image || !thumb || thumb === image)
        continue
      if (map[image] !== thumb) {
        map[image] = thumb
        changed = true
      }
    }
    if (changed)
      root.thumbMap = map
    return changed
  }

  function emitListed(items) {
    root.cachedListed = items
    root.cachedMode = root.listMode
    root.listed(items, root.listMode)
  }

  // Same cache as Ctrl+Super+Space (omarchy-menu-images): JPEG 1536x864.
  readonly property string thumbScript: "cache=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector; "
    + "index=$cache/index.tsv; mkdir -p \"$cache\"; "
    + "generate_thumbnail() { "
    + "local image=\"$1\" thumbnail=\"$2\" lock=\"$2.lock\" tmp=\"$2.$$.jpg\" fd; "
    + "exec 9>\"$lock\" || return; flock -w 30 9 || return; "
    + "rm -f \"$thumbnail\".*.jpg; [[ -f $thumbnail ]] && return; "
    + "if command -v vipsthumbnail >/dev/null 2>&1 && VIPS_CONCURRENCY=1 vipsthumbnail \"$image\" --size 1536x864 --smartcrop=centre --path \"$tmp[Q=82,strip]\"; then "
    + "mv -f \"$tmp\" \"$thumbnail\"; else rm -f \"$tmp\"; fi; }; "
    + "missing_img=(); missing_thumb=(); "
    + "for image in \"$@\"; do "
    + "[[ -f $image ]] || continue; "
    + "signature=$(stat -Lc '%s:%Y' \"$image\" 2>/dev/null) || continue; "
    + "hash=$(awk -F '\\t' -v path=\"$image\" -v sig=\"$signature\" '$1 == path && $2 == sig { print $3; exit }' \"$index\" 2>/dev/null); "
    + "if [[ -z $hash ]]; then hash=$(printf '%s\\t%s' \"$image\" \"$signature\" | md5sum | cut -d ' ' -f 1); "
    + "printf '%s\\t%s\\t%s\\n' \"$image\" \"$signature\" \"$hash\" >>\"$index\"; fi; "
    + "thumb=$cache/$hash.jpg; "
    + "if [[ -f $thumb ]]; then printf '%s\\t%s\\n' \"$image\" \"$thumb\"; "
    + "else missing_img+=(\"$image\"); missing_thumb+=(\"$thumb\"); fi; "
    + "done; "
    + "if ((${#missing_img[@]})); then "
    + "export -f generate_thumbnail; "
    + "for i in \"${!missing_img[@]}\"; do printf '%s\\0%s\\0' \"${missing_img[$i]}\" \"${missing_thumb[$i]}\"; done | "
    + "xargs -0 -n 2 -P \"$(nproc)\" bash -c 'generate_thumbnail \"$1\" \"$2\"' _; "
    + "for i in \"${!missing_img[@]}\"; do "
    + "if [[ -f ${missing_thumb[$i]} ]]; then printf '%s\\t%s\\n' \"${missing_img[$i]}\" \"${missing_thumb[$i]}\"; "
    + "else printf '%s\\t%s\\n' \"${missing_img[$i]}\" \"${missing_img[$i]}\"; fi; "
    + "done; fi"

  function resolveThumbs(items) {
    var list = items || []
    root.thumbPending = list
    root.thumbSerial = root.listSerial
    if (!list.length)
      return
    var map = root.thumbMap || {}
    var paths = []
    var missing = false
    for (var i = 0; i < list.length; i++) {
      var p = String((list[i] && list[i].path) || "")
      if (!p)
        continue
      paths.push(p)
      if (!map[p])
        missing = true
    }
    if (!paths.length || !missing)
      return
    if (thumbProc.running)
      thumbProc.running = false
    thumbProc.command = ["bash", "-c", root.thumbScript, "bg-thumbs"].concat(paths)
    thumbProc.running = true
  }

  function warmThumbRows() {
    if (rowsProc.running)
      return
    rowsProc.running = true
  }

  function applyThumbRows(text) {
    root.mergeThumbMap(text)
    var next = root.attachKnownThumbs(root.thumbPending)
    for (var j = 0; j < next.length; j++) {
      if (!next[j].thumbnail)
        next[j].thumbnail = next[j].path
    }
    root.emitListed(next)
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

  Process {
    id: thumbProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.thumbSerial !== root.listSerial)
          return
        root.applyThumbRows(text)
      }
    }
  }

  Process {
    id: rowsProc
    command: ["bash", "-c", "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector\"/*.rows 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.mergeThumbMap(text))
          return
        if (root.cachedListed && root.cachedListed.length)
          root.emitListed(root.attachKnownThumbs(root.cachedListed))
      }
    }
  }

  Component.onCompleted: root.warmThumbRows()
}
