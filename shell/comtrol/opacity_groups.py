#!/usr/bin/env python3
"""Discover Omarchy Hyprland opacity rules and persist cOMtrol overrides."""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys

OMARCHY = pathlib.Path(os.environ.get("OMARCHY_PATH") or "/usr/share/omarchy")
HYPR_DEFAULT = OMARCHY / "default" / "hypr"
HOME = pathlib.Path.home()
USER_HYPR = HOME / ".config" / "hypr"
OPACITY_FILE = USER_HYPR / "comtrol-opacity.lua"
LOOKNFEEL = USER_HYPR / "looknfeel.lua"
HYPRLAND = USER_HYPR / "hyprland.lua"

MEDIA_CLASS = (
    "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|"
    "com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$"
)

# Logical groups: id, label, icon, rules to apply, optional source file hints.
GROUP_DEFS = [
    {
        "id": "default",
        "label": "Default",
        "icon": "󰖲",
        "rules": [{"type": "tag", "value": "default-opacity"}],
        "defaults": (98, 96),
        "sources": ["windows.lua"],
    },
    {
        "id": "terminal",
        "label": "Terminal",
        "icon": "",
        "rules": [{"type": "tag", "value": "terminal"}],
        "defaults": (100, 100),
        "sources": ["apps/terminals.lua"],
    },
    {
        "id": "browser",
        "label": "Browser",
        "icon": "󰖟",
        "rules": [
            {"type": "tag", "value": "chromium-based-browser"},
            {"type": "tag", "value": "firefox-based-browser"},
        ],
        "defaults": (100, 98),
        "sources": ["apps/browser.lua"],
    },
    {
        "id": "steam",
        "label": "Steam",
        "icon": "󰓓",
        "rules": [{"type": "class", "value": "steam.*"}],
        "defaults": (100, 100),
        "sources": ["apps/steam.lua"],
    },
    {
        "id": "media",
        "label": "Media",
        "icon": "󰕼",
        "rules": [{"type": "class", "value": MEDIA_CLASS}],
        "defaults": (100, 100),
        "sources": ["apps/system.lua"],
    },
    {
        "id": "pip",
        "label": "PiP",
        "icon": "󰐝",
        "rules": [{"type": "tag", "value": "pip"}],
        "defaults": (100, 100),
        "sources": ["apps/pip.lua"],
    },
    {
        "id": "qemu",
        "label": "QEMU",
        "icon": "󰍺",
        "rules": [{"type": "class", "value": "qemu"}],
        "defaults": (100, 100),
        "sources": ["apps/qemu.lua"],
    },
    {
        "id": "retroarch",
        "label": "RetroArch",
        "icon": "󰊖",
        "rules": [{"type": "class", "value": "com.libretro.RetroArch"}],
        "defaults": (100, 100),
        "sources": ["apps/retroarch.lua"],
    },
    {
        "id": "davinci",
        "label": "DaVinci",
        "icon": "󰕧",
        "rules": [{"type": "class", "value": ".*[Rr]esolve.*"}],
        "defaults": (100, 100),
        "sources": ["apps/davinci-resolve.lua"],
    },
    {
        "id": "hermes",
        "label": "Hermes",
        "icon": "󰒍",
        "rules": [{"type": "class", "value": "^Hermes$"}],
        "defaults": (100, 100),
        "sources": ["apps/hermes.lua"],
    },
    {
        "id": "webcam",
        "label": "Webcam",
        "icon": "󰖠",
        "rules": [{"type": "class", "value": "^WebcamOverlay-(small|medium|large)$"}],
        "defaults": (100, 100),
        "sources": ["apps/webcam-overlay.lua"],
    },
]

OPACITY_RE = re.compile(r'opacity\s*=\s*"([^"]+)"')
SAVED_RE = re.compile(
    r'name\s*=\s*"comtrol-opacity-([a-z0-9-]+)".*?opacity\s*=\s*"([^"]+)"',
    re.S,
)


def parse_pair(raw: str) -> tuple[int, int]:
    parts = raw.replace("override", " ").split()
    nums = []
    for p in parts:
        try:
            nums.append(float(p))
        except ValueError:
            continue
        if len(nums) >= 2:
            break
    if not nums:
        return 100, 100
    if len(nums) == 1:
        nums.append(nums[0])
    return max(1, min(100, round(nums[0] * 100))), max(1, min(100, round(nums[1] * 100)))


def read_source_defaults() -> dict[str, tuple[int, int]]:
    found: dict[str, tuple[int, int]] = {}
    if not HYPR_DEFAULT.exists():
        return found
    for group in GROUP_DEFS:
        for rel in group.get("sources") or []:
            path = HYPR_DEFAULT / rel
            if not path.exists():
                continue
            text = path.read_text()
            m = OPACITY_RE.search(text)
            if m:
                found[group["id"]] = parse_pair(m.group(1))
                break
    # User/theme terminal overrides often live outside defaults.
    for path in (USER_HYPR / "hyprland.lua", USER_HYPR / "looknfeel.lua"):
        if not path.exists():
            continue
        text = path.read_text()
        if 'tag = "terminal"' in text or "tag = 'terminal'" in text:
            for m in OPACITY_RE.finditer(text):
                # Prefer the opacity near a terminal mention.
                start = max(0, m.start() - 200)
                chunk = text[start : m.end() + 20]
                if "terminal" in chunk:
                    found["terminal"] = parse_pair(m.group(1))
                    break
    return found


