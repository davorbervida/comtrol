import QtQuick

// Root → Search — home-directory file/folder discovery by type.
QtObject {
  id: root

  readonly property string itemId: "search"
  readonly property string label: "Search"
  readonly property string icon: "󰍉"
  readonly property string title: "Search"

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
      { itemId: "search.directories", label: "Directories", icon: "󰉋", kind: "action", domain: "search", mode: "directories" }
    ]
  })
}
