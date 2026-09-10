pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Window border only — general.border_size.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string looknfeelFile: root.home + "/.config/hypr/looknfeel.lua"
  readonly property int minSize: 0
  readonly property int maxSize: 10

  function toFileUrl(path) {
    var p = String(path || "")
    if (!p)
      return ""
    if (p.indexOf("file://") === 0)
      return p
    return "file://" + p
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

  function writeTextFile(path, text) {
    writeView.path = ""
    writeView.path = root.toFileUrl(path)
    try {
      writeView.setText(String(text || ""))
      return true
    } catch (e) {
      return false
    }
  }

  function clamp(value) {
    var n = Math.round(Number(value))
    if (!isFinite(n))
      return root.minSize
    return Math.max(root.minSize, Math.min(root.maxSize, n))
  }

  function evalLua(border) {
    return "hl.config({ general = { border_size = " + root.clamp(border) + " } })"
  }

  function upsertMarker(path, begin, end, block) {
    var text = root.readTextFile(path)
    var body = String(block || "")
    if (body.length && body.charAt(body.length - 1) !== "\n")
      body += "\n"
    var start = text.indexOf(begin)
    if (start >= 0) {
      var stop = text.indexOf(end, start)
      if (stop >= 0) {
        stop += end.length
        if (stop < text.length && text.charAt(stop) === "\n")
          stop += 1
        text = text.substring(0, start) + body + text.substring(stop)
      } else {
        text = text.replace(/\s+$/, "") + "\n\n" + body
      }
    } else {
      if (text.length && text.charAt(text.length - 1) !== "\n")
        text += "\n"
      text += (text.length ? "\n" : "") + body
    }
    root.writeTextFile(path, text)
  }

  function save(border) {
    var n = root.clamp(border)
    var block = "-- BEGIN COMTROL-BORDER\n"
      + "hl.config({\n"
      + "  general = {\n"
      + "    border_size = " + n + ",\n"
      + "  },\n"
      + "})\n"
      + "-- END COMTROL-BORDER\n"
    root.upsertMarker(root.looknfeelFile, "-- BEGIN COMTROL-BORDER", "-- END COMTROL-BORDER", block)
    return n
  }

  FileView {
    id: fileView
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: writeView
    blockLoading: true
    printErrors: false
  }
}