def read_saved() -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    if not OPACITY_FILE.exists():
        return out
    text = OPACITY_FILE.read_text()
    # Per-rule blocks are small; match each window_rule separately.
    for block in re.finditer(
        r'hl\.window_rule\(\{(.*?)\}\)',
        text,
        re.S,
    ):
        body = block.group(1)
        name_m = re.search(r'name\s*=\s*"comtrol-opacity-([^"]+)"', body)
        op_m = re.search(r'opacity\s*=\s*"([^"]+)"', body)
        if not name_m or not op_m:
            continue
        gid = name_m.group(1)
        # browser has -0 -1 suffixes
        gid = re.sub(r"-\d+$", "", gid)
        out[gid] = parse_pair(op_m.group(1))
    return out


def build_groups(include_saved: bool = True) -> list[dict]:
    source = read_source_defaults()
    saved = read_saved() if include_saved else {}
    groups = []
    for g in GROUP_DEFS:
        gid = g["id"]
        active, inactive = g["defaults"]
        if gid in source:
            active, inactive = source[gid]
        if gid in saved:
            active, inactive = saved[gid]
        groups.append(
            {
                "id": gid,
                "label": g["label"],
                "icon": g["icon"],
                "active": active,
                "inactive": inactive,
                "rules": g["rules"],
            }
        )
    return groups


def pct(n: int) -> str:
    return f"{max(1, min(100, int(n))) / 100:.2f}"


def rule_lua(name: str, rule: dict, active: int, inactive: int) -> str:
    op = f'{pct(active)} override {pct(inactive)} override'
    if rule["type"] == "tag":
        match = f'match = {{ tag = "{rule["value"]}" }}'
    else:
        # class regex — escape for lua string
        val = rule["value"].replace("\\", "\\\\").replace('"', '\\"')
        match = f'match = {{ class = "{val}" }}'
    return (
        "hl.window_rule({\n"
        f'  name = "{name}",\n'
        f"  {match},\n"
        f'  opacity = "{op}",\n'
        "})"
    )


def render_file(groups: list[dict]) -> str:
    lines = [
        "-- Managed by cOMtrol. Do not edit by hand.",
        "hl.config({",
        "  decoration = {",
        "    active_opacity = 1.0,",
        "    inactive_opacity = 1.0,",
        "  },",
        "})",
        "",
    ]
    for g in groups:
        for i, rule in enumerate(g["rules"]):
            name = f"comtrol-opacity-{g['id']}" if len(g["rules"]) == 1 else f"comtrol-opacity-{g['id']}-{i}"
            lines.append(rule_lua(name, rule, g["active"], g["inactive"]))
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def upsert_marker(path: pathlib.Path, begin: str, end: str, block: str) -> None:
    text = path.read_text() if path.exists() else ""
    if not block.endswith("\n"):
        block += "\n"
    start = text.find(begin)
    if start >= 0:
        stop = text.find(end, start)
        if stop >= 0:
            stop += len(end)
            if stop < len(text) and text[stop] == "\n":
                stop += 1
            text = text[:start] + block + text[stop:]
        else:
            text = text.rstrip() + "\n\n" + block
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += ("\n" if text else "") + block
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def ensure_hyprland_require() -> None:
    if not HYPRLAND.exists():
        return
    text = HYPRLAND.read_text()
    text = re.sub(
        r"\n-- Terminals:.*?o\.window\(\{\s*tag\s*=\s*\"terminal\"\s*\},\s*\{\s*opacity\s*=\s*\"[^\"]+\"\s*\}\)\s*\n",
        "\n",
        text,
        count=1,
        flags=re.S,
    )
    require_block = (
        "-- BEGIN COMTROL-OPACITY-REQUIRE\n"
        'pcall(function() require("hypr.comtrol-opacity") end)\n'
        "-- END COMTROL-OPACITY-REQUIRE\n"
    )
    begin, end = "-- BEGIN COMTROL-OPACITY-REQUIRE", "-- END COMTROL-OPACITY-REQUIRE"
    start = text.find(begin)
    if start >= 0:
        stop = text.find(end, start)
        if stop >= 0:
            stop += len(end)
            if stop < len(text) and text[stop] == "\n":
                stop += 1
            text = text[:start] + require_block + text[stop:]
        else:
            text = text.rstrip() + "\n\n" + require_block
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\n" + require_block
    HYPRLAND.write_text(text)


def strip_legacy_looknfeel_opacity() -> None:
    if not LOOKNFEEL.exists():
        return
    text = LOOKNFEEL.read_text()
    begin, end = "-- BEGIN COMTROL-OPACITY", "-- END COMTROL-OPACITY"
    start = text.find(begin)
    if start < 0:
        return
    stop = text.find(end, start)
    if stop < 0:
        return
    stop += len(end)
    if stop < len(text) and text[stop] == "\n":
        stop += 1
    LOOKNFEEL.write_text(text[:start] + text[stop:])


