import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string activeMenu: "root"
  property var navStack: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  property bool showingResults: false
  property bool loading: false
  property string resultsTitle: "Results"
  property var resultRows: []
  property string pendingDomain: ""
  property string pendingMode: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(36), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int rowSpacing: Style.spacing.xs
  property int cardWidth: Math.min(Style.space(360), panel.width - Style.gapsOut * 2)
  readonly property int visibleRowsHeight: Math.min(
    Math.max(displayModel.count, 1) * (rowHeight + rowSpacing) - rowSpacing,
    Math.max(rowHeight, panel.height - Style.gapsOut * 2 - headerHeight - contentSpacing - contentMargin * 2)
  )
  readonly property int cardHeight: headerHeight + contentSpacing + visibleRowsHeight + contentMargin * 2

  readonly property var menus: ({
    "root": {
      title: "Control",
      rows: [
        { id: "themes", label: "Themes", icon: "󰏘", kind: "menu" },
        { id: "plugins", label: "Plugins", icon: "󰐱", kind: "menu" },
        { id: "packages", label: "Packages", icon: "󰏖", kind: "menu" },
        { id: "aurs", label: "AUR", icon: "󰣇", kind: "menu" }
      ]
    },
    "themes": {
      title: "Themes",
      rows: [
        { id: "themes.local", label: "Installed", icon: "󰉋", kind: "action", domain: "themes", mode: "local" },
        { id: "themes.web", label: "Browse", icon: "󰖟", kind: "action", domain: "themes", mode: "web" }
      ]
    },
    "plugins": {
      title: "Plugins",
      rows: [
        { id: "plugins.local", label: "Installed", icon: "󰉋", kind: "action", domain: "plugins", mode: "local" },
        { id: "plugins.web", label: "Browse", icon: "󰖟", kind: "action", domain: "plugins", mode: "web" }
      ]
    },
    "packages": {
      title: "Packages",
      rows: [
        { id: "packages.local", label: "Installed", icon: "󰉋", kind: "action", domain: "packages", mode: "local" },
        { id: "packages.web", label: "Browse", icon: "󰖟", kind: "action", domain: "packages", mode: "web" }
      ]
    },
    "aurs": {
      title: "AUR",
      rows: [
        { id: "aurs.local", label: "Installed", icon: "󰉋", kind: "action", domain: "aurs", mode: "local" },
        { id: "aurs.web", label: "Browse", icon: "󰖟", kind: "action", domain: "aurs", mode: "web" }
      ]
    }
  })

  function pluginDir() {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0)
      url = url.substring(7)
    while (url.length > 1 && url.charAt(url.length - 1) === "/")
      url = url.substring(0, url.length - 1)
    return url
  }

  function runScript() {
    return root.pluginDir() + "/run.sh"
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (searchProcess.running)
      searchProcess.running = false

    root.opened = true
    root.navStack = []
    root.activeMenu = payload.initialMenu || payload.menu || "root"
    root.showingResults = false
    root.loading = false
    root.resultRows = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (searchProcess.running)
      searchProcess.running = false
    root.opened = false
  }

  function dismiss() {
    if (searchProcess.running)
      searchProcess.running = false
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "comtrol")
  }

  function currentMenu() {
    if (root.showingResults)
      return { title: root.loading ? "Loading" : root.resultsTitle, rows: root.resultRows }
    return root.menus[root.activeMenu] || root.menus.root
  }

  function headerText() {
    if (root.filterText)
      return root.filterText
    return (root.currentMenu().title || "Control") + "…"
  }

  function rebuildDisplay() {
    var menu = root.currentMenu()
    var rows = menu.rows || []
    var q = root.filterText.trim().toLowerCase()

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (q && String(row.label).toLowerCase().indexOf(q) < 0 && String(row.id).toLowerCase().indexOf(q) < 0)
        continue
      displayModel.append({
        itemId: row.id,
        kind: row.kind,
        icon: row.icon || "",
        label: row.label,
        domain: row.domain || "",
        mode: row.mode || ""
      })
    }

    if (displayModel.count === 0) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count) {
      root.selectedIndex = displayModel.count - 1
    }
    if (displayModel.count > 0 && !root.cursorActive)
      root.cursorActive = true
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function goBack() {
    if (root.showingResults) {
      if (searchProcess.running)
        searchProcess.running = false
      root.showingResults = false
      root.loading = false
      root.resultRows = []
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = true
      root.rebuildDisplay()
      return
    }
    if (root.navStack.length === 0) {
      root.dismiss()
      return
    }
    root.activeMenu = root.navStack.pop()
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.kind === "menu") {
      root.navStack.push(root.activeMenu)
      root.activeMenu = row.itemId
      root.filterText = ""
      root.selectedIndex = 0
      root.cursorActive = true
      root.rebuildDisplay()
      return
    }
    if (row.kind === "action" && row.domain && row.mode) {
      root.runComtrol(row.domain, row.mode, row.label)
      return
    }
  }

  function runComtrol(domain, mode, title) {
    root.pendingDomain = domain
    root.pendingMode = mode
    root.resultsTitle = title || (domain + " " + mode)
    root.showingResults = true
    root.loading = true
    root.resultRows = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.rebuildDisplay()

    var argv = [root.runScript(), domain, mode]
    searchProcess.command = argv
    searchProcess.running = true
  }

  // Parse human-readable cOMtrol stdout into menu rows.
  // Entries start on a non-indented line; indented lines are ignored for the label.
  function parseResults(text) {
    var lines = String(text || "").split("\n")
    var rows = []
    var i
    for (i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line || line.charAt(0) === " " || line.charAt(0) === "\t")
        continue
      if (/^\d+\s+result\(s\)/.test(line))
        continue

      var label = line
      var em = line.indexOf("  —  ")
      if (em >= 0)
        label = line.substring(0, em)

      rows.push({
        id: "result." + rows.length,
        label: label,
        icon: "󰈔",
        kind: "result"
      })
    }
    return rows
  }

  ListModel { id: displayModel }

  Process {
    id: searchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.resultRows = root.parseResults(text)
        root.loading = false
        root.selectedIndex = 0
        root.cursorActive = root.resultRows.length > 0
        root.rebuildDisplay()
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || !String(text).trim())
          return
        if (root.loading && root.resultRows.length === 0) {
          root.resultRows = [{
            id: "result.error",
            label: String(text).trim().split("\n")[0],
            icon: "󰀦",
            kind: "result"
          }]
          root.loading = false
          root.rebuildDisplay()
        }
      }
    }
    onExited: function(exitCode) {
      if (!root.loading)
        return
      if (exitCode !== 0 && root.resultRows.length === 0) {
        root.resultRows = [{
          id: "result.error",
          label: "cOMtrol failed (exit " + exitCode + ")",
          icon: "󰀦",
          kind: "result"
        }]
      }
      root.loading = false
      root.rebuildDisplay()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "comtrol-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.goBack()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerText()
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string label
              required property string domain
              required property string mode

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"
              borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(12)

                Text {
                  textFormat: Text.PlainText
                  text: row.icon
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(24)
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  width: parent.width - Style.space(24) - Style.space(12) - Style.space(16) - Style.space(24)
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  width: Style.space(16)
                  height: parent.height
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = index
                  root.activateIndex(index)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: displayModel.count === 0
            text: root.loading ? "Loading…" : "No matches"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
