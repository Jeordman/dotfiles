---
name: obsidian-vaults
description: Locates and operates on the user's personal Obsidian markdown notes stored in iCloud. Use this skill ANY time the user references their notes, vaults, daily/weekly notes, todos, meeting notes, or any markdown file that isn't part of the current code project — even casually ("my notes on X", "what did I write about Y", "add this to my todo", "find that climbing log", "the unicity weekly template"). Also trigger on direct mentions of Obsidian, "the vault", a specific vault name (jeordin-vault, unicity-vault), or filenames like `todo.md`, `Calendar sync.md`, `Weekly Template.md`. Prefer to invoke this skill rather than ask "where are your notes?" — the paths are known. Note: `younique-vault` is legacy/read-only — never write to it and don't route ambiguous notes there; only read it when the user explicitly mentions Younique.
---

# Obsidian Vaults

The user keeps three Obsidian vaults in iCloud. They live under:

```
/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/
```

Each vault is one subdirectory there. **Always use the full absolute path** (with the spaces in `Mobile Documents`) — quote it in shell commands.

## The vaults

| Vault | Absolute path | What lives there |
|---|---|---|
| `jeordin-vault` | `/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/jeordin-vault` | Personal life: climbing (`Climbing/`, `ClimbHarder/`, `topout/`), cooking (`Cooking/`), books (`books/`), coaching (`Coaching/`), personal dev (`Personal/`, `Personal Dev/`), top-level `todo.md`, `Calendar sync.md`. |
| `unicity-vault` | `/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/unicity-vault` | Unicity work: `docs/`, `people/`, `tasks/`, `subagents/`, `Unicon/`, `Weekly Template.md`, `Shopify Tour.md`. |
| `younique-vault` | `/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/younique-vault` | **Legacy / read-only.** Younique-era work: `APP/`, `Meetings/`, `people/`, `Subs/`, `Task/`, `LEGACY/`. |

`unicity-vault` is the user's current work vault. `younique-vault` is from a previous role and is **archived** — read it only when the user explicitly says "younique", and **never write to it**. The two work vaults are separate worlds; never mix notes between them.

## Routing: which vault?

Pick the vault from context before searching. The user usually drops at least one cue:

- **Explicit vault name** (`unicity`, `younique`, `jeordin`, "my personal vault") → use that vault.
- **Topic cue** → personal topics (climbing, cooking, books, todo, coaching, personal dev) go to `jeordin-vault`. Work topics tied to Unicity (Unicon, Shopify Tour, anything with "Unicity"/"unicon" framing) go to `unicity-vault`. Younique-tagged work (APP, Subs, anything with "Younique" framing) goes to `younique-vault`.
- **Filename cue** — match against the vault contents:
  - `todo.md`, `Calendar sync.md`, `final day.md` → `jeordin-vault`
  - `Weekly Template.md`, `Shopify Tour.md`, `anuppuccin icons and emoji.md` → `unicity-vault`
  - Files inside `APP/`, `Meetings/`, `Subs/`, `LEGACY/` → `younique-vault`
- **Genuinely ambiguous** (e.g., bare "find my notes on auth" with no work/personal cue) → search **all three** vaults and present matches grouped by vault. Don't ask the user to pick first; do the search and let the results disambiguate. Only ask if the search returns hits in multiple vaults that all look plausible.

When in doubt between the two work vaults, lean on the user's recent conversation — if they were just talking about a Unicity project, stay in `unicity-vault`.

## How to search and read

Always quote the path because of spaces in `Mobile Documents`.

**Search for a topic across one vault:**
```bash
grep -rli "auth" "/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/unicity-vault" --include="*.md"
```

**Find a file by name:**
```bash
find "/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/jeordin-vault" -iname "*todo*"
```

**Read a known file:** use the Read tool with the absolute path. Don't `cat` it.

**Search all three vaults at once** (for ambiguous queries):
```bash
grep -rli "QUERY" \
  "/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/jeordin-vault" \
  "/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/unicity-vault" \
  "/Users/jeordin.callister/Library/Mobile Documents/iCloud~md~obsidian/Documents/younique-vault" \
  --include="*.md"
```

## Editing notes

- Use the Edit or Write tools — Obsidian picks up filesystem changes automatically via iCloud sync.
- Preserve YAML frontmatter, `[[wikilinks]]`, `#tags`, and Obsidian-specific syntax (callouts `> [!note]`, embeds `![[file]]`, dataview blocks). These look like ordinary markdown but matter to Obsidian.
- For new notes, match the existing vault's style: peek at a neighboring file in the same folder for frontmatter conventions before writing.
- Don't rename or move files unless asked — Obsidian's link graph breaks silently.

## Things to avoid

- Don't touch the `.obsidian/` directory at the iCloud Documents root or inside any vault — that's Obsidian's config, not user content.
- Don't follow paths into `attachments/`, `Excalidraw/`, or `Images/` for text searches — those hold binaries and `.excalidraw` files. Stick to `--include="*.md"`.
- The `Pasted image *.png.md` files are Obsidian's metadata sidecars for pasted images; ignore unless explicitly asked.
- Never assume a file path; always confirm with `find`/`ls` before reading. iCloud occasionally renames or relocates files.
