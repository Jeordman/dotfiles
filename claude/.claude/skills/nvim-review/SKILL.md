---
name: nvim-review
description: Build a rich code-review packet for the current branch/PR that lives INSIDE cmux beside nvim — feature-clustered, with a per-feature "how it works" explanation (architecture, data-flow, why — ported from /visual-review's analysis depth), risk banner, and inline-SVG diagrams. It does NOT embed diffs; instead each feature has an "isolate in diffview" button. Served locally and opened in a cmux browser pane, with a bridge so clicks drive your nvim pane: "open" opens a file, "isolate in diffview" opens just that feature's changes in nvim's diffview, and checkboxes sync to the <leader>rc checklist. Use when the user wants to REVIEW a branch/PR and read how it works, then inspect the actual changes in nvim — e.g. "/nvim-review", "review this branch/PR in cmux", "build the review packet", "walk this release feature-by-feature", "review PR #N". The cmux-native, nvim-bridged cousin of /visual-review (which makes a hosted shareable artifact). NOT for ticking files off a checklist (that's review-checklist).
---

# nvim-review — a review packet inside cmux, wired to nvim

Turn a branch/PR diff into a rich HTML packet that opens **in a cmux browser pane next to
your nvim**. It is the **understanding layer**: it explains *what each feature does, how it
works, and what to scrutinize* — it deliberately does **not** show the code. You read how a
feature works, then hit **▣ isolate in diffview** and inspect the actual changes in nvim's
diffview, in the same cmux window.

Two surfaces, one workspace:
- **The packet** (cmux browser tab) — risk banner, feature clustering, per-feature
  *how-it-works* (architecture / data-flow / why) + review-focus, inline-SVG diagrams.
- **The bridge** (a local server cmux talks to) — every click spawns its OWN new full-screen
  nvim tab, in the **background** (`--focus false`) and in the review's workspace, so it never
  pulls you away from what you're doing (no existing nvim pane is touched or even needed):
  - `▸ open` → POST `/newtab {mode:file}` → a new tab running `nvim -- '<path>'`
  - `▣ isolate in diffview` → POST `/newtab {mode:diff}` → a new tab running
    `nvim -c 'DiffviewOpen <range> -- :(literal)<paths>'`
  - `☑ checkbox` → writes `<git-dir>/nvim-review-checklist.json` (the same file `<leader>rc` reads)

This is the cmux-native, nvim-bridged cousin of `/visual-review`. It carries that command's
**analysis depth** (read the code, explain how it works) but the deliverable is local and
the code-reading happens in nvim, not embedded in the page.

## Split of work

A bundled script does everything deterministic and fragile (pull the change set,
**literal pathspecs** — the repo's `[alpha3]/[language]` paths contain `[`, which git would
read as a glob — seed checkboxes from the nvim checklist, render the self-contained shell).
**You** supply the judgment as a JSON spec: the clusters, and for each one a *how-it-works*
explanation grounded in actually reading the code.

```
python3 <skill-dir>/scripts/build_review.py --list-json [--mode MODE | --range A...B]   # 1: change set
python3 <skill-dir>/scripts/build_review.py --spec <spec.json> [--mode MODE | --range A...B]  # 2: render
python3 <skill-dir>/scripts/serve_review.py --html .review/<branch>.html --title "Review — <name>"   # 3: serve+open tab
```

Resolve `<skill-dir>` to where this SKILL.md lives. **Run from inside the user's repo.**

`MODE` (default `main`): `main` = this branch vs `origin/main` (`<leader>rm`); `staging` =
vs `origin/staging` (`<leader>rs`); `worktree` = uncommitted vs HEAD (`<leader>rr`).

### Reviewing a specific or already-merged PR — use `--range`

When the user names a PR (`review PR #4926` / a link), don't use `--mode` (a merged PR's
three-dot range is empty). Pass `--range <base>...<head>` to BOTH `--list-json` and `--spec`:

