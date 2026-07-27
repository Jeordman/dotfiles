#!/usr/bin/env bash
# Stop hook — deterministic backstop for an unattended run.
#
# NO-OP unless .claude/state/unattended.json exists, so ordinary sessions are
# never gated. Wired from settings.unattended.json.
#
# This is the check the agent cannot talk its way past. The independent verifier
# does the per-row judgement; this only enforces things that are mechanically
# decidable, and it deliberately refuses to accept "done" without evidence.
#
# Differences from the repo's attended goal-loop gate, both required here:
#   * There is no human checkpoint, so stopping with rows still TODO is refused
#     rather than treated as a pause point.
#   * The final gate is NOT `pnpm dev-build`. In a cloud sandbox that fails
#     forever for want of env vars, and even locally the meaningful proof is a
#     green preview deployment plus browser evidence — so the gate requires a
#     verified preview URL in the ledger instead.
#
# Claude Code force-overrides a Stop hook after 8 consecutive blocks, so this
# yields at 6 with a clear message rather than being overridden mid-thought.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || exit 0

MARKER="$ROOT/.claude/state/unattended.json"
[ -f "$MARKER" ] || exit 0

REPO_HASH=$(printf '%s' "$ROOT" | shasum | cut -c1-8)
BLOCKS="${TMPDIR:-/tmp}/claude-unattended-blocks-$REPO_HASH"

if [ -f "$BLOCKS" ]; then
  N=$(cat "$BLOCKS" 2>/dev/null || echo 0)
  if [ -n "$N" ] && [ "$N" -ge 6 ] 2>/dev/null; then
    echo '{"systemMessage":"unattended gate yielded after 6 blocks — it could not be satisfied automatically. Inspect the ledger; the gate re-arms on the next clean turn."}'
    rm -f "$BLOCKS"
    exit 0
  fi
fi

LEDGER=$(jq -r '.ledger // empty' "$MARKER" 2>/dev/null)

# No `ledger` key at all is a deliberate opt-out (claude-unattended -L).
if [ -z "$LEDGER" ]; then
  echo '{"systemMessage":"unattended gate: no ledger declared (-L) — evidence check disabled for this run."}'
  exit 0
fi

# A ledger was NAMED but does not exist. This used to no-op, and combined with
# claude-unattended omitting the field entirely it meant the gate never fired at
# all (found 2026-07-26). Treat it as a block: an unattended verify run whose
# only output is "looks good" is precisely the failure this hook exists to stop.
if [ ! -f "$LEDGER" ]; then
  N=$(cat "$BLOCKS" 2>/dev/null || echo 0); echo $((N + 1)) > "$BLOCKS"
  printf 'unattended verification gate — cannot stop yet:\n- No verification record at %s.\n  Write it before ending: route, market, locale, auth state, the flow walked, and one\n  "N | STATUS | assertion" row per check (STATUS is TODO/DOING/NEEDS-VERIFY/PASS/FAIL/BLOCKED),\n  recording the deployed preview URL you actually exercised. If the flow was unreachable,\n  say so in a row — do not omit the file.\n' "$LEDGER" 1>&2
  exit 2
fi

STATUSES=$(grep -E '^[0-9]+ \| (TODO|DOING|NEEDS-VERIFY|PASS|FAIL|BLOCKED)' "$LEDGER" 2>/dev/null | sed -E 's/^[0-9]+ \| //')
TOTAL=$(printf '%s\n' "$STATUSES" | grep -cE '.' || true)
PASS=$(printf '%s\n' "$STATUSES" | grep -cE '^PASS$' || true)
MID=$(printf '%s\n' "$STATUSES" | grep -cE '^(DOING|NEEDS-VERIFY|FAIL)$' || true)
BLOCKED=$(printf '%s\n' "$STATUSES" | grep -cE '^BLOCKED$' || true)
TODO=$(printf '%s\n' "$STATUSES" | grep -cE '^TODO$' || true)

REASONS=""

# 1) Nothing may be mid-flight.
if [ "$MID" -gt 0 ] 2>/dev/null; then
  REASONS="$REASONS\n- $MID row(s) are mid-flight (DOING/NEEDS-VERIFY/FAIL). A FAIL is not fixed here: write the root cause and file:line to a findings file, dispatch it with cloud-fix-dispatch, wait for the push (wait-for-push), gate on the build (deploy-watch), then re-verify. Or set the row BLOCKED with a specific question. Never write your own verdict."
fi

