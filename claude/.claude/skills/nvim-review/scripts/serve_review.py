#!/usr/bin/env python3
"""Serve an nvim-review packet locally and bridge its clicks into cmux.

The packet (rendered by build_review.py) is served over http://127.0.0.1:<port>
(same-origin, so the page's fetch() just works) and opened as a **full-screen named
cmux tab** (a browser surface — not a split). Clicking in the page spawns NEW
full-screen nvim tabs via the cmux CLI — your existing editor is never touched:

    ▸ open                 → POST /newtab {mode:"file", value:"<path>"}        → new tab: nvim -- '<path>'
    ▣ isolate in diffview  → POST /newtab {mode:"diff", value:"DiffviewOpen …"} → new tab: nvim -c '<…>'
    ☑ checkbox             → POST /check  {path,reviewed}                       → write <git-dir>/nvim-review-checklist.json

Those tabs are opened in the BACKGROUND (--focus false) and in the review's own
workspace (the workspace this server was launched in), so they never interrupt what
you're doing or pull you away — you switch to them when you're ready. No nvim pane to
detect, so a fresh run opens exactly one review tab.

Lifecycle — no orphans:
  • Singleton: a prior server recorded in <git-dir>/nvim-review-server.json is killed
    on start, so re-runs never stack.
  • Auto-shutdown: a watchdog polls whether the review tab still exists; close the tab
    and the server exits and removes its pidfile (the /ping heartbeat is only a backstop
    for --no-open). /bye is a deliberate no-op (pagehide fires on reload too).
  • `serve_review.py --stop` kills the recorded server explicitly.

    python3 serve_review.py --html .review/<branch>.html [--title "Review — <branch>"] \
        [--root <repo>] [--port <p>] [--no-open] [--review-surface surface:N]
    python3 serve_review.py --stop [--root <repo>]
"""

import argparse
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CMUX = os.environ.get("CMUX_BUNDLED_CLI_PATH") or "/Applications/cmux.app/Contents/Resources/bin/cmux"
WORKSPACE = os.environ.get("CMUX_WORKSPACE_ID")  # the review's workspace — pin new tabs here
IDLE_TIMEOUT = 120   # no /ping for this long → exit (heartbeat backstop, --no-open only)
WATCH_EVERY = 4      # seconds between watchdog checks (tab-close detected in ~2×)


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def git(args, root=None):
    cmd = ["git"] + (["-C", root] if root else []) + args
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout


def repo_root():
    rc, out = git(["rev-parse", "--show-toplevel"])
    return out.strip() if rc == 0 else os.getcwd()


def git_dir(root):
    rc, out = git(["rev-parse", "--absolute-git-dir"], root=root)
    return out.strip() if rc == 0 and out.strip() else os.path.join(root, ".git")


def pidfile_path(root):
    return os.path.join(git_dir(root), "nvim-review-server.json")


def cmux(*args):
    return subprocess.run([CMUX, *args], capture_output=True, text=True)


def cmux_ok(*args):
    """(ok, output). ok=False if the command errored or named a missing surface."""
    p = cmux(*args)
    out = (p.stdout + p.stderr).lower()
    ok = p.returncode == 0 and "not found" not in out and "not_found" not in out
    return ok, p.stdout + p.stderr


# ── checklist state (same file + format as <leader>rc / mark_reviewed.py) ─────

def fingerprint(root, path):
    if not os.path.isfile(os.path.join(root, path)):
        return "<absent>"
    rc, out = git(["hash-object", "--", path], root=root)
    h = out.strip()
    return h if rc == 0 and h else "<absent>"


def state_file(root):
    return os.path.join(git_dir(root), "nvim-review-checklist.json")


def load_state(root):
    sf = state_file(root)
    if not os.path.isfile(sf):
        return {"reviewed": {}, "hidden": {}}
    try:
        data = json.load(open(sf))
    except Exception:
        return {"reviewed": {}, "hidden": {}}
    rev, hid = data.get("reviewed"), data.get("hidden")
    return {"reviewed": rev if isinstance(rev, dict) else {},
            "hidden": hid if isinstance(hid, dict) else {}}


def save_state(root, st):
    sf = state_file(root)
    body = json.dumps({"version": 1, "reviewed": st.get("reviewed", {}), "hidden": st.get("hidden", {})})
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".nvim-review-", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        f.write(body)
    os.replace(tmp, sf)


def set_reviewed(root, path, reviewed):
    st = load_state(root)
    if reviewed:
        st["reviewed"][path] = fingerprint(root, path)
    else:
        st["reviewed"].pop(path, None)
    save_state(root, st)


# ── singleton / pidfile ───────────────────────────────────────────────────────

