#!/usr/bin/env python3
"""Build a self-contained HTML review packet for the current branch's diff.

Two phases, mirroring how the skill is meant to run:

  1.  build_review.py --list-json
        Emit every changed file (status, +/- counts, and whether it's already
        ticked in the nvim checklist) so the CALLER can cluster files by feature.

  2.  build_review.py --spec spec.json [--out PATH]
        Given a clustering spec the caller authored, render ONE self-contained
        HTML file: risk banner, per-feature sections, the ACTUAL diff embedded
        per file (collapsible, +/- colored), and copy-to-nvim buttons whose
        commands match the user's real review keymaps. Checkbox state is seeded
        from <git-dir>/nvim-review-checklist.json (the same file <leader>rc uses).

Base detection and changed-file logic are the SAME as the review-checklist
skill and lua/review_checklist.lua, so the file set and seed marks line up with
what the editor shows.

Modes (which change-set to review):
    main      this branch vs origin/main (…/master fallback) — `origin/main...HEAD`
    staging   this branch vs origin/staging                  — `origin/staging...HEAD`
    worktree  uncommitted working tree vs HEAD

Spec schema (all judgment fields are optional except clusters[].paths):
    {
      "title":   "Review — <branch>",            # optional
      "mode":    "main",                          # optional; overridden by --mode
      "risk": {                                   # optional overall banner
        "level": "High|Medium|Low",
        "summary": "one-line blast-radius statement",
        "review_first": ["thing one", "thing two"]
      },
      "clusters": [
        {
          "name": "Checkout vertical slice",
          "risk": "Medium",                       # High|Medium|Low (optional)
          "goal": "one sentence",                 # optional
          "review_focus": ["bullet", "bullet"],   # optional
          "diagram_html": "<svg>…</svg>",          # optional, injected verbatim
          "paths": ["apps/.../Checkout.tsx", …]   # REQUIRED
        }
      ],
      "housekeeping": {                           # optional; diffs not embedded
        "name": "Housekeeping",
        "paths": ["pnpm-lock.yaml", "…/messages/en.json"]
      }
    }

Any changed file not named in a cluster or housekeeping is collected into an
"Unassigned" cluster so nothing is ever silently dropped from review.
"""

import argparse
import fnmatch
import html
import json
import os
import re
import subprocess
import sys

SENTINEL_ABSENT = "<absent>"


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


# ── git + state primitives (shared shape with review-checklist) ──────────────

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


def current_branch():
    rc, out = git(["rev-parse", "--abbrev-ref", "HEAD"])
    return out.strip() if rc == 0 else "HEAD"


def base_branch():
    rc, _ = git(["rev-parse", "--verify", "origin/main"])
    return "origin/main" if rc == 0 else "origin/master"


def range_for(mode):
    if mode == "staging":
        return "origin/staging...HEAD"
    if mode == "worktree":
        return None
    return f"{base_branch()}...HEAD"


def literal(path):
    """git pathspec that disables glob — required because paths contain
    [alpha3]/[language], whose brackets git would otherwise read as a class."""
    return ":(literal)" + path


def changed_files(root, rng):
    """[(status, path)] in git order. rng=None -> uncommitted working tree."""
    files = []
    if rng:
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


def numstat(root, rng):
    """{path: (additions, deletions)}. '-' (binary) -> (0, 0)."""
    args = ["diff", "--numstat"] + ([rng] if rng else ["HEAD"])
    stats = {}
    for line in git_lines(args, root=root):
        parts = line.split("\t")
        if len(parts) >= 3:
            add = 0 if parts[0] == "-" else int(parts[0] or 0)
            dele = 0 if parts[1] == "-" else int(parts[1] or 0)
            stats[parts[-1]] = (add, dele)
    return stats


def fingerprint(root, path):
    if not os.path.isfile(os.path.join(root, path)):
        return SENTINEL_ABSENT
    rc, out = git(["hash-object", "--", path], root=root)
    h = out.strip()
    return h if rc == 0 and h else SENTINEL_ABSENT


def load_reviewed():
    sf = os.path.join(git_dir(), "nvim-review-checklist.json")
    if not os.path.isfile(sf):
        return {}
    try:
        data = json.load(open(sf))
    except Exception:
        return {}
    rev = data.get("reviewed") if isinstance(data, dict) else None
    return rev if isinstance(rev, dict) else {}


def seeded_reviewed(root, paths):
    """Set of paths already ticked in the nvim checklist (hash still current)."""
    reviewed = load_reviewed()
    out = set()
    for p in paths:
        if p in reviewed and reviewed[p] == fingerprint(root, p):
            out.add(p)
    return out


# ── HTML assembly ────────────────────────────────────────────────────────────

