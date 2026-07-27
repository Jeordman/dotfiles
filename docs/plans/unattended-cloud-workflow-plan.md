# Unattended Cloud Workflow — Implementation Plan

**Status:** implemented and cut down. Verify half validated end-to-end 2026-07-26; dispatch half deliberately minimal and still unproven. See "Simplification + end-to-end validation" below — it supersedes the phase plan.
**Owner:** Jeordin (personal workflow — deliberately NOT shared repo tooling)
**Target repo for the workflow:** `~/unicity/new-shop` (generalize later)

---

## Goal

Create a second worktree mode. `git gtr new …` keeps today's local behaviour. `gtrc ECOM-1234` hands the ticket to a cloud session that implements and pushes, lets Vercel build-check the branch, then drives Playwright **locally** against the preview URL to prove the feature works — fixing and round-tripping until verified, without asking me anything at all. (There is no plan-approval step; dispatch is fire-and-forget as of 2026-07-26.)

Everything lives in `~/dotfiles`. No teammate is forced into this workflow.

## Non-goals

- Not built on `claude -p`, the Agent SDK, or Claude-in-GitHub-Actions — that family is the metered tier (separate monthly credit, then API rates; currently paused, but a policy flip would re-price the whole workflow).
- CI's smoke suite is not the feature gate. It stays a thin regression backstop.
- No secrets in the cloud environment. The sandbox never builds, so it never needs them.
- No permanent loosening of my everyday permission policy.
- No new shared-repo conventions. One possible 10-line upstream hook fix is the only repo change on the table, and only if P0.1 proves it necessary.

---

## Simplification + end-to-end validation — 2026-07-26 (supersedes the phases below)

The plan was reviewed against "what does this complexity actually buy?" and cut. It was one feature welded out of two, and only one half earned its moving parts.

**Split into two things that do not know about each other:**

| Half | What it is | Status |
|---|---|---|
| **Dispatch** | `gtrc` → worktree → push → prove remote → `claude --cloud` with a ticket ID. No plan file, no ledger, no Verification Contract, no local research, **and no PR** — the cloud session only pushes commits. | Minimal, unverifiable by design |
| **Verify** | `deploy-watch` → `claude-unattended` → Playwright against the preview. Input is a *branch*, not a cloud session. | **Validated end-to-end** |

Why dispatch was cut rather than hardened: six probes produced zero observable side effects and a cloud session cannot be watched from a terminal, so a 200-line contract and a 20-line prompt are equally unenforced from here — the contract bought the appearance of control. It also spent local context briefing a session that can clone the repo and read ClickUp itself. Two guards were kept because they cost nothing and prevent silently building on the wrong code: refuse protected branches, and `git ls-remote` proof after push.

The verify half is deliberately reframed: it is not "cloud mode", it is a **branch verifier**. It works on a cloud session's branch, on your own, or on a coworker's PR.

### End-to-end results — live data, not fixtures

| Check | Result |
|---|---|
| `deploy-watch` vs. real GitHub commit statuses | **5/5** |
| ↳ `Vercel – shop2` success while *overall* commit state = failure | correctly READY — validates matching the exact context, not the rollup |
| ↳ `Vercel – shop-api` failure | correctly exit 2 |
| ↳ hyphen instead of en dash; bogus context | correctly exit 3 (timeout) — never a false pass |
| SHA → deployment resolution | `state: READY`, `meta.githubCommitSha` matched exactly |
| Preview reachable from local browser | yes — raw `*.vercel.app`, no Cloudflare wall |
| Root redirect | `/` → `/usa/en/products` (307 healthy), real content rendered |
| git guard | **46/46** (38 + 8 subshell) |
| stop gate | **8/8** — including "all PASS with no preview URL → block" |
| dispatch guards | protected-branch refusal, usage, dry run correct; regex anchored (`masterful`, `my-main` allowed) |
| stow symlinks | same inode — dotfiles edits are live in `~/.claude` |

**A cheaper resolution path was found while doing it:** the commit status's `target_url` already contains the deployment ID, so `get_deployment` can be called directly and `list_deployments` skipped. SHA-exact by construction. `teamId` accepts the slug `unicity`.

### Defect the E2E test found in this plan's own design

A clean preview of *untouched* code logs 2 console errors and 2 warnings — CookieYes interpolating `undefined` into its script URL (preview env var unset), and Vercel's own preview toolbar blocked by the app's CSP. Neither can occur in production; neither is fixable from a branch.

So `Pass: … no console errors`, which the contract template mandated, **would false-FAIL every run** — the worst outcome for an unattended loop, which would either burn three deploy cycles patching a non-bug or learn to ignore the console entirely and miss a real error later. Fixed: `preview-url-verification` now documents the baseline explicitly, and the criterion is "no console errors beyond the baseline". The claim that previews give you "real production env vars" was also falsified and corrected — you get production *code paths*, not production *config*.

### Second defect — the Stop gate had never been able to fire

`unattended-stop-gate.sh` reads the verification record's path from `.claude/state/unattended.json`'s `ledger` field. `claude-unattended` wrote that marker **without a `ledger` field**, so the gate hit `[ -z "$LEDGER" ]` and `exit 0` on every real run. The entire anti-false-pass protection was dead code — the same shape as the duplicate-`"hooks"`-key bug found in the shared repo, and equally invisible.

The 8/8 test suite passed because it authored markers by hand *with* the field. It tested the gate and never the wiring. Fixed at three layers:

