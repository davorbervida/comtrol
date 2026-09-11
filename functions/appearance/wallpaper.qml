pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Live wallpaper without writing the persisted symlink.
// preview() shows via shell IPC; persist() commits with omarchy-theme-bg-set;
// restore() re-reads the symlink (uncommitted previews never touch it).
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string currentLink: root.home + "/.local/state/omarchy/current/background"

  property bool session: false
  property bool dirty: false
  property string livePath: ""
  property string persistedPath: ""
  property string pendingPath: ""

  function normalized(path) {
    var p = String(path || "").trim()
    if (p.indexOf("file://") === 0)
      p = p.substring(7)
    try {
      return decodeURIComponent(p)
    } catch (e) {
      return p
    }
  }

  function readPersisted() {
    if (readProc.running)
      readProc.running = false
    readProc.running = true
  }

  function refreshLive() {
    Quickshell.execDetached(["omarchy-shell", "-q", "background", "refresh"])
    root.livePath = ""
    root.readPersisted()
  }

  function begin() {
    if (root.session)
      return
    root.session = true
    if (!root.livePath)
      root.readPersisted()
  }

  function preview(path) {
    var p = root.normalized(path)
    if (!p)
      return
    if (!root.session)
      root.begin()
    if (p === root.pendingPath)
      return
    root.pendingPath = p
    previewTimer.restart()
  }

  function flushPreview() {
    var p = root.pendingPath
    if (!p || p === root.livePath)
      return
    if (previewProc.running || persistProc.running)
      return
    previewProc.command = ["omarchy-shell", "-q", "background", "setInstant", p]
    previewProc.running = true
  }

  function persist(path) {
    var p = root.normalized(path)
    if (!p)
      return
    previewTimer.stop()
    if (!root.session)
      root.begin()
    root.pendingPath = p
    root.livePath = p
    root.persistedPath = p
    root.dirty = false
    if (previewProc.running)
      previewProc.running = false
    if (persistProc.running)
      persistProc.running = false
    // Preview already showed this path via setInstant, so a plain
    // `background set` is a no-op. Snap back to the symlink first, then
    // omarchy-theme-bg-set can run the reveal animation.
    persistProc.command = [
      "bash", "-c",
      "orig=$(readlink -f \"$1\" 2>/dev/null || true); "
        + "if [[ -n $orig && $orig != \"$2\" ]]; then "
        + "omarchy-shell -q background setInstant \"$orig\"; "
        + "fi; "
        + "omarchy-theme-bg-set \"$2\"",
      "wallpaper-persist",
      root.currentLink,
      p
    ]
    persistProc.running = true
  }

  function restore() {
    previewTimer.stop()
    var needsRefresh = root.dirty || previewProc.running
    root.session = false
    root.pendingPath = ""
    root.dirty = false
    if (previewProc.running)
      return
    if (!needsRefresh)
      return
    root.refreshLive()
  }

  Component.onCompleted: root.readPersisted()

  Timer {
    id: previewTimer
    interval: 40
    repeat: false
    onTriggered: root.flushPreview()
  }

  Process {
    id: previewProc
    onStarted: {
      if (root.pendingPath)
        root.livePath = root.pendingPath
      if (root.session)
        root.dirty = true
    }
    onExited: {
      if (root.session) {
        if (root.pendingPath && root.pendingPath !== root.livePath)
          root.flushPreview()
        return
      }
      if (root.dirty || String(root.livePath || "").length > 0)
        root.refreshLive()
    }
  }

  Process {
    id: persistProc
  }

  Process {
    id: readProc
    command: ["readlink", "-f", root.currentLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (!p)
          return
        root.persistedPath = p
        if (!root.session || !root.dirty)
          root.livePath = p
      }
    }
  }
}