CSS = """
:root{
  --ground:#e8eaec;--paper:#fcfcfd;--ink:#171b21;--muted:#5a626e;--faint:#899099;
  --line:#d5d9de;--line-soft:#e6e9ed;
  --teal:#15616d;--teal-deep:#0e4953;--teal-wash:#edf4f4;
  --hi:#9a6312;--hi-wash:#f7f0e1;--hi-line:#e7d3a8;
  --md:#4f5d75;--md-wash:#eef0f3;--md-line:#cfd5df;
  --lo:#3f7d57;--lo-wash:#e9f1ec;--lo-line:#c2dac9;
  --add-bg:#e6f4ea;--add-ink:#216e39;--del-bg:#fbe9eb;--del-ink:#b1383e;
  --sans:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  --mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Monaco,"Cascadia Code",monospace;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.55;-webkit-font-smoothing:antialiased}
a{color:var(--teal)}
.path,code{font-family:var(--mono)}
.wrap{max-width:1240px;margin:0 auto;padding:0 clamp(16px,4vw,40px) 96px}

/* sticky nav */
.nav{position:sticky;top:0;z-index:20;background:rgba(232,234,236,.86);backdrop-filter:blur(8px);border-bottom:1px solid var(--line);padding:10px clamp(16px,4vw,40px);display:flex;align-items:center;gap:14px;flex-wrap:wrap}
.nav .brand{font-weight:680;letter-spacing:-.01em;margin-right:auto}
.nav .brand small{display:block;font-family:var(--mono);font-size:.66rem;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);font-weight:500}
.nav a.jump{font-size:.78rem;text-decoration:none;color:var(--muted);border:1px solid var(--line);background:var(--paper);border-radius:999px;padding:3px 11px;border-left-width:4px}
.nav a.jump.High{border-left-color:var(--hi)}.nav a.jump.Medium{border-left-color:var(--md)}.nav a.jump.Low{border-left-color:var(--lo)}
.prog{font-family:var(--mono);font-size:.78rem;color:var(--teal-deep);background:var(--teal-wash);border:1px solid #cfe3e3;border-radius:999px;padding:4px 12px;font-variant-numeric:tabular-nums;white-space:nowrap}

header.head{padding:clamp(26px,5vw,52px) 0 8px}
header.head h1{font-size:clamp(1.7rem,4vw,2.5rem);font-weight:700;letter-spacing:-.025em;line-height:1.05;margin:0}
header.head .sub{color:var(--muted);font-family:var(--mono);font-size:.82rem;margin-top:10px}

.banner{margin-top:22px;border:1px solid var(--line);border-left-width:5px;border-radius:13px;background:var(--paper);padding:18px 20px}
.banner.High{border-left-color:var(--hi)}.banner.Medium{border-left-color:var(--md)}.banner.Low{border-left-color:var(--lo)}
.banner .v{display:flex;align-items:center;gap:10px;font-weight:640}
.banner .chip{font-family:var(--mono);font-size:.7rem;letter-spacing:.08em;text-transform:uppercase;padding:3px 9px;border-radius:6px;font-weight:600}
.chip.High{background:var(--hi-wash);color:var(--hi)}.chip.Medium{background:var(--md-wash);color:var(--md)}.chip.Low{background:var(--lo-wash);color:var(--lo)}
.banner p{margin:8px 0 0;color:var(--muted);font-size:.92rem}
.banner ul{margin:8px 0 0;padding-left:18px;color:var(--ink);font-size:.9rem}
.banner ul li{margin:2px 0}

.hint{display:flex;gap:10px;align-items:center;margin-top:14px;font-size:.82rem;color:var(--muted)}
.hint code{background:var(--paper);border:1px solid var(--line);border-radius:6px;padding:1px 6px;font-size:.92em;color:var(--teal-deep)}

section.feat{margin-top:30px;background:var(--paper);border:1px solid var(--line);border-radius:14px;overflow:hidden;scroll-margin-top:64px}
.feat>.fh{padding:16px 22px;border-bottom:1px solid var(--line-soft);border-left:5px solid var(--md)}
.feat.High>.fh{border-left-color:var(--hi)}.feat.Medium>.fh{border-left-color:var(--md)}.feat.Low>.fh{border-left-color:var(--lo)}
.fh .top{display:flex;align-items:center;gap:11px;flex-wrap:wrap}
.fh h2{font-size:1.16rem;font-weight:660;letter-spacing:-.015em;margin:0}
.fh .meta{margin-left:auto;font-family:var(--mono);font-size:.74rem;color:var(--faint);white-space:nowrap}
.fh .meta .plus{color:var(--add-ink)}.fh .meta .minus{color:var(--del-ink)}
.fh .goal{margin:9px 0 2px;color:var(--ink);font-size:.96rem;font-weight:500}
.fh .hiw{margin:12px 0 2px;font-size:.92rem;color:var(--muted);line-height:1.62}
.fh .hiw p{margin:0 0 9px}
.fh .hiw b,.fh .hiw strong{color:var(--ink);font-weight:600}
.fh .hiw code,.fh .hiw .path{font-family:var(--mono);font-size:.86em;background:var(--md-wash);padding:1px 5px;border-radius:5px;color:var(--teal-deep)}
.fh .focus-h{margin:16px 0 5px;font-family:var(--mono);font-size:.7rem;letter-spacing:.1em;text-transform:uppercase;color:var(--faint)}
.fh .focus{margin:0;padding-left:0;list-style:none}
.fh .focus li{position:relative;padding-left:20px;font-size:.88rem;margin:3px 0}
.fh .focus li::before{content:"";position:absolute;left:4px;top:.62em;width:6px;height:6px;border-radius:50%;background:var(--teal)}

/* ── visual component library (assembled by the caller inside how_it_works) ── */

/* full-bleed band: breaks a visual out to the full card width */
.band{margin:16px -22px;padding:20px 22px;background:linear-gradient(180deg,#fbfcfd,#f5f7f8);border-top:1px solid var(--line-soft);border-bottom:1px solid var(--line-soft)}
.band+.band{border-top:none}
.band .cap{font-family:var(--mono);font-size:.68rem;letter-spacing:.09em;text-transform:uppercase;color:var(--faint);margin:0 0 12px;display:flex;align-items:center;gap:8px}
.band .cap::before{content:"";width:14px;height:2px;background:var(--teal);border-radius:2px}

/* node — the shared box primitive used by flow / branch */
.node{background:var(--paper);border:1.5px solid var(--md-line);border-radius:11px;padding:11px 14px;text-align:center;min-width:0}
.node .t{font-family:var(--mono);font-size:.82rem;font-weight:640;color:var(--ink);line-height:1.3;word-break:break-word}
.node .s{font-size:.76rem;color:var(--muted);margin-top:3px;line-height:1.35}
.node.hi{border-color:var(--hi);background:var(--hi-wash)}.node.hi .t{color:var(--hi)}
.node.lo{border-color:var(--lo-line);background:var(--lo-wash)}.node.lo .t{color:var(--add-ink)}
.node.teal{border-color:var(--teal);background:var(--teal-wash)}.node.teal .t{color:var(--teal-deep)}
.node.mute{border-color:var(--line);background:#f7f8f9}.node.mute .t{color:var(--muted);font-weight:600}
.node .tag{display:inline-block;font-family:var(--mono);font-size:.6rem;letter-spacing:.06em;text-transform:uppercase;padding:1px 6px;border-radius:5px;margin-bottom:6px;background:var(--md-wash);color:var(--md)}
.node.hi .tag{background:#efdcb6;color:var(--hi)}.node.lo .tag{background:#d6ebdd;color:var(--add-ink)}

/* flow — horizontal (default) or vertical pipeline of nodes, auto-arrowed */
.flow{display:flex;align-items:stretch;flex-wrap:wrap;gap:0}
.flow>.node{flex:1 1 130px;margin-left:30px}
.flow>.node:first-child{margin-left:0}
.flow>.node:not(:first-child)::before{content:"";position:absolute;left:-21px;top:50%;width:9px;height:9px;border-top:2px solid var(--faint);border-right:2px solid var(--faint);transform:translateY(-50%) rotate(45deg)}
.flow>.node{position:relative}
.flow.col{flex-direction:column;align-items:stretch}
.flow.col>.node{margin-left:0;margin-top:26px}
.flow.col>.node:first-child{margin-top:0}
.flow.col>.node:not(:first-child)::before{left:50%;top:-18px;transform:translateX(-50%) rotate(135deg)}

/* branch — one head node fanning out to N children (decision / dispatch) */
.branch{display:flex;flex-direction:column;align-items:center}
.branch>.node{min-width:200px;max-width:70%}
.branch .q{font-family:var(--mono);font-size:.8rem;color:var(--muted);margin:0;padding:22px 0 20px;position:relative}
.branch .q::before{content:"";position:absolute;left:50%;top:0;width:2px;height:16px;background:var(--line);transform:translateX(-50%)}
.branch .kids{display:flex;gap:14px;width:100%;position:relative}
.branch .kids::before{content:"";position:absolute;top:-20px;left:10%;right:10%;height:2px;background:var(--line)}
.branch .kids>*{flex:1 1 0;position:relative}
.branch .kids>*::before{content:"";position:absolute;top:-20px;left:50%;width:2px;height:20px;background:var(--line);transform:translateX(-50%)}
.branch .kids .node{height:100%}
/* a child can carry a follow-on node beneath it */
.kidcol{display:flex;flex-direction:column;align-items:stretch}
.kidcol .node+.node{margin-top:24px;position:relative}
.kidcol .node+.node::before{content:"";position:absolute;top:-18px;left:50%;width:9px;height:9px;border-top:2px solid var(--faint);border-right:2px solid var(--faint);transform:translateX(-50%) rotate(135deg)}

/* cols — two/three column before/after (polished) */
.cols{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:4px 0}
.cols.c3{grid-template-columns:repeat(3,1fr)}
.cols>div{background:var(--paper);border:1px solid var(--line-soft);border-radius:10px;padding:12px 14px}
.cols .lbl{font-family:var(--mono);font-size:.66rem;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);margin-bottom:7px;display:flex;align-items:center;gap:7px}
.cols .lbl.before::before{content:"−";color:var(--del-ink);font-weight:700}
.cols .lbl.after::before{content:"+";color:var(--add-ink);font-weight:700}

/* tiles — stat / metric row */
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px;margin:4px 0}
.tile{background:var(--paper);border:1px solid var(--line-soft);border-radius:10px;padding:13px 15px;border-top:3px solid var(--md)}
.tile.hi{border-top-color:var(--hi)}.tile.lo{border-top-color:var(--lo)}.tile.teal{border-top-color:var(--teal)}
.tile .num{font-size:1.5rem;font-weight:700;letter-spacing:-.02em;line-height:1;font-variant-numeric:tabular-nums}
.tile .cap{font-family:var(--mono);font-size:.66rem;letter-spacing:.07em;text-transform:uppercase;color:var(--faint);margin-top:6px}

/* callout — highlighted note */
.callout{border:1px solid var(--md-line);border-left-width:4px;border-radius:9px;background:#fbfcfd;padding:11px 14px;margin:10px 0;font-size:.9rem;color:var(--ink)}
.callout .h{font-weight:640;margin-right:6px}
.callout.warn{border-color:var(--hi-line);border-left-color:var(--hi);background:var(--hi-wash)}
.callout.warn .h{color:var(--hi)}
.callout.danger{border-color:#e7bcbf;border-left-color:var(--del-ink);background:var(--del-bg)}
.callout.danger .h{color:var(--del-ink)}
.callout.ok{border-color:var(--lo-line);border-left-color:var(--lo);background:var(--lo-wash)}
.callout.ok .h{color:var(--add-ink)}

/* steps — numbered ordered process */
ol.steps{list-style:none;counter-reset:s;margin:6px 0;padding:0}
ol.steps>li{counter-increment:s;position:relative;padding:3px 0 12px 40px;margin:0}
ol.steps>li::before{content:counter(s);position:absolute;left:0;top:0;width:26px;height:26px;border-radius:50%;background:var(--teal-wash);border:1.5px solid var(--teal);color:var(--teal-deep);font-family:var(--mono);font-size:.8rem;font-weight:700;display:flex;align-items:center;justify-content:center}
ol.steps>li:not(:last-child)::after{content:"";position:absolute;left:13px;top:28px;bottom:2px;width:2px;background:var(--line-soft)}
ol.steps>li .st{font-weight:600;color:var(--ink)}

/* legend */
.legend{display:flex;gap:16px;flex-wrap:wrap;margin:10px 0 0;font-size:.78rem;color:var(--muted)}
.legend span{display:inline-flex;align-items:center;gap:6px}
.legend i{width:11px;height:11px;border-radius:3px;display:inline-block}
.legend i.hi{background:var(--hi)}.legend i.lo{background:var(--lo)}.legend i.teal{background:var(--teal)}.legend i.md{background:var(--md)}

/* SVG escape-hatch: consistent styling for hand-authored diagrams */
.fh .hiw svg,.diagram svg{display:block;width:100%;max-width:100%;height:auto}
.diagram{margin:14px 0 2px;overflow-x:auto}
svg .dg-node{fill:var(--paper);stroke:var(--md);stroke-width:1.5}
svg .dg-node.hi{fill:var(--hi-wash);stroke:var(--hi)}
svg .dg-node.lo{fill:var(--lo-wash);stroke:var(--lo)}
svg .dg-node.teal{fill:var(--teal-wash);stroke:var(--teal)}
svg .dg-t{fill:var(--ink);font-family:var(--mono)}
svg .dg-s{fill:var(--muted);font-family:var(--mono)}
svg .dg-edge{fill:none;stroke:var(--faint);stroke-width:1.5}

.btn{font-family:var(--mono);font-size:.72rem;border:1px solid var(--line);background:var(--paper);color:var(--muted);border-radius:7px;padding:4px 9px;cursor:pointer;white-space:nowrap;transition:all .12s}
.btn:hover{border-color:var(--teal);color:var(--teal-deep);background:var(--teal-wash)}
.btn.copied{border-color:var(--lo);color:var(--lo);background:var(--lo-wash)}
.btn.primary{border-color:var(--teal);color:#fff;background:var(--teal);font-weight:600}
.btn.primary:hover{background:var(--teal-deep);border-color:var(--teal-deep);color:#fff}
.btn .ic{font-size:.9em;opacity:.7}
.fh .iso{margin-top:15px;display:flex;gap:8px;align-items:center}

.files{list-style:none;margin:0;padding:0}
.file{border-top:1px solid var(--line-soft)}
.file .row{display:flex;align-items:center;gap:10px;padding:9px 22px}
.file .row:hover{background:#f7f8f9}
.file .ck{width:16px;height:16px;flex:none;cursor:pointer;accent-color:var(--teal)}
.file .st{font-family:var(--mono);font-size:.68rem;font-weight:700;width:18px;text-align:center;flex:none;border-radius:4px;padding:1px 0}
.st.A{background:var(--add-bg);color:var(--add-ink)}.st.M{background:#fef0d6;color:var(--hi)}.st.D{background:var(--del-bg);color:var(--del-ink)}.st.R{background:var(--md-wash);color:var(--md)}.st.x{background:var(--line);color:var(--muted)}
.file .p{font-family:var(--mono);font-size:.8rem;min-width:0;overflow-wrap:anywhere;flex:1}
.file .p .dir{color:var(--faint)}.file .p .base{color:var(--ink);font-weight:600}
.file.done .p .base{color:var(--faint);font-weight:500;text-decoration:line-through}
.file .n{font-family:var(--mono);font-size:.72rem;color:var(--faint);white-space:nowrap;flex:none}
.file .n .plus{color:var(--add-ink)}.file .n .minus{color:var(--del-ink)}

.house summary{cursor:pointer;font-weight:600;padding:16px 22px}
.house summary::-webkit-details-marker{color:var(--faint)}
.house .files .row{padding:7px 22px}

footer{margin-top:40px;padding-top:18px;border-top:1px solid var(--line);font-family:var(--mono);font-size:.72rem;color:var(--faint);display:flex;gap:8px 18px;flex-wrap:wrap;justify-content:space-between}
.toast{position:fixed;bottom:22px;left:50%;transform:translateX(-50%) translateY(20px);background:var(--ink);color:#fff;font-family:var(--mono);font-size:.78rem;padding:9px 16px;border-radius:9px;opacity:0;pointer-events:none;transition:all .2s;z-index:50}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
@media(max-width:680px){.fh .meta{margin-left:0;width:100%}.nav .prog{order:-1}.branch .kids{flex-direction:column}.branch .kids::before{display:none}}
"""

