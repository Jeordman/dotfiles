# /debate-plan

Run a consensus planning loop between Claude (Opus) and Codex. Both agents produce initial plans in parallel for the same prompt, then debate back-and-forth under a Team Lead (main Claude) until they converge or hit a 3-round cap. The Team Lead writes a single **combined plan** reflecting the agreed approach.

Runs inside Claude Code's native plan mode — the final combined plan is what the user reviews before approval.

## Arguments

`$ARGUMENTS` — the feature description or prompt to plan. Required.

If omitted, ask the user: "What should Claude and Codex plan together?"

---

## Phase 0: Pre-flight usage warning

**Before spending tokens, check recent usage and warn the user if either agent is above 60% of its current window.** This is a warning, not a gate — the user can Ctrl+C to abort during the brief pause, otherwise execution continues.

Claude usage comes from `~/.claude/usage-cache.json`, which `statusline-command.sh` writes on every render using the ground-truth `rate_limits` JSON that Claude Code passes in. Codex has no public usage endpoint, so Codex usage is a rough best-effort estimate from `~/.codex/history.jsonl`.

1. Run the pre-flight script:

   ```bash
   bash ~/.claude/scripts/debate-plan-preflight.sh
   ```

   This script (source at `claude/.claude/scripts/debate-plan-preflight.sh` in the dotfiles repo) reads `~/.claude/usage-cache.json` for Claude's 5hr/7d percentages and scans the 5 most recent `~/.codex/sessions/**/rollout-*.jsonl` files for Codex's `rate_limits.primary/secondary.used_percent`. If any metric is >=60%, it prints a WARNING and sleeps 5s so the user can Ctrl+C. Otherwise it returns immediately. Allowlisted in `settings.json` so it runs without a permission prompt.

2. If the cache is missing or older than 10 minutes, Claude values stay `unknown`. If no Codex session rollout files exist, Codex values stay `unknown`. Do NOT abort on `unknown` — pre-flight is best-effort.

3. Announce to the user: "Running /debate-plan — will make up to 4 Codex calls over 2–4 minutes."

### Why these sources

**Claude.** Claude Code pipes a JSON blob to the statusline command on every render. That blob has `rate_limits.five_hour.used_percentage` and `rate_limits.seven_day.used_percentage` — the same numbers shown in the statusline. `statusline-command.sh` caches them to `~/.claude/usage-cache.json`.

**Codex.** Codex writes a `rate_limits` snapshot (from the API response headers) into every `event_msg` payload inside its session rollout files at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Fields: `payload.rate_limits.primary.used_percent` (5hr) and `payload.rate_limits.secondary.used_percent` (7d). These match the values Codex's own TUI shows for "Xh limit / Weekly limit." The pre-flight scans the 5 most recent rollout files and picks the newest entry.

If pre-flight ever reports impossible percentages, inspect the cache file and the most recent rollout file directly.

---

## Phase 1: Parallel initial plans

Kick off Claude's plan and Codex's plan **in parallel** — a single assistant turn with both operations in flight.

**Claude's plan (in-session):**
- Launch up to 3 Explore subagents if scope is broad.
- Draft a full plan following the structure from `plan-feature.md` (Context, Assumptions, Files, Architecture, Implementation Steps, Testing).
- Hold in memory — do not write to disk yet.

**Codex's plan (via MCP):**

Before calling, announce to the user: `Calling Codex for initial plan (may take 30-90s)...` — this way if the call hangs or errors, the user knows exactly where you are.

Call `mcp__codex__codex` with:
- `cwd`: current project root
- `sandbox`: `"read-only"`
- `approval-policy`: `"never"`
- `prompt`:

  > Produce an implementation plan for this feature: `<$ARGUMENTS>`
  >
  > Cover: context, files to create, files to modify (with paths), component/system architecture, state/data model changes, API changes if any, testing strategy, and concrete step-by-step implementation.
  >
  > Be specific — cite real file paths and function names from the repo. Under ~400 lines.

- **Keep only the feature description in the prompt** — do NOT paste Claude's Explore agent output into this prompt. Codex should plan from a clean slate and cross-reference the repo via its own `cwd`. Larger prompts increase failure rate.

