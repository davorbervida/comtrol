pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Hyprland window opacity groups — pure QML (replaces opacity_groups.py).
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string hyprDefault: root.omarchyPath + "/default/hypr"
  readonly property string userHypr: root.home + "/.config/hypr"
  readonly property string opacityFile: root.userHypr + "/comtrol-opacity.lua"
  readonly property string looknfeelFile: root.userHypr + "/looknfeel.lua"
  readonly property string hyprlandFile: root.userHypr + "/hyprland.lua"

  readonly property string mediaClass: "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$"

  readonly property var groupDefs: [
    {
      id: "default",
      label: "Default",
      icon: "󰖲",
      rules: [{ type: "tag", value: "default-opacity" }],
      defaults: [98, 96],
      sources: ["windows.lua"]
    },
    {
      id: "terminal",
      label: "Terminal",
      icon: "",
      rules: [{ type: "tag", value: "terminal" }],
      defaults: [100, 100],
      sources: ["apps/terminals.lua"]
    },
    {
      id: "browser",
      label: "Browser",
      icon: "󰖟",
      rules: [
        { type: "tag", value: "chromium-based-browser" },
        { type: "tag", value: "firefox-based-browser" }
      ],
      defaults: [100, 98],
      sources: ["apps/browser.lua"]
    },
    {
      id: "steam",
      label: "Steam",
      icon: "󰓓",
      rules: [{ type: "class", value: "steam.*" }],
      defaults: [100, 100],
      sources: ["apps/steam.lua"]
    },
    {
      id: "media",
      label: "Media",
      icon: "󰕼",
      rules: [{ type: "class", value: root.mediaClass }],
      defaults: [100, 100],
      sources: ["apps/system.lua"]
    },
    {
      id: "pip",
      label: "PiP",
      icon: "󰐝",
      rules: [{ type: "tag", value: "pip" }],
      defaults: [100, 100],
      sources: ["apps/pip.lua"]
    },
    {
      id: "qemu",
      label: "QEMU",
      icon: "󰍺",
      rules: [{ type: "class", value: "qemu" }],
      defaults: [100, 100],
      sources: ["apps/qemu.lua"]
    },
    {
      id: "retroarch",
      label: "RetroArch",
      icon: "󰊖",
      rules: [{ type: "class", value: "com.libretro.RetroArch" }],
      defaults: [100, 100],
      sources: ["apps/retroarch.lua"]
    },
    {
      id: "davinci",
      label: "DaVinci",
      icon: "󰕧",
      rules: [{ type: "class", value: ".*[Rr]esolve.*" }],
      defaults: [100, 100],
      sources: ["apps/davinci-resolve.lua"]
    },
    {
      id: "hermes",
      label: "Hermes",
      icon: "󰒍",
      rules: [{ type: "class", value: "^Hermes$" }],
      defaults: [100, 100],
      sources: ["apps/hermes.lua"]
    },
    {
      id: "webcam",
      label: "Webcam",
      icon: "󰖠",
      rules: [{ type: "class", value: "^WebcamOverlay-(small|medium|large)$" }],
      defaults: [100, 100],
      sources: ["apps/webcam-overlay.lua"]
    }
  ]

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

  function ensureHyprDir() {
    if (!mkdirProc.running) {
      mkdirProc.command = ["mkdir", "-p", root.userHypr]
      mkdirProc.running = true
    }
  }

  function clampPct(n) {
    var v = Math.round(Number(n))
    if (!isFinite(v))
      return 100
    return Math.max(1, Math.min(100, v))
  }

  function parsePair(raw) {
    var s = String(raw || "").replace(/override/g, " ")
    var parts = s.split(/\s+/)
    var nums = []
    for (var i = 0; i < parts.length; i++) {
      var n = Number(parts[i])
      if (!isFinite(n))
        continue
      nums.push(n)
      if (nums.length >= 2)
        break
    }
    if (nums.length === 0)
      return [100, 100]
    if (nums.length === 1)
      nums.push(nums[0])
    return [
      root.clampPct(Math.round(nums[0] * 100)),
      root.clampPct(Math.round(nums[1] * 100))
    ]
  }

  function firstOpacityPair(text) {
    var m = String(text || "").match(/opacity\s*=\s*"([^"]+)"/)
    if (!m)
      return null
    return root.parsePair(m[1])
  }

  function readSourceDefaults() {
    var found = ({})
    var defs = root.groupDefs
    for (var i = 0; i < defs.length; i++) {
      var g = defs[i]
      var sources = g.sources || []
      for (var s = 0; s < sources.length; s++) {
        var text = root.readTextFile(root.hyprDefault + "/" + sources[s])
        var pair = root.firstOpacityPair(text)
        if (pair) {
          found[g.id] = pair
          break
        }
      }
    }
    var userFiles = [root.hyprlandFile, root.looknfeelFile]
    for (var u = 0; u < userFiles.length; u++) {
      var utext = root.readTextFile(userFiles[u])
      if (!utext)
        continue
      if (utext.indexOf('tag = "terminal"') < 0 && utext.indexOf("tag = 'terminal'") < 0)
        continue
      var re = /opacity\s*=\s*"([^"]+)"/g
      var m
      while ((m = re.exec(utext)) !== null) {
        var start = Math.max(0, m.index - 200)
        var chunk = utext.substring(start, m.index + m[0].length + 20)
        if (chunk.indexOf("terminal") >= 0) {
          found["terminal"] = root.parsePair(m[1])
          break
        }
      }
    }
    return found
  }

  function readSaved() {
    var out = ({})
    var text = root.readTextFile(root.opacityFile)
    if (!text)
      return out
    var re = /hl\.window_rule\(\{([\s\S]*?)\}\)/g
    var block
    while ((block = re.exec(text)) !== null) {
      var body = block[1]
      var nameM = body.match(/name\s*=\s*"comtrol-opacity-([^"]+)"/)
      var opM = body.match(/opacity\s*=\s*"([^"]+)"/)
      if (!nameM || !opM)
        continue
      var gid = String(nameM[1] || "").replace(/-\d+$/, "")
      out[gid] = root.parsePair(opM[1])
    }
    return out
  }

  function buildGroups(includeSaved) {
    var source = root.readSourceDefaults()
    var saved = includeSaved ? root.readSaved() : ({})
    var groups = []
    var defs = root.groupDefs
    for (var i = 0; i < defs.length; i++) {
      var g = defs[i]
      var active = g.defaults[0]
      var inactive = g.defaults[1]
      if (source[g.id]) {
        active = source[g.id][0]
        inactive = source[g.id][1]
      }
      if (saved[g.id]) {
        active = saved[g.id][0]
        inactive = saved[g.id][1]
      }
      groups.push({
        id: g.id,
        label: g.label,
        icon: g.icon,
        active: root.clampPct(active),
        inactive: root.clampPct(inactive),
        rules: g.rules
      })
    }
    return groups
  }

  function pct(n) {
    return (root.clampPct(n) / 100).toFixed(2)
  }

  function escapeLuaString(value) {
    return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  function ruleLua(name, rule, active, inactive) {
    var op = root.pct(active) + " override " + root.pct(inactive) + " override"
    var match
    if (String(rule.type || "") === "tag")
      match = 'match = { tag = "' + String(rule.value || "") + '" }'
    else
      match = 'match = { class = "' + root.escapeLuaString(rule.value) + '" }'
    return "hl.window_rule({\n"
      + '  name = "' + name + '",\n'
      + "  " + match + ",\n"
      + '  opacity = "' + op + '",\n'
      + "})"
  }

  function renderFile(groups) {
    var lines = [
      "-- Managed by cOMtrol. Do not edit by hand.",
      "hl.config({",
      "  decoration = {",
      "    active_opacity = 1.0,",
      "    inactive_opacity = 1.0,",
      "  },",
      "})",
      ""
    ]
    var list = groups || []
    for (var i = 0; i < list.length; i++) {
      var g = list[i] || {}
      var rules = g.rules || []
      for (var r = 0; r < rules.length; r++) {
        var name = rules.length === 1
          ? ("comtrol-opacity-" + g.id)
          : ("comtrol-opacity-" + g.id + "-" + r)
        lines.push(root.ruleLua(name, rules[r], g.active, g.inactive))
        lines.push("")
      }
    }
    return lines.join("\n").replace(/\n+$/, "") + "\n"
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
    root.ensureHyprDir()
    root.writeTextFile(path, text)
  }

  function ensureHyprlandRequire() {
    var text = root.readTextFile(root.hyprlandFile)
    if (!text)
      return
    text = text.replace(
      /\n-- Terminals:[\s\S]*?o\.window\(\{\s*tag\s*=\s*"terminal"\s*\},\s*\{\s*opacity\s*=\s*"[^"]+"\s*\}\)\s*\n/,
      "\n"
    )
    var requireBlock = "-- BEGIN COMTROL-OPACITY-REQUIRE\n"
      + 'pcall(function() require("hypr.comtrol-opacity") end)\n'
      + "-- END COMTROL-OPACITY-REQUIRE\n"
    var begin = "-- BEGIN COMTROL-OPACITY-REQUIRE"
    var end = "-- END COMTROL-OPACITY-REQUIRE"
    var start = text.indexOf(begin)
    if (start >= 0) {
      var stop = text.indexOf(end, start)
      if (stop >= 0) {
        stop += end.length
        if (stop < text.length && text.charAt(stop) === "\n")
          stop += 1
        text = text.substring(0, start) + requireBlock + text.substring(stop)
      } else {
        text = text.replace(/\s+$/, "") + "\n\n" + requireBlock
      }
    } else {
      if (text.length && text.charAt(text.length - 1) !== "\n")
        text += "\n"
      text += "\n" + requireBlock
    }
    root.writeTextFile(root.hyprlandFile, text)
  }

  function stripLegacyLooknfeelOpacity() {
    var text = root.readTextFile(root.looknfeelFile)
    if (!text)
      return
    var begin = "-- BEGIN COMTROL-OPACITY"
    var end = "-- END COMTROL-OPACITY"
    var start = text.indexOf(begin)
    if (start < 0)
      return
    var stop = text.indexOf(end, start)
    if (stop < 0)
      return
    stop += end.length
    if (stop < text.length && text.charAt(stop) === "\n")
      stop += 1
    root.writeTextFile(root.looknfeelFile, text.substring(0, start) + text.substring(stop))
  }

  function rulesForId(gid) {
    var defs = root.groupDefs
    for (var i = 0; i < defs.length; i++) {
      if (defs[i].id === gid)
        return defs[i].rules
    }
    return []
  }

  function renderEvalLua(groups) {
    var parts = [
      "hl.config({ decoration = { active_opacity = 1.0, inactive_opacity = 1.0 } })"
    ]
    var list = groups || []
    for (var i = 0; i < list.length; i++) {
      var g = list[i] || {}
      var gid = String(g.id || "")
      var active = root.clampPct(g.active)
      var inactive = root.clampPct(g.inactive)
      var rules = g.rules || root.rulesForId(gid)
      for (var r = 0; r < rules.length; r++) {
        var rule = rules[r] || {}
        var name = rules.length === 1
          ? ("comtrol-opacity-" + gid)
          : ("comtrol-opacity-" + gid + "-" + r)
        var op = root.pct(active) + " override " + root.pct(inactive) + " override"
        var match
        if (String(rule.type || "") === "tag")
          match = 'match = { tag = "' + String(rule.value || "") + '" }'
        else
          match = 'match = { class = "' + root.escapeLuaString(rule.value) + '" }'
        parts.push('hl.window_rule({ name = "' + name + '", ' + match + ', opacity = "' + op + '" })')
      }
    }
    return parts.join("; ")
  }

  function scan() {
    return root.buildGroups(true)
  }

  function defaults() {
    return root.buildGroups(false)
  }

  function reset() {
    var groups = root.buildGroups(false)
    root.ensureHyprDir()
    root.writeTextFile(root.opacityFile, root.renderFile(groups))
    root.ensureHyprlandRequire()
    root.stripLegacyLooknfeelOpacity()
    return groups
  }

  function save(groups) {
    var incoming = ({})
    var list = groups || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i] || {}
      var id = String(item.id || "")
      if (id)
        incoming[id] = item
    }
    var next = root.buildGroups(true)
    for (var j = 0; j < next.length; j++) {
      var g = next[j]
      if (incoming[g.id]) {
        g.active = root.clampPct(incoming[g.id].active)
        g.inactive = root.clampPct(incoming[g.id].inactive)
      }
    }
    root.ensureHyprDir()
    root.writeTextFile(root.opacityFile, root.renderFile(next))
    root.ensureHyprlandRequire()
    root.stripLegacyLooknfeelOpacity()
    return next
  }

  function evalGroup(gid, active, inactive) {
    var rules = root.rulesForId(gid)
    if (!rules.length)
      return ""
    return root.renderEvalLua([{
      id: gid,
      active: active,
      inactive: inactive,
      rules: rules
    }])
  }

  function evalAll(groups) {
    var defs = ({})
    for (var i = 0; i < root.groupDefs.length; i++)
      defs[root.groupDefs[i].id] = root.groupDefs[i]
    var incoming = groups || []
    var out = []
    for (var j = 0; j < incoming.length; j++) {
      var item = incoming[j] || {}
      var id = String(item.id || "")
      if (!defs[id])
        continue
      out.push({
        id: id,
        active: root.clampPct(item.active !== undefined ? item.active : defs[id].defaults[0]),
        inactive: root.clampPct(item.inactive !== undefined ? item.inactive : defs[id].defaults[1]),
        rules: defs[id].rules
      })
    }
    if (!out.length) {
      for (var k = 0; k < root.groupDefs.length; k++) {
        var d = root.groupDefs[k]
        out.push({
          id: d.id,
          active: d.defaults[0],
          inactive: d.defaults[1],
          rules: d.rules
        })
      }
    }
    return root.renderEvalLua(out)
  }

  Component.onCompleted: root.ensureHyprDir()

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

  Process {
    id: mkdirProc
  }
}
