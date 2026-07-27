---
name: unattended-execution
description: The autonomy contract for a run with nobody watching — never ask and idle, escalate as a committed artifact instead, order the gates cheapest-first, and keep git writes on a feature branch. Use when running under claude-unattended, when driving a goal-plan ledger without a human checkpoint between rows, when a run must finish or stop cleanly while the user is asleep, and when writing the Execution Protocol section of a plan file that a separate session will later execute. Also use when deciding whether to stop or continue after a gate fails.
---

# Working with nobody watching

An attended session can ask a question and wait. An unattended one cannot: a question is a hang, and a hang looks exactly like progress. Everything here follows from that.

## The first rule: never ask — escalate as an artifact

When you hit something you genuinely cannot decide:

1. Write a `BLOCKED` row into the ledger, containing the **specific question**, the options you considered, and what you would do by default.
2. Commit and push it, so the question survives this session dying.
3. Send one `PushNotification` — terminal plus phone. One, not a running commentary.
4. Then stop.

If you are a cloud session you may also ask natively afterwards; the mobile app surfaces it and the answer resumes you with full context. Write the row **first** regardless, because the environment can expire while nobody is looking.

What does *not* justify escalating: a choice with an obvious default, something the plan already answers, or a preference you can state as an assumption and proceed under. Decide, record the assumption in the row, keep moving.

## Gate ladder — cheapest first, always

Ordered by cost, and a failure at any level means fix before descending:

1. `pnpm tsc`
2. `pnpm formatAndLint`
3. `pnpm fallow audit` on the diff
4. the independent verifier
5. push → build → browser verification against the deployed URL

Level 5 costs a full build-and-deploy round trip. Never reach it with a type error in the tree. This ordering is the difference between a run that finishes overnight and one that burns three deploy cycles on a typo.

## Verdicts are not yours to write

Implement, gather evidence, set the row to `NEEDS-VERIFY`, then dispatch the independent verifier. It writes `PASS`/`FAIL`. You never write your own verdict — the whole design exists because agents grade themselves generously.

Max three verify rounds per row, then `BLOCKED` with a note. After two failed attempts at the same root cause, stop and escalate rather than patching a third time.

## Git discipline

- Commit per ledger row. The commits are the audit trail and the progress signal — a watcher reads the pushed ledger, because there is no other channel out of a cloud session.
- Push to the feature branch only. Never master, main, staging, production, release or develop.
- Never force-push, `reset`, `rebase`, `checkout`, `clean`, or rewrite history. A reset can silently discard a row that was already verified.
- `unattended-git-guard.sh` enforces all of the above and will refuse you. If it refuses, that is the answer — do not look for a way around it.
- The user opens and merges the PR. You never merge.

## Never fake a pass

- A gate you could not run is **declared**, not skipped. Say which gate, why it could not run here, and what evidence you have instead.
- A flow you could not reach is `unreachable`, never `pass`.
- Do not delete or skip a test to make a gate green. Do not print success strings to satisfy a checker.
- If the environment cannot support a check at all — no browser, no secrets, no network to a host — say so in the row and let the next phase cover it.

## Know which environment you are in

- **Cloud session** (`CLAUDE_CODE_REMOTE_SESSION_ID` is set): no build, no browser, no secrets. Cheap gates only, then push. Nothing you print is readable from a terminal — git is the only channel out, so anything that matters goes in the ledger and gets pushed.
- **Local unattended** (`.claude/state/unattended.json` exists): full toolchain and a real browser. This is where verification and fixes happen.

## Stopping

Stop when every row is `PASS` and the contract row has browser evidence — or when a row is `BLOCKED` and you have pushed the question and notified once. Those are the only two clean endings.

Do not stop with a row mid-flight. Do not stop silently on a timeout: whatever was waiting must report why it gave up, because silence is indistinguishable from still working.