- **Keep the returned `threadId`** — required for Phase 2 follow-ups.

### Error handling (CRITICAL)

Codex MCP calls occasionally fail with errors like `[Tool result missing due to internal error]`, timeouts, or empty responses. Handle these explicitly — do NOT let the user stare at a silent "Calling codex…" spinner wondering if it's stuck.

1. **Detect failure.** After the `mcp__codex__codex` call returns, check: is `content` empty, is it an error string, or did the tool error out? If yes → failure path.

2. **Retry ONCE.** Announce: `Codex call failed ("<short error>"). Retrying once with a smaller prompt...`. Re-call `mcp__codex__codex` with a trimmed prompt (drop the "under ~400 lines" qualifier, simplify to: "Produce a concise implementation plan for: `<$ARGUMENTS>`. Files to create/modify, architecture, steps.").

3. **Fall back if retry also fails.** Announce: `Codex unavailable after retry. Falling back to Claude-only plan.` Skip Phase 2 entirely. Emit Claude's Phase 1 plan as the final plan. Under `## Codex gap analysis` write: `Skipped — Codex MCP call failed twice. Run /codex-plan-review manually once Codex is back up.` Proceed to Phase 4 (ExitPlanMode).

4. **Never hang silently.** If you've been waiting on a tool result for more than ~2 minutes and nothing is coming back, assume failure and follow step 3.

---

## Phase 2: Debate rounds (max 3)

Team Lead (main Claude) coordinates. Each round = one message from each side.

### Round structure

1. **Codex critiques Claude's plan.** Call `mcp__codex__codex-reply` on the thread from Phase 1 with:

   > Here is Claude's plan for the same feature. Audit and critique it. List specific disagreements, gaps, or recommended changes, tied to specific steps. Focus on: missing edge cases, error-handling holes, security/data-integrity concerns, architectural fragility, testing blind spots. Ignore stylistic nits and do not rewrite the plan.
   >
   > Claude's plan:
   >
   > <paste Claude's plan verbatim>

2. **Claude audits Codex's plan and Codex's critique.** Main Claude reviews both artifacts and produces its own audit inline: which of Codex's points are load-bearing, which are wrong and why, what Claude's plan already covered that Codex missed, and what pushback Claude has on Codex's own approach. Write this as a structured list, one point per bullet.

3. **Convergence check.** Team Lead compares both positions:
   - If remaining disagreements are resolved by one side conceding or narrowed to a single tie-breakable decision → stop (go to Phase 3).
   - Otherwise → feed Claude's pushback back to Codex via another `codex-reply`:

     > Claude pushed back on these points: <list>. For each, concede or defend with a sharper reason. Keep it tight — one paragraph per point. If you agree, say so explicitly.

4. **Loop** to step 1 for the next round, using the fresh Codex reply as the starting critique.

### Error handling in Phase 2

Same pattern as Phase 1. Before each `codex-reply` call, announce: `Codex round N critique (may take 30-90s)...`. After the call:

- If it fails or returns empty → retry ONCE with a shorter prompt (drop "Focus on…" list, keep just the core ask).
- If retry also fails → stop the debate immediately. Write the combined plan using whatever debate rounds succeeded so far. Note in "Points of divergence": `Debate terminated early at round N — Codex MCP error, final reply unavailable.`
- Never hang silently. ~2 min without response = assume failure.

### Hard cap

**3 rounds maximum.** If no consensus after Round 3:
- Team Lead declares the tie-break.
- Picks the approach with stronger reasoning.
- Records the unresolved concern under "Points of divergence" in the combined plan.

---

## Phase 3: Write the combined plan

**The plan file MUST be written inside the current working directory (`$PWD`) where the user ran `/debate-plan`.** Never anywhere else. The user chose `cwd` deliberately — that's where they want the artifact.

### Resolving the output path (in order)

1. **Determine `cwd`.** Run `pwd` and use that exact value as the root. Do NOT substitute `~`, `$HOME`, `~/.claude`, or any global directory.
2. **Pick the plans directory under `cwd`:**
   - If `{cwd}/docs/plans/` exists → use it.
   - Else if `{cwd}/plans/` exists → use it.
   - Else if `{cwd}/specs/` exists → use it.
   - Else if `{cwd}/.claude/plans/` exists → use it (repo-local, not `~/.claude/plans/`).
   - Else → create `{cwd}/docs/plans/` (mkdir -p) and use it.
