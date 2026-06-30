---
name: review-checklist
description: Update the user's nvim diffview review checklist from within a conversation — tick files off as reviewed, or hide files that aren't worth their time. Use this skill WHENEVER the user, while you're walking them through a code change, wants to shrink what they personally review — e.g. "mark those as reviewed", "check off the files you just explained", "I don't need to review the SubManager components", "mark everything reviewed except the migration", "uncheck X", "hide the lockfile and snapshots", "remove the generated files from my list", or "narrow the list down to just what needs human eyes" (where YOU decide which files are mechanical/low-risk and hide them). Also "what's left to review?". The user reviews multi-file changes in nvim (<leader>rc opens a checklist); this skill lets you update its state directly. Trigger even when the user doesn't say "checklist" by name — the intent is "take these files off my plate" or "trim this down to what matters." Only ever shrink the list when the user asks you to.
---

# Review checklist — shrink what the user has to review

The user reviews changes in nvim with a diffview-based checklist (`<leader>rc`). Its
state is a JSON file in the repo's git dir that nvim and this skill share. You can do
two things to it, both only when asked:

- **Tick a file reviewed** (`--check`) — it stays in the list, marked done. Use when the
  user is satisfied they don't need to read that file's diff themselves.
- **Hide a file** (`--hide`) — it's removed from the list entirely. Use for files that
  aren't worth human eyes at all (noise, generated, mechanical). nvim still shows a
  "N hidden" count and the user can reveal them, so nothing disappears silently.

## The one tool you need

Run the bundled script with `python3`. It lives next to this file:

```
python3 <skill-dir>/scripts/mark_reviewed.py <action>
```

Resolve `<skill-dir>` to wherever this SKILL.md is. **Run it from inside the user's repo**
(the repo whose changes are under review) so it finds the right git state — `cd` there
first if your working directory is elsewhere.

### Actions

| You want to… | Command |
|---|---|
| See the current checklist | `mark_reviewed.py --list` (`--json` for full data incl. hidden) |
| Mark specific files reviewed | `mark_reviewed.py --check NAME [NAME...]` |
| Mark all reviewed *except* some | `mark_reviewed.py --check-all-except NAME [NAME...]` |
| Unmark files | `mark_reviewed.py --uncheck NAME [NAME...]` |
| Hide files from the list | `mark_reviewed.py --hide NAME [NAME...]` |
| Hide a whole **category** at once | `mark_reviewed.py --hide '<glob>'` — e.g. `'src/lib/i18n/messages/*.json'` |
| Bring hidden files back | `mark_reviewed.py --unhide NAME [NAME...]` · `--unhide-all` |
| Wipe reviewed marks (keeps hides) | `mark_reviewed.py --clear` |
| Review committed work vs a branch | add `--base origin/main` to any of the above |

**Reviewed vs hidden — pick the right one:** `--check` keeps a file visible but ticked
("the user glanced/trusts it's fine"). `--hide` removes it from the list ("not worth a
human looking at all"). When the user says "I don't need to review X," default to
`--check` unless they clearly mean it's noise to remove ("hide", "remove", "get rid of",
"don't show me", "narrow down"), in which case `--hide`.

`NAME` is loose — a basename (`SubManagerProductLine.tsx`), a path suffix
(`_components/SubManagerProductLine.tsx`), or a unique substring all work. A plain name
resolves to exactly one changed file; if it's ambiguous or matches nothing, the script
stops and prints the candidates so you can retry with a more specific name.

A name that contains a glob metacharacter (`*` `?` `[`) is matched as a **glob** and may
match many files at once — this is the one right way to hide a whole category. The glob
matches the full path, a path suffix (`'messages/*.json'` catches `a/b/messages/x.json`),
or the basename. **Single-quote it** so the shell passes it through verbatim.

## Hiding many files: ONE glob, never a long argument list

When the noise is a whole category (all translation JSONs, every snapshot, a generated
directory), hide it with a **single quoted glob in a single call**:

```
python3 <skill-dir>/scripts/mark_reviewed.py --hide 'apps/shop/src/lib/i18n/messages/*.json'
```

Do **not**:
- build a command line with dozens/hundreds of individual path arguments,
- pipe paths through `xargs` (it backgrounds/splits unpredictably), or
- stuff paths into a shell variable (zsh — the user's shell — does **not** word-split
  unquoted variables, so all paths arrive as one giant argument and the call fails).

