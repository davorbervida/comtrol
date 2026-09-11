pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Font family + size per target: shell (bar/Quickshell), terminal, GTK.
// Size is 1:1. Does not write GTK text-scaling-factor.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string shellFile: root.home + "/.config/omarchy/shell.toml"
  readonly property string fontconfigFile: root.home + "/.config/fontconfig/fonts.conf"
  readonly property string footFile: root.home + "/.config/foot/foot.ini"
  readonly property string kittyFile: root.home + "/.config/kitty/kitty.conf"
  readonly property string alacrittyFile: root.home + "/.config/alacritty/alacritty.toml"
  readonly property string ghosttyFile: root.home + "/.config/ghostty/config"

  readonly property int minSize: 9
  readonly property int maxSize: 20
  readonly property int gtkDefaultSize: 11

  property var names: []
  property var monoNames: []
  property var allNames: []
  property bool loading: false
  property bool monoReady: false
  property bool allReady: false
  property string listKind: "mono"
  property int listSerial: 0

  property string shellFamily: ""
  property string terminalFamily: ""
  property string gtkFamily: ""
  property int shellSize: 12
  property int terminalSize: 12
  property int gtkSize: 11

  signal listed()
  signal changed()

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

  function patchFile(path, transform) {
    var text = root.readTextFile(path)
    if (!text)
      return false
    var next = transform(text)
    if (next === text)
      return true
    return root.writeTextFile(path, next)
  }

  function clamp(value) {
    var n = Math.round(Number(value))
    if (!isFinite(n))
      return root.minSize
    return Math.max(root.minSize, Math.min(root.maxSize, n))
  }

  function xmlEscape(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }

  function tomlEscape(value) {
    return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
  }

  function familyOf(target) {
    var t = String(target || "")
    if (t === "terminal")
      return root.terminalFamily
    if (t === "gtk")
      return root.gtkFamily
    return root.shellFamily
  }

  function sizeOf(target) {
    var t = String(target || "")
    if (t === "terminal")
      return root.terminalSize
    if (t === "gtk")
      return root.gtkSize
    return root.shellSize
  }

  function listKindFor(target) {
    return String(target || "") === "gtk" ? "all" : "mono"
  }

  function parseNameList(text) {
    var seen = ({})
    var names = []
    var rawLines = String(text || "").split("\n")
    for (var i = 0; i < rawLines.length; i++) {
      var name = String(rawLines[i] || "").trim()
      if (!name || seen[name])
        continue
      seen[name] = true
      names.push(name)
    }
    return names
  }

  function scan(kind) {
    var k = String(kind || "mono") === "all" ? "all" : "mono"
    if (k === "all" && root.allReady) {
      root.listKind = "all"
      root.names = root.allNames
      root.listed()
      return
    }
    if (k === "mono" && root.monoReady) {
      root.listKind = "mono"
      root.names = root.monoNames
      root.listed()
      return
    }
    if (listProc.running)
      listProc.running = false
    root.listKind = k
    root.listSerial += 1
    listProc.serial = root.listSerial
    listProc.command = k === "all"
      ? ["bash", "-c", "fc-list :family -f '%{family[0]}\\n' 2>/dev/null | grep -v -i -E 'emoji|signwriting|omarchy' | sort -u"]
      : ["bash", "-c", "omarchy-font-list 2>/dev/null"]
    listProc.running = true
  }

  function applyList(text) {
    var names = root.parseNameList(text)
    if (root.listKind === "all") {
      root.allNames = names
      root.allReady = true
    } else {
      root.monoNames = names
      root.monoReady = true
    }
    root.names = names
    root.loading = false
    root.listed()
  }

  function replaceLinePrefix(text, pattern, replacement) {
    var re = new RegExp(pattern)
    var lines = String(text || "").split("\n")
    var found = false
    for (var i = 0; i < lines.length; i++) {
      if (!re.test(lines[i]))
        continue
      lines[i] = replacement
      found = true
    }
    return { text: lines.join("\n"), found: found }
  }

  function appendLine(text, line) {
    var body = String(text || "")
    if (body.length && body.charAt(body.length - 1) !== "\n")
      body += "\n"
    return body + line + "\n"
  }

  function patchFootSize(text, size) {
    var n = String(size)
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("font=") !== 0)
        continue
      if (/:size=[0-9.]+/.test(lines[i]))
        lines[i] = lines[i].replace(/:size=[0-9.]+/g, ":size=" + n)
      else
        lines[i] = lines[i] + ":size=" + n
    }
    return lines.join("\n")
  }

  function patchFootFamily(text, name) {
    var lines = String(text || "").split("\n")
    var found = false
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("font=") !== 0)
        continue
      var rest = lines[i].substring(5)
      var sizeIdx = rest.indexOf(":size=")
      var commaIdx = rest.indexOf(",")
      var end = rest.length
      if (sizeIdx >= 0)
        end = sizeIdx
      if (commaIdx >= 0 && commaIdx < end)
        end = commaIdx
      lines[i] = "font=" + name + rest.substring(end)
      found = true
    }
    if (found)
      return lines.join("\n")
    return root.appendLine(text, "font=" + name + ":size=" + root.terminalSize)
  }

  function patchAlacrittySize(text, size) {
    return root.replaceLinePrefix(text, "^size\\s*=", "size = " + size).text
  }

  function patchAlacrittyFamily(text, name) {
    return String(text || "").replace(/family\s*=\s*"[^"]*"/g, 'family = "' + root.tomlEscape(name) + '"')
  }

  function patchKittyKey(text, key, value) {
    var patched = root.replaceLinePrefix(text, "^\\s*" + key + "\\s+", key + " " + value)
    if (patched.found)
      return patched.text
    return root.appendLine(text, key + " " + value)
  }

  function patchGhosttySize(text, size) {
    var patched = root.replaceLinePrefix(text, "^font-size\\s*=", "font-size = " + size)
    if (patched.found)
      return patched.text
    return root.appendLine(text, "font-size = " + size)
  }

  function patchGhosttyFamily(text, name) {
    var patched = root.replaceLinePrefix(text, "^font-family\\s*=", 'font-family = "' + root.tomlEscape(name) + '"')
    if (patched.found)
      return patched.text
    return root.appendLine(text, 'font-family = "' + root.tomlEscape(name) + '"')
  }

  function readFootLine() {
    var text = root.readTextFile(root.footFile)
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("font=") !== 0)
        continue
      var rest = lines[i].substring(5)
      var sizeIdx = rest.indexOf(":size=")
      var commaIdx = rest.indexOf(",")
      var end = rest.length
      if (sizeIdx >= 0)
        end = sizeIdx
      if (commaIdx >= 0 && commaIdx < end)
        end = commaIdx
      var family = rest.substring(0, end).trim()
      var size = 0
      if (sizeIdx >= 0) {
        var sm = rest.substring(sizeIdx).match(/:size=([0-9.]+)/)
        if (sm)
          size = Math.round(Number(sm[1]))
      }
      return { family: family, size: size }
    }
    return { family: "", size: 0 }
  }

  function readKittyFamily() {
    var text = root.readTextFile(root.kittyFile)
    var lines = String(text || "").split("\n")
    var family = ""
    var size = 0
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (/^\s*#/.test(line))
        continue
      var fm = line.match(/^\s*font_family\s+(.+)$/)
      if (fm)
        family = String(fm[1] || "").trim()
      var sm = line.match(/^\s*font_size\s+([0-9.]+)/)
      if (sm)
        size = Math.round(Number(sm[1]))
    }
    return { family: family, size: size }
  }

  function readAlacrittyFamily() {
    var text = root.readTextFile(root.alacrittyFile)
    var fm = String(text || "").match(/family\s*=\s*"([^"]+)"/)
    var sm = String(text || "").match(/^size\s*=\s*([0-9.]+)/m)
    return {
      family: fm ? String(fm[1] || "").trim() : "",
      size: sm ? Math.round(Number(sm[1])) : 0
    }
  }

  function readGhosttyFamily() {
    var text = root.readTextFile(root.ghosttyFile)
    var fm = String(text || "").match(/^font-family\s*=\s*"([^"]+)"/m)
    var sm = String(text || "").match(/^font-size\s*=\s*([0-9.]+)/m)
    return {
      family: fm ? String(fm[1] || "").trim() : "",
      size: sm ? Math.round(Number(sm[1])) : 0
    }
  }

  function readShellBaseSize() {
    var text = root.readTextFile(root.shellFile)
    var lines = String(text || "").split("\n")
    var inFont = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (/^\s*\[/.test(line)) {
        inFont = /^\s*\[font\](\s|$)/.test(line)
        continue
      }
      if (inFont && /^\s*base-size\s*=/.test(line)) {
        var v = line.replace(/^[^=]*=\s*/, "").replace(/\s*(#.*)?$/, "")
        var n = Math.round(Number(v))
        if (isFinite(n) && n > 0)
          return n
      }
    }
    return 12
  }

  function readShellFamily() {
    var text = root.readTextFile(root.fontconfigFile)
    var m = String(text || "").match(/<edit name="family"[\s\S]*?<string>([^<]+)<\/string>/)
    if (m)
      return String(m[1] || "").trim()
    return ""
  }

  function parseGtkFont(raw) {
    var s = String(raw || "").trim()
    if (s.charAt(0) === "'" && s.charAt(s.length - 1) === "'")
      s = s.substring(1, s.length - 1)
    s = s.replace(/^"|"$/g, "").trim()
    var parts = s.split(/\s+/)
    var last = parts.length ? parts[parts.length - 1] : ""
    if (/^[0-9]+(\.[0-9]+)?$/.test(last) && parts.length >= 2) {
      return {
        family: parts.slice(0, parts.length - 1).join(" "),
        size: Math.round(Number(last))
      }
    }
    return { family: s, size: root.gtkDefaultSize }
  }

  function loadTerminal() {
    var foot = root.readFootLine()
    var kitty = root.readKittyFamily()
    var alacritty = root.readAlacrittyFamily()
    var ghostty = root.readGhosttyFamily()
    root.terminalFamily = foot.family || kitty.family || alacritty.family || ghostty.family || ""
    var size = foot.size || kitty.size || alacritty.size || ghostty.size || 12
    root.terminalSize = root.clamp(size)
  }

  function loadShell() {
    root.shellFamily = root.readShellFamily()
    root.shellSize = root.clamp(root.readShellBaseSize())
  }

  function loadGtk() {
    if (gtkReadProc.running)
      gtkReadProc.running = false
    gtkReadProc.running = true
  }

  function load() {
    var prevShell = root.shellFamily
    var prevTerm = root.terminalFamily
    var prevGtk = root.gtkFamily
    root.loadTerminal()
    root.loadShell()
    root.loadGtk()
    if (root.shellFamily !== prevShell || root.terminalFamily !== prevTerm || root.gtkFamily !== prevGtk)
      root.changed()
  }

  function setShellBaseSize(size) {
    var n = String(size)
    var text = root.readTextFile(root.shellFile)
    if (!text) {
      root.writeTextFile(root.shellFile, "[font]\nbase-size = " + n + "\n")
      return
    }
    var lines = text.split("\n")
    var inFont = false
    var done = false
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (/^\s*\[/.test(line)) {
        if (inFont && !done) {
          out.push("base-size = " + n)
          done = true
        }
        inFont = /^\s*\[font\](\s|$)/.test(line)
        out.push(line)
        continue
      }
      if (inFont && /^\s*base-size\s*=/.test(line)) {
        if (!done) {
          out.push("base-size = " + n)
          done = true
        }
        continue
      }
      out.push(line)
    }
    if (inFont && !done) {
      out.push("base-size = " + n)
      done = true
    }
    if (!done) {
      if (out.length && String(out[out.length - 1] || "").length)
        out.push("")
      out.push("[font]")
      out.push("base-size = " + n)
    }
    root.writeTextFile(root.shellFile, out.join("\n"))
  }

  function saveFontconfig(name) {
    var xml = '<?xml version="1.0"?>\n'
      + '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
      + "<fontconfig>\n"
      + '  <match target="pattern">\n'
      + '    <test name="family" qual="any">\n'
      + "      <string>monospace</string>\n"
      + "    </test>\n"
      + '    <edit name="family" mode="prepend_first" binding="strong">\n'
      + "      <string>" + root.xmlEscape(name) + "</string>\n"
      + "    </edit>\n"
      + "  </match>\n"
      + "</fontconfig>\n"
    root.writeTextFile(root.fontconfigFile, xml)
  }

  function reloadTerminals() {
    Quickshell.execDetached(["pkill", "-USR1", "kitty"])
    Quickshell.execDetached(["pkill", "-SIGUSR2", "ghostty"])
  }

  function writeGtkFont(family, size) {
    var fontName = String(family || "").trim()
    var n = root.clamp(size)
    if (!fontName)
      fontName = "Sans"
    root.gtkFamily = fontName
    root.gtkSize = n
    gtkSetProc.command = ["gsettings", "set", "org.gnome.desktop.interface", "font-name", fontName + " " + n]
    if (gtkSetProc.running)
      gtkSetProc.running = false
    gtkSetProc.running = true
  }

  function saveTerminalSize(size) {
    var n = root.clamp(size)
    root.terminalSize = n
    root.patchFile(root.footFile, function(text) { return root.patchFootSize(text, n) })
    root.patchFile(root.alacrittyFile, function(text) { return root.patchAlacrittySize(text, n) })
    root.patchFile(root.kittyFile, function(text) { return root.patchKittyKey(text, "font_size", n + ".0") })
    root.patchFile(root.ghosttyFile, function(text) { return root.patchGhosttySize(text, n) })
    root.reloadTerminals()
    return n
  }

  function saveTerminalFamily(name) {
    var fontName = String(name || "").trim()
    if (!fontName)
      return
    root.terminalFamily = fontName
    root.patchFile(root.footFile, function(text) { return root.patchFootFamily(text, fontName) })
    root.patchFile(root.alacrittyFile, function(text) { return root.patchAlacrittyFamily(text, fontName) })
    root.patchFile(root.kittyFile, function(text) { return root.patchKittyKey(text, "font_family", fontName) })
    root.patchFile(root.ghosttyFile, function(text) { return root.patchGhosttyFamily(text, fontName) })
    root.reloadTerminals()
  }

  function saveShellSize(size) {
    var n = root.clamp(size)
    root.shellSize = n
    root.setShellBaseSize(n)
    return n
  }

  function saveShellFamily(name) {
    var fontName = String(name || "").trim()
    if (!fontName)
      return
    root.shellFamily = fontName
    root.saveFontconfig(fontName)
    Quickshell.execDetached(["omarchy-restart-shell"])
    Quickshell.execDetached(["omarchy-hook", "font-set", fontName])
  }

  function setFamily(target, name) {
    var fontName = String(name || "").trim()
    if (!fontName)
      return
    var t = String(target || "shell")
    if (t === "terminal")
      root.saveTerminalFamily(fontName)
    else if (t === "gtk")
      root.writeGtkFont(fontName, root.gtkSize)
    else
      root.saveShellFamily(fontName)
    root.changed()
    root.listed()
  }

  function setSize(target, px) {
    var next = root.clamp(px)
    var t = String(target || "shell")
    if (t === "terminal") {
      if (next === root.terminalSize)
        return
      root.saveTerminalSize(next)
    } else if (t === "gtk") {
      if (next === root.gtkSize)
        return
      root.writeGtkFont(root.gtkFamily, next)
    } else {
      if (next === root.shellSize)
        return
      root.saveShellSize(next)
    }
  }

  Component.onCompleted: root.load()

  Process {
    id: listProc
    property int serial: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (listProc.serial !== root.listSerial)
          return
        root.applyList(text)
      }
    }
    onStarted: root.loading = true
    onExited: {
      if (listProc.serial !== root.listSerial)
        return
      if (root.listKind === "all") {
        if (!root.allReady)
          root.applyList("")
      } else if (!root.monoReady) {
        root.applyList("")
      }
    }
  }

  Process {
    id: gtkReadProc
    command: ["gsettings", "get", "org.gnome.desktop.interface", "font-name"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseGtkFont(text)
        var familyChanged = false
        if (parsed.family && parsed.family !== root.gtkFamily) {
          root.gtkFamily = parsed.family
          familyChanged = true
        }
        if (parsed.size > 0) {
          var n = root.clamp(parsed.size)
          if (n !== root.gtkSize)
            root.gtkSize = n
        }
        if (familyChanged)
          root.changed()
      }
    }
  }

  Process {
    id: gtkSetProc
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