def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def read_pidfile(root):
    try:
        return json.load(open(pidfile_path(root)))
    except Exception:
        return None


def kill_recorded(root):
    """Kill a previously-recorded server so re-runs never stack."""
    rec = read_pidfile(root)
    if not rec:
        return False
    pid = int(rec.get("pid", 0) or 0)
    if pid and pid != os.getpid() and pid_alive(pid):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
        for _ in range(20):
            if not pid_alive(pid):
                break
            time.sleep(0.05)
        return True
    try:
        os.remove(pidfile_path(root))
    except OSError:
        pass
    return False


def write_pidfile(root, port, url, review_surface):
    json.dump({"pid": os.getpid(), "port": port, "url": url, "review_surface": review_surface},
              open(pidfile_path(root), "w"))


def remove_pidfile(root):
    try:
        pf = pidfile_path(root)
        if int((read_pidfile(root) or {}).get("pid", -1)) == os.getpid():
            os.remove(pf)
    except Exception:
        pass


def free_port(preferred):
    for p in ([preferred] if preferred else []) + list(range(8765, 8825)):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", p))
                return p
            except OSError:
                continue
    die("No free port in 8765–8824.")


def port_of(url):
    m = re.search(r":(\d+)/", url) if isinstance(url, str) else None
    return int(m.group(1)) if m else None


def bind_server(port, handler):
    """Bind QuietServer on an exact port, retrying briefly. SO_REUSEADDR (set by
    HTTPServer) lets us rebind a port the just-killed prior server left in TIME_WAIT —
    essential when REUSING an open tab, which still points at that exact port."""
    last = None
    for _ in range(50):
        try:
            return QuietServer(("127.0.0.1", port), handler)
        except OSError as e:
            last = e
            time.sleep(0.1)
    raise last


# ── cmux tabs ─────────────────────────────────────────────────────────────────

def _ws_args():
    return ["--workspace", WORKSPACE] if WORKSPACE else []


def open_named_tab(url, title):
    """The review packet itself: a full-screen browser tab in this workspace, focused
    (running /nvim-review is the user initiating, so taking them to it is expected)."""
    out = cmux("new-surface", "--type", "browser", "--url", url, "--focus", "true", *_ws_args()).stdout
    m = re.search(r"surface:\d+", out)
    surf = m.group(0) if m else None
    if surf and title:
        cmux("tab-action", "--tab", surf, "--action", "rename", "--title", title)
    return surf


def surface_exists(surface):
    ok, _ = cmux_ok("browser", "--surface", surface, "get", "url")
    return ok


class QuietServer(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):
        # The webview drops in-flight /ping connections on reload/close — a
        # BrokenPipe/ConnectionReset, not a real error. Swallow it; log the rest.
        exc = sys.exc_info()[1]
        if isinstance(exc, (BrokenPipeError, ConnectionResetError, ConnectionAbortedError)):
            return
        super().handle_error(request, client_address)