JS = r"""
const REPO = document.body.dataset.repo || "repo";
// Served over http(s) by the cmux bridge → clicks drive nvim. Opened as a bare
// file:// → no bridge, so fall back to copying the ex-command to the clipboard.
const SERVED = location.protocol === "http:" || location.protocol === "https:";
const lsKey = p => `nvim-review:${REPO}:${p}`;
let toastT;
function toast(msg){
  let t=document.getElementById("toast");
  t.textContent=msg; t.classList.add("show");
  clearTimeout(toastT); toastT=setTimeout(()=>t.classList.remove("show"),1500);
}
function flash(btn,label){
  const o=btn.dataset.label||btn.textContent;
  btn.classList.add("copied"); btn.textContent=label;
  setTimeout(()=>{btn.classList.remove("copied");btn.textContent=o;},1100);
}
async function clip(text,btn){
  try{ await navigator.clipboard.writeText(text); }
  catch(e){ const ta=document.createElement("textarea"); ta.value=text; document.body.appendChild(ta); ta.select(); document.execCommand("copy"); ta.remove(); }
  if(btn) flash(btn,"✓ copied");
  toast("Copied — in nvim: :  then  Ctrl-r +  ↵");
}
async function sendNvim(cmd,btn){
  try{
    await fetch("/nvim",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({cmd})});
    if(btn) flash(btn,"✓ nvim"); toast("→ sent to your nvim pane");
  }catch(e){ toast("bridge unreachable — is the review server running?"); }
}
async function openInTab(mode,value,name,btn){
  try{
    await fetch("/newtab",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({mode,value,name})});
    if(btn) flash(btn,"✓ tab"); toast("→ opened a new full-screen nvim tab");
  }catch(e){ toast("bridge unreachable — is the review server running?"); }
}
function act(btn){
  const cmd=btn.dataset.cmd, mode=btn.dataset.mode||"diff";
  if(!SERVED){ clip((mode==="file"?":edit ":":")+cmd, btn); return; }
  if(btn.dataset.newtab) openInTab(mode, cmd, btn.dataset.name||"nvim", btn);
  else sendNvim(cmd,btn);
}
async function persistCheck(path,reviewed){
  if(!SERVED) return;
  try{ await fetch("/check",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({path,reviewed})}); }catch(e){}
}
function updateProgress(){
  const all=[...document.querySelectorAll(".file .ck")];
  const done=all.filter(c=>c.checked).length;
  const el=document.getElementById("prog");
  if(el) el.textContent=`${done} / ${all.length} reviewed`;
}
document.addEventListener("DOMContentLoaded",()=>{
  if(SERVED){  // heartbeat (only used as a backstop when there's no tab to watch).
    // NOTE: deliberately NO pagehide→/bye beacon — pagehide also fires on reload,
    // which would wrongly kill the server. Tab-close is detected by the server's
    // surface-existence watchdog instead (reload keeps the surface; close drops it).
    const ping=()=>fetch("/ping",{method:"POST"}).catch(()=>{});
    ping(); setInterval(ping,5000);
  }
  const hint=document.getElementById("hint");
  if(hint) hint.innerHTML = SERVED
    ? "Bridged to your nvim pane: <b>▸ open</b> opens the file, <b>▣ isolate in diffview</b> shows just that feature's changes, and checkboxes sync to <code>&lt;leader&gt;rc</code>."
    : "Static file (no bridge): buttons copy an ex-command — in nvim type <code>:</code> then <code>Ctrl-r +</code> then <code>↵</code>.";
  document.querySelectorAll(".act").forEach(b=>{
    b.dataset.label=b.textContent;
    b.addEventListener("click",e=>{ e.preventDefault(); e.stopPropagation(); act(b); });
  });
  document.querySelectorAll(".file").forEach(f=>{
    const ck=f.querySelector(".ck"); if(!ck) return;
    const key=lsKey(ck.dataset.path);
    const saved=localStorage.getItem(key);
    ck.checked = saved!==null ? saved==="1" : ck.dataset.seeded==="1";
    f.classList.toggle("done",ck.checked);
    ck.addEventListener("change",()=>{
      localStorage.setItem(key,ck.checked?"1":"0");
      f.classList.toggle("done",ck.checked);
      persistCheck(ck.dataset.path,ck.checked);
      updateProgress();
    });
  });
  updateProgress();
});
"""


