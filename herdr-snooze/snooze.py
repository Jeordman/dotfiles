#!/usr/bin/env python3
"""Snooze Herdr Spaces: sink them to the bottom of the sidebar with a
countdown token, then move them back and alert when the timer expires.

Herdr has no folder, collapse, or hide primitive for plain Spaces, so
"snoozed" is modelled as: bottom of the list, contiguous, tagged with a
$snooze token. Nothing is hidden and nothing is destroyed.

Ordering uses workspace.move / workspace.move_block, which exist only on the
socket API (~/.config/herdr/herdr.sock), not the herdr CLI.
"""

import contextlib
import fcntl
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta

SOURCE = "jeordin.snooze"
TOKEN = "snooze"

# Prefixed onto the Space name while it sleeps, and the value the sidebar's
# `starts_with` rule keys off to grey the row out. Changing it means changing
# that rule in config.toml too, or the dimming silently stops matching.
#
# The emoji is double-width. That was a problem when it sat in the countdown
# token and knocked the column out of line; as a name prefix it only has to
# align snoozed rows with each other, which it does.
BADGE = "💤"

# Long enough to survive a late tick, short enough that a dead ticker clears
# the countdown instead of leaving a stale lie on the row.
TOKEN_TTL_MS = 300_000


def server_key():
    """Short id for the herdr server this process talks to.

    Workspace ids are only unique within one server: two machines can both
    have a `w1`. Keying state by bare id would let a remote Space overwrite a
    local one's timer and label, so every server gets its own state file,
    lock and ticker. The socket path is what identifies a server.
    """
    real = os.path.realpath(sock_path())
    return hashlib.sha256(real.encode()).hexdigest()[:8]


def state_dir():
    d = os.environ.get("HERDR_PLUGIN_STATE_DIR") or os.path.expanduser(
        "~/.local/state/herdr-snooze"
    )
    os.makedirs(d, exist_ok=True)
    return d


def state_path():
    d = state_dir()
    p = os.path.join(d, f"state-{server_key()}.json")
    # One-time move from the single-server layout. Only the default socket can
    # have written it, so it belongs to whichever server that resolves to now.
    legacy = os.path.join(d, "state.json")
    if not os.path.exists(p) and os.path.exists(legacy):
        try:
            os.rename(legacy, p)
        except OSError:
            pass
    return p


def load_state():
    try:
        with open(state_path()) as f:
            s = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"version": 1, "snoozes": {}}
    s.setdefault("snoozes", {})
    return s


def save_state(s):
    p = state_path()
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=2)
    os.replace(tmp, p)


