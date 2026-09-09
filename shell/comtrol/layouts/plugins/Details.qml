import QtQuick
import Quickshell.Io
import qs.Commons

// Full plugin detail view opened from Browse.
Item {
  id: root

  property var plugin: ({})
  property bool layoutSettled: false
  property bool heartBusy: false
  property bool heartSent: false

  property color dimColor: Color.background
  property color foreground: Color.menu.text
  property color cardBackground: Color.menu.background
  property color borderColor: Color.menu.border
  property color selectedBorder: Color.menu.selectedBorder
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal backRequested()
  signal dismissRequested()
  signal heartSentFor(string pluginId)
  // Do not name this installedChanged — clashes with property `installed`.
  signal refreshInstalledRequested()

  readonly property string pluginId: String(plugin.id || plugin["id"] || "")
  readonly property string preview: String(plugin.preview || plugin.preview_image || "")
  readonly property string tagsText: {
    var tags = plugin.tags || []
    var parts = []
    if (tags && tags.length !== undefined) {
      for (var i = 0; i < tags.length; i++)
        parts.push(String(tags[i]))
    }
    return parts.join(" · ")
  }
  readonly property int heartsCount: Number(plugin.hearts || 0) + (heartSent ? 1 : 0)
  readonly property int starsCount: Number(plugin.stars || 0)
  readonly property bool installed: !!(plugin.installed || plugin["installed"])
  readonly property bool canInstall: {
    var cmd = String(plugin.install_command || "")
    return cmd.length > 0 || !!(plugin.install_available || plugin["install_available"])
  }
  readonly property bool showActionButton: installed || canInstall
  readonly property string actionIcon: installed ? "󰆴" : "󰐕"
  readonly property string actionLabel: installed ? "Remove" : "Add"

  function runScript() {
    var url = Qt.resolvedUrl("../../run.sh").toString()
    if (url.indexOf("file://") === 0)
      url = url.substring(7)
    return url
  }

  function clear() {
    root.plugin = ({})
    root.heartBusy = false
    root.heartSent = false
    if (applyProc.running)
      applyProc.running = false
    if (removeProc.running)
      removeProc.running = false
  }

  function applyPlugin(plugin) {
    var target = plugin || root.plugin
    if (!target)
      return
    // Catalog install_command is typically: "omarchy plugin add <git-url> --enable"
    var cmd = String(target.install_command || "").trim()
    if (!cmd)
      return
    // Quickshell Process has no TTY — omarchy-plugin-add refuses without --yes.
    if (cmd.indexOf("--yes") < 0 && !/(^|\s)-y(\s|$)/.test(cmd))
      cmd += " --yes"
    if (applyProc.running)
      applyProc.running = false
    applyProc.command = ["bash", "-lc", cmd]
    applyProc.running = true
  }

  function removePlugin(plugin) {
    var target = plugin || root.plugin
    if (!target)
      return
    var id = String(target.id || target["id"] || "")
    if (!id)
      return
    if (removeProc.running)
      removeProc.running = false
    removeProc.command = [root.runScript(), "-r", "-plugin", id]
    removeProc.running = true
  }

  onPluginChanged: {
    root.heartBusy = false
    root.heartSent = false
    root.revealWhenSettled()
  }

  function imageSource(path) {
    var p = String(path || "")
    if (!p)
      return ""
    if (p.indexOf("http://") === 0 || p.indexOf("https://") === 0 || p.indexOf("file://") === 0)
      return p
    return Util.fileUrl(p)
  }

  function revealWhenSettled() {
    Qt.callLater(function() {
      if (root.visible) {
        root.layoutSettled = true
        focusScope.forceActiveFocus()
      }
    })
  }

  function focusDetail() {
    if (root.visible && root.layoutSettled)
      focusScope.forceActiveFocus()
  }

  function sendHeart() {
    if (!root.pluginId || root.heartBusy || root.heartSent)
      return
    root.heartBusy = true
    var body = JSON.stringify({ pluginId: root.pluginId, type: "heart" })
    heartProc.command = [
      "curl", "-fsS", "-X", "POST",
      "https://api.omarchyplugins.com/v1/events",
      "-H", "Content-Type: application/json",
      "-H", "Accept: application/json",
      "-H", "Origin: https://plugins.omarchy.org",
      "-H", "Referer: https://plugins.omarchy.org/",
      "--data-binary", body
    ]
    heartProc.running = true
  }

  Component.onCompleted: revealWhenSettled()
  onVisibleChanged: if (visible) revealWhenSettled()

  Process {
    id: applyProc
    onExited: function(exitCode) {
      if (exitCode === 0)
        root.refreshInstalledRequested()
    }
  }

  Process {
    id: removeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function() {
      root.refreshInstalledRequested()
    }
  }

  Process {
    id: heartProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.heartBusy = false
      if (exitCode === 0) {
        root.heartSent = true
        root.heartSentFor(root.pluginId)
      }
    }
  }

  Item {
    id: focusScope
    anchors.fill: parent
    visible: root.layoutSettled && !!root.pluginId
    focus: true

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.dismissRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) {
        root.backRequested()
        event.accepted = true
      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.showActionButton) {
        if (root.installed)
          root.removePlugin(root.plugin)
        else
          root.applyPlugin(root.plugin)
        event.accepted = true
      } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ShiftModifier) && root.canInstall && !root.installed) {
        root.applyPlugin(root.plugin)
        event.accepted = true
      } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ShiftModifier) && root.installed) {
        root.removePlugin(root.plugin)
        event.accepted = true
      } else if (event.key === Qt.Key_H) {
        root.sendHeart()
        event.accepted = true
      }
    }

    MouseArea { anchors.fill: parent; onClicked: {} }

    Rectangle {
      id: panel
      width: Math.min(parent.width - Style.gapsOut * 2, Style.space(1100))
      height: Math.min(parent.height - Style.gapsOut * 2, Style.space(560))
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.cardBackground
      border.width: 1
      border.color: root.borderColor
      clip: true

      // Left: preview image — full width of pane, fit inside without overflow
      Item {
        id: leftPane
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.round(parent.width * 0.58)
        clip: true

        Image {
          anchors.fill: parent
          anchors.margins: Style.space(24)
          visible: !!root.preview
          source: root.preview ? root.imageSource(root.preview) : ""
          fillMode: Image.PreserveAspectFit
          verticalAlignment: Image.AlignTop
          horizontalAlignment: Image.AlignHCenter
          asynchronous: true
          cache: true
        }
      }

      // Right: information
      Item {
        id: rightPane
        anchors.left: leftPane.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Flickable {
          id: scroller
          anchors.fill: parent
          anchors.leftMargin: 0
          anchors.topMargin: Style.space(24)
          anchors.rightMargin: Style.space(24)
          anchors.bottomMargin: Style.space(24)
          contentWidth: width
          contentHeight: infoCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: infoCol
            width: scroller.width
            spacing: Style.space(12)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(root.plugin.name || root.pluginId || "Plugin")
              color: root.foreground
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: text.length > 0
              textFormat: Text.PlainText
              text: String(root.plugin.version || "")
              color: root.foreground
              opacity: 0.75
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              visible: text.length > 0
              textFormat: Text.PlainText
              text: String(root.plugin.author || "")
              color: root.foreground
              opacity: 0.75
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              visible: text.length > 0
              textFormat: Text.PlainText
              text: root.tagsText
              color: root.foreground
              opacity: 0.65
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(16)

              Rectangle {
                id: heartBtn
                width: heartRow.implicitWidth + Style.space(16)
                height: Style.space(32)
                radius: Style.cornerRadius
                color: heartArea.containsMouse || root.heartSent
                  ? root.selectedBackground
                  : Util.alpha(root.foreground, 0.08)
                border.width: 1
                border.color: root.heartSent ? root.selectedBorder : root.borderColor
                opacity: root.heartBusy ? 0.6 : 1

                Row {
                  id: heartRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Text {
                    text: "♥"
                    color: root.foreground
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: String(root.heartsCount)
                    color: root.foreground
                    font.pixelSize: Style.font.body
                  }
                }

                MouseArea {
                  id: heartArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  enabled: !root.heartBusy && !root.heartSent && root.pluginId.length > 0
                  onClicked: root.sendHeart()
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "★ " + root.starsCount
                color: root.foreground
                opacity: 0.8
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Number(root.plugin.views || 0) > 0
                textFormat: Text.PlainText
                text: "Views " + Number(root.plugin.views || 0)
                color: root.foreground
                opacity: 0.65
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Number(root.plugin.copies || 0) > 0
                textFormat: Text.PlainText
                text: "Copies " + Number(root.plugin.copies || 0)
                color: root.foreground
                opacity: 0.65
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              width: parent.width
              visible: text.length > 0
              textFormat: Text.PlainText
              text: String(root.plugin.description || "")
              color: root.foreground
              opacity: 0.85
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(20)
              rowSpacing: Style.space(8)

              Text {
                text: "ID"
                color: root.foreground
                opacity: 0.5
                font.pixelSize: Style.font.caption
              }
              Text {
                width: Math.max(40, infoCol.width - Style.space(100))
                text: root.pluginId
                color: root.foreground
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }

              Text {
                text: "Category"
                color: root.foreground
                opacity: 0.5
                font.pixelSize: Style.font.caption
              }
              Text {
                text: String(root.plugin.category || "—")
                color: root.foreground
                font.pixelSize: Style.font.caption
              }

              Text {
                text: "Source"
                color: root.foreground
                opacity: 0.5
                font.pixelSize: Style.font.caption
              }
              Text {
                text: String(root.plugin.source_type || root.plugin.sourceType || "—")
                color: root.foreground
                font.pixelSize: Style.font.caption
              }

              Text {
                text: "Repository"
                color: root.foreground
                opacity: 0.5
                font.pixelSize: Style.font.caption
              }
              Text {
                width: Math.max(40, infoCol.width - Style.space(100))
                text: String(root.plugin.repo || "—")
                color: root.foreground
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }

            Row {
              spacing: Style.space(10)
              visible: root.showActionButton

              Rectangle {
                width: actionRow.implicitWidth + Style.space(24)
                height: Style.space(36)
                radius: Style.cornerRadius
                color: actionArea.containsMouse ? root.selectedBackground : Util.alpha(root.foreground, 0.1)
                border.width: 1
                border.color: root.selectedBorder

                Row {
                  id: actionRow
                  anchors.centerIn: parent
                  spacing: Style.space(8)

                  Text {
                    text: root.actionIcon
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.actionLabel
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                  }
                }

                MouseArea {
                  id: actionArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.installed)
                      root.removePlugin(root.plugin)
                    else
                      root.applyPlugin(root.plugin)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