def esc(s):
    return html.escape(s or "")


def split_path(path):
    if "/" in path:
        d, b = path.rsplit("/", 1)
        return f'<span class="dir">{esc(d)}/</span><span class="base">{esc(b)}</span>'
    return f'<span class="base">{esc(path)}</span>'


def display_status(status):
    """One letter for the badge. Range modes give 'A'/'M'/'D'/'R'; worktree
    porcelain gives two cols with spaces shown as '.' ('.M', 'A.', '??')."""
    s = (status or "").replace(".", "").replace(" ", "")
    if not s:
        return "M"
    if s.startswith("?"):
        return "A"  # untracked = new file
    return s[0].upper()


def status_class(letter):
    return letter if letter in ("A", "M", "D", "R") else "x"


def render_file(f):
    path, status = f["path"], f["status"]
    add, dele = f["additions"], f["deletions"]
    seeded = "1" if f["reviewed"] else "0"
    nums = []
    if add:
        nums.append(f'<span class="plus">+{add}</span>')
    if dele:
        nums.append(f'<span class="minus">−{dele}</span>')
    numhtml = " ".join(nums) or "·"
    letter = display_status(status)
    base = path.rsplit("/", 1)[-1]
    return f"""<li class="file">
  <div class="row">
    <input type="checkbox" class="ck" data-path="{esc(path)}" data-seeded="{seeded}" title="mark reviewed">
    <span class="st {status_class(letter)}">{esc(letter)}</span>
    <span class="p">{split_path(path)}</span>
    <span class="n">{numhtml}</span>
    <button class="btn act" data-newtab="1" data-mode="file" data-cmd="{esc(path)}" data-name="{esc(base)}" title="open this file in its own full-screen nvim tab"><span class="ic">▸</span> open</button>
  </div>
</li>"""