1. `gh pr view <N> --json baseRefName,headRefName,state,title` — get base/head/state.
2. **Merged** → reproduce GitHub's diff from the merge commit's parents:
   `MERGE=$(git log origin/<base> --merges --grep='#<N>' --format='%H' -n1)`, then
   `--range "$(git rev-parse $MERGE^1)...$(git rev-parse $MERGE^2)"` (`git fetch` first).
   **Open** → `--range origin/<base>...origin/<head>`.
3. **Release PR** → cluster by the PRs it bundles:
   `git log <base>...<head> --merges --first-parent --format='%H %s'`; attribute each inner
   merge's files with `git diff --name-only <merge>^1...<merge>^2`; pull intent with `gh pr view`.

## The workflow

### 1 — Get the change set

`build_review.py --list-json …` → `{branch, mode, base, files:[{status,path,additions,deletions,reviewed}]}`.
`reviewed:true` = already ticked in `<leader>rc`.

### 2 — Analyze & cluster (this is the real work — match /visual-review's depth)

Build a mental model: which **logical clusters** the change contains, each one's intent,
architecture, and risk. Group by **intent, not by file or commit**.

- **Gather the signal** (committed work): `git log <base>..HEAD --first-parent --oneline`,
  `… --merges --oneline`, `git diff <base>..HEAD --stat`.
- **PR descriptions** (high signal, skip if no `gh`): for each merge PR,
  `gh pr view <N> --json number,title,body,labels,closingIssuesReferences`. Use the title as
  the cluster name, the body for goal + focus (rewrite, don't paste), labels to inform risk.
- **Cluster heuristics**: a merge from a `feat/…`/`fix/…` branch = one cluster (read the
  slug); a run of direct commits on one area = one cluster; translations
  (`**/messages/*.json`), lockfiles, snapshots, generated output → one `housekeeping` block
  (sweep with globs, never hand-list). Plan/design-doc *additions* go with their feature.
- **Read high-signal files per cluster** — this is what makes the packet worth more than a
  `git log`. Per cluster read 1–2 representative files + the entry point: enough to map the
  architecture and data flow. New dir → learn the pattern from one file. Single-file fix →
  read the hunk in context and know *why it broke and why this fixes it*. Refactor → the old
  vs new shape. **Never let a cluster bottom out at "various files updated."**

For each cluster decide: **name**, **risk** (`High`/`Medium`/`Low` — High = touches a
globally-loaded module: proxy / layout / providers / auth / payments), **goal** (≤1
sentence), a **how_it_works** explanation (the ported-from-visual-review piece — see below),
and **review_focus** (≤5 bullets: the things most likely wrong). Optionally an overall
**risk banner**.

### 3 — Write the spec, render

Write `.review/spec.json` (the dir is git-excluded automatically), then `build_review.py
--spec .review/spec.json …`. Check stderr: an "Unassigned" warning means you missed files
(they're parked in an `Unassigned` section so nothing's dropped — re-cluster if the count is
meaningful); "glob matched nothing" means a spec typo.

### 4 — Serve into cmux

```
python3 <skill-dir>/scripts/serve_review.py --html .review/<branch>.html --title "Review — <name>"
```

**Run it in the background.** It serves the packet and opens it as ONE **full-screen, named
cmux tab** (a browser surface) in the current workspace. No nvim surface to detect, so it
never opens a stray second tab; if a prior server's review tab is still open, a re-run
**reuses it** instead of opening another. `--title` names the tab.

It self-cleans — no orphaned servers:
- **Singleton + reuse** — a prior server is killed on start and its review tab reused, so
  re-running never stacks servers or tabs.
- **Auto-shutdown** — the server watches whether the review tab still exists and exits
  (removing its pidfile, `<git-dir>/nvim-review-server.json`) when you close it. **So don't
  kill it at the end of the skill** — leave it; it dies with the tab.
- **Force-stop** — `serve_review.py --stop` kills the recorded server for this repo.

Then tell the user: *read each feature's how-it-works, then click ▣ isolate in diffview (or ▸
open on a file) — each opens in its own new full-screen tab, in the background, so you're not
pulled away; switch to it when ready. Tick files off (syncs to `<leader>rc`). Close the review
tab when done — the server stops itself; close the per-feature tabs as you finish them.*

