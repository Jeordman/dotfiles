# herdr-snooze

Snooze a Space. It sinks to the bottom of the sidebar with a `💤` countdown,
then moves back to where it was and alerts you when the timer runs out.

Not stowed. Linked machine-locally with `herdr plugin link`, so it does not
reach the other machines until it earns its place in `STOW_PACKAGES`.

## Why it looks like this

The obvious design is a collapsible "Snoozed" folder. Herdr cannot do that for
ordinary Spaces, checked against 0.9.1:

- The socket API has no collapse, fold, group, hide, or archive concept.
- `[ui.sidebar.spaces]` has only `rows` and `row_gap`, so there is no way to
  draw a section header.
- Collapsible groups do exist, but only as **worktree groups**: a parent Space
  with indented children. There is no re-parent call (`worktree.*` is
  create/list/open/remove), and Spaces built with `workspace.create` report
  `worktree: null`, so a live Space cannot join one. Moving it in would mean
  destroying and recreating it, losing its panes and agent sessions.
- Worktree groups also draw `├─`/`└─` connector lines with no key to disable
  them, across all 208 config keys. That tradeoff was already rejected once,
  on 2026-08-30, when repo-grouping the sidebar was investigated.

So "snoozed" is: bottom of the list, contiguous, tagged. Nothing is hidden and
nothing is destroyed.

## What it cannot do

**Snoozed Spaces still notify.** Herdr has no per-workspace mute.
`notification.show` is send-only, `[ui.toast] delivery` and `[ui.sound]
enabled` are global, and `[ui.sound.agents]` keys on agent type, not
workspace. Silencing a snoozed Space would mean silencing everything.

## Install

```bash
herdr plugin link ~/dotfiles/herdr-snooze
```

Then add the sidebar token and a keybind to `herdr/.config/herdr/config.toml`
(see "Config" below) and run `herdr server reload-config`.

Remove with `herdr plugin unlink jeordin.snooze`.

## Config

The countdown only renders if `$snooze` is in the Space row layout:

```toml
[ui.sidebar.spaces]
rows = [["state_icon", "workspace", "$snooze"], ["branch", "git_status"]]

[[keys.command]]
key = "prefix+z"
type = "plugin_action"
command = "jeordin.snooze.snooze-picker"
description = "Snooze"
```

`prefix+z` is herdr's default zoom, so zoom moves to `prefix+shift+z` in the
`[keys]` block. `s` was unavailable in every form: `prefix+s` is
workspace_picker, `prefix+shift+s` is settings.

Edit the repo copy, never `~/.config/herdr/config.toml` — that path is the
stow symlink and herdr rewrites it at runtime.

## Use

`prefix+z` opens an fzf popup: 30m, 1h, 2h, 4h, tomorrow 9am, Monday, 3d,
1w, or a free-form entry. From a shell:

```bash
python3 snooze.py snooze 2h          # the focused Space
python3 snooze.py snooze "thu 9am" wAM
python3 snooze.py list
python3 snooze.py wake wAM
python3 snooze.py wake-all
```

The list is a shortcut, not a menu: anything typed that is already a valid
duration wins over it. fzf runs with `--exact` and the typed query is
validated first, because fuzzy matching turned `1m` into the `15m` row and
silently snoozed for the wrong length.

j/k move through the list while you type, with no mode switch, because no
valid entry contains either letter. If the parser ever accepts a word with a j
or k in it, that binding in `picker.sh` has to go.

The header shows the exact wake time as you type ("wakes tomorrow 8:59pm
(in 1d 5h)"), for the typed entry or the highlighted row by the same rule, and
each row shows its own wake time beside it. Both come from `snooze.py when`
and `snooze.py rows`, which use the same parser as the snooze itself, so the
preview and the result cannot disagree. Search matches the duration column
only, so typing `9` finds the 9am rows rather than every time with a 9 in it.

The popup's colours are the herdr theme tokens from `config.toml` (neutral
greys, white accent), not fzf's defaults; the rows keep the Kanagawa
fujiWhite/fujiGray pair that `herdr-agent-picker` also uses.

Durations: `45m`, `2h`, `3d`, `1w`, and compounds like `2h30m`. Clock times:
`9am`, `14:30`. Days: `tomorrow 9am`, `mon`, `thu 5pm`. Bare times and
weekdays resolve to the next future occurrence; a bare weekday defaults to 9am.

Snoozing a Space that is already asleep offers "Wake now" at the top of the
picker, so `prefix+z` cancels as easily as it sets.

Only an expiring timer alerts. Waking a Space yourself is silent, because you
are already looking at it.

macOS suppresses banners from the frontmost app, so a wake that fires while
you are looking at herdr is audible but not visible. That is macOS, not herdr;
`[ui.toast] delivery = "terminal"` hands the toast to Ghostty either way.

## How it runs

Ordering uses `workspace.move` and `workspace.move_block`, which exist only on
the socket API at `~/.config/herdr/herdr.sock`, not the `herdr` CLI. That is
undocumented and can break on upgrade; `snooze.py` is the only thing that
talks to it.

A single ticker process refreshes countdowns every 60s and wakes anything due.
It starts on the first snooze, is restarted by the plugin's startup hook after
a herdr restart, and exits by itself once nothing is snoozed — so there is no
launchd agent and no process running when nothing is snoozed. Singleton guard
is a pidfile beside the state.

State lives in `HERDR_PLUGIN_STATE_DIR` (falling back to
`~/.local/state/herdr-snooze/`), never in this repo.

### Several machines

Everything is keyed per herdr server: `state-<key>.json` and
`daemon-<key>.pid`, where the key is a hash of the socket path. Workspace ids
are only unique within one server, so two machines can both have a `w1`; a
single state file would let a remote Space overwrite a local one's timer and
label.

That makes each machine independent rather than making one install manage
several. Snoozing a remote Space needs the plugin installed on that machine
too, because herdr "does not copy local command plugins, configuration,
executables, or secrets onto SSH hosts". Each machine then gets its own
sleeping block at the bottom of its own sidebar section.

Sidebar tokens carry a 5 minute TTL against a 60s tick, so a dead ticker
clears the countdown instead of leaving a stale number on the row.

### Restoring position

Raw list indices do not survive: snoozing sinks a Space, which shifts
everything below it, so a second snooze would record an already-shifted index
and Spaces would creep toward the top as they woke. Instead `state.json` keeps
a `home_order`, refreshed from the live sidebar only while nothing is snoozed,
since that is the only moment the order reflects what you arranged. A waking
Space is inserted after every unsnoozed Space that outranks it there.