def render_cluster(root, c, rng, dv_prefix):
    files = c["_files"]
    paths = [f["path"] for f in files]
    risk = c.get("risk", "Medium")
    risk = risk if risk in ("High", "Medium", "Low") else "Medium"
    add = sum(f["additions"] for f in files)
    dele = sum(f["deletions"] for f in files)
    iso = diffview_excmd(dv_prefix, paths)
    focus = ""
    if c.get("review_focus"):
        focus = ('<div class="focus-h">Review focus</div><ul class="focus">'
                 + "".join(f"<li>{esc(b)}</li>" for b in c["review_focus"]) + "</ul>")
    goal = f'<p class="goal">{esc(c["goal"])}</p>' if c.get("goal") else ""
    # how_it_works and diagram_html are injected verbatim (raw HTML/SVG authored by caller)
    hiw = f'<div class="hiw">{c["how_it_works"]}</div>' if c.get("how_it_works") else ""
    diagram = f'<div class="diagram">{c["diagram_html"]}</div>' if c.get("diagram_html") else ""
    files_html = "".join(render_file(f) for f in files)
    anchor = c["_anchor"]
    return f"""<section class="feat {risk}" id="{anchor}">
  <div class="fh">
    <div class="top">
      <span class="chip {risk}">{risk}</span>
      <h2>{esc(c["name"])}</h2>
      <span class="meta">{len(files)} files &nbsp; <span class="plus">+{add}</span> <span class="minus">−{dele}</span></span>
    </div>
    {goal}
    {hiw}
    {diagram}
    {focus}
    <div class="iso">
      <button class="btn act primary" data-cmd="{esc(iso)}" data-newtab="1" data-mode="diff" data-name="◫ {esc(c['name'])}" title="open just this feature's changes in a new full-screen diffview tab"><span class="ic">▣</span> isolate in diffview</button>
    </div>
  </div>
  <ul class="files">{files_html}</ul>
</section>"""