# 2) No human checkpoint exists, so unfinished work is not a stopping point.
#    A BLOCKED row IS a legitimate stop — that is the escalation path.
if [ "$TODO" -gt 0 ] 2>/dev/null && [ "$BLOCKED" -eq 0 ] 2>/dev/null; then
  REASONS="$REASONS\n- $TODO row(s) still TODO and nothing is BLOCKED. This is an unattended run: there is no checkpoint to stop at. Work the next row, or set one BLOCKED with a specific question if you genuinely cannot proceed."
fi

# 3) Cloud-always: the local session diagnoses, it does not implement. Source
#    edits here mean the fix bypassed the cloud round trip and will never exist
#    on the branch that gets deployed and re-verified. Mechanically decidable,
#    so it belongs in the gate rather than in a prompt.
#    .claude/state/ is excluded (and gitignored anyway) — that is where the
#    verification record and findings files live.
#    Porcelain v1 is exactly 2 status chars + 1 space + path, so cut -c4- is safe.
SRC_DIRTY=$(git status --porcelain 2>/dev/null | cut -c4- | grep -v '^\.claude/state/' || true)
if [ -n "$SRC_DIRTY" ]; then
  REASONS="$REASONS\n- Uncommitted changes outside .claude/state/. This is cloud-always mode: diagnose locally, then dispatch with cloud-fix-dispatch — do not edit source here. Revert these or dispatch them:\n$(printf '%s\n' "$SRC_DIRTY" | head -10)"
fi

# 4) Lint must be clean — but only bother when something actually changed.
#    Reuses the dirtiness signal above so there is one source of truth.
if [ -n "$SRC_DIRTY" ]; then
  LINTLOG=$(mktemp -t claude-unattended-lint.XXXXXX.log)
  if ! pnpm formatAndLint >"$LINTLOG" 2>&1; then
    REASONS="$REASONS\n- pnpm formatAndLint is failing. Tail:\n$(tail -n 30 "$LINTLOG")"
  fi
  rm -f "$LINTLOG"
fi

# 5) Cheap anti-gaming tripwires.
if git rev-parse HEAD >/dev/null 2>&1; then
  if git diff HEAD --name-status 2>/dev/null | grep -qE '^D[[:space:]].*(\.(test|spec)\.|__tests__/|/tests?/)'; then
    REASONS="$REASONS\n- A test file was DELETED. Restore it and make it pass."
  fi
  ADDED=$(git diff HEAD 2>/dev/null | grep -E '^\+' || true)
  if printf '%s\n' "$ADDED" | grep -qE '(\.skip\(|xit\(|xdescribe\(|describe\.skip|it\.skip|pending\()'; then
    REASONS="$REASONS\n- A test was skipped. Skipping tests games the gate."
  fi
  if printf '%s\n' "$ADDED" | grep -qiE 'console\.(log|info)\([^)]*PASS'; then
    REASONS="$REASONS\n- A literal PASS print was added."
  fi
fi

# 6) Final gate: every row PASS must be backed by real browser evidence against a
#    real deployment. Without this the loop can mark everything PASS having never
#    left localhost — which is the failure this whole design exists to prevent.
if [ "$TOTAL" -gt 0 ] 2>/dev/null && [ "$MID" -eq 0 ] && [ "$PASS" -eq "$TOTAL" ]; then
  if ! grep -qE 'https://[a-z0-9.-]*vercel\.app' "$LEDGER" 2>/dev/null; then
    REASONS="$REASONS\n- Every row is PASS but the ledger contains no preview URL. The contract row must record the deployed URL that was exercised, plus its evidence. If the flow was genuinely unreachable, say so explicitly in the row — do not mark it PASS."
  fi
fi

if [ -n "$REASONS" ]; then
  N=$(cat "$BLOCKS" 2>/dev/null || echo 0); echo $((N + 1)) > "$BLOCKS"
  printf 'unattended verification gate — cannot stop yet:%b\n' "$REASONS" 1>&2
  exit 2
fi

rm -f "$BLOCKS"
if [ "$TOTAL" -gt 0 ] 2>/dev/null && [ "$PASS" -eq "$TOTAL" ]; then
  echo '{"systemMessage":"unattended: all rows PASS with preview evidence recorded. Run teardown — remove .claude/state/unattended.json, hand off design docs, delete the plan file."}'
elif [ "$BLOCKED" -gt 0 ] 2>/dev/null; then
  echo '{"systemMessage":"unattended: stopping on a BLOCKED row. Confirm the question was pushed and one notification sent."}'
fi
exit 0
