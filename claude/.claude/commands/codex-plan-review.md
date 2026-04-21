# /codex-plan-review

Send a plan file to Codex for gap analysis. Codex inspects the plan for missing edge cases, unstated assumptions, error-handling holes, data-migration concerns, testing blind spots, security implications, performance risks, and anything else that would trip up the implementer.

Findings are appended to the plan file under `## Codex gap analysis` so they persist alongside the plan.

## Arguments

`$ARGUMENTS` — optional path to the plan file.

- If omitted and `~/.claude/plans/` exists, use the most recently modified `*.md` in that directory.
- Otherwise, look for the most recently modified `*.plan.md` in the current working directory.
- If multiple candidates and ambiguous, ask the user which plan to audit before calling Codex.

## Process

1. **Locate the plan file.** Resolve `$ARGUMENTS` to an absolute path. If the file doesn't exist, stop and tell the user.

2. **Read the plan.** Load the full contents.

3. **Invoke Codex via MCP** (`mcp__codex__codex`) with:
   - `cwd`: current project root (so Codex can cross-reference against the actual codebase if the plan cites files)
   - `sandbox`: `"read-only"`
   - `approval-policy`: `"never"`
   - `prompt`: template below, substituting the plan contents:

     > Audit the following implementation plan for gaps. Specifically, look for:
     >
     > - Missing edge cases or failure modes
     > - Unstated assumptions that could break under different conditions
     > - Error-handling holes (what happens when X fails?)
     > - Data-migration concerns (backward compatibility, partial states)
     > - Testing blind spots (what's not covered?)
     > - Security implications (auth, input validation, trust boundaries)
     > - Performance risks (N+1 queries, unbounded loops, payload size)
     > - Architectural fragility (tight coupling, hidden dependencies)
     > - Anything that would trip up the implementer or cause a production incident
     >
     > Do NOT rewrite the plan. Do NOT suggest alternative implementations. Just identify the gaps, one per bullet, each tied to a specific section or step of the plan. If the plan is solid and you find no meaningful gaps, say so briefly.
     >
     > Plan:
     >
     > <full plan content>

4. **Append Codex's response to the plan file.** Add a new section at the end:

   ```markdown

   ---

   ## Codex gap analysis

   <Codex's response, verbatim>
   ```

   Use Edit to append (preserves whatever's already in the file). Do NOT resolve the gaps automatically — the user decides which to act on.

5. **Report back.** Tell the user the gap analysis was appended and summarize in one sentence what Codex flagged (e.g., "Codex raised 4 concerns, mostly around error handling in step 3 and a missing migration path.").

## Notes

- Raw dump is intentional. Codex's findings go in verbatim so the user sees them exactly as produced.
- This command always invokes Codex. Invoke it explicitly — nothing auto-chains to it anymore. For a full Claude ↔ Codex consensus loop, use `/debate-plan` instead.
- If Codex is not registered, the MCP tool call will fail. Run `claude mcp add -s user codex codex mcp-server` or `./install.sh`.