def diffview_excmd(dv_prefix, paths):
    """The ex-command (no leading colon) that scopes diffview to these paths."""
    specs = " ".join(literal(p) for p in paths)
    return f"DiffviewOpen {dv_prefix}-- {specs}"


def render_housekeeping(root, hk, rng, dv_prefix):
    files = hk["_files"]
    if not files:
        return ""
    add = sum(f["additions"] for f in files)
    dele = sum(f["deletions"] for f in files)
    iso = diffview_excmd(dv_prefix, [f["path"] for f in files])
    rows = ""
    for f in files:
        letter = display_status(f["status"])
        rows += f"""<li class="file"><div class="row">
  <input type="checkbox" class="ck" data-path="{esc(f['path'])}" data-seeded="{'1' if f['reviewed'] else '0'}">
  <span class="st {status_class(letter)}">{esc(letter)}</span>
  <span class="p">{split_path(f['path'])}</span>
  <span class="n"><span class="plus">+{f['additions']}</span> <span class="minus">−{f['deletions']}</span></span>
</div></li>"""
    return f"""<details class="feat house" id="cl-housekeeping" style="margin-top:30px">
  <summary>{esc(hk.get('name','Housekeeping'))} — {len(files)} files (<span class="plus">+{add}</span> <span class="minus">−{dele}</span>), diffs not embedded
    &nbsp;<button class="btn act" data-cmd="{esc(iso)}" data-newtab="1" data-mode="diff" data-name="◫ Housekeeping"><span class="ic">▣</span> all in diffview</button>
  </summary>
  <ul class="files">{rows}</ul>
</details>"""


