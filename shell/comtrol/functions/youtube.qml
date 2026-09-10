pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// YouTube search via scripts/node/search/youtube.mjs (Puppeteer).
Item {
  id: root

  property int webSerial: 0
  property string webQuery: ""
  property var cachedResults: []
  property string cachedQuery: ""

  signal webListed(var results)
  signal webFailed(string message)

  function pluginRoot() {
    var url = String(Qt.resolvedUrl("..") || "")
    if (url.indexOf("file://") === 0)
      url = url.substring(7)
    try {
      url = decodeURIComponent(url)
    } catch (e) {
    }
    while (url.length > 1 && url.charAt(url.length - 1) === "/")
      url = url.substring(0, url.length - 1)
    return url
  }

  function scriptPath() {
    return root.pluginRoot() + "/scripts/node/search/youtube.mjs"
  }

  function scriptDir() {
    return root.pluginRoot() + "/scripts/node/search"
  }

  function cancel() {
    root.webSerial += 1
    if (searchProc.running)
      searchProc.running = false
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

  function iconForType(type) {
    var t = String(type || "")
    if (t === "channel")
      return "󰡉"
    if (t === "short")
      return "󰎁"
    if (t === "live")
      return "󰐻"
    return "󰗃"
  }

  // Prefer JPEG thumbnails — YouTube often serves AVIF/WebP on hq720 URLs.
  function safeThumbnail(item) {
    var id = String((item && item.id) || "").trim()
    var type = String((item && item.type) || "")
    if (id && type !== "channel")
      return "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg"
    var thumb = String((item && item.thumbnail) || "").trim()
    var m = thumb.match(/\/vi\/([^/]+)\//)
    if (m && m[1])
      return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
    return thumb
  }

  function normalizeResults(results) {
    var list = results || []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      out.push({
        type: item.type,
        id: item.id,
        title: item.title,
        channel: item.channel,
        detail: item.detail,
        url: item.url,
        thumbnail: root.safeThumbnail(item)
      })
    }
    return out
  }

  function searchWeb(query) {
    root.webSerial += 1
    root.webQuery = String(query || "")
    searchProc.serial = root.webSerial

    var q = root.webQuery.trim()
    if (!q) {
      root.cachedResults = []
      root.cachedQuery = ""
      root.webListed([])
      return root.webSerial
    }

    if (root.cachedQuery === q && root.cachedResults && root.cachedResults.length > 0) {
      root.webListed(root.normalizeResults(root.cachedResults))
      return root.webSerial
    }

    // Use login shell so mise/nvm node + local node_modules resolve.
    var cmd = "cd " + root.shellQuote(root.scriptDir())
      + " && command -v node >/dev/null"
      + " && node " + root.shellQuote(root.scriptPath())
      + " " + root.shellQuote(q)
    root.startProc(searchProc, ["bash", "-lc", cmd])
    return root.webSerial
  }

  function parseResults(text) {
    var raw = String(text || "").trim()
    if (!raw)
      return []
    // Script may print warnings before JSON — take last JSON object line.
    var lines = raw.split("\n")
    var jsonText = ""
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = String(lines[i] || "").trim()
      if (line.charAt(0) === "{") {
        jsonText = line
        break
      }
    }
    if (!jsonText)
      jsonText = raw
    try {
      var data = JSON.parse(jsonText)
      return data && data.results ? data.results : []
    } catch (e) {
      return null
    }
  }

  function onSearchFinished(exitCode, stdout, stderr, serial) {
    if (serial !== root.webSerial)
      return
    if (exitCode !== 0) {
      var err = String(stderr || "").trim() || String(stdout || "").trim() || ("YouTube search failed (" + exitCode + ")")
      // Prefer last line of stderr
      var errLines = err.split("\n")
      root.webFailed(errLines[errLines.length - 1] || err)
      return
    }
    var results = root.parseResults(stdout)
    if (results === null) {
      root.webFailed("Invalid YouTube search response")
      return
    }
    results = root.normalizeResults(results)
    root.cachedResults = results
    root.cachedQuery = root.webQuery.trim()
    root.webListed(results)
  }

  function open(url) {
    var u = String(url || "").trim()
    if (!u)
      return false
    Quickshell.execDetached(["xdg-open", u])
    return true
  }

  Process {
    id: searchProc
    property int serial: 0
    property string _stdout: ""
    property string _stderr: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        searchProc._stdout = String(text || "")
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        searchProc._stderr = String(text || "")
      }
    }
    onExited: function(exitCode) {
      var out = searchProc._stdout
      var err = searchProc._stderr
      searchProc._stdout = ""
      searchProc._stderr = ""
      root.onSearchFinished(exitCode, out, err, searchProc.serial)
    }
  }
}