def make_handler(html_path, root):
    diff_lock = threading.Lock()

    def shell_ready(surf):
        """Wait (briefly) for the new terminal's shell prompt before typing."""
        for _ in range(40):
            out = cmux("capture-pane", "--surface", surf, "--lines", "4").stdout
            if "❯" in out or "$ " in out or out.rstrip().endswith("%"):
                return
            time.sleep(0.1)

    def open_nvim_tab(nvim_cmd, name):
        """Open a NEW full-screen cmux tab and launch nvim in it — in the BACKGROUND
        (--focus false), in the review's workspace, so it never pulls the user away.
        `nvim_cmd` is the full, already-shell-safe `nvim …` invocation."""
        with diff_lock:
            out = cmux("new-surface", "--type", "terminal", "--working-directory", root,
                       "--focus", "false", *_ws_args()).stdout
            m = re.search(r"surface:\d+", out)
            surf = m.group(0) if m else None
            if not surf:
                return None
            cmux("tab-action", "--tab", surf, "--action", "rename", "--title", name)
            shell_ready(surf)
            cmux("send", "--surface", surf, nvim_cmd)
            cmux("send-key", "--surface", surf, "enter")
            return surf

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _json(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path in ("/", "/review.html", "/index.html"):
                try:
                    body = open(html_path, "rb").read()
                except OSError:
                    return self._json(404, {"error": "html missing"})
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self._json(404, {"error": "not found"})

        def _read_json(self):
            n = int(self.headers.get("Content-Length") or 0)
            try:
                return json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                return {}

        def do_POST(self):
            if self.path == "/ping":
                return self._json(200, {"ok": True})
            if self.path == "/bye":
                # No-op: pagehide (which posts this) also fires on RELOAD, so letting
                # /bye shut down would make a reload kill the server. The watchdog
                # detects a real close via tab-existence instead.
                return self._json(200, {"ok": True})
            if self.path == "/newtab":
                d = self._read_json()
                mode = d.get("mode") or "file"
                value = (d.get("value") or "").strip()
                name = (d.get("name") or "nvim").strip()
                if not value:
                    return self._json(400, {"error": "no value"})
                # shlex.quote keeps [alpha3]/[language] brackets literal so neither
                # zsh nor nvim treats them as a glob.
                nvim_cmd = ("nvim -c " + shlex.quote(value)) if mode == "diff" \
                    else ("nvim -- " + shlex.quote(value))
                surf = open_nvim_tab(nvim_cmd, name)
                return self._json(200, {"ok": bool(surf), "surface": surf})
            if self.path == "/check":
                d = self._read_json()
                p = d.get("path")
                if not p:
                    return self._json(400, {"error": "no path"})
                set_reviewed(root, p, bool(d.get("reviewed")))
                return self._json(200, {"ok": True})
            self._json(404, {"error": "not found"})

    return H


def main():
    ap = argparse.ArgumentParser(description="Serve an nvim-review packet; clicks spawn background cmux nvim tabs.")
    ap.add_argument("--html", help="path to the rendered review HTML")
    ap.add_argument("--root", help="repo root (default: git toplevel of cwd)")
    ap.add_argument("--title", default="nvim-review", help="name for the review tab")
    ap.add_argument("--port", type=int, help="port (default: first free 8765+)")
    ap.add_argument("--no-open", action="store_true", help="serve only; don't open a cmux tab")
    ap.add_argument("--review-surface", dest="review_surface",
                    help="adopt an already-open review tab (no new tab) instead of opening one")
    ap.add_argument("--stop", action="store_true", help="kill the recorded server for this repo and exit")
    args = ap.parse_args()

    root = args.root or repo_root()

    if args.stop:
        print("stopped" if kill_recorded(root) else "no server running")
        return

    if not args.html:
        die("--html is required (or use --stop).")
    html_path = os.path.abspath(args.html)
    if not os.path.isfile(html_path):
        die(f"HTML not found: {html_path}")

    # Singleton, but first remember the prior server's review tab so a re-run can
    # REUSE it instead of opening a second one.
    prior = read_pidfile(root)
    kill_recorded(root)

    # Pick the review tab and the port together. When REUSING an open tab we must bind
    # the exact port it already points at (we deliberately don't navigate it — repeated
    # reloads wedge the webview), so its clicks reach this server.
    review_surface, port = None, None
    if args.review_surface:
        # Adopt the given tab and bind the port IT is actually on (not a free one),
        # so its clicks reach us without navigating/reloading it.
        ok, tab_url = cmux_ok("browser", "--surface", args.review_surface, "get", "url")
        review_surface = args.review_surface
        port = (port_of(tab_url) if ok else None) or free_port(args.port)
    elif args.no_open:
        port = free_port(args.port)
    else:
        # Reuse the prior review tab if it's still open — binding the port THE TAB IS
        # ACTUALLY ON (read from the tab, not the pidfile, which can drift), so clicks
        # reach us without navigating/reloading the tab.
        prior_surf = (prior or {}).get("review_surface")
        ok, tab_url = cmux_ok("browser", "--surface", prior_surf, "get", "url") if prior_surf else (False, "")
        tab_port = port_of(tab_url) if ok else None
        if prior_surf and tab_port:
            review_surface, port = prior_surf, tab_port
        else:
            port = free_port(args.port)
            review_surface = open_named_tab(f"http://127.0.0.1:{port}/review.html", args.title)

    url = f"http://127.0.0.1:{port}/review.html"
    httpd = bind_server(port, make_handler(html_path, root))
    write_pidfile(root, port, url, review_surface)

    def shutdown(*_):
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    def watchdog():
        # Tab-existence is the authoritative close signal (focus-independent, so an
        # unfocused tab stays alive). 2 consecutive misses → exit. Heartbeat backstop
        # only when there's no tab to watch (--no-open).
        misses, last_ping = 0, time.time()
        while True:
            time.sleep(WATCH_EVERY)
            if review_surface:
                misses = 0 if surface_exists(review_surface) else misses + 1
                if misses >= 2:
                    return shutdown()
            elif time.time() - last_ping > IDLE_TIMEOUT:
                return shutdown()

    threading.Thread(target=watchdog, daemon=True).start()

    print(json.dumps({"url": url, "review_surface": review_surface, "root": root,
                      "reused_tab": bool(args.review_surface) or (review_surface == (prior or {}).get("review_surface")),
                      "pid": os.getpid()}))
    sys.stdout.flush()
    try:
        httpd.serve_forever()
    finally:
        remove_pidfile(root)


if __name__ == "__main__":
    main()