def render_banner(spec):
    r = spec.get("risk")
    if not r:
        return ""
    level = r.get("level", "Medium")
    level = level if level in ("High", "Medium", "Low") else "Medium"
    summary = f'<p>{esc(r["summary"])}</p>' if r.get("summary") else ""
    rf = ""
    if r.get("review_first"):
        rf = "<ul>" + "".join(f"<li>{esc(x)}</li>" for x in r["review_first"]) + "</ul>"
    return f"""<div class="banner {level}">
  <div class="v"><span class="chip {level}">{level} risk</span> Overall</div>
  {summary}{rf}
</div>"""


def render_nav(spec, clusters, has_house):
    jumps = "".join(
        f'<a class="jump {c.get("risk","Medium") if c.get("risk","Medium") in ("High","Medium","Low") else "Medium"}" href="#{c["_anchor"]}">{esc(c["name"])}</a>'
        for c in clusters
    )
    if has_house:
        jumps += '<a class="jump Low" href="#cl-housekeeping">Housekeeping</a>'
    return jumps


def assemble(spec, root, branch, mode_label, rng, dv_prefix, base_label):
    clusters = [c for c in spec["clusters"] if c["_files"]]
    has_house = bool(spec.get("housekeeping", {}).get("_files"))
    title = spec.get("title") or f"Review — {branch}"
    body_sections = "".join(render_cluster(root, c, rng, dv_prefix) for c in clusters)
    house = render_housekeeping(root, spec.get("housekeeping", {}), rng, dv_prefix) if has_house else ""
    nav_jumps = render_nav(spec, clusters, has_house)
    banner = render_banner(spec)
    repo_name = os.path.basename(root)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)}</title>
<style>{CSS}</style>
</head>
<body data-repo="{esc(repo_name)}">
<nav class="nav">
  <span class="brand">{esc(title)}<small>nvim-review · {esc(base_label)}</small></span>
  {nav_jumps}
  <span class="prog" id="prog">0 / 0 reviewed</span>
</nav>
<div class="wrap">
  <header class="head">
    <h1>{esc(title)}</h1>
    <div class="sub">branch <b>{esc(branch)}</b> &nbsp;·&nbsp; {esc(mode_label)} ({esc(base_label)})</div>
    {banner}
    <div class="hint" id="hint"></div>
  </header>
  {body_sections}
  {house}
  <footer>
    <span>nvim-review · {esc(branch)} · {esc(mode_label)}</span>
    <span>checkboxes persist in localStorage · not committed</span>
  </footer>
</div>
<div class="toast" id="toast"></div>
<script>{JS}</script>
</body>
</html>"""


# ── spec resolution ──────────────────────────────────────────────────────────

def anchorize(name, i):
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or f"cluster-{i}"
    return f"cl-{i}-{slug}"


def resolve_entry(entry, all_paths, by_path, assigned):
    """Ordered, deduped list of changed paths for one cluster/housekeeping entry.
    `paths` are LITERAL (safe for the [alpha3] brackets); `globs` are fnmatch
    patterns swept over the change set (match full path, suffix, or basename) —
    use them to fold whole categories like translations in one line. Paths already
    claimed by an earlier cluster are skipped (first cluster wins)."""
    out, seen = [], set()

    def take(p):
        if p in assigned or p in seen:
            return
        seen.add(p)
        out.append(p)

    for p in entry.get("paths", []):
        if p in by_path:
            take(p)
        else:
            print(f"warning: literal path not in change set, skipped: {p}", file=sys.stderr)
    for g in entry.get("globs", []):
        hits = [p for p in all_paths
                if fnmatch.fnmatch(p, g) or fnmatch.fnmatch(p, "*" + g)
                or fnmatch.fnmatch(os.path.basename(p), g)]
        if not hits:
            print(f"warning: glob matched no changed file: {g}", file=sys.stderr)
        for p in hits:
            take(p)
    return out


def attach_files(spec, root, rng):
    """Bind each spec path to its {status, additions, deletions, reviewed}.
    Collect any changed file the spec didn't mention into an 'Unassigned' cluster."""
    changed = changed_files(root, rng)
    stats = numstat(root, rng)
    by_path = {p: s for s, p in changed}
    all_paths = [p for _, p in changed]
    seeded = seeded_reviewed(root, all_paths)

    def mk(path):
        add, dele = stats.get(path, (0, 0))
        return {
            "path": path,
            "status": by_path.get(path, "?"),
            "additions": add,
            "deletions": dele,
            "reviewed": path in seeded,
        }

    assigned = set()
    for i, c in enumerate(spec.get("clusters", [])):
        resolved = resolve_entry(c, all_paths, by_path, assigned)
        c["_files"] = [mk(p) for p in resolved]
        assigned.update(resolved)
        c["_anchor"] = anchorize(c.get("name", ""), i)

    hk = spec.setdefault("housekeeping", {})
    resolved = resolve_entry(hk, all_paths, by_path, assigned)
    hk["_files"] = [mk(p) for p in resolved]
    assigned.update(resolved)

    leftover = [p for p in all_paths if p not in assigned]
    if leftover:
        print(f"warning: {len(leftover)} changed file(s) not assigned to any cluster — "
              "added to an 'Unassigned' section so nothing is dropped.", file=sys.stderr)
        spec["clusters"].append({
            "name": "Unassigned",
            "risk": "Medium",
            "goal": "Files the spec did not place into a feature — review or re-cluster.",
            "paths": leftover,
            "_files": [mk(p) for p in leftover],
            "_anchor": anchorize("unassigned", len(spec["clusters"])),
        })


