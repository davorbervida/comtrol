import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "../../functions/appearance"

// Appearance → Shell: element first, then opacity / rounding / states.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property var host: null

  onHostChanged: ShellLook.host = host

  Component.onCompleted: {
    if (root.host)
      ShellLook.host = root.host
  }

  readonly property string itemId: "shell"
  readonly property string barItemId: "shell.bar"
  readonly property string positionItemId: "shell.bar.position"
  readonly property string transparencyItemId: "shell.bar.transparency"
  readonly property string spacingItemId: "shell.spacing"
  readonly property string label: "Shell"
  readonly property string icon: "󰨇"
  readonly property string title: "Shell"

  readonly property int minBorder: ShellLook.minBorder
  readonly property int maxBorder: ShellLook.maxBorder
  readonly property int minRounding: ShellLook.minRounding
  readonly property int maxRounding: ShellLook.maxRounding
  readonly property int minAlpha: ShellLook.minAlpha
  readonly property int maxAlpha: ShellLook.maxAlpha
  readonly property int minBarSize: ShellLook.minBarSize
  readonly property int maxBarSize: ShellLook.maxBarSize
  readonly property int minSpacingPct: ShellLook.minSpacingPct
  readonly property int maxSpacingPct: ShellLook.maxSpacingPct
  readonly property int minPadding: ShellLook.minPadding
  readonly property int maxPadding: ShellLook.maxPadding
  readonly property int sliderRowHeight: Math.max(
    Style.space(72),
    Style.font.caption + Style.spacing.controlGap + Math.max(Style.space(22), Math.round(Style.spacing.controlHeight * 0.38) + Style.spacing.md)
  )
  readonly property int separatorRowHeight: Style.space(12)

  readonly property var lookGroups: [
    { id: "menu", label: "Menu", icon: "󰍜" },
    { id: "popups", label: "Popups", icon: "󰁌" },
    { id: "notifications", label: "Notifications", icon: "󰂚" },
    { id: "launcher", label: "Launcher", icon: "󰀻" },
    { id: "tooltip", label: "Tooltip", icon: "󰈇" },
    { id: "controls", label: "Controls", icon: "󰺲" },
    { id: "polkit", label: "Polkit", icon: "󰌆" },
    { id: "lock", label: "Lock", icon: "󰌾" }
  ]

  readonly property var borderSides: [
    { id: "all", label: "All" },
    { id: "top", label: "Top" },
    { id: "right", label: "Right" },
    { id: "bottom", label: "Bottom" },
    { id: "left", label: "Left" }
  ]

  property string position: "top"
  property bool transparent: false
  property var previewValues: ({})
  property var pendingSpec: null
  property int pendingValue: -1

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

  readonly property var menu: {
    var rows = [
      {
        itemId: root.barItemId,
        label: "Bar",
        icon: "󰖯",
        kind: "menu",
        status: root.positionLabel
      },
      { itemId: "shell.sep.surfaces", kind: "separator" }
    ]
    for (var i = 0; i < root.lookGroups.length; i++) {
      var g = root.lookGroups[i]
      rows.push({
        itemId: root.elementId(g.id),
        label: g.label,
        icon: g.icon,
        kind: "menu"
      })
    }
    rows.push({ itemId: "shell.sep.spacing", kind: "separator" })
    rows.push({
      itemId: root.spacingItemId,
      label: "Spacing",
      icon: "󰘕",
      kind: "menu",
      status: String(root.displayedValue(root.sliderSpec(root.spacingItemId + ".scale"))) + "%"
    })
    return { title: root.title, rows: rows }
  }

  readonly property var positionMenu: ({
    title: "Bar position",
    rows: [
      root.positionRow("top", "Top", "󰁝"),
      root.positionRow("bottom", "Bottom", "󰁅"),
      root.positionRow("left", "Left", "󰁍"),
      root.positionRow("right", "Right", "󰁔")
    ]
  })

  signal changed()

  function elementId(groupId) {
    return "shell." + String(groupId || "")
  }

  function positionRow(id, name, icon) {
    return {
      itemId: id,
      label: name,
      icon: root.position === id ? "✓" : icon,
      kind: "bar-position"
    }
  }

  function groupLabel(groupId) {
    var id = String(groupId || "")
    if (id === "bar")
      return "Bar"
    for (var i = 0; i < root.lookGroups.length; i++) {
      if (root.lookGroups[i].id === id)
        return root.lookGroups[i].label
    }
    return ""
  }

  function sliderKey(role, groupId, channel) {
    return String(role || "") + "|" + String(groupId || "") + "|" + String(channel || "")
  }

  function sliderSpec(itemId) {
    var sid = String(itemId || "")
    if (sid === "shell.bar.opacity")
      return root.makeSpec("alpha", "bar", "background", sid)
    if (sid === "shell.bar.size.h")
      return root.makeSpec("barSize", "bar", "h", sid)
    if (sid === "shell.bar.size.v")
      return root.makeSpec("barSize", "bar", "v", sid)
    if (sid === "shell.spacing.scale")
      return root.makeSpec("spacingScale", "spacing", "scale", sid)
    if (sid.indexOf("shell.spacing.") === 0 && sid !== root.spacingItemId) {
      var token = sid.substring("shell.spacing.".length)
      if (token === "panel-padding" || token === "popup-padding" || token === "control-height")
        return root.makeSpec("spacingToken", "spacing", token, sid)
      return null
    }
    var m = sid.match(/^shell\.([a-z]+)\.(rounding|opacity|idle|hover|focus|selected|pressed)(?:\.(.+))?$/)
    if (!m)
      return null
    var gid = m[1]
    var kind = m[2]
    var rest = m[3] || ""
    if (gid === "bar" || gid === "spacing")
      return null
    if (kind === "rounding" && !rest)
      return root.makeSpec("rounding", gid, "", sid)
    if (kind === "opacity" && (rest === "background" || rest === "scrim"))
      return root.makeSpec("alpha", gid, rest, sid)
    if (rest === "fill")
      return root.makeSpec("stateFill", gid, kind, sid)
    if (rest.indexOf("border.") === 0) {
      var side = rest.substring("border.".length)
      if (side === "all" || side === "top" || side === "right" || side === "bottom" || side === "left")
        return root.makeSpec("stateBorder", gid, kind + "." + side, sid)
    }
    if (kind === "idle" && (rest === "all" || rest === "top" || rest === "right" || rest === "bottom" || rest === "left"))
      return root.makeSpec("stateBorder", gid, "idle." + rest, sid)
    return null
  }

  function makeSpec(role, groupId, channel, itemId) {
    var r = String(role || "")
    var spec = {
      role: r,
      groupId: String(groupId || ""),
      channel: String(channel || ""),
      itemId: String(itemId || ""),
      key: root.sliderKey(r, groupId, channel),
      minValue: root.minBorder,
      maxValue: root.maxBorder,
      step: 1,
      suffix: ""
    }
    if (r === "rounding") {
      spec.minValue = root.minRounding
      spec.maxValue = root.maxRounding
    } else if (r === "alpha" || r === "fill" || r === "selectionFill" || r === "stateFill") {
      spec.minValue = root.minAlpha
      spec.maxValue = root.maxAlpha
      spec.suffix = "%"
    } else if (r === "controlBorder" || r === "stateBorder") {
      spec.minValue = root.minBorder
      spec.maxValue = root.maxBorder
    } else if (r === "barSize") {
      spec.minValue = root.minBarSize
      spec.maxValue = root.maxBarSize
    } else if (r === "spacingScale") {
      spec.minValue = root.minSpacingPct
      spec.maxValue = root.maxSpacingPct
      spec.step = 5
      spec.suffix = "%"
    } else if (r === "spacingToken") {
      spec.minValue = root.minPadding
      spec.maxValue = root.maxPadding
    }
    return spec
  }

  function sliderRoleFor(itemId) {
    var spec = root.sliderSpec(itemId)
    return spec ? spec.role : ""
  }

  function sliderGroupFor(itemId) {
    var spec = root.sliderSpec(itemId)
    return spec ? spec.groupId : ""
  }

  function sliderChannelFor(itemId) {
    var spec = root.sliderSpec(itemId)
    return spec ? spec.channel : ""
  }

  function isShellSlider(itemId) {
    return !!root.sliderSpec(itemId)
  }

  function liveValue(spec) {
    if (!spec)
      return 0
    var r = spec.role
    if (r === "rounding")
      return ShellLook.roundingOf(spec.groupId)
    if (r === "border")
      return ShellLook.borderOf(spec.groupId, spec.channel)
    if (r === "alpha")
      return ShellLook.alphaOf(spec.groupId, spec.channel)
    if (r === "fill")
      return ShellLook.fillOf(spec.channel)
    if (r === "stateFill")
      return ShellLook.stateFillOf(spec.groupId, spec.channel)
    if (r === "controlBorder")
      return ShellLook.controlBorderOf(spec.groupId, spec.channel)
    if (r === "stateBorder") {
      var parts = String(spec.channel || "").split(".")
      return ShellLook.stateBorderOf(spec.groupId, parts[0] || "idle", parts[1] || "all")
    }
    if (r === "selectionFill")
      return ShellLook.selectionFillOf(spec.groupId)
    if (r === "selectionBorder")
      return ShellLook.selectionBorderOf(spec.groupId)
    if (r === "barSize")
      return ShellLook.barSizeOf(spec.channel)
    if (r === "spacingScale")
      return ShellLook.spacingScalePct()
    if (r === "spacingToken")
      return ShellLook.spacingTokenOf(spec.channel)
    return 0
  }

  function clampSpec(spec, value) {
    if (!spec)
      return 0
    if (spec.role === "rounding")
      return ShellLook.clampRounding(value)
    if (spec.role === "border" || spec.role === "selectionBorder" || spec.role === "controlBorder" || spec.role === "stateBorder")
      return ShellLook.clampBorder(value)
    if (spec.role === "alpha" || spec.role === "fill" || spec.role === "selectionFill" || spec.role === "stateFill")
      return ShellLook.clampAlpha(value)
    if (spec.role === "barSize")
      return ShellLook.clampBarSize(value)
    if (spec.role === "spacingScale")
      return ShellLook.clampSpacingPct(value)
    if (spec.role === "spacingToken")
      return ShellLook.clampPadding(value)
    return Math.round(Number(value) || 0)
  }

  function displayedValue(spec) {
    if (!spec)
      return 0
    var preview = root.previewValues || ({})
    if (preview[spec.key] !== undefined)
      return root.clampSpec(spec, preview[spec.key])
    return root.liveValue(spec)
  }

  readonly property int displayedMenuRounding: {
    void root.previewValues
    void ShellLook.liveRoundings
    return root.displayedValue(root.makeSpec("rounding", "menu", "", ""))
  }

  function opacityStatus(groupId) {
    var bg = root.displayedValue(root.makeSpec("alpha", groupId, "background", ""))
    if (!ShellLook.hasScrim(groupId))
      return String(bg) + "%"
    var scrim = root.displayedValue(root.makeSpec("alpha", groupId, "scrim", ""))
    return String(bg) + "% / " + String(scrim) + "%"
  }

  function stateStatus(groupId, state) {
    var gid = String(groupId || "")
    var s = String(state || "")
    var parts = []
    if (ShellLook.stateHasFill(gid, s))
      parts.push(String(root.displayedValue(root.makeSpec("stateFill", gid, s, ""))) + "%")
    if (ShellLook.stateHasBorder(gid, s))
      parts.push(String(root.displayedValue(root.makeSpec("stateBorder", gid, s + ".all", ""))))
    return parts.join(" · ")
  }

  function elementRows(groupId) {
    var gid = String(groupId || "")
    var rows = []
    if (gid !== "controls") {
      rows.push({
        itemId: root.elementId(gid) + ".opacity",
        label: "Opacity",
        icon: "󰂵",
        kind: "menu",
        status: root.opacityStatus(gid)
      })
    }
    rows.push({
      itemId: root.elementId(gid) + ".rounding",
      label: "Rounding",
      kind: "slider"
    })
    rows.push({ itemId: root.elementId(gid) + ".sep.states", kind: "separator" })
    var states = ShellLook.statesOf(gid)
    for (var i = 0; i < states.length; i++) {
      var st = states[i]
      rows.push({
        itemId: root.elementId(gid) + "." + st.id,
        label: st.label,
        kind: "menu",
        status: root.stateStatus(gid, st.id)
      })
    }
    return rows
  }

  function opacityRows(groupId) {
    var gid = String(groupId || "")
    var rows = [
      { itemId: root.elementId(gid) + ".opacity.background", label: "Card", kind: "slider" }
    ]
    if (ShellLook.hasScrim(gid))
      rows.push({ itemId: root.elementId(gid) + ".opacity.scrim", label: "Scrim", kind: "slider" })
    return rows
  }

  function borderSideRows(itemPrefix) {
    var rows = []
    for (var i = 0; i < root.borderSides.length; i++) {
      var s = root.borderSides[i]
      rows.push({
        itemId: String(itemPrefix || "") + "." + s.id,
        label: s.label,
        kind: "slider"
      })
    }
    return rows
  }

  function stateRows(groupId, state) {
    var gid = String(groupId || "")
    var s = String(state || "")
    var base = root.elementId(gid) + "." + s
    return [
      { itemId: base + ".fill", label: "Fill", kind: "slider" },
      {
        itemId: base + ".border",
        label: "Border",
        icon: "󰃇",
        kind: "menu",
        status: String(root.displayedValue(root.makeSpec("stateBorder", gid, s + ".all", "")))
      }
    ]
  }

  function nestedMenus() {
    var out = ({})
    out[root.barItemId] = {
      title: "Bar",
      rows: [
        {
          itemId: root.positionItemId,
          label: "Position",
          icon: "",
          kind: "menu",
          status: root.positionLabel
        },
        {
          itemId: root.transparencyItemId,
          label: "Transparency",
          icon: "󰂵",
          kind: "bar-transparency",
          status: root.transparencyLabel
        },
        { itemId: "shell.bar.sep.size", kind: "separator" },
        { itemId: "shell.bar.opacity", label: "Opacity", kind: "slider" },
        { itemId: "shell.bar.size.h", label: "Horizontal", kind: "slider" },
        { itemId: "shell.bar.size.v", label: "Vertical", kind: "slider" }
      ]
    }
    out[root.positionItemId] = root.positionMenu
    out[root.spacingItemId] = {
      title: "Spacing",
      rows: [
        { itemId: "shell.spacing.scale", label: "Scale", kind: "slider" },
        { itemId: "shell.spacing.panel-padding", label: "Panel", kind: "slider" },
        { itemId: "shell.spacing.popup-padding", label: "Popup", kind: "slider" },
        { itemId: "shell.spacing.control-height", label: "Control", kind: "slider" }
      ]
    }
    for (var i = 0; i < root.lookGroups.length; i++) {
      var g = root.lookGroups[i]
      var eid = root.elementId(g.id)
      out[eid] = { title: g.label, rows: root.elementRows(g.id) }
      if (g.id !== "controls")
        out[eid + ".opacity"] = { title: "Opacity", rows: root.opacityRows(g.id) }
      var states = ShellLook.statesOf(g.id)
      for (var j = 0; j < states.length; j++) {
        var st = states[j]
        out[eid + "." + st.id] = { title: st.label, rows: root.stateRows(g.id, st.id) }
        out[eid + "." + st.id + ".border"] = { title: "Border", rows: root.borderSideRows(eid + "." + st.id + ".border") }
      }
    }
    return out
  }

  function isNestedMenu(menuId) {
    var id = String(menuId || "")
    if (!id || id === root.itemId)
      return false
    var menus = root.nestedMenus()
    return !!menus[id]
  }

  function isSliderOnlyMenu(menuId) {
    var menus = root.nestedMenus()
    var m = menus[String(menuId || "")]
    if (!m || !m.rows || !m.rows.length)
      return false
    var hasSlider = false
    for (var i = 0; i < m.rows.length; i++) {
      var k = String((m.rows[i] && m.rows[i].kind) || "")
      if (k === "slider")
        hasSlider = true
      else if (k !== "separator")
        return false
    }
    return hasSlider
  }

  function sliderHeader(spec) {
    if (!spec)
      return ""
    var r = spec.role
    var ch = spec.channel
    if (r === "stateBorder") {
      var bits = String(ch || "").split(".")
      ch = bits.length > 1 ? bits[1] : bits[0]
    }
    if (r === "rounding")
      return "ROUNDING"
    if (r === "border" || r === "controlBorder" || r === "stateBorder") {
      if (ch === "top")
        return "TOP"
      if (ch === "right")
        return "RIGHT"
      if (ch === "bottom")
        return "BOTTOM"
      if (ch === "left")
        return "LEFT"
      return "BORDER"
    }
    if (r === "alpha") {
      if (ch === "scrim")
        return "SCRIM"
      if (spec.groupId === "bar")
        return "OPACITY"
      return "CARD"
    }
    if (r === "fill" || r === "selectionFill" || r === "stateFill")
      return "FILL"
    if (r === "selectionBorder")
      return "BORDER"
    if (r === "barSize")
      return ch === "v" ? "VERTICAL" : "HORIZONTAL"
    if (r === "spacingScale")
      return "SCALE"
    if (r === "spacingToken") {
      if (ch === "popup-padding")
        return "POPUP"
      if (ch === "control-height")
        return "CONTROL"
      return "PANEL"
    }
    return ""
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

  function clonePreview(src) {
    var preview = ({})
    for (var k in src)
      preview[k] = src[k]
    return preview
  }

  function applySpec(spec, value) {
    var n = root.clampSpec(spec, value)
    var r = spec.role
    if (r === "rounding")
      ShellLook.applyRounding(spec.groupId, n)
    else if (r === "border")
      ShellLook.applyBorder(spec.groupId, spec.channel, n)
    else if (r === "alpha")
      ShellLook.applyAlpha(spec.groupId, spec.channel, n)
    else if (r === "fill")
      ShellLook.applyFill(spec.channel, n)
    else if (r === "stateFill")
      ShellLook.applyStateFill(spec.groupId, spec.channel, n)
    else if (r === "controlBorder")
      ShellLook.applyControlBorder(spec.groupId, spec.channel, n)
    else if (r === "stateBorder") {
      var pb = String(spec.channel || "").split(".")
      ShellLook.applyStateBorder(spec.groupId, pb[0] || "idle", pb[1] || "all", n)
    }
    else if (r === "selectionFill")
      ShellLook.applySelectionFill(spec.groupId, n)
    else if (r === "selectionBorder")
      ShellLook.applySelectionBorder(spec.groupId, n)
    else if (r === "barSize")
      ShellLook.applyBarSize(spec.channel, n)
    else if (r === "spacingScale")
      ShellLook.applySpacingScale(n)
    else if (r === "spacingToken")
      ShellLook.applySpacingToken(spec.channel, n)
    return n
  }

  function saveSpec(spec, value) {
    var n = root.clampSpec(spec, value)
    var r = spec.role
    if (r === "rounding")
      ShellLook.saveRounding(spec.groupId, n)
    else if (r === "border")
      ShellLook.saveBorder(spec.groupId, spec.channel, n)
    else if (r === "alpha")
      ShellLook.saveAlpha(spec.groupId, spec.channel, n)
    else if (r === "fill")
      ShellLook.saveFill(spec.channel, n)
    else if (r === "stateFill")
      ShellLook.saveStateFill(spec.groupId, spec.channel, n)
    else if (r === "controlBorder")
      ShellLook.saveControlBorder(spec.groupId, spec.channel, n)
    else if (r === "stateBorder") {
      var pb = String(spec.channel || "").split(".")
      ShellLook.saveStateBorder(spec.groupId, pb[0] || "idle", pb[1] || "all", n)
    }
    else if (r === "selectionFill")
      ShellLook.saveSelectionFill(spec.groupId, n)
    else if (r === "selectionBorder")
      ShellLook.saveSelectionBorder(spec.groupId, n)
    else if (r === "barSize")
      ShellLook.saveBarSize(spec.channel, n)
    else if (r === "spacingScale")
      ShellLook.saveSpacingScale(n)
    else if (r === "spacingToken")
      ShellLook.saveSpacingToken(spec.channel, n)
  }

  function setLookSpec(spec, value, persist) {
    if (!spec)
      return
    var next = root.clampSpec(spec, value)
    var preview = root.clonePreview(root.previewValues)
    preview[spec.key] = next
    root.previewValues = preview
    root.pendingSpec = spec
    root.pendingValue = next
    root.applySpec(spec, next)
    liveTimer.interval = persist ? 40 : 80
    liveTimer.restart()
  }

  function setLookRole(role, value, persist, groupId, channel) {
    root.setLookSpec(root.makeSpec(role, groupId, channel, ""), value, persist)
  }

  function adjustSlider(itemId, delta) {
    var spec = root.sliderSpec(itemId)
    if (!spec)
      return
    var step = spec.step || 1
    root.setLookSpec(spec, root.displayedValue(spec) + delta * step, true)
  }

  function flushPending() {
    var spec = root.pendingSpec
    if (!spec || !spec.role)
      return
    var next = root.pendingValue
    root.saveSpec(spec, next)
    if (root.previewValues && root.previewValues[spec.key] !== undefined
        && root.liveValue(spec) === root.previewValues[spec.key]) {
      var preview = ({})
      for (var k in root.previewValues) {
        if (k !== spec.key)
          preview[k] = root.previewValues[k]
      }
      root.previewValues = preview
    }
  }

  function loadLook() {
    ShellLook.load()
  }

  function previewStateFor(menuId) {
    var id = String(menuId || "")
    var m = id.match(/^shell\.[a-z]+\.(idle|hover|focus|selected|pressed)(?:\.|$)/)
    return m ? m[1] : "idle"
  }

  function editGroup(menuId) {
    var id = String(menuId || "")
    if (id.indexOf("shell.") !== 0)
      return ""
    return ShellLook.knownGroup(id.substring("shell.".length).split(".")[0])
  }

  function editState(menuId) {
    var gid = root.editGroup(menuId)
    if (!gid)
      return ""
    var m = String(menuId || "").match(/^shell\.[a-z]+\.(idle|hover|focus|selected|pressed)(?:\.|$)/)
    return m ? m[1] : ""
  }

  function previewGroupFor(menuId) {
    var id = String(menuId || "")
    if (id.indexOf("shell.") !== 0)
      return ""
    if (id === "shell" || id === "shell.spacing" || id.indexOf("shell.spacing.") === 0)
      return ""
    if (id === "shell.bar" || id.indexOf("shell.bar.") === 0)
      return ""
    var gid = id.substring("shell.".length).split(".")[0]
    if (gid === "menu")
      return ""
    return ShellLook.knownGroup(gid)
  }

  function syncPreview(menuId) {
    ShellLook.setPreview(root.previewGroupFor(menuId), root.previewStateFor(menuId))
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyShellJson(text())
    onFileChanged: reload()
  }

  Timer {
    id: liveTimer
    interval: 40
    repeat: false
    onTriggered: root.flushPending()
  }

  Component {
    id: sliderRowComponent

    Item {
      id: sliderRow
      property bool hasCursor: false
      property string role: "border"
      property string groupId: ""
      property string channel: ""

      readonly property var spec: root.makeSpec(sliderRow.role, sliderRow.groupId, sliderRow.channel, "")
      readonly property color ink: sliderRow.hasCursor ? root.selectedText : root.foreground
      readonly property int minValue: sliderRow.spec.minValue
      readonly property int maxValue: sliderRow.spec.maxValue
      readonly property int step: sliderRow.spec.step
      readonly property string suffix: sliderRow.spec.suffix
      readonly property int currentValue: root.displayedValue(sliderRow.spec)
      readonly property string headerText: root.sliderHeader(sliderRow.spec)

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
            text: sliderRow.headerText
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
            text: String(panelSlider.dragging ? Math.round(panelSlider.liveValue) : sliderRow.currentValue) + sliderRow.suffix
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
          step: sliderRow.step
          integer: true
          tickCount: {
            var span = sliderRow.maxValue - sliderRow.minValue
            if (sliderRow.step > 1)
              return Math.floor(span / sliderRow.step) + 1
            if (span <= 24)
              return span + 1
            return 0
          }
          value: sliderRow.currentValue
          fillColor: sliderRow.ink
          knobColor: sliderRow.ink
          trackColor: Qt.rgba(sliderRow.ink.r, sliderRow.ink.g, sliderRow.ink.b, 0.22)
          tickColor: root.background
          onMoved: function(v) {
            root.setLookSpec(sliderRow.spec, Math.round(v), false)
          }
          onReleased: function(v) {
            root.setLookSpec(sliderRow.spec, Math.round(v), true)
          }
        }
      }
    }
  }

  readonly property Component sliderDelegate: sliderRowComponent
}
