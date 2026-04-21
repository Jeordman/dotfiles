# /codex-review

Run a Codex code review against the current repository's diff. Dumps Codex's output verbatim, then adds Claude's own notes.

## Arguments

`$ARGUMENTS` — optional base branch to compare against. Defaults to `main`.

Examples:
- `/codex-review` → review uncommitted + branch changes vs `main`
- `/codex-review master` → base is `master`
- `/codex-review HEAD~1` → review the last commit

## Process

1. **Determine scope.** Inspect the working tree:
   - If there are uncommitted changes (staged or unstaged), Codex reviews those against the base.
   - If the working tree is clean but the current branch has commits past the base, Codex reviews the branch diff.
   - If both, Codex reviews the full delta against the base (unpushed commits + uncommitted changes).

2. **Invoke Codex via MCP** (`mcp__codex__codex`) with:
   - `cwd`: current project root
   - `sandbox`: `"read-only"`
   - `approval-policy`: `"never"`
   - `prompt`: a focused review instruction. Template:

     > Review the changes in this repository compared to `<base>`. Include both the branch commits (if any) and uncommitted changes (staged + unstaged). Report findings grouped by severity (critical / warning / suggestion). For each finding, cite `file:line`. Focus on: correctness bugs, edge cases, security issues, race conditions, error handling, and anything that would fail in production. Skip style nits unless they obscure intent. If the diff is clean, say so briefly.

   Substitute `<base>` with `$ARGUMENTS` or `main` if no argument.

3. **Present the response**:

   ```markdown
   ## Codex review

   <Codex's response, verbatim>

   ## Claude notes

   <Claude's own take: agreements, disagreements, anything Codex missed.
    Disagreements are the most useful output — be explicit about them.>
   ```

4. **Do not fix anything automatically.** This command produces review findings; the user decides which to act on.

## Notes

- This command always invokes Codex. For a Claude-only review, use the built-in `/review` skill instead.
- If Codex is not registered, the MCP tool call will fail. Run `claude mcp add -s user codex codex mcp-server` to register, or run `./install.sh` which does this automatically.
- The raw dump is intentional. Two different model families give two different perspectives; merging them into one voice destroys signal.