1. `claude-unattended` now defaults `ledger` to `.claude/state/verification-<branch>.md` and prints the path at startup; `-L` opts out explicitly.
2. The gate now distinguishes **no `ledger` key** (deliberate opt-out → no-op, but *announced* in a `systemMessage`, so silent rot is impossible) from **a named ledger that does not exist** (→ block, telling the session to write the record and giving the row format). The old code conflated the two and no-op'd for both.
3. Two wiring assertions added to the suite: that `claude-unattended` writes the field, and that the disabled path announces itself. **57 tests now pass** (38 guard + 8 subshell + 11 gate).

**Then a third instance of the same bug, one layer further out:** the `Stop` hook was never registered. `settings.unattended.json` declared only `PreToolUse`, so even with the `ledger` field fixed the gate would still never be invoked. The gate's own header said "Wired from settings.unattended.json" and the profile's comment implied the same — both aspirational. Now registered with a 300 s timeout (it runs `pnpm formatAndLint`).

So the protection failed at three independent layers simultaneously — script not registered, marker field absent, missing-file case silently no-op'd — and every individual piece tested green.

Lesson worth keeping: unit-testing a hook against hand-built fixtures proves the logic and nothing about whether it is *reachable*. Test the wiring separately, assert that a disabled state is loud, and verify registration at the settings level rather than trusting a comment that says it is wired.

### Cloud-always fix loop — added 2026-07-26

Decision: when local verification finds a break, the fix is **always** dispatched to the cloud. The local session never edits source.

The split that makes it work: **local owns the diagnosis, cloud owns the typing.** The local session has the browser and the cloud cannot reach the preview, so a findings file must name the root cause and `file:line` — "cart total is wrong" forces a fresh session to re-derive blind, which is the one thing it cannot do.

```
cloud-fix-dispatch <findings>          # commits findings (-f, state/ is gitignored),
                                       #   pushes, re-reads baseline, dispatches
NEW=$(wait-for-push -s "$BASELINE") \  # blocks until origin/<branch> tip MOVES
  && deploy-watch -s "$NEW" \          # gates on the build for that exact SHA
  && re-verify                         # Playwright, locally, against the new URL
```

Cost accepted knowingly: ~8–12 min per round trip (cold clone + install + fix + ~3.2 min Vercel build) vs ~3.5 min fixing locally. The 3-round-trip cap therefore means a ~30 minute ceiling. Findings are batched per dispatch — trickling one per cycle is the most expensive available mistake.

**Enforced mechanically, not by prompt.** The Stop gate now blocks on any uncommitted change outside `.claude/state/`, so a local "quick fix" cannot reach the branch that gets deployed. This belongs in the gate because it is mechanically decidable, which is the gate's stated remit.

Two wiring holes closed at the same time: `Bash(cloud-fix-dispatch:*)`, `Bash(wait-for-push:*)` and `Bash(deploy-watch:*)` added to the profile's allow list, and all three added to `sandbox.excludedCommands` (bare **and** starred forms — they accept no-argument invocations). Seatbelt applies to the whole process tree, so a sandboxed wrapper would break the `gh`/`git`/`claude` children inside it. `claude.ai` was deliberately **not** added to `allowedDomains`: excluding one wrapper is narrower than opening a domain to every command.

**Bug found and fixed during testing:** `git ls-remote` always returns a full 40-char SHA, so comparing it against an abbreviated baseline with `!=` reported MOVED on the first poll. That would have returned the *pre-fix* SHA, sent `deploy-watch` at the already-built deployment, and re-verified **stale code** — reporting the same failure forever, or passing on the pre-fix build. Now compares by prefix in both directions, and refuses a baseline under 7 hex chars (a 1–2 char baseline would match any tip). 6/6 on retest.

### Executable bits — manual step

New scripts were created mode 644; every pre-existing script in `bin/bin/` is 755, and `~/bin` → `dotfiles/bin/bin` is on `PATH`, so they resolve but cannot run. `chmod` is denied to the agent by policy, so this is a one-time manual step:

```bash
chmod +x ~/dotfiles/bin/bin/{claude-unattended,cloud-ticket-dispatch,cloud-fix-dispatch,deploy-watch,dev-cloud,gtrc,wait-for-push}
```

The `.sh` hooks deliberately do **not** need this — both are invoked as `bash '<path>'` from the profile precisely so they never depend on an exec bit.

### Revised file verdicts

