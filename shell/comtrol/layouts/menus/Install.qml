import QtQuick

// Install hub nested under the root Control menu.
QtObject {
  id: root

  readonly property string itemId: "install"
  readonly property string label: "Install"
  readonly property string icon: "󰐕"
  readonly property string title: "Install"

  readonly property var rootRow: ({
    itemId: root.itemId,
    label: root.label,
    icon: root.icon,
    kind: "menu"
  })

  readonly property var menu: ({
    title: root.title,
    rows: [
      { itemId: "install.themes", label: "Themes", icon: "󰏘", kind: "action", domain: "themes", mode: "web" },
      { itemId: "install.plugins", label: "Plugins", icon: "󰐱", kind: "action", domain: "plugins", mode: "web" },
      { itemId: "install.packages", label: "Packages", icon: "󰏖", kind: "action", domain: "packages", mode: "web" },
      { itemId: "install.aurs", label: "AUR", icon: "󰣇", kind: "action", domain: "aurs", mode: "web" }
    ]
  })
}
