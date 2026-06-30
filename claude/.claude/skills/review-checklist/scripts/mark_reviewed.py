#!/usr/bin/env python3
"""Mark files reviewed/unreviewed in the nvim review checklist.

State lives in <git-dir>/nvim-review-checklist.json:
    {"version": 1, "reviewed": {"rel/path.tsx": "<blob-hash>"}}

A mark stores the git blob hash of the file's current working-tree content. A
file counts as reviewed only while that hash still matches, so editing a file
again auto-expires its mark. This is the SAME rule nvim's lua/review_checklist.lua
uses, so whatever this script writes shows up correctly in the editor.

Reviewed vs hidden:
    --check / --uncheck  tick a file off (stays listed). Auto-expires on edit.
    --hide   / --unhide  drop a file from the checklist entirely (for noise the
                         user, or Claude on request, decides isn't worth human
                         eyes). nvim still shows a "N hidden" count and can reveal.

Usage:
    mark_reviewed.py --list                          # --json for machine output
    mark_reviewed.py --check SubManagerProductLine get-subscription-line
    mark_reviewed.py --check-all-except SubManagerDeliveryHero
    mark_reviewed.py --uncheck path/to/file.tsx
    mark_reviewed.py --hide package-lock.json __snapshots__   # narrow the list
    mark_reviewed.py --hide 'src/lib/i18n/messages/*.json'    # GLOB: a whole category in ONE arg
    mark_reviewed.py --unhide package-lock.json   # or --unhide-all
    mark_reviewed.py --clear
    mark_reviewed.py --base origin/main --list      # review a branch vs main

Names are loose: pass a basename, a path suffix, or a substring. A plain name
must resolve to exactly one changed file or the script errors (and lists
candidates). A name containing a glob metacharacter (* ? [) is matched as a
glob against every changed path and MAY match many — this is how you hide a
whole category (e.g. all translation JSONs) in a single argument instead of
listing every file. Always single-quote globs so the shell passes them through
verbatim rather than expanding them itself.
"""

import argparse
import fnmatch
import json
import os
import subprocess
import sys
import tempfile

SENTINEL_ABSENT = "<absent>"


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def git(args, root=None):
    cmd = ["git"] + (["-C", root] if root else []) + args
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout


def git_lines(args, root=None):
    rc, out = git(args, root)
    return out.splitlines() if rc == 0 else []


def repo_root():
    rc, out = git(["rev-parse", "--show-toplevel"])
    if rc != 0:
        die("Not inside a git repository.")
    return out.strip()


def git_dir():
    rc, out = git(["rev-parse", "--absolute-git-dir"])
    return out.strip() if rc == 0 and out.strip() else os.path.join(repo_root(), ".git")


def state_file():
    return os.path.join(git_dir(), "nvim-review-checklist.json")


def fingerprint(root, path):
    """Blob hash of the file's current content (sentinel if it's gone)."""
    if not os.path.isfile(os.path.join(root, path)):
        return SENTINEL_ABSENT
    rc, out = git(["hash-object", "--", path], root=root)
    h = out.strip()
    return h if rc == 0 and h else SENTINEL_ABSENT


def changed_files(root, base):
    """[(status, path)] in git's order. base=None -> uncommitted working tree."""
    files = []
    if base:
        rng = base if ".." in base else f"{base}...HEAD"
        for line in git_lines(["diff", "--name-status", rng], root=root):
            parts = line.split("\t")
            if len(parts) >= 2:
                files.append((parts[0][:1], parts[-1]))  # rename -> current path
    else:
        for line in git_lines(["status", "--porcelain", "--untracked-files=all"], root=root):
            if len(line) > 3:
                status, path = line[:2], line[3:]
                if " -> " in path:
                    path = path.split(" -> ", 1)[1]
                files.append((status.replace(" ", "."), path.strip('"')))
    return files


def load_state():
    sf = state_file()
    empty = {"reviewed": {}, "hidden": {}}
    if not os.path.isfile(sf):
        return empty
    try:
        data = json.load(open(sf))
    except Exception:
        return empty
    if not isinstance(data, dict):
        return empty
    rev, hid = data.get("reviewed"), data.get("hidden")
    return {
        "reviewed": rev if isinstance(rev, dict) else {},
        "hidden": hid if isinstance(hid, dict) else {},
    }


