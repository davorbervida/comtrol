pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Shared Puppeteer browser daemon for web search providers.
Item {
  id: root

  property bool nodeChecked: false
  property bool nodeAvailable: false
  property bool modulesReady: false
  property bool installing: false
  property string lastError: ""
  property bool warmWanted: false
  property bool ready: false
  property int nextReqId: 0
  property var pending: []

  signal reply(string provider, int reqId, bool ok, var results, string error)
  signal daemonFailed(string message)
  signal depsFailed(string message)

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

  function scriptDir() {
    return root.pluginRoot() + "/scripts/node/search"
  }

  function scriptPath() {
    return root.scriptDir() + "/browser-server.mjs"
  }

  function puppeteerMarker() {
    return root.scriptDir() + "/node_modules/puppeteer/package.json"
  }

  function shellQuote(s) {
    return "'" + String(s || "").replace(/'/g, "'\\''") + "'"
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

  function writeCmd(obj) {
    if (!daemon.running)
      return false
    try {
      daemon.write(JSON.stringify(obj) + "\n")
      return true
    } catch (e) {
      return false
    }
  }

  function flushPending() {
    if (!root.ready)
      return
    var queue = root.pending || []
    root.pending = []
    for (var i = 0; i < queue.length; i++) {
      var item = queue[i]
      if (!item)
        continue
      root.writeCmd({
        cmd: "search",
        id: item.id,
        provider: item.provider,
        query: item.query
      })
    }
  }

  function checkNode() {
    root.startProc(nodeCheckProc, ["bash", "-lc",
      "command -v node >/dev/null 2>&1 && echo yes || echo no"
    ])
  }

  function failPending(message) {
    var msg = String(message || "web search unavailable")
    var queue = root.pending || []
    root.pending = []
    for (var i = 0; i < queue.length; i++) {
      var item = queue[i]
      if (!item)
        continue
      root.reply(String(item.provider || ""), Number(item.id) || 0, false, [], msg)
    }
  }

  function ensureModulesThenDaemon() {
    if (!root.nodeAvailable) {
      root.lastError = "Node.js is not installed"
      root.depsFailed(root.lastError)
      root.failPending(root.lastError)
      return
    }
    if (root.modulesReady) {
      root.lastError = ""
      root.ensureDaemon()
      return
    }
    if (root.installing || depsProc.running)
      return
    root.installing = true
    root.lastError = ""
    var dir = root.shellQuote(root.scriptDir())
    var marker = root.shellQuote(root.puppeteerMarker())
    var cmd = "cd " + dir
      + " && if [ -f " + marker + " ]; then echo READY; exit 0; fi"
      + " && if ! command -v npm >/dev/null 2>&1; then echo NPM_MISSING; exit 3; fi"
      + " && echo INSTALLING"
      + " && npm install"
      + " && if [ -f " + marker + " ]; then echo READY; exit 0; fi"
      + " && echo INSTALL_FAILED; exit 1"
    root.startProc(depsProc, ["bash", "-lc", cmd])
  }

  function ensureDaemon() {
    if (!root.nodeAvailable || !root.modulesReady)
      return
    if (daemon.running)
      return
    root.ready = false
    var cmd = "cd " + root.shellQuote(root.scriptDir())
      + " && command -v node >/dev/null"
      + " && exec node " + root.shellQuote(root.scriptPath())
    root.startProc(daemon, ["bash", "-lc", cmd])
  }

  function warm() {
    root.warmWanted = true
    root.lastError = ""
    if (!root.nodeChecked) {
      root.checkNode()
      return
    }
    if (!root.nodeAvailable)
      return
    root.ensureModulesThenDaemon()
  }

  function cool() {
    root.warmWanted = false
    root.pending = []
    root.ready = false
    if (depsProc.running)
      depsProc.running = false
    root.installing = false
    if (!daemon.running)
      return
    root.writeCmd({ cmd: "shutdown" })
    coolKillTimer.restart()
  }

  // Returns request id; listen for reply(provider, reqId, ...).
  function search(provider, query) {
    root.warm()
    root.nextReqId += 1
    var id = root.nextReqId
    var p = String(provider || "")
    var q = String(query || "")
    if (!root.ready || !daemon.running) {
      var list = (root.pending || []).slice()
      list.push({ id: id, provider: p, query: q })
      root.pending = list
      return id
    }
    root.writeCmd({ cmd: "search", id: id, provider: p, query: q })
    return id
  }

  function cancelAll() {
    root.pending = []
    root.nextReqId += 1
  }

  function onLine(line) {
    var raw = String(line || "").trim()
    if (!raw)
      return
    var data = null
    try {
      data = JSON.parse(raw)
    } catch (e) {
      return
    }
    if (!data)
      return
    if (data.event === "ready") {
      root.ready = true
      root.flushPending()
      return
    }
    if (data.event === "error") {
      root.daemonFailed(String(data.error || "browser daemon failed"))
      return
    }
    if (data.id === undefined || data.id === null)
      return
    var ok = data.ok === true
    root.reply(
      String(data.provider || ""),
      Number(data.id) || 0,
      ok,
      ok ? (data.results || []) : [],
      ok ? "" : String(data.error || "search failed")
    )
  }

  function onDepsFinished(exitCode, stdout) {
    root.installing = false
    var out = String(stdout || "")
    if (out.indexOf("READY") >= 0) {
      root.modulesReady = true
      root.lastError = ""
      if (root.warmWanted)
        root.ensureDaemon()
      return
    }
    root.modulesReady = false
    root.warmWanted = false
    var msg = "Failed to install web search packages"
    if (out.indexOf("NPM_MISSING") >= 0)
      msg = "npm is not installed"
    else if (out.indexOf("INSTALL_FAILED") >= 0)
      msg = "npm install failed"
    else if (exitCode !== 0)
      msg = "npm install failed (" + exitCode + ")"
    root.lastError = msg
    root.depsFailed(msg)
    root.failPending(msg)
  }

  Component.onCompleted: root.checkNode()

  Timer {
    id: coolKillTimer
    interval: 2500
    repeat: false
    onTriggered: {
      if (root.warmWanted)
        return
      if (daemon.running)
        daemon.running = false
    }
  }

  Process {
    id: nodeCheckProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        nodeCheckProc._out = String(text || "")
      }
    }
    property string _out: ""
    onExited: function(/*exitCode*/) {
      var yes = String(nodeCheckProc._out || "").indexOf("yes") >= 0
      nodeCheckProc._out = ""
      root.nodeAvailable = yes
      root.nodeChecked = true
      if (root.warmWanted && yes)
        root.ensureModulesThenDaemon()
    }
  }

  Process {
    id: depsProc
    property string _stdout: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        depsProc._stdout = String(text || "")
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var out = depsProc._stdout
      depsProc._stdout = ""
      root.onDepsFinished(exitCode, out)
    }
  }

  Process {
    id: daemon
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        root.onLine(line)
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        void line
      }
    }
    onStarted: {
      root.ready = false
    }
    onExited: function(/*exitCode*/) {
      root.ready = false
      if (root.warmWanted && root.modulesReady)
        Qt.callLater(function() {
          if (root.warmWanted && root.modulesReady && !daemon.running)
            root.ensureDaemon()
        })
    }
  }
}