All three of those are how this turns into a ten-minute fight. One glob = one fast call.
If a call doesn't do what you expect, **read the script's error or open the script** — it
prints exactly what matched and why. Do not retry blind with a new shell trick.

## How to use it well

1. **Default to the working tree.** The common case is reviewing the uncommitted pile
   before a commit — that's the default (no `--base`). Only pass `--base origin/main`
   (or `origin/staging`) when the user is reviewing already-committed branch work.

2. **Map the user's words to real files yourself.** If you just explained
   `SubManagerProductLine.tsx` and `SubManagerDeliveryHero.tsx` and the user says "yeah,
   check those off," call `--check SubManagerProductLine SubManagerDeliveryHero`. Prefer
   the names of files you actually discussed; don't guess at files you haven't seen.

3. **Always confirm what changed.** The script prints which canonical paths it matched
   and the new `done/total` count. Relay that back briefly — e.g. "Marked 2 reviewed,
   checklist now 5/12" — so the user can catch a wrong match immediately.

4. **Marks auto-expire — that's intended.** A mark is tied to the file's current
   content. If the user (or you) edits that file again afterward, nvim will show it
   unreviewed again because there are new changes to look at. You don't manage this; the
   fingerprint does. Don't try to "re-affirm" a file unless the user asks.

5. **Don't touch files the user wants to read.** This skill is for taking files *off*
   the user's plate, never for hiding things from them. If unsure whether they wanted a
   file checked or hidden, ask rather than assume.

## "Narrow the list to what needs human eyes"

This is the high-value case: the user asks you to decide which files don't deserve their
attention and hide them, leaving only what genuinely warrants a human read.

Do it with judgment, not pattern-matching:

1. Run `--json` to get every changed file (with its status and flags).
2. For files where the *kind* of change is obviously low-risk, look only as much as you
   need to confirm; for anything touching real behavior, keep it visible.
3. Hide the low-value ones **by category with a glob, one call per category** (e.g.
   `--hide '**/__snapshots__/*' '*.snap'`), not by enumerating every file. Then tell the
   user what you hid and **why**, grouped (e.g. "Hid 9: lockfile, 4 snapshots, 3 generated
   API types, 1 pure import reorder"). The script prints a per-directory count for big
   globs, so confirm the count matches what you intended before relaying it.

Typically **safe to hide** (when that's all the change is): lockfiles
(`package-lock.json`, `yarn.lock`, `Cargo.lock`), generated/compiled output, snapshots
(`__snapshots__`, `*.snap`), vendored deps, pure formatting / import-reordering, and
mechanical renames with no logic change. **Translation / i18n message files**
(`src/lib/i18n/messages/*.json` and the like) are this user's most common noise — they're
machine-synced from an external translation system (Google Sheets), never reviewed as raw
JSON diffs — so hide the whole `messages/*.json` glob unless the diff changes *keys or
structure* rather than just translated string values.

**Keep visible** (needs human eyes): business logic, control flow, auth/permissions,
data handling and migrations, money/pricing math, public API or contract changes, config
that changes runtime behavior, and anything security-sensitive. **When unsure, leave it
visible** — wrongly hiding a real change is far costlier than leaving one extra file on
the list. Hiding is reversible (`--unhide`), but the user has to notice it was hidden.

Never hide on your own initiative — only when the user asks you to trim the list.

## Example

**Input:** (after you've explained the two SubManager components and the helper)
> "Nice, I don't need to look at those two components or the get-subscription helper. Check them off."

**Action:**
```
python3 <skill-dir>/scripts/mark_reviewed.py --check SubManagerProductLine SubManagerDeliveryHero get-subscription-line
```

**Then tell the user:** "Marked those 3 reviewed — your checklist is now 3/12. Open
`<leader>rc` in nvim to see the rest."

## If something looks off

- "No changed file matches 'X'": the file isn't in the current change set, or the user
  is in a different review base. Run `--list` (and try `--base origin/main`) to see what
  git actually reports, then reconcile with the user.
- "'X' is ambiguous": two changed files share that name — rerun with a path suffix.
- Nothing shows up in nvim afterward: the user needs to reopen `<leader>rc` (the float
  reads state fresh each time; it doesn't live-refresh while open).
