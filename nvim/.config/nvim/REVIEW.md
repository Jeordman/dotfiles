# Code Review in Neovim

A consistent way to review changes — your own or AI-generated — without getting
lost in a sprawling multi-file diff. Built on
[diffview.nvim](https://github.com/sindrets/diffview.nvim) plus a small checklist
layer that tracks what you've reviewed.

Config lives in:
- `lua/plugins/git/diffview.lua` — the keymaps and the checklist UI
- `lua/review_checklist.lua` — the data layer (what's changed, what's reviewed/hidden)

---

## The loop

1. **`<leader>rr`** — open the review (your uncommitted changes).
2. **`<leader>rc`** — open the checklist: every changed file + a progress count.
3. Walk the diff file by file (`<Tab>`), tracing logic with `grd` / `grr` as needed.
4. **`<leader>rc`** again and tick files off (`x`) as you finish them.
5. **`<leader>rq`** — close when done.

That's it. The rest below is detail and shortcuts.

---

## Starting a review — pick what to compare against

| Key | Compares… | Use when |
|-----|-----------|----------|
| `<leader>rr` | working tree vs HEAD (uncommitted) | the usual case — about to commit a pile |
| `<leader>rm` | your branch vs `main`/`master` | the changes are already **committed** |
| `<leader>rs` | your branch vs `staging` | reviewing against staging |
| `<leader>rh` | history of the **current file**, commit by commit | following one file's evolution |
| `<leader>rH` | history of the **whole branch**, commit by commit | stepping through commits |

The checklist (`<leader>rc`) always reflects whichever of these you opened.

---

## Inside the diff

These are diffview's own keys (they work in the diff and the file panel):

| Key | Action |
|-----|--------|
| `<Tab>` / `<S-Tab>` | next / previous changed file |
| `i` | toggle the file panel between tree and flat list |
| `]c` / `[c` | next / previous hunk |
| `grd` / `grr` / `K` | go to definition / references / signature — **works right in the diff** |
| `<C-t>` | jump back after a `grd` |
| `g<C-x>` | cycle diff layout (side-by-side ↔ stacked) |
| `<leader>rf` or `<leader>b` | hide/show the file panel |
| `q` | close the review |

Tracing a call with `grd` from inside the diff is how you follow logic across
files instead of scrolling blind.

---

## The checklist (`<leader>rc`)

A floating window listing every changed file with a progress count
(`5 / 12 reviewed`). It reads fresh each time you open it.

**Normal mode** (acts on the file under the cursor):

| Key | Action |
|-----|--------|
| `x` or `<Space>` | tick reviewed / un-tick |
| `h` | hide this file / unhide it |
| `H` | reveal hidden files (and collapse them again) |
| `<CR>` or `o` | open the file |
| `q` or `<Esc>` | close the checklist |

**Visual mode** — select a range of lines with `V`, then apply to all of them:

| Key | Action |
|-----|--------|
| `x` or `<Space>` | mark every selected file reviewed |
| `h` | hide every selected file |
| `H` | unhide every selected file |

(`H` is reveal in normal mode and unhide in visual mode — so you reveal the
hidden rows, select them, then unhide.)

Other:
- **`<leader>rx`** — clear all reviewed marks and start fresh (hidden files stay hidden).

---

## How "reviewed" works

A reviewed mark is tied to the file's **current content** (its git blob hash),
not just its name. So:

- Tick a file, leave it alone → it stays reviewed.
- **Edit it again → the mark clears automatically**, because there are new
  changes to look at. (Same idea as GitHub un-checking "viewed" when a file
  changes.)

Marks are also pruned to the current change every time the checklist opens, so
old reviews of unrelated files never linger.

---

## Hiding files

Hiding **removes a file from the checklist entirely** — for noise that isn't
worth a human read (lockfiles, generated code, snapshots, pure formatting).

Hidden files don't vanish silently: the checklist shows a `· N hidden` count,
and `H` reveals them so you can audit or unhide. Use this to cut a 30-file
change down to the handful that actually need your eyes.

---

## Letting Claude update the checklist

Claude can tick **and** hide files for you, via the `review-checklist` skill
(in `claude/.claude/skills/review-checklist/`). Useful when Claude has just
explained a change and you don't need to read every file yourself.

Just say it naturally — no need to mention "checklist":

- *"Check off the files you just explained."*
- *"Mark everything reviewed except the migration."*
- *"Hide the lockfile and the snapshots."*
- *"Narrow the list down to just what needs human eyes"* — Claude judges which
  files are mechanical/low-risk, hides them, and tells you what it hid and why.
- *"What's left to review?"*

Claude edits the same state file your checklist reads, then tells you the new
count. **Reopen `<leader>rc`** to see its changes — the float doesn't refresh
while it's open.

---

## Where the state lives

`<git-dir>/nvim-review-checklist.json` (i.e. inside `.git/`), per repo. It holds
two sets — `reviewed` and `hidden` — keyed by file path.

Because it's inside `.git/`, it never shows in `git status`, is never committed,
and needs no `.gitignore`. Nothing to clean up.