3. **Write to `{that_dir}/{feature_name}.md`.** `feature_name` = short kebab-case from the prompt.

### Hard bans

- ❌ **Never** write to `~/.claude/plans/`, `$HOME/.claude/plans/`, `/Users/*/.claude/plans/`, or any path outside `cwd`. That directory is a global dumping ground, invisible to teammates, and not what the user wants.
- ❌ **Never** write to `/tmp`, `/var/folders`, or any path outside the repo.
- ✅ If `cwd` is itself `~/.claude` or a subdirectory of it (e.g. user is editing the dotfiles repo), that's fine — the rule is "inside `cwd`," not "outside `~/.claude`."

### Self-check before writing

Before calling the Write tool, print one line to the user: `Writing plan to: <absolute path>`. The path MUST start with the `pwd` output. If it does not, stop and re-resolve — something went wrong.

Structure:

```markdown
# {feature_name}

## Context
Brief summary of the feature, the motivation, and constraints.

## Combined plan
The authoritative implementation plan — the consensus view.
Include: files to create, files to modify, architecture, step-by-step implementation, testing strategy.

## Debate log
### Round 1
- Codex said: ...
- Claude responded: ...

### Round 2
...

## Points of divergence
Any unresolved disagreements + Team Lead's tie-break rationale.
Omit this section if both sides fully agreed.

## Codex gap analysis
Codex's final list of concerns that made it into the combined plan,
plus any Team Lead deliberately set aside with reasoning.
```

The `## Codex gap analysis` section is part of the combined plan's value — it preserves Codex's flagged concerns verbatim alongside the agreed plan.

---

## Phase 4: Present the plan and wait for explicit approval

**Do NOT call `ExitPlanMode` automatically.** Auto mode's classifier will silently approve it and the user loses the chance to review the debate output — defeating the whole point of this command.

Instead:

1. **Print a summary block inline** so the user can read the key decisions without opening the file. Include:
   - Path to the full plan file (`{cwd}/docs/plans/{feature_name}.md`, or whichever in-repo plans dir was used).
   - Debate stats: rounds run, consensus status (full / partial / tie-broken).
   - 3-6 bullets of the key decisions from the debate (the concrete "we chose X over Y because Z" calls).
   - If there are points of divergence, list them explicitly.

2. **Use `AskUserQuestion`** with these options to force an explicit checkpoint:
   - `Accept plan` — proceed to `ExitPlanMode` and **begin implementing immediately**.
   - `Request changes` — user will describe what to revise; DO NOT exit plan mode, route through Phase 5 below instead.
   - `Abort` — discard the plan; stay in plan mode and await further instructions.

3. **On `Accept plan`:**
   - **If the session was already in plan mode** when `/debate-plan` was invoked (system reminder indicated `Plan mode is active`): call `ExitPlanMode`, then start implementing.
   - **If the session was NOT in plan mode**: skip `ExitPlanMode` entirely — calling it forces the harness to enter plan mode just to exit it, producing a visible "Entered plan mode / Exited plan mode" flash. Just start implementing directly.
   - **Either way, start implementing immediately after Accept.** Do NOT add a second pause ("Ready when you say go", "Tell me to proceed", etc.). The user already approved — a second confirmation wastes a turn and duplicates a checkpoint they already cleared.
   - If Auto mode is on, execute per normal Auto-mode semantics from here on. If plain plan mode, just start editing.

This mirrors normal plan-mode UX (user sees the plan, clicks approve/reject) but works uniformly across Auto / interactive / plan modes — the `AskUserQuestion` tool surfaces a visible dialog that Auto mode cannot silently bypass, and Accept then hands off cleanly to whatever execution mode is active.

---

## Phase 5: Revision routing (when user picks `Request changes`)

The user describes what they want changed. **Classify the change significance** and pick the cheapest mode that handles it correctly. Announce the chosen mode before acting so the user can course-correct.

### Classification rules

Read the user's change request and classify as one of:

- **Trivial / scoping tweak** — wording fixes, reordering steps, changing one parameter value, renaming a variable, clarifying a section, dropping/adding a small step that doesn't alter architecture. **Mode: Claude-only edit.** Zero Codex calls.
- **Meaningful but local** — adding a concrete new requirement (e.g. "add rate limiting", "handle null tenant IDs"), changing a data shape, swapping one library for another, adjusting a testing approach. Touches 1-2 sections but keeps the overall architecture. **Mode: 1-round mini-debate.** 1 Codex call.
- **Fundamentally different** — rethinking architecture (e.g. "use server components instead of client", "cookie-based instead of localStorage", "server-side rendering vs SPA"), scoping that doubles file count, changing a security/auth model, reversing a core decision the debate agreed on. **Mode: Full re-debate.** Fresh Phase 1 + up to 3 rounds.

### Decision heuristic (in priority order)

1. Does the change **contradict a point the debate explicitly agreed on**? → Full re-debate. (The agreement was reached with reasoning; overturning it deserves the same rigor.)
2. Does it **introduce a new concern Codex never saw** (new security surface, new migration, new external dependency, new data boundary)? → Full re-debate OR 1-round mini-debate depending on surface area. Default to full if in doubt.
3. Does it add/remove **≥3 files** or **≥200 lines of plan content**? → Full re-debate.
4. Does it change behavior in **1-2 sections** without reshaping the approach? → 1-round mini-debate.
5. Is it purely **editorial** (wording, ordering, small numeric tweaks)? → Claude-only edit.

### Execution per mode

**Claude-only edit:**
1. Announce: `Classified as trivial/scoping. Editing plan directly (no Codex).`
2. Edit the plan file inline. Touch only the sections the user asked about.
3. Return to Phase 4 (re-present summary + approval question).

**1-round mini-debate:**
1. Announce: `Classified as meaningful-but-local. Running one Codex critique pass (~30-60s).`
2. Claude edits the plan file with the requested change.
3. Call `mcp__codex__codex-reply` on the Phase 1 thread (if still alive) — fall back to fresh `mcp__codex__codex` if the thread is gone:

   > The plan was revised with this change: `<user's change description>`. Audit ONLY the revised sections for new gaps, broken assumptions, or downstream impact on other sections. One paragraph per concern. If the change is clean, say so.

4. Apply the same retry-once + fallback error handling as Phase 2.
5. If Codex surfaces load-bearing concerns → Claude edits the plan again to address them; update `## Debate log` with a new "Round N (revision)" entry.
6. Return to Phase 4.

**Full re-debate:**
1. Announce: `Classified as fundamentally different. Running a fresh debate (~2-4 min, up to 4 Codex calls). Ctrl+C to downgrade to 1-round.`
2. Rewrite the feature prompt to include the user's change (so both Claude and Codex start from the new constraint).
3. Re-run Phase 1 (parallel plans) + Phase 2 (up to 3 rounds) + Phase 3 (new combined plan overwrites the file, but `## Debate log` appends a new top-level "# Revision N" section so earlier debate history is preserved).
4. Return to Phase 4.

### User-override escape hatch

If the user's change request already tells you how to handle it (e.g. "just change X, no Codex" or "do a full debate on this"), honor that directly and skip classification. Classification is for when the user only describes **what** to change, not **how** to re-plan.

---

## Abort path (user interrupt during debate)

If the user says "just use Claude's plan," "skip codex," "abort," or similar mid-flow:
- Stop debate immediately.
- Emit Claude's Phase 1 plan alone as the final plan file (without the Combined / Debate / Gap-analysis sections).
- Still go through Phase 4's AskUserQuestion checkpoint — don't skip straight to `ExitPlanMode`. User still wants to see what they're accepting.

---

## Notes

- Codex prompt templates here intentionally duplicate the ones in `codex-plan-review.md` and `codex-review.md` — keeping them local to this command means the command file is self-contained and removing the old `codex-orchestrate` skill doesn't break anything.
- If Codex MCP is not registered, the first `mcp__codex__codex` call fails. Run `claude mcp add -s user codex codex mcp-server` or `./install.sh` and retry.
- Never chain more than 3 Codex rounds regardless of model disagreement. The cost-benefit curve flattens fast.
