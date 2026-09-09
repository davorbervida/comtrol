import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
  id: root
  property var lines: []
  FileView {
    id: fv
    blockLoading: true
    printErrors: false
  }
  Process { id: writer }
  function log(s) { root.lines.push(String(s)) }
  function flush() {
    var cmd = "printf '%s\\n'"
    for (var i = 0; i < root.lines.length; i++)
      cmd += " " + JSON.stringify(root.lines[i])
    cmd += " > /home/davor/Work/Linux/cOMtrol/.tmp-xhr/cache-test.txt"
    writer.command = ["bash", "-c", cmd]
    writer.running = true
  }
  Component.onCompleted: {
    var path = "/home/davor/Work/Linux/cOMtrol/shell/comtrol/data/plugins.json"
    fv.path = "file://" + path
    var text = ""
    try { text = String(fv.text() || "") } catch (e) { log("readerr=" + e) }
    log("textlen=" + text.length)
    var plugins = null
    try { plugins = JSON.parse(text) } catch (e) { log("parseerr=" + e) }
    log("count=" + (plugins && plugins.length !== undefined ? plugins.length : -1))
    if (plugins && plugins[0]) {
      log("first.id=" + plugins[0].id)
      log("has_install_command=" + !!(plugins[0].install_command))
      log("install_available=" + plugins[0].install_available)
      var keys = []
      for (var k in plugins[0]) keys.push(k)
      log("keys=" + keys.join(","))
    }
    // XHR small
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "https://api.omarchyplugins.com/v1/stats")
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      log("stats_status=" + xhr.status)
      log("stats_len=" + String(xhr.responseText || "").length)
      flush()
    }
    xhr.send()
  }
  Connections { target: writer; function onExited() { Qt.quit() } }
  Timer { interval: 15000; running: true; onTriggered: { log("timeout"); flush() } }
}
