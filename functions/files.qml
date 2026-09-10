pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Home-directory file search via find (Process) — fast tree walk with early exit.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property int maxResults: 1500
  readonly property int maxDepth: 10

  // Default: skip hidden (.*). Ctrl+H toggles via Menu → Main.
  property bool showHidden: false

  property int listSerial: 0
  property string listMode: "" // audio | video | images | files | documents | directories
  property var cachedListed: []
  property string cachedMode: ""
  property bool cachedShowHidden: false

  signal listed(var items, string mode)

  function cancel() {
    root.listSerial += 1
    if (findProc.running)
      findProc.running = false
  }

  function clearCache() {
    root.cachedListed = []
    root.cachedMode = ""
    root.cachedShowHidden = false
  }

  function resetHidden() {
    if (!root.showHidden)
      return
    root.showHidden = false
    root.clearCache()
  }

  function toggleHidden() {
    root.showHidden = !root.showHidden
    root.clearCache()
    return root.showHidden
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

  function shellQuote(s) {
    return "'" + String(s || "").replace(/'/g, "'\\''") + "'"
  }

  function pruneExpr() {
    // Visible mode: skip all hidden entries plus common build junk.
    // Hidden mode (Ctrl+H): no prune — full $HOME walk including .git/.cache/etc.
    if (root.showHidden)
      return ""
    return "\\( -name '.*' -o -name node_modules -o -name __pycache__"
      + " -o -name venv -o -name target -o -name dist -o -name build"
      + " -o -name lost+found \\) -prune"
  }

  function buildFindCmd(mode) {
    var home = root.shellQuote(root.home)
    var depth = "-mindepth 1 -maxdepth " + String(root.maxDepth)
    var prune = root.pruneExpr()
    var match = ""

    if (mode === "directories") {
      match = "-type d -print"
    } else if (mode === "files") {
      match = "-type f -print"
    } else {
      var names = root.nameFilterForMode(mode)
      match = "-type f " + names + " -print"
    }

    var expr = prune ? (prune + " -o " + match) : match
    // head closes the pipe early so find stops after maxResults hits.
    return "find " + home + " " + depth + " " + expr
      + " 2>/dev/null | head -n " + String(root.maxResults)
  }

  function inameOr(exts) {
    var parts = []
    for (var i = 0; i < exts.length; i++)
      parts.push("-iname " + root.shellQuote("*." + exts[i]))
    return "\\( " + parts.join(" -o ") + " \\)"
  }

  function nameFilterForMode(mode) {
    if (mode === "audio") {
      return root.inameOr([
        "mp3", "flac", "wav", "ogg", "m4a", "aac", "wma", "opus",
        "aiff", "ape", "oga", "mka"
      ])
    }
    if (mode === "video") {
      return root.inameOr([
        "mp4", "mkv", "webm", "avi", "mov", "wmv", "m4v", "mpeg",
        "mpg", "flv", "ts", "m2ts"
      ])
    }
    if (mode === "images") {
      return root.inameOr([
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "svg", "tiff",
        "tif", "heic", "heif", "avif", "ico", "jxl"
      ])
    }
    if (mode === "documents") {
      return root.inameOr([
        "pdf", "doc", "docx", "odt", "rtf", "txt", "md", "markdown",
        "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp", "epub",
        "pages", "numbers", "key", "tex", "org", "html", "htm"
      ])
    }
    return ""
  }

  function iconForMode(mode) {
    var m = String(mode || "")
    if (m === "audio")
      return "󰝚"
    if (m === "video")
      return "󰕧"
    if (m === "images")
      return "󰋩"
    if (m === "documents")
      return "󰧮"
    if (m === "directories")
      return "󰉋"
    return "󰈔"
  }

  function basename(path) {
    var p = String(path || "")
    var i = p.lastIndexOf("/")
    if (i < 0)
      return p
    return p.substring(i + 1)
  }

  function parseFindOutput(text) {
    var lines = String(text || "").split("\n")
    var items = []
    var seen = ({})
    for (var i = 0; i < lines.length; i++) {
      if (items.length >= root.maxResults)
        break
      var path = String(lines[i] || "").replace(/\r$/, "").trim()
      if (!path || seen[path])
        continue
      seen[path] = true
      items.push({
        path: path,
        name: root.basename(path),
        isDir: root.listMode === "directories"
      })
    }
    items.sort(function(a, b) {
      return String(a.name || a.path || "").localeCompare(String(b.name || b.path || ""), undefined, { sensitivity: "base" })
    })
    return items
  }

  function list(mode) {
    var m = String(mode || "files").trim().toLowerCase()
    if (m !== "audio" && m !== "video" && m !== "images"
        && m !== "files" && m !== "documents" && m !== "directories")
      m = "files"

    root.listSerial += 1
    root.listMode = m
    findProc.serial = root.listSerial

    if (!root.home) {
      root.cachedListed = []
      root.cachedMode = m
      root.cachedShowHidden = root.showHidden
      root.listed([], m)
      return root.listSerial
    }

    if (root.cachedMode === m
        && root.cachedShowHidden === root.showHidden
        && root.cachedListed && root.cachedListed.length > 0) {
      root.listed(root.cachedListed.slice(), m)
      return root.listSerial
    }

    root.startProc(findProc, ["bash", "-lc", root.buildFindCmd(m)])
    return root.listSerial
  }

  function onFindFinished(exitCode, text, serial) {
    if (serial !== root.listSerial)
      return
    // find may exit non-zero when head closes the pipe (SIGPIPE) — still OK.
    var items = root.parseFindOutput(text)
    root.cachedListed = items
    root.cachedMode = root.listMode
    root.cachedShowHidden = root.showHidden
    root.listed(items, root.listMode)
  }

  function open(path) {
    var p = String(path || "").trim()
    if (!p)
      return false
    Quickshell.execDetached(["xdg-open", p])
    return true
  }

  Process {
    id: findProc
    property int serial: 0
    property string _stdout: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        findProc._stdout = String(text || "")
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var text = findProc._stdout
      findProc._stdout = ""
      root.onFindFinished(exitCode, text, findProc.serial)
    }
  }
}
