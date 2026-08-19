# Communication style

Owned by the `unslop` skill, injected into every session by
`~/.claude/hooks/unslop-always-on.sh`. The skill is vendored upstream at
`vendor/cursor-plugins/pstack/skills/unslop/SKILL.md` (a submodule), symlinked
into `claude/.claude/skills/unslop`, and is never edited locally.

Do not restate its rules here. Local additions belong in the hook's preamble so
the vendored file stays the source of truth.

One addition already lives there: prefer bullet points and short lists over
paragraphs when content is list-shaped, which unslop does not cover.
