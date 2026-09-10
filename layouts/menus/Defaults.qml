import Quickshell
import Quickshell.Io
import QtQuick

// Config → Default apps — mirrors Omarchy menu setup.default (browser/terminal/editor/agent).
Item {
  id: root

  width: 0
  height: 0
  visible: false

  readonly property string itemId: "defaults"
  readonly property string label: "Default apps"
  readonly property string icon: ""
  readonly property string title: "Default apps"

  property string currentBrowser: ""
  property string currentTerminal: ""
  property string currentEditor: ""
  property string currentAgent: ""
  property var presentCmds: ({})

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property string browserItemId: "defaults.browser"
  readonly property string terminalItemId: "defaults.terminal"
  readonly property string editorItemId: "defaults.editor"
  readonly property string agentItemId: "defaults.agent"

  readonly property var browserOptions: [
    { id: "chromium", label: "Chromium", icon: "", cmd: "chromium" },
    { id: "chrome", label: "Chrome", icon: "󰊯", cmd: "google-chrome-stable" },
    { id: "brave", label: "Brave", icon: "󰖟", cmd: "brave" },
    { id: "brave-origin", label: "Brave Origin", icon: "󰖟", cmd: "brave-origin" },
    { id: "edge", label: "Edge", icon: "󰇩", cmd: "microsoft-edge-stable" },
    { id: "firefox", label: "Firefox", icon: "", cmd: "firefox" },
    { id: "zen", label: "Zen", icon: "󰖟", cmd: "zen-browser" }
  ]

  readonly property var terminalOptions: [
    { id: "alacritty", label: "Alacritty", icon: "", cmd: "alacritty" },
    { id: "foot", label: "Foot", icon: "", cmd: "foot" },
    { id: "ghostty", label: "Ghostty", icon: "", cmd: "ghostty" },
    { id: "kitty", label: "Kitty", icon: "", cmd: "kitty" }
  ]

  // Omarchy checks Zed against "zeditor" but sets via "zed".
  readonly property var editorOptions: [
    { id: "nvim", label: "Neovim", icon: "", cmd: "nvim", setId: "nvim" },
    { id: "code", label: "VSCode", icon: "", cmd: "code", setId: "code" },
    { id: "cursor", label: "Cursor", icon: "󰘦", cmd: "cursor", setId: "cursor" },
    { id: "zed", label: "Zed", icon: "", cmd: "zeditor", setId: "zed", checkId: "zeditor" },
    { id: "sublime_text", label: "Sublime Text", icon: "", cmd: "sublime_text", setId: "sublime_text" },
    { id: "helix", label: "Helix", icon: "", cmd: "helix", setId: "helix" },
    { id: "vim", label: "Vim", icon: "", cmd: "vim", setId: "vim" },
    { id: "emacs", label: "Emacs", icon: "", cmd: "emacs", setId: "emacs" }
  ]

  // Agents have no `when` in omarchy-menu — always listed.
  readonly property var agentOptions: [
    { id: "claude", label: "Claude", icon: "󰛄" },
    { id: "codex", label: "Codex", icon: "󰚩" },
    { id: "copilot", label: "Copilot", icon: "" },
    { id: "crush", label: "Crush", icon: "󰋑" },
    { id: "cursor-agent", label: "Cursor CLI", icon: "󰘦" },
    { id: "gemini", label: "Gemini", icon: "󰫢" },
    { id: "grok", label: "Grok", icon: "󰚩" },
    { id: "hermes", label: "Hermes", icon: "󰚩" },
    { id: "muse", label: "Muse Code", icon: "󰛤" },
    { id: "omp", label: "omp", icon: "󰚩" },
    { id: "openclaw", label: "OpenClaw", icon: "󰚩" },
    { id: "opencode", label: "OpenCode", icon: "󰚩" },
    { id: "pi", label: "Pi", icon: "󰚩" }
  ]

  readonly property var menu: ({
    title: root.title,
    rows: [
      {
        itemId: root.browserItemId,
        label: "Browser",
        icon: "",
        kind: "menu",
        status: root.displayLabel(root.browserOptions, root.currentBrowser)
      },
      {
        itemId: root.terminalItemId,
        label: "Terminal",
        icon: "",
        kind: "menu",
        status: root.displayLabel(root.terminalOptions, root.currentTerminal)
      },
      {
        itemId: root.editorItemId,
        label: "Editor",
        icon: "",
        kind: "menu",
        status: root.displayLabel(root.editorOptions, root.currentEditor)
      },
      {
        itemId: root.agentItemId,
        label: "Agent",
        icon: "󰚩",
        kind: "menu",
        status: root.displayLabel(root.agentOptions, root.currentAgent)
      }
    ]
  })

  signal changed()

  function cmdPresent(cmd) {
    return !!root.presentCmds[String(cmd || "")]
  }

  function displayLabel(options, current) {
    var cur = String(current || "").trim()
    if (!cur)
      return ""
    var list = options || []
    for (var i = 0; i < list.length; i++) {
      var opt = list[i] || {}
      var id = String(opt.id || "")
      var setId = String(opt.setId || id)
      var checkId = String(opt.checkId || setId)
      if (cur === id || cur === setId || cur === checkId || cur === String(opt.cmd || ""))
        return String(opt.label || id)
    }
    return cur
  }

  function isCurrentOption(opt, current) {
    var cur = String(current || "").trim()
    if (!cur)
      return false
    var id = String(opt.id || "")
    var setId = String(opt.setId || id)
    var checkId = String(opt.checkId || setId)
    return cur === id || cur === setId || cur === checkId || cur === String(opt.cmd || "")
  }

  function optionRows(kind, options, current, requirePresent) {
    var rows = []
    var list = options || []
    for (var i = 0; i < list.length; i++) {
      var opt = list[i] || {}
      var cmd = String(opt.cmd || opt.id || "")
      var currentOpt = root.isCurrentOption(opt, current)
      // Always keep the active default visible, even if presence scan lagged.
      if (requirePresent && cmd && !root.cmdPresent(cmd) && !currentOpt)
        continue
      var id = String(opt.id || "")
      var setId = String(opt.setId || id)
      rows.push({
        itemId: "defaults." + kind + "." + id,
        label: String(opt.label || id),
        icon: String(opt.icon || ""),
        kind: "default",
        command: "omarchy-default-" + kind + " " + setId,
        status: currentOpt ? "✓" : ""
      })
    }
    return rows
  }

  readonly property var browserMenu: ({
    title: "Default Browser",
    rows: root.optionRows("browser", root.browserOptions, root.currentBrowser, true)
  })

  readonly property var terminalMenu: ({
    title: "Default Terminal",
    rows: root.optionRows("terminal", root.terminalOptions, root.currentTerminal, true)
  })

  readonly property var editorMenu: ({
    title: "Default Editor",
    rows: root.optionRows("editor", root.editorOptions, root.currentEditor, true)
  })

  readonly property var agentMenu: ({
    title: "Default Agent",
    rows: root.optionRows("agent", root.agentOptions, root.currentAgent, false)
  })

  function isDefaultsMenu(menuId) {
    var id = String(menuId || "")
    return id === root.itemId
      || id === root.browserItemId
      || id === root.terminalItemId
      || id === root.editorItemId
      || id === root.agentItemId
  }

  function load() {
    if (!scanProc.running)
      scanProc.running = true
  }

  function setDefault(command) {
    var cmd = String(command || "").trim()
    if (!cmd)
      return false
    if (setProc.running)
      setProc.running = false
    setProc.command = ["bash", "-lc", cmd]
    setProc.running = true
    return true
  }

  Component.onCompleted: root.load()

  Process {
    id: scanProc
    // Use RS (|) for present cmds — QML "\\n" was becoming a literal \n in bash.
    command: [
      "bash", "-lc",
      "present=''; "
        + "for c in chromium google-chrome-stable brave brave-origin microsoft-edge-stable firefox zen-browser "
        + "alacritty foot ghostty kitty nvim code cursor zeditor sublime_text helix vim emacs; do "
        + "  if command -v \"$c\" >/dev/null 2>&1; then present=\"${present}|${c}\"; fi; "
        + "done; "
        + "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "
        + "\"$(omarchy-default-browser 2>/dev/null | tr -d '\\n')\" "
        + "\"$(omarchy-default-terminal 2>/dev/null | tr -d '\\n')\" "
        + "\"$(omarchy-default-editor 2>/dev/null | tr -d '\\n')\" "
        + "\"$(omarchy-default-agent 2>/dev/null | tr -d '\\n')\" "
        + "\"${present#|}\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").replace(/\r?\n$/, "").split("\t")
        root.currentBrowser = String(parts[0] || "").trim()
        root.currentTerminal = String(parts[1] || "").trim()
        root.currentEditor = String(parts[2] || "").trim()
        root.currentAgent = String(parts[3] || "").trim()
        var present = ({})
        var tokens = String(parts[4] || "").split("|")
        for (var i = 0; i < tokens.length; i++) {
          var c = String(tokens[i] || "").trim()
          if (c)
            present[c] = true
        }
        root.presentCmds = present
        root.changed()
      }
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.load()
    }
  }
}
