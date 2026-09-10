pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Window frosting only — Hyprland decoration.blur + terminal frost keys.
// Never writes opacity / alpha (owned by Opacity).
Item {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string looknfeelFile: root.home + "/.config/hypr/looknfeel.lua"
  readonly property string footFile: root.home + "/.config/foot/foot.ini"
  readonly property string kittyFile: root.home + "/.config/kitty/kitty.conf"
  readonly property string alacrittyFile: root.home + "/.config/alacritty/alacritty.toml"
  readonly property string ghosttyFile: root.home + "/.config/ghostty/config"

  readonly property int minSize: 0
  readonly property int maxSize: 20

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

  function clamp(size) {
    var n = Math.round(Number(size))
    if (!isFinite(n))
      return root.minSize
    return Math.max(root.minSize, Math.min(root.maxSize, n))
  }

  function passes(size) {
    var n = root.clamp(size)
    if (n <= 0)
      return 1
    return Math.max(1, Math.min(5, Math.ceil(n / 4)))
  }

  // Live hyprctl eval payload. bounceFrom: prior applied size (refresh blur buffers).
  function evalLua(size, bounceFrom) {
    var next = root.clamp(size)
    var enabled = next > 0
    var sz = enabled ? next : 1
    var p = root.passes(next)
    var lua = enabled
      ? ("hl.config({ decoration = { blur = { enabled = true, size = "
        + sz + ", passes = " + p + ", ignore_opacity = true } } }); "
        + 'hl.layer_rule({ name = "comtrol-blur", match = { namespace = "comtrol-menu" }, blur = true, ignore_alpha = 0 })')
      : ("hl.config({ decoration = { blur = { enabled = false } } }); "
        + 'hl.layer_rule({ name = "comtrol-blur", match = { namespace = "comtrol-menu" }, blur = false })')
    var prev = Math.round(Number(bounceFrom))
    if (enabled && isFinite(prev) && prev > 0 && prev !== next)
      lua = "hl.config({ decoration = { blur = { enabled = false } } }); " + lua
    return lua
  }

  function upsertMarker(path, begin, end, block) {
    var text = root.readTextFile(path)
    var old = ""
    var body = String(block || "")
    var start = text.indexOf(begin)
    if (start >= 0) {
      var stop = text.indexOf(end, start)
      if (stop >= 0)
        old = text.substring(start, stop + end.length)
    }
    if (!body) {
      if (start < 0)
        return { changed: false, old: old }
      var stopEmpty = text.indexOf(end, start)
      if (stopEmpty < 0)
        return { changed: false, old: old }
      stopEmpty += end.length
      if (stopEmpty < text.length && text.charAt(stopEmpty) === "\n")
        stopEmpty += 1
      var cleared = text.substring(0, start) + text.substring(stopEmpty)
      if (cleared === text)
        return { changed: false, old: old }
      root.writeTextFile(path, cleared)
      return { changed: true, old: old }
    }
    if (body.charAt(body.length - 1) !== "\n")
      body += "\n"
    if (start >= 0) {
      var stop2 = text.indexOf(end, start)
      if (stop2 >= 0) {
        stop2 += end.length
        if (stop2 < text.length && text.charAt(stop2) === "\n")
          stop2 += 1
        text = text.substring(0, start) + body + text.substring(stop2)
      } else {
        text = text.replace(/\s+$/, "") + "\n\n" + body
      }
    } else {
      if (text.length && text.charAt(text.length - 1) !== "\n")
        text += "\n"
      text += (text.length ? "\n" : "") + body
    }
    root.writeTextFile(path, text)
    return { changed: true, old: old }
  }

  function hyprBlock(enabled, size, passes) {
    return "-- BEGIN COMTROL-BLUR\n"
      + "hl.config({\n"
      + "  decoration = {\n"
      + "    blur = {\n"
      + "      enabled = " + (enabled ? "true" : "false") + ",\n"
      + "      size = " + size + ",\n"
      + "      passes = " + passes + ",\n"
      + "      ignore_opacity = true,\n"
      + "    },\n"
      + "  },\n"
      + "})\n"
      + "hl.layer_rule({\n"
      + '  name = "comtrol-blur",\n'
      + '  match = { namespace = "comtrol-menu" },\n'
      + "  blur = " + (enabled ? "true" : "false") + ",\n"
      + "  ignore_alpha = 0,\n"
      + "})\n"
      + "-- END COMTROL-BLUR\n"
  }

  function footFrostBlock() {
    return "# BEGIN COMTROL-BLUR\n"
      + "[colors-dark]\n"
      + "blur=yes\n"
      + "[colors-light]\n"
      + "blur=yes\n"
      + "# END COMTROL-BLUR\n"
  }

  function kittyFrostBlock() {
    return "# BEGIN COMTROL-BLUR\n"
      + "background_blur 16\n"
      + "# END COMTROL-BLUR\n"
  }

  // One-shot: old COMTROL-BLUR mixed alpha + frost. Move alpha under Opacity.
  function migrateLegacyAlpha(path, oldBlur) {
    var blob = String(oldBlur || "")
    if (!blob)
      return
    var m = blob.match(/(?:^|\n)\s*(?:alpha|background_opacity|opacity|background-opacity)\s*[= ]\s*([0-9.]+)/)
    if (!m)
      return
    var text = root.readTextFile(path)
    if (text.indexOf("# BEGIN COMTROL-OPACITY") >= 0)
      return
    var alpha = m[1]
    var name = String(path || "").split("/").pop()
    var block = ""
    if (name === "foot.ini") {
      block = "# BEGIN COMTROL-OPACITY\n"
        + "[colors-dark]\n"
        + "alpha=" + alpha + "\n"
        + "alpha-mode=all\n"
        + "[colors-light]\n"
        + "alpha=" + alpha + "\n"
        + "alpha-mode=all\n"
        + "# END COMTROL-OPACITY\n"
    } else if (name === "kitty.conf") {
      block = "# BEGIN COMTROL-OPACITY\n"
        + "background_opacity " + alpha + "\n"
        + "# END COMTROL-OPACITY\n"
    } else if (name === "alacritty.toml") {
      block = "# BEGIN COMTROL-OPACITY\n"
        + "[window]\n"
        + "opacity = " + alpha + "\n"
        + "# END COMTROL-OPACITY\n"
    } else if (name === "config") {
      block = "# BEGIN COMTROL-OPACITY\n"
        + "background-opacity = " + alpha + "\n"
        + "# END COMTROL-OPACITY\n"
    } else {
      return
    }
    root.upsertMarker(path, "# BEGIN COMTROL-OPACITY", "# END COMTROL-OPACITY", block)
  }

  function saveTerminalFrost(on) {
    var targets = [
      { path: root.footFile, block: on ? root.footFrostBlock() : "" },
      { path: root.kittyFile, block: on ? root.kittyFrostBlock() : "" },
      // No frost key — only strip legacy blur markers.
      { path: root.alacrittyFile, block: "" },
      { path: root.ghosttyFile, block: "" }
    ]
    for (var i = 0; i < targets.length; i++) {
      var t = targets[i]
      // Do not create terminal configs from scratch.
      if (!root.readTextFile(t.path))
        continue
      var result = root.upsertMarker(t.path, "# BEGIN COMTROL-BLUR", "# END COMTROL-BLUR", t.block)
      if (result.old)
        root.migrateLegacyAlpha(t.path, result.old)
    }
  }

  function save(size) {
    var next = root.clamp(size)
    var enabled = next > 0
    var sz = enabled ? next : 1
    var p = root.passes(next)
    root.upsertMarker(
      root.looknfeelFile,
      "-- BEGIN COMTROL-BLUR",
      "-- END COMTROL-BLUR",
      root.hyprBlock(enabled, sz, p)
    )
    root.saveTerminalFrost(enabled)
    return next
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
