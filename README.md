# cOMtrol

> **Disclaimer:** cOMtrol is still in active development. Stability is not guaranteed — features change, bugs are still being found and fixed, and things may break. Use at your own risk.

Omarchy shell **menu** plugin — a control hub for appearance, apps, search, install, config, reset, and power actions.

Plugin ID: `com.github.davorbervida.comtrol`

## Toggle

Open or close cOMtrol from the shell:

```bash
omarchy-shell shell toggle com.github.davorbervida.comtrol
```

### Keybinding

Omarchy does not assign a shortcut on install. Add one in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + SPACE", "cOMtrol", "omarchy-shell shell toggle com.github.davorbervida.comtrol")
```

Pick any free chord. Check existing binds with `omarchy menu keybindings --print`. If the key is already taken, unbind it first:

```lua
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "cOMtrol", "omarchy-shell shell toggle com.github.davorbervida.comtrol")
```

Hyprland usually reloads on save; otherwise run `hyprctl reload`.

## Install

```bash
omarchy plugin add https://github.com/davorbervida/comtrol.git --enable
```

Then open it with the toggle command above, a keybinding, or from the Omarchy menu.

### Web search dependency

**Search → Web** (YouTube, Reddit, Google, DuckDuckGo, X, Wikipedia) needs **Node.js** on the system.

- If Node is missing, the **Web** entry is hidden.
- On first open of Web, the plugin runs `npm install` in `scripts/node/search/` (Puppeteer + Chromium). That can take a minute; the header shows `installing…`.

Optional manual setup:

```bash
cd ~/.config/omarchy/plugins/com.github.davorbervida.comtrol/scripts/node/search
npm install
```

## Remove

```bash
omarchy plugin remove com.github.davorbervida.comtrol
```

Or disable without removing:

```bash
omarchy plugin disable com.github.davorbervida.comtrol
```

## Update

```bash
omarchy plugin update com.github.davorbervida.comtrol
```

## Features

### Appearance
- **Themes** — browse and apply installed Omarchy themes
- **Backgrounds** — current theme, all themes, my wallpapers, all wallpapers
- **Unlock** — boot/unlock screen backgrounds
- **Fonts** — change UI font and text size
- **Desktop** — bar/desktop look: blur, shadows, opacity groups, position

### Apps
- **Desktop** — launch installed desktop applications
- **Packages** — list local pacman packages; remove with shortcut
- **AUR** — list foreign/AUR packages
- **Web Apps** — list and launch web apps; remove with shortcut

### Search
- **Local** — Audio, Video, Images, Files, Documents, Directories under `$HOME` (fast `find`-based)
- **Web** — YouTube, Reddit, Google, DuckDuckGo, X, Wikipedia (shared warm headless browser)

### Install
- Install **Themes**, **Plugins** (plugins.omarchy.org), **Packages**, **AUR** from the web catalogs
- **Update** — Omarchy update and related actions

### Config
- Channel, password, timezone, default apps (browser/terminal/editor/agent), and related Omarchy settings

### Reset
- Config / Process / Hardware reset actions (Omarchy helpers)

### Power
- Screensaver, lock, suspend, hibernate, reboot, shutdown (availability-aware)

## Keybindings

### Main menu / lists
| Key | Action |
|-----|--------|
| **Esc** | Dismiss / close cOMtrol |
| **↑** / **↓** | Move selection |
| **Enter** / **→** | Activate selected item |
| **←** / **Backspace** | Go back (or dismiss at root) |
| **Type** | Filter current menu (live search where supported) |
| **←** / **→** | Adjust slider when a slider row is selected |
| **Ctrl+R** | Remove selected item (local packages, web apps, or local plugins) |
| **Ctrl+S** | Toggle enable/disable for selected local plugin |
| **Ctrl+H** | Toggle hidden files during local file search |

### Theme / background / unlock previews
| Key | Action |
|-----|--------|
| **Esc** | Dismiss |
| **Enter** | Apply / confirm |
| **←** / **→** or **Tab** / **Shift+Tab** | Previous / next item |
| **Backspace** | Go back |
| **Type** | Filter |
| **Ctrl+R** | Remove selected (themes); **Ctrl+R** or **Shift+R** on backgrounds |

### Plugin browse (Install → Plugins)
| Key | Action |
|-----|--------|
| **Esc** | Dismiss |
| **↑** **↓** **←** **→** | Move in grid |
| **Enter** | Open plugin details |
| **Backspace** | Go back |
| **Type** | Filter catalog |

### Plugin details
| Key | Action |
|-----|--------|
| **Esc** | Dismiss |
| **←** / **Backspace** | Back to browse |
| **Enter** | Install or remove (depending on state) |
| **Ctrl+A** | Add / install |
| **Ctrl+R** | Remove |
| **H** | Send heart on plugins.omarchy.org |

## License

MIT — see [LICENSE](LICENSE).