**Not in cmux?** Skip `serve_review.py`; open `.review/<branch>.html` in a browser — its
buttons copy the ex-commands to paste into nvim (`:` then `Ctrl-r +` `↵`).

## Spec schema

```json
{
  "title": "Release v1.12.8 — review",          // optional
  "mode": "main",                                // optional; --mode/--range override
  "risk": { "level": "High", "summary": "blast-radius line", "review_first": ["…","…"] },
  "clusters": [
    {
      "name": "Pricing pipeline",
      "risk": "High",                            // High|Medium|Low (default Medium)
      "goal": "one sentence",
      "how_it_works": "<p>Raw HTML — explain the mechanism…</p>",   // the explanation block
      "diagram_html": "<svg …>…</svg>",           // optional standalone diagram
      "review_focus": ["most likely wrong thing", "…"],            // ≤5
      "paths":  ["literal/path/[alpha3]/File.tsx"],                // LITERAL (bracket-safe)
      "globs":  ["apps/shop/src/lib/pricing/**"]                   // fnmatch category sweeps
    }
  ],
  "housekeeping": { "name": "Housekeeping", "globs": ["**/messages/*.json"], "paths": ["pnpm-lock.yaml"] }
}
```

**`how_it_works` is the heart of the packet** — it's where the "explain how it works" depth
lives, and it is NOT optional for any non-trivial cluster. The failure mode to avoid is a
cluster with only a goal + review-focus bullets (a `git log` paraphrase). Every cluster that
has real behavior MUST have a `how_it_works` that:

1. is **grounded in actually reading the code** (Step 2's "read high-signal files") — name the
   real functions/modules and what they do, not vague summaries; and
2. includes a **diagram (inline SVG)** whenever the cluster has a data flow, pipeline, request
   path, or cooperating modules — which most do. Diagram the flow the way `/visual-review`
   would: boxes + arrows showing how data moves, with the key decision points labeled. A
   before/after for a refactor; a node graph for a blast radius. Reach for the diagram first;
   prose fills the gaps the picture can't.

Raw HTML injected verbatim; keep it self-contained (no CDN, no external anything). Pick the
clearest form per the data:

| The thing is… | Use |
| --- | --- |
| A data-flow / pipeline / blast radius | inline `<svg>` boxes + arrows |
| A refactor's shape change | two columns: `<div class="cols"><div><div class="lbl">before</div>…</div><div><div class="lbl">after</div>…</div></div>` |
| The mechanism / why it broke / why this fixes it | tight `<p>` prose; wrap symbols in `<code>` or `<span class="path">` |

Available styling inside `how_it_works`: `<p>`, `<b>`, `<code>`/`<span class="path">`,
`<div class="cols">`+`.lbl` (two-column before/after), and inline `<svg>` (palette: teal
`#15616d`, amber `#9a6312`, slate `#4f5d75`; system mono font). Keep it terse — a diagram
beats a paragraph; a paragraph beats nothing; skip it for a linear one-line change.

**`paths` vs `globs`:** exact files go in `paths` (always literal — bracket-safe); `globs`
(fnmatch over the change set) fold whole categories in one entry. First cluster to claim a
path wins.

## Guardrails

- **No embedded diffs** — the packet explains; the code is read in nvim via *isolate in
  diffview*. Don't try to put diffs back in the HTML.
- **Never drop a file** — every changed file lands in a cluster, housekeeping, or the auto
  `Unassigned` catch-all. Re-cluster if Unassigned is non-trivial.
- **Don't hand-list categories** — one glob per category.
- **Honest risk** (High = globally-loaded module). Per cluster: goal ≤1 sentence, focus ≤5.
- **Output is never committed** — it lives in `.review/` (auto-added to `.git/info/exclude`).
- This packet is for *reviewing*; to tick/trim the checklist outside a click, use the
  **review-checklist** skill.