- **Keep:** `gtrc`, `gtr-postcreate` fork, `dev-cloud` (saves the port — user's call, 2026-07-26), `deploy-watch`, `claude-unattended`, `settings.unattended.json`, `unattended-git-guard.sh`, `unattended-stop-gate.sh`, `preview-url-verification`
- **Reduced to dispatch-only:** `cloud-ticket-dispatch` (takes a `<TICKET>`, not a plan file), `/cloud-ticket` (a 3-line wrapper)
- **Parked:** `repo-hook-proxy.sh`
- **Under reconsideration:** `unattended-execution` skill. Flagged for drop as a *cloud* artifact, but most of its content (never ask and idle, gates cheapest-first, never write your own verdict, never fake a pass, two clean endings) is exactly what the **local** unattended session needs. Left in place rather than deleted — retarget or drop deliberately.

### Still open

- Whether cloud sessions execute at all (D1). Unchanged, and now **decoupled** — the verify half does not depend on it.
- P1 cloud environment for `new-shop`, and whether `pnpm install --frozen-lockfile` fits the ~5-minute setup budget.
- One real ticket end-to-end (P2).

---

## Validation results — 2026-07-25

Everything below was executed, not reasoned about. Three artifacts are built and passing; one gate is still open.

### Verified working

| # | Finding |
|---|---|
| 1 | **Launch incantation:** `claude --setting-sources local --settings ~/dotfiles/claude/.claude/settings.unattended.json`. Under it `git commit` runs; under normal settings the same command is `DENIED`. |
| 2 | `--setting-sources` accepts only `user\|project\|local`. **There is no `managed`** — the earlier plan was wrong. |
| 3 | **A `deny` in a lower scope beats an `allow` in a higher one.** Under `--setting-sources user`, the global `git commit` deny still refused, even with the profile supplying an allow. This is why `local` is the only usable base: the repo's `settings.local.json` has an empty deny array and defines no hooks. |
| 4 | `unattended-git-guard.sh`: **46/46** — 38 direct cases plus 8 subshell-bypass cases. Verified live in the real launch config: `git push origin master` refused with the guard's own message. |
| 5 | **SSH git cannot work inside the sandbox** — a sandboxed push fails with `nc: authentication method negotiation failed`. The proxy allowlists by hostname over HTTP(S) and cannot carry SSH. Fixed by adding `git *` to `sandbox.excludedCommands`; git stays governed by the guard hook, which is the semantic layer anyway. |
| 6 | **`claude --cloud` requires a TTY** — *"Non-interactive invocations run locally and would silently ignore --cloud."* `script -q /dev/null claude --cloud "…"` works, dispatches, prints the session URL, and **exits immediately**. There is no streaming. |
| 7 | **`gh` commit statuses are the deployment signal.** SHA-exact, no token needed. Five Vercel projects post one status each, so the context must be matched exactly — and it contains an **en dash**: `Vercel – shop2`. |
| 8 | `deploy-watch`: **4/4** against real commits — success, build failure, unknown SHA, and timeout. |
| 9 | `git show origin/<ref>:<path>` reads the pushed ledger with no checkout, and the ledger status parser is correct on both partial and all-pass fixtures. |
| 10 | Vercel MCP resolves branch → deployment → `state` → `meta.branchAlias` → `githubCommitSha`. Observed states include `READY`, `ERROR` and `CANCELED`. |
| 11 | **Plugins must be re-declared in the profile.** Playwright is a plugin enabled through `enabledPlugins` in *user*-scope settings, so omitting the user scope silently removed every browser tool — the local verification phase would have had nothing to drive. Adding `enabledPlugins` to the profile restores them at the same prefix, `mcp__plugin_playwright_playwright__`. Caught only by asking a session to enumerate its MCP servers. |
| 12 | **End-to-end verification proven.** Under the profile, Playwright navigated `https://shop2-git-merge-buynow-jul2526-unicity.vercel.app`, followed the expected `307` to `/usa/en/products`, got `200` fully rendered, and hit **no Cloudflare Access wall** — the raw `*.vercel.app` host is reachable, and console/network are readable. This is the feature gate working against a real deployment. |
| 13 | `browser_close` and `browser_install` were missing from the allow list; the first denial left a browser process open. Both added — an unattended loop that leaks a browser per cycle would degrade the machine over a night. |

### Pre-existing bug found in the shared repo — unrelated to this project, but it changes the plan

`apps/../.claude/settings.json` (repo root) declares **two top-level `"hooks"` keys**, at lines 406 and 617. JSON keeps the last duplicate, so the entire first block is discarded. Everything in it is silently inert:

| Event | Dead hooks |
|---|---|
| PreToolUse | 22 × `_deny.sh` rules, `pre-write-store-policy.sh`, `pre-bash-git-deny.sh` |
| PostToolUse | `post-edit-format.sh`, `post-edit-rules.sh` |
| Stop | `stop-tsc.sh` |
| SessionStart | `session-start.sh` |
| UserPromptSubmit | `user-prompt-submit.sh`, `user-prompt-submit-planning.sh` |
| PreCompact / PostCompact | `pre-compact.sh`, `post-compact.sh` |

Only the second block — the MCP-deny-on-`bypassPermissions` hook — is live.

Two independent confirmations: parsing the file with duplicate-key capture shows block 1 discarded, and a baseline `git add -A` was refused with the generic *"Permission to use Bash … has been denied"* rather than the hook's own *"AI does not run git add"* text, so the hook demonstrably never fired.

**This affects normal daily sessions**, not just this workflow: no auto-format on edit, no tsc gate at stop, no planning nudge, no store-policy guard, no session-start summary. Worth a one-line upstream fix (merge the two blocks) independent of anything here.

**What it changes for this plan:**

1. **`pre-bash-git-deny.sh` is not a blocker** — it is inert. What actually refuses git in a cloud session is the *permissions deny list* (45 entries, project scope, which does travel with the clone). The fix target changes accordingly.
2. **The MCP-deny hook is a real blocker**, since it is the one live hook.
3. **D3 loses its rationale.** "Re-wire the repo's useful hooks" assumed they were running. They are not running for anyone, so skipping the project scope costs nothing. `repo-hook-proxy.sh` is built and tested anyway, and becomes useful the moment the upstream duplicate-key bug is fixed.

### Verified broken — no cloud→local read channel exists

Four independent channels were tried; all failed:

1. `claude agents --json` lists only local sessions — cloud sessions never appear.
2. `WebFetch` on a session URL → **403**.
3. `claude -p --teleport <id>` loads **no conversation history** — the session receives only system context.
4. After that teleport, no cloud turns are persisted to `~/.claude/projects/*.jsonl` either.

**Consequence, and it is structural:** git is the *only* channel from the cloud phase back to local automation. The ledger must therefore carry failures as well as progress, and the absence of a push is indistinguishable from work still in flight. Every waiting path needs a timeout that launches something able to report, which is why `deploy-watch` exits non-zero on timeout rather than staying quiet.

### Cloud probes — dispatched successfully, results unreadable

Four cloud sessions were launched. All four dispatched cleanly; **none produced an observable result.**

| Probe | Target | Session | Observable outcome |
|---|---|---|---|
| 1 | new-shop | `session_014DHS8bQup9SLQ8ZBwaSCF4` | none readable |
| 2 | new-shop | `session_01EsqWEJWaYM7o3Ljh7BnjFP` | none readable |
| 3 | dotfiles | `session_014Rfny5qZ6JvmKDdwuwkmyi` | no branch after ~25 min |
| 4 | dotfiles, `--permission-mode bypassPermissions` | `session_01EPSUyoxAo3azhoRE1chh6C` | no branch after ~8 min |

Probes 3 and 4 targeted the **dotfiles** repo deliberately: its `.claude/` is untracked, so the cloud clone carries no repo policy at all. Neither pushed a branch. That rules the *repo's* configuration out as the cause.

Probes 5 and 6 asked only for a **GitHub issue** — no git, no branch, using the built-in GitHub tools that do not route through Bash. Nothing appeared on either repo, confirmed by a 30-minute poll and by direct `gh issue list` / `gh pr list` checks afterwards.

Final tally: **six probes · two repositories · two permission modes · three different deliverable types (branch push, issue, PR) · zero observable side effects of any kind.** Thirty minutes rules out slow container boot. Because probe 5 and 6 required no Bash and no git at all, this is not a permissions nuance — the sessions are not doing work. That points at authentication or provisioning failing before execution begins, which is exactly the documented IP-allowlist symptom.

**Retracted hypothesis:** I initially blamed the Claude GitHub App not being installed. That is wrong on two counts. The docs are explicit — *"a cloud session can access any repository the connecting GitHub account can see… App installation enables PR webhooks for Auto-fix; it is not a session-level access control"* — and either the App **or** `/web-setup` (which syncs the local `gh` token) suffices for clone and push. It also doesn't fit the evidence: a per-repo App gap cannot produce uniform failure across two repos including a pure issue-creation task.

**Best-fitting hypothesis now:** the sessions are created but never successfully execute. The docs describe exactly this failure mode:

> Cloud sessions call the Anthropic API from Anthropic-managed infrastructure, not your network. If your organization has **IP allowlisting** enabled, **every cloud session fails with an authentication error.** The same applies to Code Review and Routines.

Unicity is an enterprise org with SAML enforced, so this is plausible; the documented remedy is asking Anthropic support to exempt Anthropic-hosted services. The competing possibility is that the only configured environment (`Text`, `env_013HfWkd2srxt7hzEsrLwNUr`) cannot service a repository task.

**Counter-evidence worth weighing:** a cloud session on this account previously cloned private `new-shop` and ran 12 shell commands. So cloud sessions have worked at least once, which argues against a permanent org-wide block and toward something environmental or recently changed.

Note `--permission-mode` must precede `--cloud`; the reverse order fails with *"--cloud requires a description."*

Confirmed by a 20-minute poll: `refs/heads/main` is the only branch on the dotfiles remote. Every remaining diagnostic was tried and is closed:

- Reading a transcript — four channels, all fail (above).
- Checking whether the Claude GitHub App is installed — `gh api /user/installations` returns **403** (the local `gh` token is not App-authorized). Moot in any case: the App is not required for clone or push, only for Auto-fix webhooks.
- Using GitHub itself as the read channel, via an issue created by the cloud session — nothing appeared on either repo.
- Pushing a probe branch to `Unicity/new-shop`, which *would* answer it — declined: it triggers a preview deploy and the smoke workflow and leaves an undeletable branch on a shared team repo.

Three hypotheses remain, and a transcript distinguishes them in seconds: the Claude GitHub App is not installed on the target repo; the cloud session's default permission posture refuses Bash with nobody to approve; or the sole configured environment (`Text`, `env_013HfWkd2srxt7hzEsrLwNUr`) is unusable for a repo task and the container never got far enough to try.

### Still open — the one real gate

**D1 could not be closed.** Determining whether the repo's committed deny hooks block a cloud session's `git commit` requires observing whether a probe branch reaches the remote. That needs a push, and:

- I cannot push — it is denied to me by both the repo hook and global settings, correctly.
- Pushing a scratch branch to `Unicity/new-shop` would trigger a preview deploy and the smoke workflow, and leave a branch on a shared team repo that I have no way to delete.

I judged that outside what I should do unilaterally to a shared resource. Two probes did dispatch successfully (`session_014DHS8bQup9SLQ8ZBwaSCF4`, `session_01EsqWEJWaYM7o3Ljh7BnjFP`) and their results are readable only by opening those URLs — see the read-channel finding above for why.

**Design hedge available:** the repo hook intercepts **Bash** only. Cloud sessions have built-in GitHub tools that authenticate through the credential proxy, so instructing the cloud session to persist via the platform's PR mechanism rather than `git commit` may sidestep it entirely. Unverified, and worth trying before touching the shared repo.

**What unblocks this in two minutes, and only you can do it:** open the session URLs and read what each reported.

- If they show an **authentication error** → org IP allowlisting is blocking Anthropic-hosted infrastructure; ask Anthropic support for an exemption. The cloud phase is impossible until then.
- If they show **no GitHub access** → run `/web-setup` in an interactive session to sync your `gh` token to the Claude account.
- If they show a **permission refusal** → the cloud phase needs a different persistence path, or the project-scope deny list needs the upstream change.
- If they show the **environment failing to start** → create a proper `new-shop` environment; `Text` is the only one configured and may not service a repo task.

Until that is known, **the cloud phase is unvalidated and should not be relied on.** The local phase is proven and can be used on its own today: plan and implement locally under `claude-unattended`, then let `deploy-watch` gate the browser verification against the preview URL. That is a complete, working loop minus the "not on my machine" property.

---

## Decisions taken

| # | Decision | Chosen |
|---|---|---|
| D1 | Cloud session inherits the shared repo's deny hooks | **Test empirically in P0.1**, then decide between a minimal upstream PR and local-only |
| D2 | Getting the autonomy contract into cloud sessions | **Dissolved — no personal skills go to the cloud.** The contract is written into the generated plan file, which is already committed and already re-read every turn (see *Skill delivery*) |
| D3 | Repo hooks lost when project settings are skipped | **Re-wire the important ones from dotfiles**, invoking the repo's own scripts by resolved path |
| D4 | Behaviour when the preview URL goes live | **Auto-start verification on READY**; notify only on final verdict or BLOCKED, via native notifications only — no ntfy, no custom channel |

---

## The key mechanism (verified)

`--setting-sources` controls which settings scopes load, and **directory-based discovery is unaffected**:

- Skipping `project` skips the repo's `.claude/settings.json` permission rules **and its hooks**.
- `.claude/skills/`, `.claude/agents/`, `.claude/commands/` still load — they're filesystem artifacts, not settings.

So an unattended local session keeps everything useful from the repo (`verifying-changes`, `playwright-regression-testing`, `/goal-plan`, the `goal-verifier` agent) while none of its 45 denies or deny-hooks apply. That is the whole basis for a dotfiles-only local half.

### What each side actually needs

Because the cloud session's work ends at push, the split is narrower than it first looked.

| | Cloud session | Local session |
|---|---|---|
| Repo | automatic clone | worktree |
| Requirements + state | the committed plan file | same file after `fetch` |
| Skills | repo `.claude/**` only — nothing personal | everything, natively |
| MCP / connectors | **none required** | Playwright, Vercel, ClickUp via user config |
| Credentials | GitHub push only, held outside the sandbox | mine |

ClickUp is a **remote HTTP MCP** (`https://mcp.clickup.com/mcp`), not a local stdio server, and is now connected as a claude.ai connector. So a cloud session *can* reach it. It still shouldn't derive requirements from it: the agent works from the criteria I approved and that are versioned on the branch, not from prose someone can edit mid-run. The connector's real use is write-back — a status comment on the ticket when the PR opens.

**Known gap: images.** Neither the connector nor the ledger gets a screenshot or a Figma frame into a cloud session. `/cloud-ticket` needs a pre-flight: if the requirements live in an attachment, say so and recommend staying local for that ticket.

### Two signals, not one marker

`.claude/state/` is gitignored (`.gitignore:60`), so a marker file cannot reach a cloud session in a commit. Rather than work around that, the two environments use different signals:

- **Local** unattended runs key on `.claude/state/unattended.json` — gitignored and per-developer, exactly as `goal-loop-active.json` already is.
- **Cloud** sessions key on `CLAUDE_CODE_REMOTE_SESSION_ID`, which exists natively in the VM.

Consequence worth keeping: the only thing this workflow ever commits to the shared repo is the plan file itself — already the `/goal-plan` convention, and already deleted at teardown.

**Resolved 2026-07-25 by test.** Permission arrays do merge, and a lower-scope `deny` beats a higher-scope `allow` — so `--setting-sources user` is unusable, because the global `git commit`/`git push` denies survive the profile. `managed` is not a valid source at all. The working launch is:

```bash
claude --setting-sources local --settings ~/dotfiles/claude/.claude/settings.unattended.json
```

`local` loads the repo's `.claude/settings.local.json`, which has an empty `deny` array and defines no hooks — the only near-empty base available. Verified: `git commit` runs under this, and is denied without it.

One dependency to keep in mind: that file is gitignored and per-developer, so it is mine to control, but if I ever add a `deny` to it the unattended profile inherits it.

---

## Skill delivery to cloud sessions

**Nothing needs delivering. No personal skills go to the cloud.**

The repo's `.claude/skills/` (36), `.claude/agents/` (incl. `goal-verifier`), `.claude/commands/` (incl. `/goal-plan`), `.claude/rules/` and `CLAUDE.md` are all part of the clone. That covers everything the cloud session does: read the ledger, implement, run `tsc` / `formatAndLint` / `fallow`, dispatch the verifier, commit, push.

The one thing that was *not* already in the repo is the **autonomy contract** — never ask-and-idle, escalate as a BLOCKED row, cycle caps, commit discipline, never fake a pass. It doesn't need to be a skill: `/cloud-ticket` writes it into the plan file it generates. The plan file is committed, is re-read every turn, and already carries an `Execution Protocol` section in the `/goal-plan` template, put there for exactly this reason — *"the loop reads this file, not this command, and may run after a compaction wiped the command from context."*

What this buys:

- No claude.ai publishing, no setup-script clone of dotfiles, no skill allowlist
- No cache-staleness and no drift between a dotfiles skill and its cloud copy
- The contract that governed a given run is recorded **in that run's plan file**, so it is auditable afterwards

`unattended-execution` therefore stays a **local** skill with two jobs: governing the local verify/fix session, and supplying the protocol text `/cloud-ticket` writes into the plan. `preview-url-verification` is local-only by nature — verification never happens in the cloud.

**The one assumption left to verify:** that repo skills and, critically, **subagent dispatch** work in a cloud session. If `goal-verifier` can't be dispatched there, the implementer grades its own homework and the anti-gaming property collapses in the cloud phase. P0.1 probe 3 tests exactly that.

---

## Preconditions and known failure modes

Established empirically on 2026-07-25.

**`--cloud` clones the current branch from GitHub, not from disk.** `gtr new` creates a branch that exists only locally, so dispatching before pushing makes the VM clone the wrong ref. The launcher treats this as a hard precondition, not a courtesy:

```bash
git push -u origin HEAD
git ls-remote --exit-code --heads origin "$(git branch --show-current)" >/dev/null \
  || { echo "branch not on remote — refusing to dispatch"; exit 1; }
```

**Teleport is a migration, not a viewer — so the loop does not use it.** Per the docs, teleport "loads the full conversation history into your terminal" and "the terminal gets its own copy of the session: new work there stays local and doesn't appear in the cloud session." It carries four hard requirements: clean git state (it prompts to stash), the same repository rather than a fork, **the cloud branch must already be pushed to the remote**, and the same claude.ai account.

That third requirement explains the `Session resumed without branch: Failed to checkout branch 'claude/review-current-code-eiss8x'` error seen 2026-07-25: the session was a read-only review, so it never committed, so its branch never reached origin — confirmed, no `claude/*` refs exist on new-shop's origin. A warning rather than a failure; the conversation still resumed.

**Watch the branch, not the session.** Cloud sessions cannot be observed from a terminal at all (see *Validation results*), so nothing in this design tries to. The signals are all git and GitHub:

| Question | Answer comes from |
|---|---|
| Has the cloud session done anything? | new commits on the branch — `git ls-remote` |
| How far has it got? | `git show origin/<branch>:<plan path>` → the `GOAL-LOOP-STATUS` block |
| Did the build pass? | `gh` commit status for that SHA — `deploy-watch` |
| Why did it stop? | **only the session URL in the Claude UI** |

Consequence accepted deliberately: **the cloud phase is managed in the Claude web/mobile UI, not the terminal.** Questions are asked and answered there. The terminal's role is to dispatch, then to wait on the branch.

The cost is that a dead or blocked session looks identical to a slow one. Only a timeout distinguishes them, and all it can say is "open the session URL". If the session cannot push, the web UI's **Create PR** button is the manual fallback that puts the branch on GitHub — after which every downstream step is validated.

**How the loop actually hands off.** `deploy-watch` does `git fetch && git checkout <branch>` and starts a **fresh** local session that reads the committed ledger. No teleport. Four reasons:

1. The ledger is the state, so the cloud transcript isn't needed — that's the whole premise of file-as-truth in `/goal-plan`.
2. Teleport's stash prompt and clean-tree requirement fight unattended operation.
3. Loading a long implementation transcript spends context the browser phase needs.
4. Teleport is one-way; a fresh dispatch reading the ledger can always return work to the cloud.

Teleport stays in the toolkit as a deliberate human move — when I want to read what the cloud session was thinking.

**Checkout into a worktree collides.** `git checkout <branch>` fails if that branch is already checked out in another worktree, which the gtr layout makes likely. `deploy-watch` needs a preflight that resolves which worktree owns the branch and either reuses it or refuses cleanly.

**`claude --cloud` requires a TTY.** Verified: with stdout piped it refuses outright — *"Non-interactive invocations run locally and would silently ignore --cloud."* So `cloud-ticket-dispatch` cannot simply be called from inside a Claude session. Two working routes: wrap it as `script -q /dev/null claude --cloud "…"` (verified — dispatches, prints the session URL, exits 0 immediately), or run it in a real herdr pane via `herdr pane run`, which is what `dev-cloud` should do so the dispatch output is visible.

**Dispatch does not stream.** It prints `Created cloud session` / `View: <url>` / `Resume with: claude --teleport <id>` and returns control. Nothing further appears in that terminal.

**Monitoring the cloud phase** is `/tasks` in the CLI, claude.ai, or the mobile app — and answering a question there continues the session cloud-side. `--remote-control` is the opposite direction and is already on by default in my global settings, so the local verify session is phone-watchable for free.

---

## File inventory

All paths relative to `~/dotfiles` (stowed: `claude/.claude` → `~/.claude`, `bin/bin` → `~/bin`).

### New

| Path | Purpose |
|---|---|
| `claude/.claude/settings.unattended.json` | **BUILT AND TESTED.** The unattended policy. Empty `ask` array by construction — an ask is a hang. Sandbox block with `git *` and `gh *` excluded. Vercel MCP, ClickUp reads, and the full Playwright set. |
| `claude/.claude/hooks/unattended-git-guard.sh` | **BUILT AND TESTED 46/46.** Replaces the repo's blanket git deny with a targeted one: `add`/`commit`/`push` allowed on feature branches; protected branches, force-push, history rewrites and HEAD movement refused, including via subshell. Resolves the real destination branch, since `git push` and `git push origin HEAD` name none. |
| `claude/.claude/skills/unattended-execution/SKILL.md` | **Local skill.** Governs the local verify/fix session, and supplies the protocol text `/cloud-ticket` writes into the generated plan file. Nothing is published anywhere. |
| `claude/.claude/skills/preview-url-verification/SKILL.md` | **Local skill.** Branch → deployment → READY → preview URL, plus the triage tree. |
| `claude/.claude/hooks/unattended-stop-gate.sh` | Dotfiles variant of `goal-loop-stop-gate.sh`: no stopping at a row PASS while rows remain; final gate is a READY deployment + a passing contract row, not `pnpm dev-build`. |
| `claude/.claude/hooks/repo-hook-proxy.sh` | Invokes `$(git rev-parse --show-toplevel)/.claude/hooks/<name>` when present, so D3's re-wiring keeps the logic in the repo. |
| `claude/.claude/commands/cloud-ticket.md` | The model half of stage 1: read the ticket, research, decompose into ledger rows, write the Verification Contract, present for approval. Stops there. Guards against running outside a suitable repo, since user-scope commands load everywhere. |
| `bin/bin/cloud-ticket-dispatch` | The mechanical half: write the plan file, commit, `push -u`, verify the remote ref, `claude --cloud`, arm the watcher. Split out so Claude never has to launch Claude from inside a session. |
| `bin/bin/claude-unattended` | **BUILT.** Wraps the verified incantation, writes and cleans up the local marker, and refuses to start if `.claude/settings.local.json` is missing (since `--setting-sources local` reads it, its absence would mean running with no base at all). Warns if that file defines deny rules, because they merge in and beat the profile's allows. |
| `bin/bin/deploy-watch` | **BUILT AND TESTED 4/4.** Polls `gh` commit statuses for the pushed SHA — not the Vercel API, because statuses are SHA-exact (the branch alias always serves the newest build, so alias polling can report ready while still serving the previous commit, producing a false pass) and because `gh` needs no token while the Vercel MCP is unreachable from a shell. Exits 0 ready / 2 failed / 3 timeout / 4 unpushed. Never exits silently. The caller does `fetch && checkout` and launches the verify session, which resolves the actual preview URL through the Vercel MCP. |
| `bin/bin/dev-cloud` | herdr sibling of `dev-init-herdr`: watcher pane + nvim, no dev server, background `pnpm install` pre-warm. |
| `claude/.claude/cloud-setup.sh` | The environment setup script, versioned in dotfiles and pasted into the claude.ai environment. Only job: `corepack` + `pnpm install --frozen-lockfile`. No dotfiles clone, no skill delivery. |

### Patched

| Path | Change |
|---|---|
| `bin/bin/gtr-postcreate` | Fork on `GTR_CLOUD` → `dev-cloud` instead of `dev-init`. Two lines. |
| `zsh/.zshrc` | `gtrc()` = `GTR_CLOUD=1 git gtr new "$@"`. |

### Reused as-is

`/goal-plan` and its ledger · `goal-verifier` agent · `.github/workflows/test-end-to-end.yml` (backstop only) · Vercel branch auto-deploy · Playwright MCP plugin · herdr + `dev-init` scaffolding · `/autofix-pr` for post-PR CI noise · native notifications (`PushNotification` + `remoteControlAtStartup: true`, already set) · `--teleport` as an optional human move, not part of the loop.

### Explicitly not used

**ntfy.** Notifications are native throughout. `PushNotification` writes a desktop notification and pushes to the phone whenever Remote Control is connected, which my global settings already enable; it also self-suppresses when I'm actively at the terminal, so it only fires when I've genuinely walked away. A custom channel would fire either way and is one more thing to maintain. The existing `ntfy` stow package stays where it is, unused by this workflow.

---

## Phases

### P0 — Prove the seams (blocking, ~half day)

**P0.1 — The cloud git probe (do this first; it decides the architecture).**

Three cheap `--cloud` probes on a scratch branch:

1. `claude --cloud "print CLAUDE_CODE_REMOTE_SESSION_ID and your current permission mode, then stop"` — confirms the env var exists (the guard condition any upstream fix would key on) and reveals what mode cloud sessions run in.
2. `claude --cloud "on this branch, make an empty commit 'probe' and push it. If any tool call is denied, quote the denial verbatim and stop"` — the decisive test.
3. `claude --cloud "list your available skills, agents and MCP servers; then dispatch the goal-verifier subagent with a trivial task and report verbatim what it returns; then stop"` — the probe that de-risks the design. It confirms (a) the repo's `.claude/**` really did travel, (b) **subagent dispatch works in a cloud session**, without which the verifier can't police the implementer and the anti-gaming property collapses cloud-side, and (c) whether a CLI-dispatched session inherits my claude.ai connectors — the docs say only "connectors are configured per session or per routine", with no mechanism given. If MCP servers are missing entirely, the repo's MCP-deny hook is the suspect; probe 1's answer predicts that, since the hook only fires on `bypassPermissions`.

| Outcome | Consequence |
|---|---|
| Push succeeds | The platform's git path doesn't route through the Bash hook. **Zero repo changes.** Proceed to P1. |
| Denied with `"AI does not run git commit"` | The hook fires. Choose: 10-line upstream PR (`[ -n "$CLAUDE_CODE_REMOTE_SESSION_ID" ] && exit 0` at the top of both hooks), or drop the cloud phase and run local-only with `--bg`. |

**P0.2 — Local unattended policy.**

**DONE.** `settings.unattended.json` and `unattended-git-guard.sh` are built and passing; the merge-vs-override question is resolved (see *Validation results*). Remaining in P0.2: `claude-unattended` as a thin wrapper around the verified incantation, and the re-wired repo hooks per D3.

**Verified:** `git commit` runs under the profile and is denied without it; `git push origin master` is refused by the guard with its own message; the guard is 46/46 including subshell bypass.

**Still to verify here:** an end-to-end push on a real feature branch, which needs a branch I am willing to push — and that Playwright MCP loads under `--setting-sources local` (the profile allows it, but only the git path has been exercised so far).

**P0.3 — Confirm usage credits are off** (Settings → Usage). With them off, a runaway loop stalls at the rate limit and can never produce a bill.

### P1 — Cloud environment (~1–2h, skip if P0.1 says local-only)

- Create a `new-shop` environment at claude.ai/code — today only `Text` exists, unconfigured for this monorepo. Network stays **Trusted**.
- Setup script: `corepack` + `pnpm install --frozen-lockfile`. **Measure against the ~5 min budget** — the cache only builds if the script fits, and expires after ~7 days. If it overruns, move install to a background SessionStart hook.
- Confirm GitHub access (App or `/web-setup`) so the session can push at all.
- **Connectors: none are required.** Since the cloud session's job ends at push, Vercel and Slack are both unnecessary there — `deploy-watch` and the local verify session read Vercel through my user config, and notifications are native. ClickUp is now connected as a claude.ai connector, which is worth having for one optional thing: the cloud session posting a status comment back to the ticket when it pushes and opens the PR. Whether that works unattended depends on P0.1 probe 3.
- Nothing else goes in the setup script. Per *Skill delivery* above, no personal skills are shipped to the cloud.

**Verify:** `claude --cloud "run pnpm tsc and report"` completes from a cold environment.

### P2 — One real ticket, by hand (deliberately manual)

Plan locally with `/goal-plan` plus a Verification Contract → push → `--cloud` → wait for deploy → drive the flow through Playwright MCP against the preview URL myself.

**Deliverable: a written defect list of everything the remote target breaks** — missing sandbox domains, access quirks, flags needed for gated markets, prompts that hung. That list is the spec for P3, and it beats writing the skills from theory.

### P3 — Automate the handoff (~1 day)

- `unattended-execution` skill: gate ladder order, commit/push discipline, cycle caps, never fake a pass, declare gates that can't run in this environment. **Escalation is a hybrid:** write the BLOCKED row, push it, then ask natively. The native ask *is* the notification — the mobile app surfaces it, so there's nothing custom to wire. If I'm around I answer from my phone and the cloud session continues with full context; if the environment expires the question is still durable on the branch.
- `preview-url-verification` skill: deployment resolution + triage tree (build broke / feature broke / pre-existing flake), raw `*.vercel.app` to sidestep Cloudflare Access, experimental flag for gated markets.
- `deploy-watch`: poll → READY → `fetch && checkout` (worktree preflight) → launch the verify session, which calls `PushNotification` on verdict or BLOCKED (D4). On timeout, launch a session anyway to report why the deploy never came up.
- Ledger reshape: no browser runs before deploy, so per-row `G2` becomes `deferred → row N` and the ledger gains a **final verification row whose acceptance criteria are the Verification Contract**. That row is the one that can't be faked.
- `goal-verifier` prompt: judge browser evidence against contract assertions; stay hostile to "couldn't reach it, marked done".

**Verify:** a second ticket runs with me only approving the plan. The watcher fires on deploy, verification runs itself, and a real failure produces either a pushed fix or one BLOCKED question on my phone.

### P4 — One command (~half day)

`/cloud-ticket` · `gtrc` + the `gtr-postcreate` fork · `dev-cloud` watcher workspace.

**Verify:** `gtrc ECOM-1234` takes me from ticket to plan approval, and the next thing I touch is a finished PR.

---

## Risks

| Risk | Mitigation |
|---|---|
| Setup script overruns 5 min, so the environment cache never builds | Move install to a background SessionStart hook. Measure in P1 before writing anything else. |
| Mac asleep, so auto-start never fires | `caffeinate` for overnight runs. The branch is pushed and building either way, so the run resumes rather than being lost. |
| Rate-limit stall mid-run | By design, not a bug — credits stay off. Cheap gates before expensive ones, 3-cycle cap, 2 tickets max in flight. |
| A forgotten host prompts once and hangs the run | Pre-allow the app's client-side hosts in the sandbox block, not just `*.vercel.app`. P2 discovers the full list. |
| `gh` fails TLS under Seatbelt | It's Go-based; add `gh *` to `sandbox.excludedCommands` or the watchers break. |
| Subagent dispatch doesn't work in a cloud session, so `goal-verifier` never runs and the implementer grades itself | P0.1 probe 3 tests this directly. If it fails, the cloud phase loses its independent check and either the rows get verified locally after fetch, or the cloud phase is dropped. |
| Dropping project settings loses a guard I forgot about | `unattended-git-guard.sh` replaces the blanket deny with a targeted one — a net improvement, not a removal. Re-read the repo's hook list before P0.2 ships. |
| Agent games a gate to reach "done" | Unchanged from the existing design: the verifier writes verdicts, the stop gate re-runs checks deterministically, the contract row needs browser evidence. |

---

## Open questions

1. Generalize beyond `new-shop`, or hardcode it first? (`dev-init` already special-cases `topout` and `UFeelGreat`.)
2. Default verification target for the contract template — USA guest is cheapest; anything auth'd or market-gated must be named per ticket.
3. Does the local fix loop open the PR immediately (so `/autofix-pr` can watch CI) or only after the contract row passes?