def git_exclude_review_dir(root):
    """Keep .review/ out of git via .git/info/exclude (never touches tracked .gitignore)."""
    exclude = os.path.join(git_dir(), "info", "exclude")
    os.makedirs(os.path.dirname(exclude), exist_ok=True)
    existing = open(exclude).read() if os.path.isfile(exclude) else ""
    if ".review/" not in existing:
        with open(exclude, "a") as f:
            if existing and not existing.endswith("\n"):
                f.write("\n")
            f.write(".review/\n")


# ── main ─────────────────────────────────────────────────────────────────────

def review_target(rng_explicit, mode):
    """Resolve the review target to (rng, dv_prefix, base_label, mode_label).
    rng       — range string for `git diff` (None = uncommitted worktree).
    dv_prefix — prefix for the :DiffviewOpen command ('' worktree, else 'A...B ').
    An explicit range (e.g. a merged PR's `<base>...HEAD`) overrides mode."""
    if rng_explicit:
        return rng_explicit, rng_explicit + " ", rng_explicit, "range"
    if mode == "worktree":
        return None, "", "working tree vs HEAD", "worktree"
    rng = range_for(mode)
    base_label = base_branch() if mode == "main" else "origin/staging"
    return rng, rng + " ", base_label, mode


def main():
    ap = argparse.ArgumentParser(description="Build an HTML review packet for nvim-side code review.")
    ap.add_argument("--mode", choices=["main", "staging", "worktree"], default="main",
                    help="which change-set to review (default: main = this branch vs origin/main)")
    ap.add_argument("--range", dest="rng_explicit", metavar="A...B",
                    help="explicit git range to review (e.g. <base-sha>...HEAD for a merged PR); "
                         "overrides --mode and any spec 'mode'. Used verbatim for diff + diffview commands.")
    ap.add_argument("--list-json", action="store_true",
                    help="emit changed files + meta as JSON (phase 1: for clustering)")
    ap.add_argument("--spec", metavar="FILE", help="clustering spec JSON (phase 2: render the packet)")
    ap.add_argument("--out", metavar="FILE", help="output HTML path (default: <repo>/.review/<branch>.html)")
    args = ap.parse_args()

    root = repo_root()
    branch = current_branch()

    if args.list_json:
        rng, _dv, base_label, mode_label = review_target(args.rng_explicit, args.mode)
        changed = changed_files(root, rng)
        stats = numstat(root, rng)
        all_paths = [p for _, p in changed]
        seeded = seeded_reviewed(root, all_paths)
        out = {
            "branch": branch,
            "mode": mode_label,
            "base": base_label,
            "files": [
                {"status": s, "path": p,
                 "additions": stats.get(p, (0, 0))[0], "deletions": stats.get(p, (0, 0))[1],
                 "reviewed": p in seeded}
                for s, p in changed
            ],
        }
        print(json.dumps(out, indent=2))
        return

    if not args.spec:
        die("Pass --list-json (phase 1) or --spec FILE (phase 2). See --help.")

    try:
        spec = json.load(open(args.spec))
    except Exception as e:
        die(f"Could not read spec {args.spec}: {e}")
    if not isinstance(spec, dict) or not spec.get("clusters"):
        die("Spec must be a JSON object with a non-empty 'clusters' array.")

    mode = spec.get("mode", args.mode)
    if mode not in ("main", "staging", "worktree"):
        mode = args.mode
    rng, dv_prefix, base_label, mode_label = review_target(args.rng_explicit, mode)

    if not changed_files(root, rng):
        die(f"No changes for {mode_label} ({base_label}). Nothing to review.")

    attach_files(spec, root, rng)
    htmlout = assemble(spec, root, branch, mode_label, rng, dv_prefix, base_label)

    out_path = args.out
    if not out_path:
        slug = re.sub(r"[^A-Za-z0-9._-]+", "-", branch).strip("-") or "review"
        out_dir = os.path.join(root, ".review")
        os.makedirs(out_dir, exist_ok=True)
        git_exclude_review_dir(root)
        out_path = os.path.join(out_dir, f"{slug}.html")
    else:
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(htmlout)

    total = sum(len(c["_files"]) for c in spec["clusters"]) + len(spec.get("housekeeping", {}).get("_files", []))
    print(os.path.abspath(out_path))
    print(f"Rendered {len(spec['clusters'])} feature section(s) + "
          f"{len(spec.get('housekeeping', {}).get('_files', []))} housekeeping file(s); {total} files total.")


if __name__ == "__main__":
    main()
