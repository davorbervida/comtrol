import QtQuick

// Root → Search — local file discovery + web search hubs.
QtObject {
  id: root

  readonly property string itemId: "search"
  readonly property string label: "Search"
  readonly property string icon: "󰍉"
  readonly property string title: "Search"

  readonly property string webItemId: "search.web"

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property var menu: ({
    title: root.title,
    rows: [
      { itemId: "search.audio", label: "Audio", icon: "󰝚", kind: "action", domain: "search", mode: "audio" },
      { itemId: "search.video", label: "Video", icon: "󰕧", kind: "action", domain: "search", mode: "video" },
      { itemId: "search.images", label: "Images", icon: "󰋩", kind: "action", domain: "search", mode: "images" },
      { itemId: "search.files", label: "Files", icon: "󰈔", kind: "action", domain: "search", mode: "files" },
      { itemId: "search.documents", label: "Documents", icon: "󰧮", kind: "action", domain: "search", mode: "documents" },
      { itemId: "search.directories", label: "Directories", icon: "󰉋", kind: "action", domain: "search", mode: "directories" },
      { itemId: root.webItemId, label: "Web", icon: "󰖟", kind: "menu" }
    ]
  })

  readonly property var webMenu: ({
    title: "Web",
    rows: [
      { itemId: "search.web.youtube", label: "YouTube", icon: "󰗃", kind: "action", domain: "youtube", mode: "web" },
      { itemId: "search.web.reddit", label: "Reddit", icon: "󰑍", kind: "action", domain: "reddit", mode: "web" }
    ]
  })
}