@contextlib.contextmanager
def locked_state():
    """Load, mutate, save with nobody else writing in between.

    The ticker, the popup and a CLI wake all mutate this file, and a plain
    load/mutate/save loses whichever write started first: the second process
    saves a snapshot taken before the first one's change. That left Spaces
    tagged in the sidebar but absent from state, so nothing ever woke them.
    """
    lock = state_path() + ".lock"
    with open(lock, "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            state = load_state()
            yield state
            save_state(state)
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def sock_path():
    return os.environ.get("HERDR_SOCKET") or os.path.expanduser(
        "~/.config/herdr/herdr.sock"
    )


def rpc(method, params=None):
    """One JSON-RPC call over the Herdr socket. `id` must be a string."""
    req = json.dumps(
        {"jsonrpc": "2.0", "id": "snooze", "method": method, "params": params or {}}
    )
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    try:
        s.connect(sock_path())
        s.sendall((req + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    finally:
        s.close()
    if not buf.strip():
        raise RuntimeError("no response from herdr socket (is the server running?)")
    resp = json.loads(buf.split(b"\n")[0])
    if "error" in resp:
        raise RuntimeError(f"{method}: {resp['error']}")
    return resp.get("result", {})


def herdr_cli(*args):
    exe = os.environ.get("HERDR_BIN_PATH", "herdr")
    return subprocess.run(
        [exe, *args], capture_output=True, text=True, timeout=10
    )


def workspaces():
    return rpc("workspace.list").get("workspaces", [])


# ---------------------------------------------------------------- durations

WEEKDAYS = {
    "mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6,
}


def parse_when(spec, now=None):
    """Turn a duration or a clock time into an absolute epoch.

    Accepts 45m, 2h, 3d, 1w; 9am, 14:30; "tomorrow 9am"; "thu", "thu 9am".
    Bare clock times and weekdays resolve to the next future occurrence.
    """
    now = now or datetime.now()
    s = spec.strip().lower()

    # One or more unit groups, so "90m", "2h" and "2h30m" all work.
    if re.fullmatch(r"(?:\d+\s*[mhdw]\s*)+", s):
        units = {"m": "minutes", "h": "hours", "d": "days", "w": "weeks"}
        total = timedelta()
        for n, unit in re.findall(r"(\d+)\s*([mhdw])", s):
            total += timedelta(**{units[unit]: int(n)})
        return int((now + total).timestamp())

    day_offset = None
    if s.startswith("tomorrow"):
        day_offset, s = 1, s[len("tomorrow"):].strip()
    else:
        m = re.match(r"(mon|tue|wed|thu|fri|sat|sun)\w*\s*(.*)", s)
        if m:
            target = WEEKDAYS[m.group(1)]
            day_offset = (target - now.weekday()) % 7 or 7
            s = m.group(2).strip()

    hour, minute = 9, 0
    if s:
        m = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", s)
        if not m:
            raise ValueError(f"cannot parse time: {spec!r}")
        hour = int(m.group(1))
        minute = int(m.group(2) or 0)
        ampm = m.group(3)
        if ampm == "pm" and hour != 12:
            hour += 12
        elif ampm == "am" and hour == 12:
            hour = 0
    elif day_offset is None:
        raise ValueError(f"cannot parse: {spec!r}")

    target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if day_offset is not None:
        target += timedelta(days=day_offset)
    elif target <= now:
        target += timedelta(days=1)
    return int(target.timestamp())


def humanize(until, now=None):
    """Short countdown for the sidebar row: 45m, 2h, 3d, or a weekday.

    Rounds to nearest rather than truncating, so a 2h snooze reads "2h"
    instead of flipping to "1h" a second after you set it.
    """
    now = now or int(time.time())
    left = until - now
    if left <= 0:
        return "now"
    if left < 3600:
        return f"{max(1, round(left / 60))}m"
    if left < 86400:
        return f"{max(1, round(left / 3600))}h"
    if left < 7 * 86400:
        return datetime.fromtimestamp(until).strftime("%a %-I%p").lower()
    return f"{max(1, round(left / 86400))}d"


# ------------------------------------------------------------------ sidebar

def set_token(ws_id, text):
    rpc(
        "workspace.report_metadata",
        {
            "workspace_id": ws_id,
            "source": SOURCE,
            "tokens": {TOKEN: text},
            "ttl_ms": TOKEN_TTL_MS,
        },
    )


def clear_token(ws_id):
    try:
        rpc(
            "workspace.report_metadata",
            {"workspace_id": ws_id, "source": SOURCE, "tokens": {TOKEN: None}},
        )
    except RuntimeError:
        pass  # Space may be gone; nothing to clear.


def rename(ws_id, label):
    try:
        rpc("workspace.rename", {"workspace_id": ws_id, "label": label})
    except RuntimeError as e:
        print(f"warn: rename failed: {e}", file=sys.stderr)


def sleep_label(label):
    """Prefix the Space name while it sleeps.

    This is the only way to grey out the whole row. Sidebar value rules match
    a token against its own value, so nothing can style the `workspace` token
    based on separate snooze metadata; the name itself has to carry the mark,
    and a `starts_with = "zzz "` rule then dims it.

    The original is kept in state and restored exactly on wake, because
    gtr-clean matches Spaces by exact label when it tears down orphans.
    """
    return label if label.startswith(f"{BADGE} ") else f"{BADGE} {label}"


def clean_label(label):
    """Strip any sleep prefixes back off.

    Re-snoozing reads the Space's current label, which is already prefixed if
    it was asleep. Storing that verbatim meant waking restored it to
    "💤 dotfiles", so the Space woke but stayed looking asleep for good. Loops
    because a Space re-snoozed twice picked up two prefixes.
    """
    while label.startswith(f"{BADGE} "):
        label = label[len(BADGE) + 1:]
    return label


BRANCH_TOKEN = "branch_"

# The longest herdr allows. Branch names are plugin-owned now, so a dead
# ticker should fade them slowly rather than blanking the sidebar at once.
BRANCH_TTL_MS = 86_400_000

# Zero-width space, prefixed onto a snoozed Space's branch purely so the
# sidebar rule has something to match. A visible mark would repeat the 💤
# already on the name row; a plain space does not work because herdr trims
# surrounding whitespace (U+00A0 is stripped too, U+200B is not).
BRANCH_MARK = "​"


def workspace_cwds():
    """workspace_id -> cwd, taken from panes; workspace payloads carry none."""
    out = {}
    for p in rpc("pane.list").get("panes", []):
        ws = p.get("workspace_id")
        if ws and ws not in out and p.get("cwd"):
            out[ws] = p["cwd"]
    return out


def git_branch(cwd):
    try:
        r = subprocess.run(
            ["git", "-C", cwd, "branch", "--show-current"],
            capture_output=True, text=True, timeout=3,
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def refresh_branches(state, only=None):
    """Report the branch name for every Space as a plugin token.

    Built-in `branch` cannot be dimmed per Space: value rules only ever match
    a token against its own value, so a snoozed row's branch can only fade if
    the plugin owns the value and marks it. The cost is that this must run for
    every Space, always, or the sidebar loses branch names entirely.
    """
    cwds = workspace_cwds()
    for ws_id, cwd in cwds.items():
        if only and ws_id != only:
            continue
        name = git_branch(cwd)
        if not name:
            continue
        if ws_id in state["snoozes"]:
            name = f"{BRANCH_MARK}{name}"
        rpc(
            "workspace.report_metadata",
            {
                "workspace_id": ws_id,
                "source": SOURCE,
                "tokens": {BRANCH_TOKEN: name},
                "ttl_ms": BRANCH_TTL_MS,
            },
        )


def refresh_home_order(state, current_ids):
    """Remember the sidebar order the user actually arranged.

    Raw list indices are useless here: snoozing sinks a Space, which shifts
    everything below it, so a second snooze would record an already-shifted
    index and Spaces would creep toward the top as they woke. Instead the
    running order is only trusted while nothing is snoozed, since that is the
    only moment it reflects intent. After that this list is authoritative and
    new Spaces are appended.
    """
    home = state.get("home_order", [])
    if not state["snoozes"]:
        home = list(current_ids)
    else:
        home += [i for i in current_ids if i not in home]
    state["home_order"] = home
    return home


def home_rank(state, ws_id):
    home = state.get("home_order", [])
    return home.index(ws_id) if ws_id in home else len(home)


def restore_index(state, ws_id, current_ids):
    """Where a waking Space belongs: after every unsnoozed Space that sat
    above it in the home order, ignoring any still-snoozed siblings."""
    rank = home_rank(state, ws_id)
    others = [i for i in current_ids if i != ws_id and i not in state["snoozes"]]
    return sum(1 for i in others if home_rank(state, i) < rank)


def sink_snoozed(state):
    """Keep every snoozed Space contiguous at the bottom, soonest to wake
    first."""
    live = {w["workspace_id"] for w in workspaces()}
    ids = [i for i in state["snoozes"] if i in live]
    if not ids:
        return
    ids.sort(key=lambda i: state["snoozes"][i]["until"])
    rpc("workspace.move_block", {"workspace_ids": ids, "before_workspace_id": None})


# ------------------------------------------------------------------ actions

def cmd_snooze(ws_id, spec):
    until = parse_when(spec)
    ws_list = workspaces()
    match = next((w for w in ws_list if w["workspace_id"] == ws_id), None)
    if not match:
        sys.exit(f"no such Space: {ws_id}")

    with locked_state() as state:
        refresh_home_order(state, [w["workspace_id"] for w in ws_list])
        # Re-snoozing replaces the timer outright. Keep the label recorded by
        # the first snooze; the live one is prefixed by now and would be
        # stored as the "original" to restore on wake.
        prior = state["snoozes"].get(ws_id, {}).get("label")
        state["snoozes"][ws_id] = {
            "label": prior or clean_label(match.get("label", ws_id)),
            "until": until,
        }
        snapshot = json.loads(json.dumps(state))

    sink_snoozed(snapshot)
    rename(ws_id, sleep_label(match.get("label", ws_id)))
    set_token(ws_id, humanize(until))
    try:
        refresh_branches(snapshot, only=ws_id)
    except RuntimeError:
        pass
    cmd_ensure_daemon()
    print(
        f"snoozed {clean_label(match.get('label', ws_id))} "
        f"until {datetime.fromtimestamp(until)}"
    )


def cmd_wake(ws_id, alert=False):
    """alert is for the timer firing when you were not expecting it. Waking a
    Space yourself is not a surprise, so those paths stay silent."""
    with locked_state() as state:
        entry = state["snoozes"].pop(ws_id, None)
        if entry is not None:
            snapshot = json.loads(json.dumps(state))
    if entry is None:
        return False

    clear_token(ws_id)
    # Exact restore: gtr-clean matches orphan Spaces by exact label. clean it
    # again in case an older state file recorded a prefixed one.
    rename(ws_id, clean_label(entry["label"]))
    # Drop the branch's dim marker now rather than at the next tick, which
    # left a woken Space with a faded branch for up to a full interval.
    try:
        refresh_branches(snapshot, only=ws_id)
    except RuntimeError:
        pass
    live = [w["workspace_id"] for w in workspaces()]
    if ws_id in live:
        idx = min(restore_index(snapshot, ws_id, live), max(0, len(live) - 1))
        try:
            rpc("workspace.move", {"workspace_id": ws_id, "insert_index": idx})
        except RuntimeError as e:
            print(f"warn: could not restore position: {e}", file=sys.stderr)

    if alert:
        herdr_cli(
            "notification", "show", f"{entry['label']} is awake",
            "--body", "Snooze finished",
            "--sound", "request",
        )
    # Anything still snoozed must stay packed at the bottom.
    sink_snoozed(load_state())
    print(f"woke {entry['label']}")
    return True


def cmd_tick():
    """Wake anything due, refresh the countdown on everything else."""
    state = load_state()
    # Branch tokens are owned by this plugin for every Space, so they are
    # refreshed even when nothing is asleep.
    try:
        refresh_branches(state)
    except RuntimeError as e:
        print(f"branch refresh failed: {e}", file=sys.stderr)
    if not state["snoozes"]:
        return
    now = int(time.time())
    live = {w["workspace_id"] for w in workspaces()}

    for ws_id in list(state["snoozes"]):
        if ws_id not in live:
            # Space was closed while snoozed; drop it silently.
            with locked_state() as s:
                s["snoozes"].pop(ws_id, None)
            continue
        if state["snoozes"][ws_id]["until"] <= now:
            cmd_wake(ws_id, alert=True)

    state = load_state()
    labels = {w["workspace_id"]: w.get("label", "") for w in workspaces()}
    for ws_id, entry in state["snoozes"].items():
        if ws_id in live:
            set_token(ws_id, humanize(entry["until"], now))
            # Self-healing: a Space snoozed before this ran, or renamed by
            # hand, still gets the prefix its dimming rule keys off.
            want = sleep_label(entry["label"])
            if labels.get(ws_id) != want:
                rename(ws_id, want)
    sink_snoozed(state)

    # A Space tagged in the sidebar but missing from state can never wake
    # itself. Clear those so a stale badge cannot outlive its entry.
    for w in workspaces():
        if w["workspace_id"] in state["snoozes"]:
            continue
        if w.get("tokens", {}).get(TOKEN):
            clear_token(w["workspace_id"])
        # A Space left wearing the sleep prefix without a matching entry looks
        # asleep forever, since nothing is left to wake it.
        if w.get("label", "").startswith(f"{BADGE} "):
            rename(w["workspace_id"], clean_label(w["label"]))


def cmd_list():
    state = load_state()
    if not state["snoozes"]:
        print("nothing snoozed")
        return
    now = int(time.time())
    rows = sorted(state["snoozes"].items(), key=lambda kv: kv[1]["until"])
    for ws_id, e in rows:
        when = datetime.fromtimestamp(e["until"]).strftime("%a %d %b %H:%M")
        print(f"{ws_id:6} {e['label']:28} {humanize(e['until'], now):>6}  {when}")


TICK_SECONDS = 60


def pid_path():
    # Per-server, like the state file: one ticker per herdr server, not one
    # for the machine. A shared pidfile would let the first server's daemon
    # convince the second's that it was already running.
    return os.path.join(state_dir(), f"daemon-{server_key()}.pid")


def daemon_running():
    """Advisory check for callers. The real guarantee is the lock in
    cmd_daemon; this only avoids spawning a process that would exit anyway."""
    try:
        with open(pid_path()) as f:
            pid = int(f.read().strip())
    except (FileNotFoundError, ValueError):
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return pid != os.getpid()


def cmd_daemon():
    """Tick forever. This used to exit once nothing was snoozed, which is no
    longer safe: branch names in the sidebar are plugin-reported for every
    Space, so stopping the loop would let them expire and blank out."""
    # An exclusive lock held for the whole run, not a pidfile check. Checking
    # then writing is a race: two launches both saw no pidfile, both spawned,
    # and the second overwrote the first's pid. The pair then fought over the
    # sidebar, one re-applying the sleep rename and token microseconds after
    # the other cleared them, so a woken Space kept looking asleep.
    lock = open(pid_path() + ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return  # another ticker already owns it

    with open(pid_path(), "w") as f:
        f.write(str(os.getpid()))
    try:
        while True:
            try:
                cmd_tick()
            except Exception as e:  # a dead socket must not kill the loop
                print(f"tick failed: {e}", file=sys.stderr)
            # Sleep to the next wake rather than a flat interval, or a snooze
            # set just after a tick fires up to a whole interval late. Still
            # capped so countdowns keep refreshing while nothing is due.
            due = [e["until"] for e in load_state()["snoozes"].values()]
            nap = min(TICK_SECONDS, *(d - time.time() for d in due)) if due else TICK_SECONDS
            time.sleep(max(1, min(TICK_SECONDS, nap)))
    finally:
        try:
            os.unlink(pid_path())
        except OSError:
            pass
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


def cmd_ensure_daemon():
    """Spawn the ticker detached and return at once, so a startup hook or a
    fresh snooze never blocks on it."""
    if daemon_running():
        return
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "daemon"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def current_workspace():
    ws = os.environ.get("HERDR_WORKSPACE_ID")
    if ws:
        return ws
    focused = next((w for w in workspaces() if w.get("focused")), None)
    if not focused:
        sys.exit("no focused Space and HERDR_WORKSPACE_ID is unset")
    return focused["workspace_id"]


def cmd_open_picker():
    ws = current_workspace()
    label = next(
        (w.get("label", ws) for w in workspaces() if w["workspace_id"] == ws), ws
    )
    # Already snoozed? Tell the picker, so it can offer waking instead of only
    # re-snoozing. Otherwise prefix+z on a sleeping Space would be a one-way
    # door: every press sets a new timer and nothing cancels it.
    entry = load_state()["snoozes"].get(ws)
    current = humanize(entry["until"]) if entry else ""

    # A popup is a session singleton, not a pane: it has no workspace of its
    # own and does not inherit the invoking context, so the target Space has to
    # be handed over explicitly through env.
    rpc(
        "plugin.pane.open",
        {
            "plugin_id": SOURCE,
            "entrypoint": "picker",
            "env": {
                "HERDR_SNOOZE_WS": ws,
                "HERDR_SNOOZE_LABEL": label,
                "HERDR_SNOOZE_CURRENT": current,
            },
        },
    )


HELP_DURATIONS = (
    "try: 45m · 2h · 2h30m · 3d · 1w · 9am · 14:30 · tomorrow 9am · thu 9am"
)


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args[0]

    if cmd == "snooze":
        if len(args) < 2:
            sys.exit("usage: snooze.py snooze <duration> [workspace_id]")
        ws = args[2] if len(args) > 2 else current_workspace()
        try:
            cmd_snooze(ws, args[1])
        except ValueError:
            # A stray keystroke in the picker lands here. Printing the
            # traceback filled the popup with Python internals; say what was
            # wrong and what would have worked instead.
            sys.exit(f"not a duration: {args[1]!r}\n{HELP_DURATIONS}")
    elif cmd == "wake":
        ws = args[1] if len(args) > 1 else current_workspace()
        if not cmd_wake(ws):
            print("that Space was not snoozed")
    elif cmd == "wake-current":
        if not cmd_wake(current_workspace()):
            print("that Space was not snoozed")
    elif cmd == "wake-all":
        for ws_id in list(load_state()["snoozes"]):
            cmd_wake(ws_id, alert=False)
    elif cmd == "tick":
        cmd_tick()
    elif cmd == "daemon":
        cmd_daemon()
    elif cmd == "ensure-daemon":
        cmd_ensure_daemon()
    elif cmd == "check":
        # Exit status only: lets the picker ask "is what they typed already a
        # valid duration?" before letting a fuzzy list match override it.
        try:
            parse_when(args[1])
        except (ValueError, IndexError):
            sys.exit(1)
    elif cmd == "list":
        cmd_list()
    elif cmd == "open-picker":
        cmd_open_picker()
    else:
        sys.exit(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
