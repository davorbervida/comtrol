import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Appearance → Desktop: bar, blur, look (gaps/border/rounding/shadow), opacity.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property string itemId: "desktop"
  readonly property string barItemId: "desktop.bar"
  readonly property string positionItemId: "desktop.bar.position"
  readonly property string transparencyItemId: "desktop.bar.transparency"
  readonly property string blurItemId: "desktop.blur"
  readonly property string gapsItemId: "desktop.look.gaps"
  readonly property string borderItemId: "desktop.look.border"
  readonly property string roundingItemId: "desktop.look.rounding"
  readonly property string shadowItemId: "desktop.look.shadow"
  readonly property string transitionsItemId: "desktop.look.transitions"
  readonly property string opacityItemId: "desktop.opacity"
  readonly property string globalOpacityItemId: "desktop.opacity.global"
  readonly property string resetOpacityItemId: "desktop.opacity.reset"
  readonly property string label: "Desktop"
  readonly property string icon: "󰇄"
  readonly property string title: "Desktop"

  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/comtrol/opacity_groups.py"

  readonly property int minBlur: 0
  readonly property int maxBlur: 20
  readonly property int minGaps: 0
  readonly property int maxGaps: 20
  readonly property int minBorder: 0
  readonly property int maxBorder: 10
  readonly property int minRounding: 0
  readonly property int maxRounding: 24
  readonly property int minTransitions: 0
  readonly property int maxTransitions: 1000
  readonly property int minOpacity: 50
  readonly property int maxOpacity: 100
  readonly property int sliderRowHeight: Math.max(
    Style.space(72),
    Style.font.caption + Style.spacing.controlGap + Math.max(Style.space(22), Math.round(Style.spacing.controlHeight * 0.38) + Style.spacing.md)
  )

  property string position: "top"
  property bool transparent: false

  property int previewBlur: -1
  property int pendingBlur: -1
  property int appliedBlur: -1
  property int liveBlur: 0
  property bool appliedBlurEnabled: false
  property bool haveAppliedBlurEnabled: false

  property int previewGaps: -1
  property int pendingGaps: -1
  property int liveGaps: 5
  property int previewBorder: -1
  property int pendingBorder: -1
  property int liveBorder: 2
  property int previewRounding: -1
  property int pendingRounding: -1
  property int liveRounding: 0
  property int previewTransitions: -1
  property int pendingTransitions: -1
  property int liveTransitions: 400
  property bool liveShadow: false
  property bool pendingShadow: false
  property bool havePendingShadow: false

  property var opacityGroups: []
  property string activeOpacityGroupId: ""
  property string pendingOpacityGroupId: ""
  property int pendingOpacityActive: -1
  property int pendingOpacityInactive: -1
  property var previewOpacity: ({})
  property int liveGlobalActive: 100
  property int liveGlobalInactive: 100
  property bool pendingOpacityAll: false

  readonly property int displayedBlur: {
    if (root.previewBlur >= 0)
      return root.previewBlur
    return Math.max(root.minBlur, Math.min(root.maxBlur, root.liveBlur))
  }
  readonly property int displayedGaps: {
    if (root.previewGaps >= 0)
      return root.previewGaps
    return Math.max(root.minGaps, Math.min(root.maxGaps, root.liveGaps))
  }
  readonly property int displayedBorder: {
    if (root.previewBorder >= 0)
      return root.previewBorder
    return Math.max(root.minBorder, Math.min(root.maxBorder, root.liveBorder))
  }
  readonly property int displayedRounding: {
    if (root.previewRounding >= 0)
      return root.previewRounding
    return Math.max(root.minRounding, Math.min(root.maxRounding, root.liveRounding))
  }
  readonly property int displayedTransitions: {
    if (root.previewTransitions >= 0)
      return root.previewTransitions
    return Math.max(root.minTransitions, Math.min(root.maxTransitions, root.liveTransitions))
  }
  readonly property bool displayedShadow: root.havePendingShadow ? root.pendingShadow : root.liveShadow
  readonly property string shadowLabel: root.displayedShadow ? "On" : "Off"

  readonly property string positionLabel: {
    var p = String(root.position || "top").toLowerCase()
    if (p === "bottom")
      return "Bottom"
    if (p === "left")
      return "Left"
    if (p === "right")
      return "Right"
    return "Top"
  }
  readonly property string transparencyLabel: root.transparent ? "On" : "Off"

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property var menu: ({
    title: root.title,
    rows: [
      {
        itemId: root.positionItemId,
        label: "Bar position",
        icon: "",
        kind: "menu",
        status: root.positionLabel
      },
      {
        itemId: root.transparencyItemId,
        label: "Bar transparency",
        icon: "󰂵",
        kind: "bar-transparency",
        status: root.transparencyLabel
      },
      { itemId: root.blurItemId, label: "Blur", kind: "slider" },
      { itemId: root.gapsItemId, label: "Gaps", kind: "slider" },
      { itemId: root.borderItemId, label: "Border", kind: "slider" },
      { itemId: root.roundingItemId, label: "Rounding", kind: "slider" },
      { itemId: root.transitionsItemId, label: "Transitions", kind: "slider" },
      {
        itemId: root.shadowItemId,
        label: "Shadow",
        icon: "󰖨",
        kind: "look-shadow",
        status: root.shadowLabel
      },
      { itemId: root.opacityItemId, label: "Opacity", icon: "󰂵", kind: "menu" }
    ]
  })

  readonly property var positionMenu: ({
    title: "Bar position",
    rows: [
      root.positionRow("top", "Top", "󰁝"),
      root.positionRow("bottom", "Bottom", "󰁅"),
      root.positionRow("left", "Left", "󰁍"),
      root.positionRow("right", "Right", "󰁔")
    ]
  })

  readonly property var opacityMenu: {
    var rows = [
      {
        itemId: root.globalOpacityItemId,
        label: "Global",
        icon: "󰒓",
        kind: "menu",
        status: root.opacityStatus("global")
      }
    ]
    for (var i = 0; i < root.opacityGroups.length; i++) {
      var g = root.opacityGroups[i]
      if (String(g.id) === "default")
        continue
      rows.push({
        itemId: root.opacityGroupMenuId(g.id),
        label: g.label,
        icon: g.icon || "󰂵",
        kind: "menu",
        status: root.opacityStatus(g.id)
      })
    }
    rows.push({
      itemId: root.resetOpacityItemId,
      label: "Reset defaults",
      icon: "󰑓",
      kind: "opacity-reset"
    })
    return { title: "Opacity", rows: rows }
  }

  signal changed()

  function opacityGroupMenuId(groupId) {
    return root.opacityItemId + "." + String(groupId || "")
  }

  function opacityActiveItemId(groupId) {
    return root.opacityGroupMenuId(groupId) + ".active"
  }

  function opacityInactiveItemId(groupId) {
    return root.opacityGroupMenuId(groupId) + ".inactive"
  }

  function isOpacityGroupMenu(menuId) {
    var id = String(menuId || "")
    if (id === root.globalOpacityItemId)
      return true
    return id.indexOf(root.opacityItemId + ".") === 0
      && id.indexOf(".active") < 0
      && id.indexOf(".inactive") < 0
      && id !== root.opacityItemId
      && id !== root.resetOpacityItemId
  }

  function groupIdFromMenu(menuId) {
    var id = String(menuId || "")
    var prefix = root.opacityItemId + "."
    if (id.indexOf(prefix) !== 0)
      return ""
    return id.substring(prefix.length)
  }

  function groupIdFromSlider(itemId) {
    var id = String(itemId || "")
    if (id.indexOf(root.opacityItemId + ".") !== 0)
      return ""
    if (id.slice(-7) === ".active")
      return id.substring((root.opacityItemId + ".").length, id.length - 7)
    if (id.slice(-9) === ".inactive")
      return id.substring((root.opacityItemId + ".").length, id.length - 9)
    return ""
  }

  function opacityGroupMenus() {
    var out = ({})
    out[root.opacityItemId] = root.opacityMenu
    out[root.globalOpacityItemId] = {
      title: "Global",
      rows: [
        { itemId: root.opacityActiveItemId("global"), label: "Active", kind: "slider" },
        { itemId: root.opacityInactiveItemId("global"), label: "Inactive", kind: "slider" }
      ]
    }
    for (var i = 0; i < root.opacityGroups.length; i++) {
      var g = root.opacityGroups[i]
      var mid = root.opacityGroupMenuId(g.id)
      out[mid] = {
        title: g.label,
        rows: [
          { itemId: root.opacityActiveItemId(g.id), label: "Active", kind: "slider" },
          { itemId: root.opacityInactiveItemId(g.id), label: "Inactive", kind: "slider" }
        ]
      }
    }
    return out
  }

  function isLookSlider(itemId) {
    var id = String(itemId || "")
    return id === root.gapsItemId || id === root.borderItemId
      || id === root.roundingItemId || id === root.transitionsItemId
  }

  function isDesktopSlider(itemId) {
    var id = String(itemId || "")
    return id === root.blurItemId || root.isLookSlider(id) || !!root.groupIdFromSlider(id)
  }

  function findGroup(groupId) {
    var id = String(groupId || "")
    for (var i = 0; i < root.opacityGroups.length; i++) {
      if (String(root.opacityGroups[i].id) === id)
        return root.opacityGroups[i]
    }
    return null
  }

  function clampOpacityPercent(value) {
    var next = Math.round(Number(value))
    if (!isFinite(next))
      return root.minOpacity
    return Math.max(root.minOpacity, Math.min(root.maxOpacity, next))
  }

  function displayedOpacity(groupId, channel) {
    var key = String(groupId || "") + ":" + String(channel || "")
    if (root.previewOpacity && root.previewOpacity[key] !== undefined)
      return root.clampOpacityPercent(root.previewOpacity[key])
    if (String(groupId) === "global")
      return root.clampOpacityPercent(channel === "inactive" ? root.liveGlobalInactive : root.liveGlobalActive)
    var g = root.findGroup(groupId)
    if (!g)
      return root.maxOpacity
    return root.clampOpacityPercent(channel === "inactive" ? g.inactive : g.active)
  }

  function syncGlobalFromGroups() {
    if (!root.opacityGroups.length) {
      root.liveGlobalActive = 100
      root.liveGlobalInactive = 100
      return
    }
    var a0 = root.clampOpacityPercent(root.opacityGroups[0].active)
    var i0 = root.clampOpacityPercent(root.opacityGroups[0].inactive)
    var sameA = true
    var sameI = true
    var sumA = 0
    var sumI = 0
    for (var i = 0; i < root.opacityGroups.length; i++) {
      var a = root.clampOpacityPercent(root.opacityGroups[i].active)
      var n = root.clampOpacityPercent(root.opacityGroups[i].inactive)
      sumA += a
      sumI += n
      if (a !== a0)
        sameA = false
      if (n !== i0)
        sameI = false
    }
    root.liveGlobalActive = sameA ? a0 : Math.round(sumA / root.opacityGroups.length)
    root.liveGlobalInactive = sameI ? i0 : Math.round(sumI / root.opacityGroups.length)
  }

  function opacityStatus(groupId) {
    return root.displayedOpacity(groupId, "active") + "/" + root.displayedOpacity(groupId, "inactive") + "%"
  }

  function positionRow(id, name, icon) {
    return {
      itemId: id,
      label: name,
      icon: root.position === id ? "✓" : icon,
      kind: "bar-position"
    }
  }

  function applyShellJson(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      var bar = (data && data.bar) || {}
      var nextPos = String(bar.position || "top").toLowerCase()
      if (nextPos !== "top" && nextPos !== "bottom" && nextPos !== "left" && nextPos !== "right")
        nextPos = "top"
      var nextTrans = bar.transparent === true
      if (nextPos === root.position && nextTrans === root.transparent)
        return
      root.position = nextPos
      root.transparent = nextTrans
      root.changed()
    } catch (e) {
    }
  }

  function applyBlurStatus(text) {
    var parts = String(text || "").split("\t")
    var enabled = false
    var size = 0
    try {
      var e = JSON.parse(parts[0] || "{}")
      enabled = e.bool === true
    } catch (err) {
    }
    try {
      var s = JSON.parse(parts[1] || "{}")
      size = Math.round(Number(s.int || 0))
    } catch (err2) {
    }
    if (!isFinite(size) || size < 0)
      size = 0
    var next = enabled ? Math.max(root.minBlur, Math.min(root.maxBlur, size)) : 0
    root.liveBlur = next
    if (root.previewBlur >= 0 && root.liveBlur === root.previewBlur)
      root.previewBlur = -1
  }

  function applyLookStatus(text) {
    var parts = String(text || "").split("\t")
    function parseIntOpt(raw, fallback) {
      try {
        var o = JSON.parse(raw || "{}")
        if (o.int !== undefined && o.int !== null) {
          var n = Math.round(Number(o.int))
          if (isFinite(n))
            return n
        }
        // gaps_* often come back as css: "5 5 5 5"
        if (o.css !== undefined && o.css !== null) {
          var css = String(o.css).trim().split(/\s+/)
          var c = Math.round(Number(css[0]))
          if (isFinite(c))
            return c
        }
      } catch (e) {
      }
      return fallback
    }
    function parseBoolOpt(raw, fallback) {
      try {
        var o = JSON.parse(raw || "{}")
        if (o.bool === true || o.bool === false)
          return o.bool === true
      } catch (e) {
      }
      return fallback
    }
    root.liveGaps = Math.max(root.minGaps, Math.min(root.maxGaps, parseIntOpt(parts[0], root.liveGaps)))
    root.liveBorder = Math.max(root.minBorder, Math.min(root.maxBorder, parseIntOpt(parts[1], root.liveBorder)))
    root.liveRounding = Math.max(root.minRounding, Math.min(root.maxRounding, parseIntOpt(parts[2], root.liveRounding)))
    root.liveShadow = parseBoolOpt(parts[3], root.liveShadow)
    root.liveTransitions = Math.max(root.minTransitions, Math.min(root.maxTransitions, parseIntOpt(parts[4], root.liveTransitions)))
    if (root.previewGaps >= 0 && root.liveGaps === root.previewGaps)
      root.previewGaps = -1
    if (root.previewBorder >= 0 && root.liveBorder === root.previewBorder)
      root.previewBorder = -1
    if (root.previewRounding >= 0 && root.liveRounding === root.previewRounding)
      root.previewRounding = -1
    if (root.previewTransitions >= 0 && root.liveTransitions === root.previewTransitions)
      root.previewTransitions = -1
    if (root.havePendingShadow && root.pendingShadow === root.liveShadow) {
      root.havePendingShadow = false
    }
    root.changed()
  }

  function applyOpacityScan(text) {
    try {
      var data = JSON.parse(String(text || "{}"))
      var groups = data.groups || []
      var next = []
      for (var i = 0; i < groups.length; i++) {
        var g = groups[i] || {}
        next.push({
          id: String(g.id || ""),
          label: String(g.label || g.id || ""),
          icon: String(g.icon || "󰂵"),
          active: root.clampOpacityPercent(g.active),
          inactive: root.clampOpacityPercent(g.inactive),
          rules: g.rules || []
        })
      }
      root.opacityGroups = next
      root.previewOpacity = ({})
      root.syncGlobalFromGroups()
      root.changed()
    } catch (e) {
    }
  }

  function resetOpacityDefaults() {
    if (opacityResetProc.running)
      return
    opacityResetProc.command = ["python3", root.scriptPath, "reset"]
    opacityResetProc.running = true
  }

  function loadDesktop() {
    root.loadBlur()
    root.loadLook()
    root.loadOpacityGroups()
  }

  function loadBlur() {
    if (!blurReadProc.running)
      blurReadProc.running = true
  }

  function loadLook() {
    if (!lookReadProc.running)
      lookReadProc.running = true
  }

  function loadOpacityGroups() {
    if (opacityScanProc.running)
      return
    opacityScanProc.command = ["python3", root.scriptPath, "scan"]
    opacityScanProc.running = true
  }

  function setPosition(name) {
    var p = String(name || "").toLowerCase()
    if (p !== "top" && p !== "bottom" && p !== "left" && p !== "right")
      return
    if (p === root.position)
      return
    root.position = p
    root.changed()
    Quickshell.execDetached(["omarchy-bar", "position", p])
  }

  function toggleTransparency() {
    root.transparent = !root.transparent
    root.changed()
    Quickshell.execDetached(["omarchy-bar", "transparent", "toggle"])
  }

  function setBlur(value, persist) {
    var next = Math.round(Number(value))
    if (!isFinite(next))
      return
    next = Math.max(root.minBlur, Math.min(root.maxBlur, next))
    root.previewBlur = next
    root.liveBlur = next
    root.pendingBlur = next
    liveBlurTimer.restart()
    blurPersistTimer.interval = persist ? 80 : 450
    blurPersistTimer.restart()
  }

  function adjustBlur(delta) {
    root.setBlur(root.displayedBlur + delta, true)
  }

  function clampLook(value, minV, maxV) {
    var next = Math.round(Number(value))
    if (!isFinite(next))
      return minV
    return Math.max(minV, Math.min(maxV, next))
  }

  function setGaps(value, persist) {
    var next = root.clampLook(value, root.minGaps, root.maxGaps)
    root.previewGaps = next
    root.liveGaps = next
    root.pendingGaps = next
    liveLookTimer.restart()
    lookPersistTimer.interval = persist ? 80 : 450
    lookPersistTimer.restart()
    root.changed()
  }

  function setBorder(value, persist) {
    var next = root.clampLook(value, root.minBorder, root.maxBorder)
    root.previewBorder = next
    root.liveBorder = next
    root.pendingBorder = next
    liveLookTimer.restart()
    lookPersistTimer.interval = persist ? 80 : 450
    lookPersistTimer.restart()
    root.changed()
  }

  function setRounding(value, persist) {
    var next = root.clampLook(value, root.minRounding, root.maxRounding)
    root.previewRounding = next
    root.liveRounding = next
    root.pendingRounding = next
    liveLookTimer.restart()
    lookPersistTimer.interval = persist ? 80 : 450
    lookPersistTimer.restart()
    root.changed()
  }

  function setTransitions(value, persist) {
    var next = root.clampLook(value, root.minTransitions, root.maxTransitions)
    // Snap to 50ms steps for a usable ms control (0 stays Off).
    if (next > 0)
      next = Math.round(next / 50) * 50
    next = root.clampLook(next, root.minTransitions, root.maxTransitions)
    root.previewTransitions = next
    root.liveTransitions = next
    root.pendingTransitions = next
    liveLookTimer.restart()
    lookPersistTimer.interval = persist ? 80 : 450
    lookPersistTimer.restart()
    root.changed()
  }

  function toggleShadow() {
    var next = !root.displayedShadow
    root.pendingShadow = next
    root.havePendingShadow = true
    root.liveShadow = next
    liveLookTimer.restart()
    lookPersistTimer.interval = 80
    lookPersistTimer.restart()
    root.changed()
  }

  function displayedLook(role) {
    if (role === "gaps")
      return root.displayedGaps
    if (role === "border")
      return root.displayedBorder
    if (role === "rounding")
      return root.displayedRounding
    if (role === "transitions")
      return root.displayedTransitions
    return 0
  }

  function setLookRole(role, value, persist) {
    if (role === "gaps")
      root.setGaps(value, persist)
    else if (role === "border")
      root.setBorder(value, persist)
    else if (role === "rounding")
      root.setRounding(value, persist)
    else if (role === "transitions")
      root.setTransitions(value, persist)
  }

  function updateGroupValue(groupId, channel, value) {
    var next = root.clampOpacityPercent(value)
    var groups = []
    for (var i = 0; i < root.opacityGroups.length; i++) {
      var src = root.opacityGroups[i]
      if (String(src.id) !== String(groupId)) {
        groups.push(src)
        continue
      }
      groups.push({
        id: src.id,
        label: src.label,
        icon: src.icon,
        active: channel === "inactive" ? src.active : next,
        inactive: channel === "inactive" ? next : src.inactive,
        rules: src.rules
      })
    }
    root.opacityGroups = groups
  }

  function updateAllGroupValues(channel, value) {
    var next = root.clampOpacityPercent(value)
    var groups = []
    for (var i = 0; i < root.opacityGroups.length; i++) {
      var src = root.opacityGroups[i]
      groups.push({
        id: src.id,
        label: src.label,
        icon: src.icon,
        active: channel === "inactive" ? src.active : next,
        inactive: channel === "inactive" ? next : src.inactive,
        rules: src.rules
      })
    }
    root.opacityGroups = groups
    if (channel === "inactive")
      root.liveGlobalInactive = next
    else
      root.liveGlobalActive = next
  }

  function setGroupOpacity(groupId, channel, value, persist) {
    if (String(groupId) === "global") {
      root.setGlobalOpacity(channel, value, persist)
      return
    }
    var next = root.clampOpacityPercent(value)
    var key = String(groupId) + ":" + String(channel)
    var preview = ({})
    for (var k in root.previewOpacity)
      preview[k] = root.previewOpacity[k]
    preview[key] = next
    root.previewOpacity = preview
    root.updateGroupValue(groupId, channel, next)
    root.pendingOpacityAll = false
    root.pendingOpacityGroupId = String(groupId)
    root.pendingOpacityActive = root.displayedOpacity(groupId, "active")
    root.pendingOpacityInactive = root.displayedOpacity(groupId, "inactive")
    if (channel === "active")
      root.pendingOpacityActive = next
    else
      root.pendingOpacityInactive = next
    liveOpacityTimer.restart()
    opacityPersistTimer.interval = persist ? 80 : 450
    opacityPersistTimer.restart()
    root.syncGlobalFromGroups()
    root.changed()
  }

  function setGlobalOpacity(channel, value, persist) {
    var next = root.clampOpacityPercent(value)
    var key = "global:" + String(channel)
    var preview = ({})
    for (var k in root.previewOpacity)
      preview[k] = root.previewOpacity[k]
    preview[key] = next
    // Keep per-group previews aligned so status rows update while dragging.
    for (var i = 0; i < root.opacityGroups.length; i++) {
      var gid = String(root.opacityGroups[i].id)
      preview[gid + ":" + String(channel)] = next
    }
    root.previewOpacity = preview
    root.updateAllGroupValues(channel, next)
    root.pendingOpacityAll = true
    root.pendingOpacityGroupId = "global"
    root.pendingOpacityActive = root.liveGlobalActive
    root.pendingOpacityInactive = root.liveGlobalInactive
    liveOpacityTimer.restart()
    opacityPersistTimer.interval = persist ? 80 : 450
    opacityPersistTimer.restart()
    root.changed()
  }

  function adjustSlider(itemId, delta) {
    if (itemId === root.blurItemId) {
      root.adjustBlur(delta)
      return
    }
    if (itemId === root.gapsItemId) {
      root.setGaps(root.displayedGaps + delta, true)
      return
    }
    if (itemId === root.borderItemId) {
      root.setBorder(root.displayedBorder + delta, true)
      return
    }
    if (itemId === root.roundingItemId) {
      root.setRounding(root.displayedRounding + delta, true)
      return
    }
    if (itemId === root.transitionsItemId) {
      root.setTransitions(root.displayedTransitions + (delta > 0 ? 50 : -50), true)
      return
    }
    var gid = root.groupIdFromSlider(itemId)
    if (!gid)
      return
    var channel = String(itemId).slice(-7) === ".active" ? "active" : "inactive"
    root.setGroupOpacity(gid, channel, root.displayedOpacity(gid, channel) + delta, true)
  }

  function blurPasses(size) {
    if (size <= 0)
      return 1
    return Math.max(1, Math.min(5, Math.ceil(size / 4)))
  }

  function blurLua(enabled, size, passes) {
    var config = enabled
      ? ("hl.config({ decoration = { blur = { enabled = true, size = "
        + size + ", passes = " + passes + ", ignore_opacity = true } } })")
      : "hl.config({ decoration = { blur = { enabled = false } } })"
    var layer = enabled
      ? 'hl.layer_rule({ name = "comtrol-blur", match = { namespace = "comtrol-menu" }, blur = true, ignore_alpha = 0 })'
      : 'hl.layer_rule({ name = "comtrol-blur", match = { namespace = "comtrol-menu" }, blur = false })'
    return config + "; " + layer
  }

  function flushBlur() {
    var next = root.pendingBlur
    if (next < 0)
      return
    var enabled = next > 0
    var size = enabled ? next : 1
    var passes = root.blurPasses(next)
    root.appliedBlur = next
    Util.execArgv(["hyprctl", "eval", root.blurLua(enabled, size, passes)])
    if (!root.haveAppliedBlurEnabled || enabled !== root.appliedBlurEnabled) {
      root.haveAppliedBlurEnabled = true
      root.appliedBlurEnabled = enabled
      blurPersistTimer.interval = 1
      blurPersistTimer.restart()
    }
  }

  function lookLua(gaps, border, rounding, shadow, transitions) {
    var gout = gaps <= 0 ? 0 : gaps * 2
    var ms = Math.max(0, Math.round(Number(transitions) || 0))
    var enabled = ms > 0
    // Hyprland animation SPEED unit ≈ 100ms.
    var speed = enabled ? (Math.max(1, Math.round((ms / 100) * 100) / 100)) : 1
    var animConfig = "hl.config({ animations = { enabled = " + (enabled ? "true" : "false") + " } })"
    var animGlobal = enabled
      ? ("; hl.animation({ leaf = \"global\", enabled = true, speed = " + speed + ", bezier = \"default\" })")
      : ""
    return "hl.config({ general = { gaps_in = " + gaps
      + ", gaps_out = " + gout
      + ", border_size = " + border
      + " }, decoration = { rounding = " + rounding
      + ", shadow = { enabled = " + (shadow ? "true" : "false")
      + " } } }); " + animConfig + animGlobal
  }

  function flushLook() {
    var gaps = root.pendingGaps >= 0 ? root.pendingGaps : root.displayedGaps
    var border = root.pendingBorder >= 0 ? root.pendingBorder : root.displayedBorder
    var rounding = root.pendingRounding >= 0 ? root.pendingRounding : root.displayedRounding
    var transitions = root.pendingTransitions >= 0 ? root.pendingTransitions : root.displayedTransitions
    var shadow = root.displayedShadow
    Util.execArgv(["hyprctl", "eval", root.lookLua(gaps, border, rounding, shadow, transitions)])
  }

  function flushOpacity() {
    var gid = root.pendingOpacityGroupId
    if (!gid)
      return
    if (root.pendingOpacityAll || gid === "global") {
      var tmp = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/comtrol-opacity-eval.json"
      var payload = JSON.stringify({ groups: root.opacityGroups })
      if (opacityEvalProc.running)
        opacityEvalProc.running = false
      opacityEvalProc.command = [
        "bash", "-lc",
        "printf %s " + Util.shellQuote(payload) + " > " + Util.shellQuote(tmp)
          + " && lua=$(python3 " + Util.shellQuote(root.scriptPath) + " eval-all @" + Util.shellQuote(tmp)
          + ") && hyprctl eval \"$lua\""
      ]
      opacityEvalProc.running = true
      return
    }
    var active = root.pendingOpacityActive >= 0 ? root.pendingOpacityActive : root.displayedOpacity(gid, "active")
    var inactive = root.pendingOpacityInactive >= 0 ? root.pendingOpacityInactive : root.displayedOpacity(gid, "inactive")
    active = root.clampOpacityPercent(active)
    inactive = root.clampOpacityPercent(inactive)
    if (opacityEvalProc.running)
      opacityEvalProc.running = false
    opacityEvalProc.command = ["bash", "-lc",
      "lua=$(python3 " + Util.shellQuote(root.scriptPath) + " eval-lua "
      + Util.shellQuote(gid) + " " + String(active) + " " + String(inactive)
      + ") && hyprctl eval \"$lua\""
    ]
    opacityEvalProc.running = true
  }

  function persistBlurPending() {
    var next = root.pendingBlur
    if (next < 0)
      next = root.displayedBlur
    var enabled = next > 0
    var size = enabled ? next : 1
    var passes = root.blurPasses(next)
    root.persistBlur(enabled, size, passes)
  }

  function persistLookPending() {
    var gaps = root.pendingGaps >= 0 ? root.pendingGaps : root.displayedGaps
    var border = root.pendingBorder >= 0 ? root.pendingBorder : root.displayedBorder
    var rounding = root.pendingRounding >= 0 ? root.pendingRounding : root.displayedRounding
    var transitions = root.pendingTransitions >= 0 ? root.pendingTransitions : root.displayedTransitions
    var shadow = root.displayedShadow
    root.persistLook(gaps, border, rounding, shadow, transitions)
  }

  function persistOpacityPending() {
    var payload = JSON.stringify({ groups: root.opacityGroups })
    var tmp = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    tmp = tmp + "/comtrol-opacity-groups.json"
    if (opacitySaveProc.running)
      opacitySaveProc.running = false
    opacitySaveProc.command = [
      "bash", "-lc",
      "printf %s " + Util.shellQuote(payload) + " > " + Util.shellQuote(tmp)
        + " && python3 " + Util.shellQuote(root.scriptPath) + " save @" + Util.shellQuote(tmp)
    ]
    opacitySaveProc.running = true
  }

  function persistBlur(enabled, size, passes) {
    Util.execArgv([
      "python3", "-c",
      [
        "import pathlib, subprocess, sys",
        "enabled, size, passes = sys.argv[1], sys.argv[2], sys.argv[3]",
        "def upsert(path, begin, end, block):",
        "    path = pathlib.Path(path)",
        "    text = path.read_text() if path.exists() else ''",
        "    start = text.find(begin)",
        "    if not block:",
        "        if start < 0:",
        "            return False",
        "        stop = text.find(end, start)",
        "        if stop < 0:",
        "            return False",
        "        stop += len(end)",
        "        if stop < len(text) and text[stop] == '\\n':",
        "            stop += 1",
        "        nxt = text[:start] + text[stop:]",
        "        if nxt == text:",
        "            return False",
        "        path.write_text(nxt)",
        "        return True",
        "    if not block.endswith('\\n'):",
        "        block += '\\n'",
        "    if start >= 0:",
        "        stop = text.find(end, start)",
        "        if stop >= 0:",
        "            stop += len(end)",
        "            if stop < len(text) and text[stop] == '\\n':",
        "                stop += 1",
        "            nxt = text[:start] + block + text[stop:]",
        "        else:",
        "            nxt = text.rstrip() + '\\n\\n' + block",
        "    else:",
        "        nxt = text",
        "        if nxt and not nxt.endswith('\\n'):",
        "            nxt += '\\n'",
        "        nxt += ('\\n' if nxt else '') + block",
        "    if nxt == text:",
        "        return False",
        "    path.parent.mkdir(parents=True, exist_ok=True)",
        "    path.write_text(nxt)",
        "    return True",
        "hypr = (",
        "    '-- BEGIN COMTROL-BLUR\\n'",
        "    'hl.config({\\n'",
        "    '  decoration = {\\n'",
        "    '    blur = {\\n'",
        "    f'      enabled = {enabled},\\n'",
        "    f'      size = {size},\\n'",
        "    f'      passes = {passes},\\n'",
        "    '      ignore_opacity = true,\\n'",
        "    '    },\\n'",
        "    '  },\\n'",
        "    '})\\n'",
        "    'hl.layer_rule({\\n'",
        "    '  name = \"comtrol-blur\",\\n'",
        "    '  match = { namespace = \"comtrol-menu\" },\\n'",
        "    f'  blur = {enabled},\\n'",
        "    '  ignore_alpha = 0,\\n'",
        "    '})\\n'",
        "    '-- END COMTROL-BLUR'",
        ")",
        "upsert(pathlib.Path.home() / '.config/hypr/looknfeel.lua', '-- BEGIN COMTROL-BLUR', '-- END COMTROL-BLUR', hypr)",
        "foot_block = '' if enabled != 'true' else (",
        "    '# BEGIN COMTROL-BLUR\\n'",
        "    '[colors-dark]\\n'",
        "    'alpha=0.80\\n'",
        "    'alpha-mode=default\\n'",
        "    'blur=yes\\n'",
        "    '[colors-light]\\n'",
        "    'alpha=0.80\\n'",
        "    'alpha-mode=default\\n'",
        "    'blur=yes\\n'",
        "    '# END COMTROL-BLUR'",
        ")",
        "foot = pathlib.Path.home() / '.config/foot/foot.ini'",
        "if foot.exists() and upsert(foot, '# BEGIN COMTROL-BLUR', '# END COMTROL-BLUR', foot_block):",
        "    subprocess.run(['pkill', '-USR1', '-x', 'foot'], check=False)",
        "    subprocess.run(['pkill', '-USR1', '-x', 'footclient'], check=False)"
      ].join("\n"),
      enabled ? "true" : "false",
      String(size),
      String(passes)
    ])
  }

  function persistLook(gaps, border, rounding, shadow, transitions) {
    var ms = Math.max(0, Math.round(Number(transitions) || 0))
    var enabled = ms > 0
    var speed = enabled ? (Math.max(1, Math.round((ms / 100) * 100) / 100)) : 1
    Util.execArgv([
      "python3", "-c",
      [
        "import pathlib, sys",
        "gaps, border, rounding, shadow, enabled, speed = sys.argv[1:7]",
        "gout = '0' if int(gaps) <= 0 else str(int(gaps) * 2)",
        "def upsert(path, begin, end, block):",
        "    path = pathlib.Path(path)",
        "    text = path.read_text() if path.exists() else ''",
        "    start = text.find(begin)",
        "    if not block.endswith('\\n'):",
        "        block += '\\n'",
        "    if start >= 0:",
        "        stop = text.find(end, start)",
        "        if stop >= 0:",
        "            stop += len(end)",
        "            if stop < len(text) and text[stop] == '\\n':",
        "                stop += 1",
        "            nxt = text[:start] + block + text[stop:]",
        "        else:",
        "            nxt = text.rstrip() + '\\n\\n' + block",
        "    else:",
        "        nxt = text",
        "        if nxt and not nxt.endswith('\\n'):",
        "            nxt += '\\n'",
        "        nxt += ('\\n' if nxt else '') + block",
        "    if nxt == text:",
        "        return False",
        "    path.parent.mkdir(parents=True, exist_ok=True)",
        "    path.write_text(nxt)",
        "    return True",
        "if enabled == 'true':",
        "    anim = (",
        "        'hl.config({\\n'",
        "        '  animations = {\\n'",
        "        '    enabled = true,\\n'",
        "        '  },\\n'",
        "        '})\\n'",
        "        + f'hl.animation({{ leaf = \"global\", enabled = true, speed = {speed}, bezier = \"default\" }})\\n'",
        "    )",
        "else:",
        "    anim = (",
        "        'hl.config({\\n'",
        "        '  animations = {\\n'",
        "        '    enabled = false,\\n'",
        "        '  },\\n'",
        "        '})\\n'",
        "    )",
        "hypr = (",
        "    '-- BEGIN COMTROL-LOOK\\n'",
        "    'hl.config({\\n'",
        "    '  general = {\\n'",
        "    f'    gaps_in = {gaps},\\n'",
        "    f'    gaps_out = {gout},\\n'",
        "    f'    border_size = {border},\\n'",
        "    '  },\\n'",
        "    '  decoration = {\\n'",
        "    f'    rounding = {rounding},\\n'",
        "    '    shadow = {\\n'",
        "    f'      enabled = {shadow},\\n'",
        "    '    },\\n'",
        "    '  },\\n'",
        "    '})\\n'",
        "    + anim",
        "    + '-- END COMTROL-LOOK\\n'",
        ")",
        "upsert(pathlib.Path.home() / '.config/hypr/looknfeel.lua', '-- BEGIN COMTROL-LOOK', '-- END COMTROL-LOOK', hypr)"
      ].join("\n"),
      String(gaps),
      String(border),
      String(rounding),
      shadow ? "true" : "false",
      enabled ? "true" : "false",
      String(speed)
    ])
  }

  function sliderRoleFor(itemId) {
    var id = String(itemId || "")
    if (id === root.blurItemId)
      return "blur"
    if (id === root.gapsItemId)
      return "gaps"
    if (id === root.borderItemId)
      return "border"
    if (id === root.roundingItemId)
      return "rounding"
    if (id === root.transitionsItemId)
      return "transitions"
    if (id.slice(-7) === ".active")
      return "active"
    if (id.slice(-9) === ".inactive")
      return "inactive"
    return "blur"
  }

  function sliderGroupFor(itemId) {
    return root.groupIdFromSlider(itemId)
  }

  Component.onCompleted: root.loadDesktop()

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellJson(text())
    onFileChanged: reload()
  }

  Process {
    id: blurReadProc
    command: ["bash", "-c",
      "printf '%s\\t%s\\n' \"$(hyprctl getoption decoration:blur:enabled -j 2>/dev/null)\" \"$(hyprctl getoption decoration:blur:size -j 2>/dev/null)\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBlurStatus(text)
    }
  }

  Process {
    id: lookReadProc
    command: ["bash", "-c",
      "en=$(hyprctl getoption animations:enabled -j 2>/dev/null); "
      + "speed=$(hyprctl animations -j 2>/dev/null | python3 -c '"
      + "import json,sys\n"
      + "try:\n"
      + " d=json.load(sys.stdin)\n"
      + " items=d[0] if isinstance(d,list) and d and isinstance(d[0],list) else d\n"
      + " for a in items:\n"
      + "  if a.get(\"name\")==\"global\":\n"
      + "   print(a.get(\"speed\",10)); break\n"
      + " else: print(10)\n"
      + "except Exception:\n"
      + " print(10)\n"
      + "'); "
      + "ms=$(python3 -c '"
      + "import json,sys\n"
      + "en=json.loads(sys.argv[1])\n"
      + "speed=float(sys.argv[2])\n"
      + "print(0 if en.get(\"bool\") is False else int(round(speed*100))\n"
      + "' \"$en\" \"$speed\"); "
      + "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "
      + "\"$(hyprctl getoption general:gaps_in -j 2>/dev/null)\" "
      + "\"$(hyprctl getoption general:border_size -j 2>/dev/null)\" "
      + "\"$(hyprctl getoption decoration:rounding -j 2>/dev/null)\" "
      + "\"$(hyprctl getoption decoration:shadow:enabled -j 2>/dev/null)\" "
      + "\"{\\\"int\\\":$ms}\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyLookStatus(text)
    }
  }

  Process {
    id: opacityScanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyOpacityScan(text)
    }
  }

  Process {
    id: opacityResetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyOpacityScan(text)
        root.pendingOpacityAll = true
        root.pendingOpacityGroupId = "global"
        root.pendingOpacityActive = root.liveGlobalActive
        root.pendingOpacityInactive = root.liveGlobalInactive
        root.flushOpacity()
      }
    }
  }

  Process {
    id: opacityEvalProc
  }

  Process {
    id: opacitySaveProc
  }

  Timer {
    id: liveBlurTimer
    interval: 40
    repeat: false
    onTriggered: root.flushBlur()
  }

  Timer {
    id: blurPersistTimer
    interval: 450
    repeat: false
    onTriggered: root.persistBlurPending()
  }

  Timer {
    id: liveLookTimer
    interval: 40
    repeat: false
    onTriggered: root.flushLook()
  }

  Timer {
    id: lookPersistTimer
    interval: 450
    repeat: false
    onTriggered: root.persistLookPending()
  }

  Timer {
    id: liveOpacityTimer
    interval: 40
    repeat: false
    onTriggered: root.flushOpacity()
  }

  Timer {
    id: opacityPersistTimer
    interval: 450
    repeat: false
    onTriggered: root.persistOpacityPending()
  }

  Component {
    id: sliderRowComponent

    Item {
      id: sliderRow
      property bool hasCursor: false
      property string role: "blur"
      property string groupId: ""

      readonly property color ink: sliderRow.hasCursor ? root.selectedText : root.foreground
      readonly property bool isBlur: sliderRow.role === "blur"
      readonly property bool isGaps: sliderRow.role === "gaps"
      readonly property bool isBorder: sliderRow.role === "border"
      readonly property bool isRounding: sliderRow.role === "rounding"
      readonly property bool isTransitions: sliderRow.role === "transitions"
      readonly property bool isLook: sliderRow.isGaps || sliderRow.isBorder || sliderRow.isRounding || sliderRow.isTransitions
      readonly property bool isActive: sliderRow.role === "active"
      readonly property int minValue: {
        if (sliderRow.isBlur)
          return root.minBlur
        if (sliderRow.isGaps)
          return root.minGaps
        if (sliderRow.isBorder)
          return root.minBorder
        if (sliderRow.isRounding)
          return root.minRounding
        if (sliderRow.isTransitions)
          return root.minTransitions
        return root.minOpacity
      }
      readonly property int maxValue: {
        if (sliderRow.isBlur)
          return root.maxBlur
        if (sliderRow.isGaps)
          return root.maxGaps
        if (sliderRow.isBorder)
          return root.maxBorder
        if (sliderRow.isRounding)
          return root.maxRounding
        if (sliderRow.isTransitions)
          return root.maxTransitions
        return root.maxOpacity
      }
      readonly property int currentValue: {
        if (sliderRow.isBlur)
          return root.displayedBlur
        if (sliderRow.isLook)
          return root.displayedLook(sliderRow.role)
        return root.displayedOpacity(sliderRow.groupId, sliderRow.isActive ? "active" : "inactive")
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Math.max(headerLabel.implicitHeight, sizeLabel.implicitHeight)

          Text {
            id: headerLabel
            textFormat: Text.PlainText
            text: {
              if (sliderRow.isBlur)
                return "BLUR"
              if (sliderRow.isGaps)
                return "GAPS"
              if (sliderRow.isBorder)
                return "BORDER"
              if (sliderRow.isRounding)
                return "ROUNDING"
              if (sliderRow.isTransitions)
                return "TRANSITIONS"
              if (sliderRow.isActive)
                return "ACTIVE"
              return "INACTIVE"
            }
            color: sliderRow.ink
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: sizeLabel
            textFormat: Text.PlainText
            text: {
              var v = panelSlider.dragging ? Math.round(panelSlider.liveValue) : sliderRow.currentValue
              if (sliderRow.isBlur)
                return v <= 0 ? "Off" : String(v)
              if (sliderRow.isTransitions)
                return v <= 0 ? "Off" : (String(v) + " ms")
              if (sliderRow.isLook)
                return String(v)
              return String(v) + "%"
            }
            color: sliderRow.ink
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSlider {
          id: panelSlider
          width: parent.width
          minimum: sliderRow.minValue
          maximum: sliderRow.maxValue
          step: sliderRow.isTransitions ? 50 : 1
          integer: true
          tickCount: sliderRow.isTransitions
            ? Math.floor((sliderRow.maxValue - sliderRow.minValue) / 50) + 1
            : (sliderRow.maxValue - sliderRow.minValue + 1)
          value: sliderRow.currentValue
          fillColor: sliderRow.ink
          knobColor: sliderRow.ink
          trackColor: Qt.rgba(sliderRow.ink.r, sliderRow.ink.g, sliderRow.ink.b, 0.22)
          tickColor: root.background
          onMoved: function(v) {
            var n = Math.round(v)
            if (sliderRow.isBlur)
              root.setBlur(n, false)
            else if (sliderRow.isLook)
              root.setLookRole(sliderRow.role, n, false)
            else
              root.setGroupOpacity(sliderRow.groupId, sliderRow.isActive ? "active" : "inactive", n, false)
          }
          onReleased: function(v) {
            var n = Math.round(v)
            if (sliderRow.isBlur)
              root.setBlur(n, true)
            else if (sliderRow.isLook)
              root.setLookRole(sliderRow.role, n, true)
            else
              root.setGroupOpacity(sliderRow.groupId, sliderRow.isActive ? "active" : "inactive", n, true)
          }
        }
      }
    }
  }

  readonly property Component sliderDelegate: sliderRowComponent
}
