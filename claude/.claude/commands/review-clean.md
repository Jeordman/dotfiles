# /review-clean

Trim the nvim review checklist down to what actually needs human eyes: scan every changed file, **hide** the mechanical/low-risk noise, and report what was pulled and why. Leaves everything that touches real behavior visible.

This is the automated form of the review-checklist skill's "narrow the list to what needs human eyes" case. Hiding is reversible (`--unhide`), and nvim still shows a "N hidden" count — nothing disappears silently.

## Arguments

`$ARGUMENTS` — optional review base. Defaults to the **working tree** (uncommitted pile).

Examples:
- `/review-clean` → clean the uncommitted working-tree change set
- `/review-clean origin/main` → clean a committed branch reviewed vs `origin/main`
- `/review-clean origin/staging` → base is `origin/staging`

## Process

Let `SCRIPT=~/.claude/skills/review-checklist/scripts/mark_reviewed.py` and `BASE` = `$ARGUMENTS` (omit `--base` entirely when no argument). Run everything **from inside the user's repo** so git state resolves correctly.

1. **Read the full change set.** Run:
   ```
   python3 $SCRIPT --json [--base BASE]
   ```
   The `files` array lists every changed file with its `status`, `reviewed`, and `hidden` flags. Skip files already hidden.

2. **Classify each file with judgment, not pattern-matching.** For files whose *kind* of change is obviously low-risk, look only as much as you need to confirm (a quick diff peek when unsure). For anything touching real behavior, leave it visible.

   **Safe to hide** (only when that's all the change is):
   - Lockfiles — `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`, `go.sum`
   - **Translation / i18n message files** — `src/lib/i18n/messages/*.json` and the like. Machine-synced from an external translation system (Google Sheets), never reviewed as raw JSON diffs. This is the most common bulk-noise category for this repo. Hide the whole glob unless the diff changes *keys or structure*, not just translated values.
   - Generated / compiled output, vendored deps, `dist/`, build artifacts
   - Snapshots — `__snapshots__/`, `*.snap`
   - Pure formatting / whitespace / import reordering with no logic change
   - Mechanical renames with no behavior change
   - Editor lockfiles like `lazy-lock.json`

   **Keep visible** (needs human eyes): business logic, control flow, auth/permissions, data handling and migrations, money/pricing math, public API or contract changes, config that changes runtime behavior, tests asserting real behavior, and anything security-sensitive.

   **When unsure, leave it visible.** Wrongly hiding a real change is far costlier than leaving one extra file on the list.

3. **Hide the noise by category — one quoted glob per category, never a long list of names:**
   ```
   python3 $SCRIPT --hide 'src/lib/i18n/messages/*.json' '**/__snapshots__/*' [--base BASE]
   ```
   A name with a glob metacharacter (`*` `?` `[`) matches many files at once; a plain name resolves to exactly one. **Single-quote globs** so the shell passes them through. The script prints a per-directory count for big globs — confirm it matches your intent.

   **Do not** enumerate hundreds of individual paths, pipe through `xargs`, or stuff paths into a shell variable. The user's shell is **zsh**, which does not word-split unquoted variables, so a list-in-a-variable collapses into one giant argument and the call fails — this is exactly what turns a 5-second task into a 10-minute fight. One glob per category is one fast, reliable call. If a call misbehaves, **read its error** (it names what matched) instead of retrying with another shell trick.

4. **Report grouped, with reasons.** Tell the user what you hid and why, grouped by category, plus the resulting count — e.g.:

   > Hid 9, list now 6 to review: lockfile (1), snapshots (4), generated API types (3), pure import reorder (1). Open `<leader>rc` in nvim to see the rest; `--unhide` anything I shouldn't have pulled.

   If nothing qualified as noise, say so and leave the list untouched.

## Notes

- **Only ever hides — never checks off and never deletes.** Reviewed marks are the user's to make; this command just removes noise from view.
- **When in doubt, keep it.** This command is conservative by design. It's better to leave a borderline file visible than to hide a real change the user needed to see.
- nvim reads checklist state fresh each time `<leader>rc` opens; it doesn't live-refresh while open, so the user may need to reopen it.
- For the inverse (ticking files off as *reviewed* after you walk through them), just ask in conversation — the review-checklist skill handles that.