def save_state(st):
    sf = state_file()
    body = json.dumps({"version": 1, "reviewed": st.get("reviewed", {}), "hidden": st.get("hidden", {})})
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".nvim-review-", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        f.write(body)
    os.replace(tmp, sf)  # atomic


def current_rows(root, base):
    st = load_state()
    rows = []
    for status, path in changed_files(root, base):
        fp = fingerprint(root, path)
        rows.append({
            "status": status,
            "path": path,
            "reviewed": st["reviewed"].get(path) is not None and st["reviewed"].get(path) == fp,
            "hidden": st["hidden"].get(path) is True,
        })
    return rows


def resolve(name, paths):
    """(path, candidates_or_None). candidates set only when ambiguous."""
    name = name.strip()
    tiers = [
        [p for p in paths if p == name],
        [p for p in paths if os.path.basename(p) == name],
        [p for p in paths if p.endswith("/" + name)],
        [p for p in paths if name in p],
    ]
    for cand in tiers:
        uniq = sorted(set(cand))
        if len(uniq) == 1:
            return uniq[0], None
        if len(uniq) > 1:
            return None, uniq
    return None, []


GLOB_META = ("*", "?", "[")


def is_glob(name):
    return any(c in name for c in GLOB_META)


def glob_expand(pat, paths):
    """Every changed path matching the glob. Matches the full relative path, the
    path as a suffix (so 'messages/*.json' catches 'a/b/messages/x.json'), or the
    basename. May match many — that's the point. Errors if it matches nothing."""
    pat = pat.strip()
    hits = [p for p in paths
            if fnmatch.fnmatch(p, pat)
            or fnmatch.fnmatch(p, "*" + pat)
            or fnmatch.fnmatch(os.path.basename(p), pat)]
    if not hits:
        die(f"No changed file matches glob '{pat}'.\nChanged files:\n  " + "\n  ".join(paths or ["(none)"]))
    return hits


def resolve_one(name, paths):
    p, cands = resolve(name, paths)
    if p is None:
        if cands:
            die(f"'{name}' is ambiguous — matches:\n  " + "\n  ".join(cands)
                + "\nPass a longer path, or a quoted glob to hit them all at once.")
        die(f"No changed file matches '{name}'.\nChanged files:\n  " + "\n  ".join(paths or ["(none)"]))
    return p


def resolve_all(names, paths):
    """Resolve each NAME to changed paths, deduped and order-preserved. A name
    with a glob metacharacter expands to all matches; a plain name resolves to
    exactly one. Pass ONE glob to hide a whole category — never list 100 names."""
    out, seen = [], set()
    for n in names:
        for m in (glob_expand(n, paths) if is_glob(n) else [resolve_one(n, paths)]):
            if m not in seen:
                seen.add(m)
                out.append(m)
    return out


def fmt_paths(ps):
    """Compact, verifiable summary of an action's paths — avoids a 100-line wall
    when a glob hides a big category. Lists paths individually up to 8, then
    collapses to a per-directory count."""
    if not ps:
        return "(nothing)"
    if len(ps) <= 8:
        return ", ".join(ps)
    dirs = {}
    for p in ps:
        d = (os.path.dirname(p) or ".") + "/"
        dirs[d] = dirs.get(d, 0) + 1
    parts = [(f"{d} (×{c})" if c > 1 else d.rstrip("/")) for d, c in sorted(dirs.items())]
    shown = "; ".join(parts[:6]) + (" …" if len(parts) > 6 else "")
    return f"{len(ps)} files — {shown}"


