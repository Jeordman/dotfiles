---
name: cmux-close-sidebar
description: Hide or show the cmux right sidebar (file explorer) when the user asks to "close", "hide", "open", "show", or "toggle" it. cmux has no built-in shortcut or CLI action for this — visibility is stored in NSUserDefaults under `fileExplorer.isVisible` and only takes effect after a quit/relaunch. Trigger on phrases like "close cmux sidebar", "hide right panel in cmux", "cmux sidebar stuck open", "reopen cmux file explorer".
---

# cmux: Close (or Open) the Right Sidebar

cmux's right sidebar (Files / Find / Sessions / Feed / Dock) has **no toggle shortcut, no setting, and no CLI/RPC action** — verified against the `cmux.schema.json`, `cmux-shortcuts.ts`, and `cmux capabilities` method list. The only way to hide it programmatically is to flip a NSUserDefaults key and relaunch.

## The key

```
domain: com.cmuxterm.app
key:    fileExplorer.isVisible   (bool)
```

Related (read-only context, do not change unless asked):
- `fileExplorer.width` — width in points when visible
- `rightSidebar.mode` — which tab is selected (`files`, `find`, `sessions`, `feed`, `dock`)
- `rightSidebar.beta.dock.enabled`, `rightSidebar.beta.feed.enabled` — feature flags

## Why a simple `defaults write` while cmux is running doesn't work

cmux caches NSUserDefaults in memory and rewrites them on quit. Writing while the app is running gets clobbered. You **must quit cmux first**, then write, then relaunch.

## Procedure

Before running, confirm with the user that **Claude is not running inside cmux** — if it is, quitting cmux kills the current session. Ask once if unclear.

```bash
# 1. Gracefully quit cmux (waits for it to actually exit)
osascript -e 'quit app "cmux"'
sleep 2
pgrep -x cmux && echo "still running — abort" || echo "quit"

# 2. Flip the visibility flag (false=hide, true=show)
defaults write com.cmuxterm.app fileExplorer.isVisible -bool false

# 3. Verify
defaults read com.cmuxterm.app fileExplorer.isVisible   # → 0

# 4. Relaunch
open -a cmux
```

To **re-open** the sidebar later, repeat with `-bool true`.

## Variants

- **Toggle** (read current, flip): `current=$(defaults read com.cmuxterm.app fileExplorer.isVisible 2>/dev/null || echo 0); new=$([ "$current" = "1" ] && echo false || echo true); osascript -e 'quit app "cmux"' && sleep 2 && defaults write com.cmuxterm.app fileExplorer.isVisible -bool "$new" && open -a cmux`
- **Hide without relaunching**: not possible. cmux only reads the value at startup.

## Safety notes

- Workspaces, panes, terminal scrollback, and tab layout are preserved across quit/relaunch — cmux restores from `~/Library/Application Support/cmux/session-com.cmuxterm.app.json`.
- Do **not** delete the session file to "force-close" the sidebar — that nukes every open workspace and pane. The defaults flip is surgical; the session file is not.
- If cmux fails to quit (`pgrep -x cmux` still returns), do not `kill -9` — investigate. A stuck cmux usually means a modal dialog or unsaved feedback form is open.

## When this stops working

cmux ships frequently. If a future version exposes `toggleRightSidebar` as a real action (check `cmux capabilities | grep -i sidebar` and the schema at `https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json`), prefer that over the defaults hack — no relaunch needed.
