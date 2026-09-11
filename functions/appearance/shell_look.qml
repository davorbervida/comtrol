pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Shell chrome in ~/.config/omarchy/shell.toml. User keys win over the theme.
// Rounding is stored per surface and re-applied onto live items because
// Omarchy binds radius to a single Style.cornerRadius.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string shellFile: root.home + "/.config/omarchy/shell.toml"
  readonly property int minBorder: 0
  readonly property int maxBorder: 10
  readonly property int minRounding: 0
  readonly property int maxRounding: 24
  readonly property int minAlpha: 0
  readonly property int maxAlpha: 100
  readonly property int minBarSize: 16
  readonly property int maxBarSize: 48
  readonly property int minSpacingPct: 50
  readonly property int maxSpacingPct: 200
  readonly property int minPadding: 4
  readonly property int maxPadding: 96
  readonly property var groupIds: [
    "menu", "popups", "notifications", "launcher", "tooltip", "controls", "polkit", "lock"
  ]
  readonly property var scrimGroups: ["menu", "launcher", "polkit"]
  readonly property var selectionGroups: ["menu", "launcher"]
  readonly property var sides: ["top", "right", "bottom", "left"]

  property var host: null
  property string previewGroup: ""
  property string previewState: "idle"
  property bool previewOwnsOsd: false
  property int shellEpoch: 0
  readonly property string notifyPreviewSummary: "Notifications preview"

  readonly property int menuRounding: {
    var live = root.liveRoundings || ({})
    if (live.menu !== undefined)
      return root.clampRounding(live.menu)
    return Style.cornerRadius
  }

  readonly property int previewRadius: {
    var live = root.liveRoundings || ({})
    var g = root.previewGroup
    if (g && live[g] !== undefined)
      return root.clampRounding(live[g])
    return Style.cornerRadius
  }

  readonly property bool ownedPreview: {
    var g = root.previewGroup
    return g === "tooltip" || g === "controls" || g === "launcher"
      || g === "polkit" || g === "lock" || g === "popups"
  }

  readonly property bool previewDockBottom: root.previewGroup === "popups"

  readonly property var liveBorders: {
    var values = Color.shellValues
    var out = ({})
    for (var i = 0; i < root.groupIds.length; i++) {
      var id = root.groupIds[i]
      out[id] = ({
        all: root.borderFromValues(values, id, "all"),
        top: root.borderFromValues(values, id, "top"),
        right: root.borderFromValues(values, id, "right"),
        bottom: root.borderFromValues(values, id, "bottom"),
        left: root.borderFromValues(values, id, "left")
      })
    }
    return out
  }

  function liveWidths(groupId) {
    var live = (root.liveBorders || ({ }))[String(groupId || "")] || ({})
    var fb = root.defaultBorder(groupId)
    return ({
      top: live.top !== undefined ? root.clampBorder(live.top) : fb,
      right: live.right !== undefined ? root.clampBorder(live.right) : fb,
      bottom: live.bottom !== undefined ? root.clampBorder(live.bottom) : fb,
      left: live.left !== undefined ? root.clampBorder(live.left) : fb
    })
  }

  function specWithLiveWidths(section, token, color, fallback, alphaKey) {
    void root.shellEpoch
    void Color.shellValues
    void root.liveBorders
    var spec = Border.surfaceSpec(section, token, color, fallback, alphaKey)
    if (!spec)
      spec = Border.flat(color, fallback)
    spec.widths = root.liveWidths(section)
    return spec
  }

  readonly property var menuBorderSpec: {
    void root.shellEpoch
    void Color.shellValues
    void Color.menu.border
    return root.specWithLiveWidths("menu", "border", Color.menu.border, root.defaultBorder("menu"))
  }

  readonly property var menuSelectedBorderSpec: {
    void root.shellEpoch
    void Color.shellValues
    void Color.menu.selectedBorder
    void root.liveSelection
    return root.selectedBorderSpecOf("menu")
  }

  readonly property var liveRoundings: {
    var values = Color.shellValues
    var out = ({})
    for (var i = 0; i < root.groupIds.length; i++) {
      var id = root.groupIds[i]
      out[id] = root.roundingFromValues(values, id)
    }
    return out
  }

  readonly property var liveAlphas: {
    var values = Color.shellValues || ({})
    var out = ({})
    out["bar.background"] = root.parseAlphaPct(values["bar.background-alpha"], 100)
    for (var i = 0; i < root.groupIds.length; i++) {
      var id = root.groupIds[i]
      out[id + ".background"] = root.parseAlphaPct(values[id + ".background-alpha"], root.defaultAlpha(id, "background"))
      if (root.hasScrim(id))
        out[id + ".scrim"] = root.parseAlphaPct(values[id + ".scrim-alpha"], root.defaultAlpha(id, "scrim"))
    }
    return out
  }

  readonly property var liveStateFills: {
    void Color.shellValues
    var values = Color.shellValues || ({})
    var out = ({})
    var states = ["idle", "hover", "focus", "selected", "pressed"]
    for (var i = 0; i < root.groupIds.length; i++) {
      var id = root.groupIds[i]
      for (var j = 0; j < states.length; j++) {
        var s = states[j]
        out[id + "." + s] = root.parseAlphaPct(values[root.stateFillKey(id, s)], root.defaultFillFor(id, s))
      }
    }
    return out
  }

  readonly property var liveStateBorders: {
    void Color.shellValues
    void Style.normalBorderWidth
    void Style.hoverBorderWidth
    void Style.focusBorderWidth
    void Style.selectedBorderWidth
    var values = Color.shellValues || ({})
    var out = ({})
    var states = ["idle", "hover", "focus", "selected", "pressed"]
    for (var i = 0; i < root.groupIds.length; i++) {
      var id = root.groupIds[i]
      var group = ({})
      for (var j = 0; j < states.length; j++) {
        var s = states[j]
        group[s] = ({
          all: root.stateBorderFromValues(values, id, s, "all"),
          top: root.stateBorderFromValues(values, id, s, "top"),
          right: root.stateBorderFromValues(values, id, s, "right"),
          bottom: root.stateBorderFromValues(values, id, s, "bottom"),
          left: root.stateBorderFromValues(values, id, s, "left")
        })
      }
      out[id] = group
    }
    return out
  }

  readonly property var liveSelection: {
    var values = Color.shellValues || ({})
    var out = ({})
    for (var i = 0; i < root.selectionGroups.length; i++) {
      var id = root.selectionGroups[i]
      out[id + ".fill"] = root.parseAlphaPct(values[id + ".selected-background-alpha"], 8)
      var n = root.parseWidth(values[id + ".selected-border-width"], -1)
      out[id + ".border"] = root.clampBorder(n < 0 ? 0 : n)
    }
    return out
  }

  readonly property var liveBarSize: {
    var values = Color.shellValues || ({})
    return ({
      h: root.clampBarSize(root.parseWidth(values["bar.size-horizontal"], 26)),
      v: root.clampBarSize(root.parseWidth(values["bar.size-vertical"], 28))
    })
  }

  readonly property int liveSpacingScale: root.clampSpacingPct(Math.round(Number(Style.spacingScale || 1) * 100))
  readonly property int livePanelPadding: root.clampPadding(Style.spacing.panelPadding)
  readonly property int livePopupPadding: root.clampPadding(Style.spacing.popupPadding)
  readonly property int liveControlHeight: root.clampPadding(Style.spacing.controlHeight)

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
    }
    return ""
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

  function parseWidth(raw, fallback) {
    var s = String(raw === undefined || raw === null ? "" : raw).trim()
    if (!s)
      return fallback
    var n = Math.round(Number(s.split(/\s+/)[0]))
    if (!isFinite(n))
      return fallback
    return n
  }

  function parseAlphaPct(raw, fallback) {
    if (raw === undefined || raw === null || String(raw).trim() === "")
      return fallback
    var n = Number(raw)
    if (!isFinite(n))
      return fallback
    if (n <= 1)
      return root.clampAlpha(Math.round(n * 100))
    return root.clampAlpha(Math.round(n))
  }

  function clampInt(value, minV, maxV) {
    var n = Math.round(Number(value))
    if (!isFinite(n))
      return minV
    return Math.max(minV, Math.min(maxV, n))
  }

  function clampBorder(value) {
    return root.clampInt(value, root.minBorder, root.maxBorder)
  }

  function clampRounding(value) {
    return root.clampInt(value, root.minRounding, root.maxRounding)
  }

  function clampAlpha(value) {
    return root.clampInt(value, root.minAlpha, root.maxAlpha)
  }

  function clampBarSize(value) {
    return root.clampInt(value, root.minBarSize, root.maxBarSize)
  }

  function clampSpacingPct(value) {
    var n = Math.round(Number(value) / 5) * 5
    return root.clampInt(n, root.minSpacingPct, root.maxSpacingPct)
  }

  function clampPadding(value) {
    return root.clampInt(value, root.minPadding, root.maxPadding)
  }

  function knownGroup(groupId) {
    var id = String(groupId || "")
    for (var i = 0; i < root.groupIds.length; i++) {
      if (root.groupIds[i] === id)
        return id
    }
    return ""
  }

  function hasScrim(groupId) {
    var id = String(groupId || "")
    for (var i = 0; i < root.scrimGroups.length; i++) {
      if (root.scrimGroups[i] === id)
        return true
    }
    return false
  }

  function hasSelection(groupId) {
    var id = String(groupId || "")
    for (var i = 0; i < root.selectionGroups.length; i++) {
      if (root.selectionGroups[i] === id)
        return true
    }
    return false
  }

  function statesOf(groupId) {
    return [
      { id: "idle", label: "Idle" },
      { id: "hover", label: "Hover" },
      { id: "focus", label: "Focus" },
      { id: "selected", label: "Selected" },
      { id: "pressed", label: "Pressed" }
    ]
  }

  function stateHasFill(groupId, state) {
    return true
  }

  function stateHasBorder(groupId, state) {
    return true
  }

  function stateHasBorderSides(groupId, state) {
    return true
  }

  function controlPrefix(state) {
    var s = String(state || "idle")
    if (s === "idle" || s === "normal")
      return "normal"
    if (s === "hover")
      return "hover-cursor"
    return s
  }

  function stateFillKey(groupId, state) {
    var id = root.knownGroup(groupId) || "controls"
    var p = root.controlPrefix(state)
    if (p === "selected" && (id === "menu" || id === "launcher"))
      return id + ".selected-background-alpha"
    return id + "." + p + "-fill-alpha"
  }

  function stateBorderKey(groupId, state, side) {
    var id = root.knownGroup(groupId)
    var p = root.controlPrefix(state)
    var s = String(side || "all")
    if (!id)
      return ""
    if (p === "normal" && id !== "controls") {
      if (s === "all")
        return id + ".border-width"
      return id + ".border-width-" + s
    }
    var base = id + "." + p + "-border-width"
    if (s === "all")
      return base
    return base + "-" + s
  }

  function defaultFillFor(groupId, state) {
    var s = String(state || "idle")
    if (String(groupId) !== "controls" && (s === "idle" || s === "normal"))
      return 0
    return root.defaultFill(s)
  }

  function defaultStateBorder(groupId, state) {
    var s = String(state || "idle")
    if (String(groupId) === "controls") {
      if (s === "selected")
        return root.clampBorder(Style.selectedBorderWidth)
      if (s === "hover")
        return root.clampBorder(Style.hoverBorderWidth)
      if (s === "focus")
        return root.clampBorder(Style.focusBorderWidth)
      if (s === "pressed")
        return 0
      return root.clampBorder(Style.normalBorderWidth)
    }
    if (s === "idle" || s === "normal")
      return root.defaultBorder(groupId)
    return 0
  }

  function defaultBorder(groupId) {
    if (String(groupId) === "controls")
      return root.clampBorder(Style.normalBorderWidth)
    var n = Math.round(Number(Style.space(2)))
    if (!isFinite(n) || n < 1)
      n = 2
    return root.clampBorder(n)
  }

  function defaultAlpha(groupId, channel) {
    var id = String(groupId || "")
    var ch = String(channel || "background")
    if (ch === "scrim")
      return 50
    if (id === "lock")
      return 80
    if (id === "tooltip")
      return 97
    if (id === "launcher")
      return 95
    return 100
  }

  function defaultFill(state) {
    var s = String(state || "idle")
    if (s === "hover" || s === "focus")
      return 8
    if (s === "selected")
      return 18
    if (s === "pressed")
      return 22
    return 4
  }

  function borderKey(groupId, side) {
    var id = root.knownGroup(groupId)
    var s = String(side || "all")
    if (!id)
      return ""
    if (id === "controls") {
      if (s === "all")
        return "controls.normal-border-width"
      return "controls.normal-border-width-" + s
    }
    if (s === "all")
      return id + ".border-width"
    return id + ".border-width-" + s
  }

  function roundingKey(groupId) {
    var id = root.knownGroup(groupId)
    if (!id)
      return ""
    return id + ".corner-radius"
  }

  function alphaKey(groupId, channel) {
    var id = String(groupId || "")
    var ch = String(channel || "background")
    if (id === "bar")
      return "bar.background-alpha"
    if (ch === "scrim")
      return id + ".scrim-alpha"
    return id + ".background-alpha"
  }

  function fillKey(state) {
    return root.stateFillKey("controls", state)
  }

  function controlBorderKey(state, side) {
    return root.stateBorderKey("controls", state, side)
  }

  function values() {
    return Color.shellValues || ({})
  }

  function borderFromValues(vals, groupId, side) {
    var v = vals || ({})
    var s = String(side || "all")
    if (s !== "all") {
      var n = root.parseWidth(v[root.borderKey(groupId, s)], -1)
      if (n < 0)
        n = root.parseWidth(v[root.borderKey(groupId, "all")], -1)
      if (n < 0)
        n = root.parseWidth(v["comtrol.border-width"], -1)
      if (n < 0)
        n = root.defaultBorder(groupId)
      return root.clampBorder(n)
    }
    var first = root.parseWidth(v[root.borderKey(groupId, "top")], -1)
    if (first >= 0) {
      var uniform = true
      for (var i = 1; i < root.sides.length; i++) {
        var sn = root.parseWidth(v[root.borderKey(groupId, root.sides[i])], -1)
        if (sn !== first) {
          uniform = false
          break
        }
      }
      if (uniform)
        return root.clampBorder(first)
    }
    var base = root.parseWidth(v[root.borderKey(groupId, "all")], -1)
    if (base < 0)
      base = root.parseWidth(v["comtrol.border-width"], -1)
    if (base < 0)
      base = root.defaultBorder(groupId)
    return root.clampBorder(base)
  }

  function stateBorderFromValues(vals, groupId, state, side) {
    var v = vals || ({})
    var s = String(side || "all")
    var fallback = root.defaultStateBorder(groupId, state)
    if (s !== "all") {
      var n = root.parseWidth(v[root.stateBorderKey(groupId, state, s)], -1)
      if (n < 0)
        n = root.parseWidth(v[root.stateBorderKey(groupId, state, "all")], -1)
      if (n < 0)
        n = fallback
      return root.clampBorder(n)
    }
    var first = root.parseWidth(v[root.stateBorderKey(groupId, state, "top")], -1)
    if (first >= 0) {
      var uniform = true
      for (var i = 1; i < root.sides.length; i++) {
        var sn = root.parseWidth(v[root.stateBorderKey(groupId, state, root.sides[i])], -1)
        if (sn !== first) {
          uniform = false
          break
        }
      }
      if (uniform)
        return root.clampBorder(first)
    }
    var base = root.parseWidth(v[root.stateBorderKey(groupId, state, "all")], -1)
    if (base < 0)
      base = fallback
    return root.clampBorder(base)
  }

  function controlBorderFromValues(vals, state, side) {
    return root.stateBorderFromValues(vals, "controls", state, side)
  }

  function roundingFromValues(vals, groupId) {
    var v = vals || ({})
    var n = root.parseWidth(v[root.roundingKey(groupId)], -1)
    if (n < 0)
      n = root.parseWidth(v["comtrol.corner-radius"], -1)
    if (n < 0)
      n = Style.cornerRadius
    return root.clampRounding(n)
  }

  function borderOf(groupId, side) {
    var live = root.liveBorders || ({})
    var s = String(side || "all")
    if (live[groupId] && live[groupId][s] !== undefined)
      return root.clampBorder(live[groupId][s])
    return root.borderFromValues(root.values(), groupId, s)
  }

  function roundingOf(groupId) {
    var live = root.liveRoundings || ({})
    if (live[groupId] !== undefined)
      return root.clampRounding(live[groupId])
    return root.roundingFromValues(root.values(), groupId)
  }

  function alphaOf(groupId, channel) {
    var id = String(groupId || "")
    var ch = String(channel || "background")
    var live = root.liveAlphas || ({})
    var key = id + "." + ch
    if (live[key] !== undefined)
      return root.clampAlpha(live[key])
    return root.parseAlphaPct(root.values()[root.alphaKey(id, ch)], root.defaultAlpha(id, ch))
  }

  function fillOf(state) {
    return root.stateFillOf("controls", state)
  }

  function stateFillOf(groupId, state) {
    var id = root.knownGroup(groupId) || "controls"
    var s = String(state || "idle")
    if (s === "normal")
      s = "idle"
    var live = root.liveStateFills || ({})
    var k = id + "." + s
    if (live[k] !== undefined)
      return root.clampAlpha(live[k])
    return root.defaultFillFor(id, s)
  }

  function controlBorderOf(state, side) {
    return root.stateBorderOf("controls", state, side)
  }

  function stateBorderOf(groupId, state, side) {
    var id = root.knownGroup(groupId) || "controls"
    var s = String(state || "idle")
    if (s === "normal")
      s = "idle"
    var ch = String(side || "all")
    var live = ((root.liveStateBorders || ({ }))[id] || ({ }))[s] || ({})
    if (live[ch] !== undefined)
      return root.clampBorder(live[ch])
    return root.stateBorderFromValues(root.values(), id, s, ch)
  }

  function controlLiveWidths(state) {
    return root.stateLiveWidths("controls", state)
  }

  function stateLiveWidths(groupId, state) {
    var s = String(state || "idle")
    var live = ((root.liveStateBorders || ({ }))[String(groupId || "")] || ({ }))[s] || ({})
    var fb = root.stateBorderOf(groupId, s, "all")
    return ({
      top: live.top !== undefined ? root.clampBorder(live.top) : fb,
      right: live.right !== undefined ? root.clampBorder(live.right) : fb,
      bottom: live.bottom !== undefined ? root.clampBorder(live.bottom) : fb,
      left: live.left !== undefined ? root.clampBorder(live.left) : fb
    })
  }

  function stateFillColor(groupId, state) {
    void root.shellEpoch
    void root.liveStateFills
    var a = root.stateFillOf(groupId, state) / 100
    if (a <= 0)
      return "transparent"
    return Util.alpha(Color.foreground, a)
  }

  function surfaceStateBorderSpec(groupId, state) {
    void root.shellEpoch
    void Color.shellValues
    void Color.menu.selectedBorder
    void root.liveStateBorders
    var spec = Border.flat(Color.menu.selectedBorder, 0)
    spec.widths = root.stateLiveWidths(groupId, state)
    return spec
  }

  function rowBorderSpec(groupId, state) {
    var s = String(state || "idle")
    if (s === "idle" || s === "normal")
      return Border.none()
    return root.surfaceStateBorderSpec(groupId, s)
  }

  function selectionFillOf(groupId) {
    return root.stateFillOf(groupId, "selected")
  }

  function selectionBorderOf(groupId) {
    return root.stateBorderOf(groupId, "selected", "all")
  }

  function barSizeOf(axis) {
    var a = String(axis) === "v" ? "v" : "h"
    var live = root.liveBarSize || ({})
    if (live[a] !== undefined)
      return root.clampBarSize(live[a])
    return a === "v" ? 28 : 26
  }

  function spacingScalePct() {
    return root.liveSpacingScale
  }

  function spacingTokenOf(key) {
    var k = String(key || "")
    if (k === "popup-padding")
      return root.livePopupPadding
    if (k === "control-height")
      return root.liveControlHeight
    return root.livePanelPadding
  }

  function cloneMap(src) {
    var out = ({})
    var v = src || ({})
    for (var k in v)
      out[k] = v[k]
    return out
  }

  function applyMap(map) {
    var next = root.cloneMap(Color.userShellValues)
    for (var k in map)
      next[k] = String(map[k])
    Color.userShellValues = next
    Color.mergeShell()
    root.shellEpoch += 1
  }

  function fmtAlpha(pct) {
    return String(root.clampAlpha(pct) / 100)
  }

  function borderAssignments(groupId, side, value) {
    return root.stateBorderAssignments(groupId, "idle", side, value)
  }

  function stateBorderAssignments(groupId, state, side, value) {
    var n = String(root.clampBorder(value))
    var ch = String(side || "all")
    var out = ({})
    var i
    if (ch === "all") {
      out[root.stateBorderKey(groupId, state, "all")] = n
      for (i = 0; i < root.sides.length; i++)
        out[root.stateBorderKey(groupId, state, root.sides[i])] = n
    } else {
      out[root.stateBorderKey(groupId, state, ch)] = n
    }
    return out
  }

  function controlBorderAssignments(state, side, value) {
    return root.stateBorderAssignments("controls", state, side, value)
  }

  function applyBorder(groupId, side, value) {
    return root.applyStateBorder(groupId, "idle", side, value)
  }

  function saveBorder(groupId, side, value) {
    root.saveStateBorder(groupId, "idle", side, value)
  }

  function applyControlBorder(state, side, value) {
    return root.applyStateBorder("controls", state, side, value)
  }

  function saveControlBorder(state, side, value) {
    root.saveStateBorder("controls", state, side, value)
  }

  function applyStateBorder(groupId, state, side, value) {
    root.applyMap(root.stateBorderAssignments(groupId, state, side, value))
    return root.clampBorder(value)
  }

  function saveStateBorder(groupId, state, side, value) {
    root.upsertToml(root.stateBorderAssignments(groupId, state, side, value))
  }

  function applyRounding(groupId, value) {
    var id = root.knownGroup(groupId)
    if (!id)
      return root.minRounding
    var n = root.clampRounding(value)
    var map = ({})
    map[root.roundingKey(id)] = String(n)
    root.applyMap(map)
    root.scheduleRadiusApply()
    return n
  }

  function saveRounding(groupId, value) {
    var id = root.knownGroup(groupId)
    if (!id)
      return
    var map = ({})
    map[root.roundingKey(id)] = String(root.clampRounding(value))
    root.upsertToml(map)
  }

  function applyAlpha(groupId, channel, value) {
    var map = ({})
    map[root.alphaKey(groupId, channel)] = root.fmtAlpha(value)
    root.applyMap(map)
    return root.clampAlpha(value)
  }

  function saveAlpha(groupId, channel, value) {
    var map = ({})
    map[root.alphaKey(groupId, channel)] = root.fmtAlpha(value)
    root.upsertToml(map)
  }

  function applyFill(state, value) {
    return root.applyStateFill("controls", state, value)
  }

  function saveFill(state, value) {
    root.saveStateFill("controls", state, value)
  }

  function applyStateFill(groupId, state, value) {
    var map = ({})
    map[root.stateFillKey(groupId, state)] = root.fmtAlpha(value)
    root.applyMap(map)
    return root.clampAlpha(value)
  }

  function saveStateFill(groupId, state, value) {
    var map = ({})
    map[root.stateFillKey(groupId, state)] = root.fmtAlpha(value)
    root.upsertToml(map)
  }

  function applySelectionFill(groupId, value) {
    return root.applyStateFill(groupId, "selected", value)
  }

  function saveSelectionFill(groupId, value) {
    root.saveStateFill(groupId, "selected", value)
  }

  function applySelectionBorder(groupId, value) {
    return root.applyStateBorder(groupId, "selected", "all", value)
  }

  function saveSelectionBorder(groupId, value) {
    root.saveStateBorder(groupId, "selected", "all", value)
  }

  function applyBarSize(axis, value) {
    var key = String(axis) === "v" ? "bar.size-vertical" : "bar.size-horizontal"
    var map = ({})
    map[key] = String(root.clampBarSize(value))
    root.applyMap(map)
    return root.clampBarSize(value)
  }

  function saveBarSize(axis, value) {
    var key = String(axis) === "v" ? "bar.size-vertical" : "bar.size-horizontal"
    var map = ({})
    map[key] = String(root.clampBarSize(value))
    root.upsertToml(map)
  }

  function applySpacingScale(pct) {
    var n = root.clampSpacingPct(pct)
    var map = ({ "spacing.scale": String(n / 100) })
    root.applyMap(map)
    return n
  }

  function saveSpacingScale(pct) {
    var n = root.clampSpacingPct(pct)
    root.upsertToml({ "spacing.scale": String(n / 100) })
  }

  function applySpacingToken(key, value) {
    var map = ({})
    map["spacing." + String(key || "")] = String(root.clampPadding(value))
    root.applyMap(map)
    return root.clampPadding(value)
  }

  function saveSpacingToken(key, value) {
    var map = ({})
    map["spacing." + String(key || "")] = String(root.clampPadding(value))
    root.upsertToml(map)
  }

  function typeName(item) {
    try {
      var s = String(item || "")
      var m = s.match(/^([A-Za-z0-9]+)/)
      if (!m)
        return ""
      return m[1].replace(/_QMLTYPE_.*$/, "").replace(/_QML_.*$/, "")
    } catch (e) {
    }
    return ""
  }

  function classifyItem(item, inherited) {
    var t = root.typeName(item).toLowerCase()
    if (t.indexOf("tooltip") >= 0)
      return "tooltip"
    if (t.indexOf("notification") >= 0)
      return "notifications"
    if (t.indexOf("polkit") >= 0)
      return "polkit"
    if (t.indexOf("lock") >= 0 && t.indexOf("block") < 0)
      return "lock"
    if (t.indexOf("popup") >= 0 || t.indexOf("osd") >= 0 || t.indexOf("keyboardpanel") >= 0)
      return "popups"
    if (t.indexOf("button") >= 0 || t.indexOf("toggle") >= 0 || t.indexOf("textfield") >= 0
        || t.indexOf("dropdown") >= 0 || t.indexOf("numberfield") >= 0
        || t.indexOf("multiselect") >= 0 || t.indexOf("cursorsurface") >= 0)
      return "controls"
    return inherited
  }

  function shouldPatchRadius(item) {
    if (!item)
      return false
    var radius = item.radius
    if (radius === undefined || radius === null)
      return false
    var w = Number(item.width) || 0
    var h = Number(item.height) || 0
    if (w >= 24 && h >= 24)
      return true
    var t = root.typeName(item).toLowerCase()
    if (t.indexOf("tooltip") >= 0 || t.indexOf("button") >= 0 || t.indexOf("toggle") >= 0
        || t.indexOf("textfield") >= 0 || t.indexOf("dropdown") >= 0)
      return true
    if (item.cornerRadius !== undefined && w >= 8 && h >= 8)
      return true
    return false
  }

  function setItemRadius(item, value) {
    var n = root.clampRounding(value)
    try {
      item.radius = n
    } catch (e) {
    }
    try {
      if (item.cornerRadius !== undefined)
        item.cornerRadius = n
    } catch (e2) {
    }
  }

  function visitRadius(item, group, depth) {
    if (!item || depth > 26)
      return
    var gid = root.classifyItem(item, group)
    if (root.shouldPatchRadius(item))
      root.setItemRadius(item, root.roundingOf(gid))
    function walkList(list) {
      if (!list)
        return
      var n = list.length
      if (!n)
        return
      for (var i = 0; i < n; i++) {
        var kid = list[i]
        if (kid && kid !== item)
          root.visitRadius(kid, gid, depth + 1)
      }
    }
    try {
      walkList(item.children)
    } catch (e) {
    }
    try {
      walkList(item.data)
    } catch (e2) {
    }
    try {
      walkList(item.instances)
    } catch (e3) {
    }
    if (item.contentItem && item.contentItem !== item)
      root.visitRadius(item.contentItem, gid, depth + 1)
  }

  function groupForPlugin(pluginId) {
    var s = String(pluginId || "")
    if (s === "omarchy.menu" || s === "omarchy.clipboard" || s === "omarchy.emojis"
        || s === "omarchy.reminders" || s.indexOf("comtrol") >= 0)
      return "menu"
    if (s === "omarchy.notifications")
      return "notifications"
    if (s === "omarchy.polkit")
      return "polkit"
    if (s === "omarchy.lock")
      return "lock"
    if (s === "omarchy.osd" || s === "omarchy.image-picker" || s === "omarchy.agents")
      return "popups"
    if (s.indexOf("omarchy.") === 0)
      return "popups"
    return "menu"
  }

  function loaderItem(loader) {
    if (!loader)
      return null
    try {
      return loader.item
    } catch (e) {
    }
    return null
  }

  function applyLiveRadius() {
    var sh = root.host
    if (!sh)
      return
    try {
      if (sh.bar)
        root.visitRadius(sh.bar, "controls", 0)
    } catch (e) {
    }
    var loaders = sh.panelLoaders || ({})
    for (var id in loaders) {
      var item = root.loaderItem(loaders[id])
      if (item)
        root.visitRadius(item, root.groupForPlugin(id), 0)
    }
    var services = ["omarchy.notifications", "omarchy.polkit", "omarchy.lock"]
    for (var s = 0; s < services.length; s++) {
      var sid = services[s]
      try {
        var svc = sh.serviceFor ? sh.serviceFor(sid) : null
        if (svc)
          root.visitRadius(svc, root.groupForPlugin(sid), 0)
      } catch (e2) {
      }
    }
  }

  function scheduleRadiusApply() {
    applyTimer.restart()
    followupTimer.restart()
    lateTimer.restart()
  }

  function hideNotificationPreview() {
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismiss", root.notifyPreviewSummary])
  }

  function hideOsdPreview() {
    if (!root.previewOwnsOsd)
      return
    root.previewOwnsOsd = false
    try {
      if (root.host && root.host.hide)
        root.host.hide("omarchy.osd")
      else
        Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "omarchy.osd"])
    } catch (e) {
      Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "omarchy.osd"])
    }
  }

  function showNotificationPreview() {
    root.hideNotificationPreview()
    Quickshell.execDetached([
      "omarchy-notification-send",
      "-t", "0",
      "--app-name", "omarchy-action",
      "-u", "low",
      "-g", "󰂚",
      root.notifyPreviewSummary,
      "Opacity, border, and rounding"
    ])
    root.scheduleRadiusApply()
  }

  function showOsdPreview() {
    var payload = JSON.stringify({
      icon: "󰁌",
      message: "Popups preview",
      duration: 0
    })
    var ok = false
    try {
      if (root.host && root.host.summon)
        ok = root.host.summon("omarchy.osd", payload) === true
    } catch (e) {
    }
    if (!ok)
      Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "omarchy.osd", payload])
    root.previewOwnsOsd = true
    root.scheduleRadiusApply()
  }

  function clearPreview() {
    root.hideNotificationPreview()
    root.hideOsdPreview()
    root.previewGroup = ""
    root.previewState = "idle"
  }

  function setPreview(groupId, state) {
    var g = String(groupId || "")
    var s = String(state || "idle")
    if (s !== "idle" && s !== "hover" && s !== "focus" && s !== "selected" && s !== "pressed")
      s = "idle"
    if (g === "menu" || g === "bar" || g === "spacing")
      g = ""
    if (!g || !root.knownGroup(g))
      g = ""
    if (g === root.previewGroup && s === root.previewState)
      return
    root.hideNotificationPreview()
    root.hideOsdPreview()
    root.previewGroup = g
    root.previewState = g ? s : "idle"
    if (g === "notifications")
      root.showNotificationPreview()
    else if (g)
      root.scheduleRadiusApply()
  }

  function upsertToml(assignments) {
    var text = root.readTextFile(root.shellFile)
    var lines = text ? String(text).split("\n") : []
    var remaining = ({})
    for (var k in assignments)
      remaining[k] = true

    function flushSection(out, section) {
      for (var full in remaining) {
        if (!remaining[full])
          continue
        var dot = full.indexOf(".")
        if (dot < 0 || full.substring(0, dot) !== section)
          continue
        out.push(full.substring(dot + 1) + " = " + assignments[full])
        remaining[full] = false
      }
    }

    var section = ""
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var sm = String(line).match(/^\s*\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
      if (sm) {
        if (section)
          flushSection(out, section)
        section = sm[1]
        out.push(line)
        continue
      }
      var km = String(line).match(/^\s*([A-Za-z0-9_-]+)\s*=/)
      if (km && section) {
        var full = section + "." + km[1]
        if (assignments[full] !== undefined) {
          out.push(km[1] + " = " + assignments[full])
          remaining[full] = false
          continue
        }
      }
      out.push(line)
    }
    if (section)
      flushSection(out, section)

    var newSections = []
    var seen = ({})
    for (var full2 in remaining) {
      if (!remaining[full2])
        continue
      var dot2 = full2.indexOf(".")
      if (dot2 < 0)
        continue
      var sec = full2.substring(0, dot2)
      if (seen[sec])
        continue
      seen[sec] = true
      newSections.push(sec)
    }
    for (var s = 0; s < newSections.length; s++) {
      if (out.length && String(out[out.length - 1] || "").length)
        out.push("")
      out.push("[" + newSections[s] + "]")
      flushSection(out, newSections[s])
    }

    var body = out.join("\n")
    if (body.length && body.charAt(body.length - 1) !== "\n")
      body += "\n"
    root.writeTextFile(root.shellFile, body)
  }

  function load() {
    root.scheduleRadiusApply()
  }

  onHostChanged: root.scheduleRadiusApply()

  Component.onCompleted: root.load()

  Connections {
    target: Style
    function onCornerRadiusChanged() {
      root.scheduleRadiusApply()
    }
  }

  Timer {
    id: applyTimer
    interval: 50
    repeat: false
    onTriggered: root.applyLiveRadius()
  }

  Timer {
    id: followupTimer
    interval: 400
    repeat: false
    onTriggered: root.applyLiveRadius()
  }

  Timer {
    id: lateTimer
    interval: 750
    repeat: false
    onTriggered: root.applyLiveRadius()
  }

  PanelWindow {
    id: previewWin
    visible: root.ownedPreview
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "comtrol-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    BorderSurface {
      id: previewFrame
      x: root.previewDockBottom
        ? Math.round((parent.width - width) / 2)
        : parent.width - width - Style.gapsOut
      y: root.previewDockBottom
        ? parent.height - height - Style.space(67)
        : Style.gapsOut + Style.bar.sizeHorizontal
      implicitWidth: Math.max(Style.space(260), previewBody.implicitWidth + Style.spacing.panelPadding * 2)
      implicitHeight: previewBody.implicitHeight + Style.spacing.panelPadding * 2
      radius: root.previewRadius
      color: root.previewFill
      borderSpec: root.previewBorderSpec

      Column {
        id: previewBody
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.panelPadding
        anchors.topMargin: Style.spacing.panelPadding
        width: parent.width - Style.spacing.panelPadding * 2
        spacing: Style.spacing.rowGap

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.previewTitle
          color: root.previewInk
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          visible: root.previewGroup !== "controls"
          width: parent.width
          textFormat: Text.PlainText
          text: "Live preview"
          color: Util.alpha(root.previewInk, 0.7)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }

        Column {
          visible: root.previewGroup === "launcher"
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: ["Browser", "Terminal", "Files"]
            BorderSurface {
              required property int index
              required property string modelData
              width: parent.width
              height: Style.spacing.controlHeight
              radius: Math.max(2, root.previewRadius - 2)
              color: index === 1 ? root.stateFillColor("launcher", root.previewState === "idle" ? "selected" : root.previewState) : "transparent"
              borderSpec: index === 1 ? root.rowBorderSpec("launcher", root.previewState === "idle" ? "selected" : root.previewState) : Border.none()
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                textFormat: Text.PlainText
                text: modelData
                color: index === 1 ? Color.menu.selectedText : root.previewInk
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Flow {
          visible: root.previewGroup === "controls"
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: [
              { id: "idle", label: "Idle" },
              { id: "hover", label: "Hover" },
              { id: "focus", label: "Focus" },
              { id: "selected", label: "Sel" },
              { id: "pressed", label: "Press" }
            ]
            BorderSurface {
              id: chip
              required property var modelData
              width: Style.space(52)
              height: Style.spacing.controlHeight
              radius: Math.max(2, root.previewRadius - 2)
              color: root.liveControlFill(chip.modelData.id)
              borderSpec: root.liveControlSpec(chip.modelData.id)
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: chip.modelData.label
                color: Color.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Rectangle {
          visible: root.previewGroup === "lock" || root.previewGroup === "polkit"
          width: parent.width
          height: Style.space(42)
          radius: Math.max(2, root.previewRadius - 2)
          color: "transparent"
          border.width: root.previewGroup === "lock" ? 3 : Math.max(1, Style.space(2))
          border.color: root.previewGroup === "lock" ? Color.lock.borderActive : Color.polkit.border

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.previewGroup === "lock" ? "••••••••" : "Authentication"
            color: root.previewInk
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  readonly property string previewTitle: {
    var g = root.previewGroup
    if (g === "popups")
      return "Popups"
    if (g === "tooltip")
      return "Tooltip"
    if (g === "controls")
      return "Controls"
    if (g === "launcher")
      return "Launcher"
    if (g === "polkit")
      return "Polkit"
    if (g === "lock")
      return "Lock"
    return "Preview"
  }

  readonly property color previewFill: {
    void Color.shellValues
    void root.liveAlphas
    var g = root.previewGroup
    if (g === "popups")
      return Color.popups.background
    if (g === "tooltip")
      return Color.tooltip.background
    if (g === "polkit")
      return Color.polkit.background
    if (g === "lock")
      return Color.lock.background
    if (g === "controls")
      return Color.popups.background
    return Util.alpha(Color.background, root.alphaOf("launcher", "background") / 100)
  }

  readonly property color previewInk: {
    void Color.shellValues
    var g = root.previewGroup
    if (g === "popups")
      return Color.popups.text
    if (g === "tooltip")
      return Color.tooltip.text
    if (g === "polkit")
      return Color.polkit.text
    if (g === "lock")
      return Color.lock.text
    return Color.menu.text
  }

  readonly property var previewBorderSpec: {
    void root.shellEpoch
    void Color.shellValues
    void root.liveBorders
    void root.liveStateBorders
    var g = root.previewGroup
    var st = root.previewState
    if (g === "controls")
      return root.liveControlSpec(st === "idle" ? "idle" : st)
    if (st && st !== "idle")
      return root.surfaceStateBorderSpec(g, st)
    if (g === "popups")
      return root.specWithLiveWidths("popups", "border", Color.popups.border, root.defaultBorder("popups"))
    if (g === "tooltip")
      return root.specWithLiveWidths("tooltip", "border", Color.tooltip.border, 1)
    if (g === "polkit")
      return root.specWithLiveWidths("polkit", "border", Color.polkit.border, root.defaultBorder("polkit"))
    if (g === "lock")
      return root.specWithLiveWidths("lock", "border", Color.lock.border, 3)
    return root.specWithLiveWidths("launcher", "border", Color.menu.border, root.defaultBorder("launcher"))
  }

  function selectedBorderSpecOf(groupId) {
    void root.shellEpoch
    void Color.shellValues
    void Color.menu.selectedBorder
    void root.liveSelection
    var id = String(groupId || "menu")
    var w = root.selectionBorderOf(id)
    var spec = Border.surfaceSpec(id, "selected-border", Color.menu.selectedBorder, 0)
    if (!spec)
      spec = Border.flat(Color.menu.selectedBorder, 0)
    spec.widths = ({ top: w, right: w, bottom: w, left: w })
    return spec
  }

  function liveControlSpec(state) {
    void root.shellEpoch
    void Color.shellValues
    void root.liveStateBorders
    void Style.normalBorderWidth
    void Style.hoverBorderWidth
    void Style.selectedBorderWidth
    void Style.focusBorderWidth
    var s = String(state || "idle")
    if (s === "normal")
      s = "idle"
    var specState = s === "idle" ? "normal" : s
    var spec = Border.controlSpec(specState, Color.foreground, Color.accent)
    if (!spec)
      spec = Border.flat(Color.foreground, 0)
    spec.widths = root.controlLiveWidths(s)
    return spec
  }

  function liveControlFill(state) {
    void root.shellEpoch
    void Color.shellValues
    void root.liveStateFills
    return root.controlPreviewFill(state)
  }

  function controlPreviewFill(state) {
    var s = String(state || "idle")
    if (s === "normal")
      s = "idle"
    var a = root.fillOf(s) / 100
    if (s === "hover")
      return Util.alpha(Style.hoverStateColor(Color.foreground, Color.accent), a)
    if (s === "focus")
      return Util.alpha(Style.focusStateColor(Color.foreground, Color.accent), a)
    if (s === "selected")
      return Util.alpha(Style.selectedStateColor(Color.foreground, Color.accent), a)
    if (s === "pressed")
      return Util.alpha(Style.pressedStateColor(Color.foreground, Color.accent), a)
    return Util.alpha(Style.normalStateColor(Color.foreground, Color.accent), a)
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