def print_list(root, base, as_json, show_all=False):
    rows = current_rows(root, base)
    visible = [r for r in rows if not r["hidden"]]
    hidden = [r for r in rows if r["hidden"]]
    done = sum(1 for r in visible if r["reviewed"])
    if as_json:
        # files includes EVERY changed file with reviewed+hidden flags, so the
        # caller can reason about the whole change (e.g. decide what to hide).
        print(json.dumps({
            "base": base or "worktree",
            "done": done, "total": len(visible), "hidden": len(hidden),
            "files": rows,
        }, indent=2))
        return
    head = f"Review checklist — {base or 'working tree'}  ({done}/{len(visible)} reviewed"
    head += f", {len(hidden)} hidden)" if hidden else ")"
    print(head)
    for r in (rows if show_all else visible):
        mark = "~" if r["hidden"] else ("x" if r["reviewed"] else " ")
        print(f"  [{mark}] {r['status']:<2} {r['path']}")
    if hidden and not show_all:
        print(f"  … {len(hidden)} hidden (--all to show, --unhide to restore)")


def main():
    ap = argparse.ArgumentParser(description="Mark files reviewed/hidden in the nvim review checklist.")
    ap.add_argument("--check", nargs="+", metavar="NAME", help="mark these files reviewed")
    ap.add_argument("--uncheck", nargs="+", metavar="NAME", help="unmark these files")
    ap.add_argument("--check-all-except", nargs="*", metavar="NAME", dest="all_except",
                    help="mark every changed file reviewed except these")
    ap.add_argument("--hide", nargs="+", metavar="NAME",
                    help="remove these files from the checklist (not worth human eyes)")
    ap.add_argument("--unhide", nargs="+", metavar="NAME", help="bring hidden files back")
    ap.add_argument("--unhide-all", action="store_true", dest="unhide_all", help="bring every hidden file back")
    ap.add_argument("--clear", action="store_true", help="wipe reviewed marks (hides kept)")
    ap.add_argument("--list", action="store_true", help="show the checklist (default)")
    ap.add_argument("--all", action="store_true", help="include hidden files in the listing")
    ap.add_argument("--base", default=None, metavar="REF",
                    help="review committed work vs REF (e.g. origin/main) instead of the working tree")
    ap.add_argument("--json", action="store_true", help="machine-readable output (always includes hidden files)")
    args = ap.parse_args()

    root = repo_root()
    st = load_state()

    if args.clear:
        save_state({"reviewed": {}, "hidden": st["hidden"]})
        print("Cleared all reviewed marks (hidden files kept; --unhide-all to restore them).")
        return
    if args.unhide_all:
        save_state({"reviewed": st["reviewed"], "hidden": {}})
        print("Unhid all files.\n")
        return print_list(root, args.base, args.json, args.all)

    rows = current_rows(root, args.base)
    paths = [r["path"] for r in rows]
    actions = {}  # verb -> [paths]

    def record(verb, ps):
        actions.setdefault(verb, []).extend(ps)

    if args.check:
        ps = resolve_all(args.check, paths)
        for p in ps:
            st["reviewed"][p] = fingerprint(root, p)
        record("Marked reviewed", ps)
    if args.uncheck:
        ps = resolve_all(args.uncheck, paths)
        for p in ps:
            st["reviewed"].pop(p, None)
        record("Unmarked", ps)
    if args.all_except is not None:
        keep = set(resolve_all(args.all_except, paths)) if args.all_except else set()
        marked = [p for p in paths if p not in keep]
        for p in paths:
            (st["reviewed"].pop(p, None) if p in keep else st["reviewed"].__setitem__(p, fingerprint(root, p)))
        record("Marked reviewed", marked)
    if args.hide:
        ps = resolve_all(args.hide, paths)
        for p in ps:
            st["hidden"][p] = True
        record("Hid", ps)
    if args.unhide:
        ps = resolve_all(args.unhide, paths)
        for p in ps:
            st["hidden"].pop(p, None)
        record("Unhid", ps)

    if any([args.check, args.uncheck, args.all_except is not None, args.hide, args.unhide]):
        cur = set(paths)  # prune both sets to the current change
        st["reviewed"] = {p: h for p, h in st["reviewed"].items() if p in cur}
        st["hidden"] = {p: v for p, v in st["hidden"].items() if p in cur}
        save_state(st)
        for verb, ps in actions.items():
            print(f"{verb}: " + fmt_paths(ps))
        print()

    print_list(root, args.base, args.json, args.all)


if __name__ == "__main__":
    main()