def cmd_scan() -> None:
    print(json.dumps({"groups": build_groups(include_saved=True)}, separators=(",", ":")))


def cmd_defaults() -> None:
    print(json.dumps({"groups": build_groups(include_saved=False)}, separators=(",", ":")))


def cmd_reset() -> None:
    groups = build_groups(include_saved=False)
    OPACITY_FILE.write_text(render_file(groups))
    ensure_hyprland_require()
    strip_legacy_looknfeel_opacity()
    print(json.dumps({"ok": True, "groups": groups}, separators=(",", ":")))


def cmd_save() -> None:
    if len(sys.argv) >= 3:
        raw = sys.argv[2]
        if raw.startswith("@") and pathlib.Path(raw[1:]).exists():
            raw = pathlib.Path(raw[1:]).read_text()
    else:
        raw = sys.stdin.read()
    data = json.loads(raw or "{}")
    incoming = {g["id"]: g for g in data.get("groups") or []}
    groups = build_groups(include_saved=True)
    for g in groups:
        if g["id"] in incoming:
            g["active"] = int(incoming[g["id"]].get("active", g["active"]))
            g["inactive"] = int(incoming[g["id"]].get("inactive", g["inactive"]))
    OPACITY_FILE.write_text(render_file(groups))
    ensure_hyprland_require()
    strip_legacy_looknfeel_opacity()
    print(json.dumps({"ok": True, "path": str(OPACITY_FILE)}))


def render_eval_lua(groups: list[dict]) -> str:
    parts = [
        "hl.config({ decoration = { active_opacity = 1.0, inactive_opacity = 1.0 } })"
    ]
    for g in groups:
        gid = g["id"]
        active = int(g["active"])
        inactive = int(g["inactive"])
        rules = g.get("rules") or []
        # Prefer GROUP_DEFS rules if missing from payload.
        if not rules and gid in {x["id"]: x for x in GROUP_DEFS}:
            rules = next(x["rules"] for x in GROUP_DEFS if x["id"] == gid)
        for i, rule in enumerate(rules):
            name = (
                f"comtrol-opacity-{gid}"
                if len(rules) == 1
                else f"comtrol-opacity-{gid}-{i}"
            )
            op = f"{pct(active)} override {pct(inactive)} override"
            if rule["type"] == "tag":
                match = f'match = {{ tag = "{rule["value"]}" }}'
            else:
                val = rule["value"].replace("\\", "\\\\").replace('"', '\\"')
                match = f'match = {{ class = "{val}" }}'
            parts.append(
                f'hl.window_rule({{ name = "{name}", {match}, opacity = "{op}" }})'
            )
    return "; ".join(parts)


def cmd_eval_lua() -> None:
    """Print hyprctl eval lua for one group from argv: id active inactive"""
    if len(sys.argv) < 5:
        raise SystemExit("usage: opacity_groups.py eval-lua <id> <active> <inactive>")
    gid, active, inactive = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    groups = {g["id"]: g for g in GROUP_DEFS}
    if gid not in groups:
        raise SystemExit(f"unknown group {gid}")
    g = {
        "id": gid,
        "active": active,
        "inactive": inactive,
        "rules": groups[gid]["rules"],
    }
    print(render_eval_lua([g]))


def cmd_eval_all() -> None:
    """Print hyprctl eval lua for all groups from JSON argv/file."""
    if len(sys.argv) >= 3:
        raw = sys.argv[2]
        if raw.startswith("@") and pathlib.Path(raw[1:]).exists():
            raw = pathlib.Path(raw[1:]).read_text()
    else:
        raw = sys.stdin.read()
    data = json.loads(raw or "{}")
    incoming = data.get("groups") or []
    # Merge with known rule definitions.
    defs = {g["id"]: g for g in GROUP_DEFS}
    groups = []
    for item in incoming:
        gid = str(item.get("id") or "")
        if gid not in defs:
            continue
        groups.append(
            {
                "id": gid,
                "active": int(item.get("active", defs[gid]["defaults"][0])),
                "inactive": int(item.get("inactive", defs[gid]["defaults"][1])),
                "rules": defs[gid]["rules"],
            }
        )
    if not groups:
        groups = [
            {
                "id": g["id"],
                "active": g["defaults"][0],
                "inactive": g["defaults"][1],
                "rules": g["rules"],
            }
            for g in GROUP_DEFS
        ]
    print(render_eval_lua(groups))


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("usage: opacity_groups.py scan|defaults|reset|save|eval-lua|eval-all ...", file=sys.stderr)
        raise SystemExit(2)
    cmd = sys.argv[1]
    if cmd == "scan":
        cmd_scan()
    elif cmd == "defaults":
        cmd_defaults()
    elif cmd == "reset":
        cmd_reset()
    elif cmd == "save":
        cmd_save()
    elif cmd == "eval-lua":
        cmd_eval_lua()
    elif cmd == "eval-all":
        cmd_eval_all()
    else:
        raise SystemExit(f"unknown command {cmd}")


if __name__ == "__main__":
    main()
