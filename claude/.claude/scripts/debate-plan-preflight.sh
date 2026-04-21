#!/usr/bin/env bash
# /debate-plan pre-flight usage check.
# Warns if Claude or Codex usage is above 60% for the current window.
# Warning only — does not abort. User can Ctrl+C during the 5s pause.

set -u

echo "=== /debate-plan pre-flight ==="

claude_5h="unknown"
claude_7d="unknown"
cache="${HOME}/.claude/usage-cache.json"
if [[ -f "$cache" ]]; then
  age=$(( $(date +%s) - $(jq -r '.updated_at // 0' "$cache" 2>/dev/null || echo 0) ))
  if (( age < 600 )); then
    raw_5h=$(jq -r '.five_hour_pct // ""' "$cache" 2>/dev/null)
    raw_7d=$(jq -r '.seven_day_pct // ""' "$cache" 2>/dev/null)
    [[ "$raw_5h" =~ ^[0-9]+(\.[0-9]+)?$ ]] && claude_5h=$(printf '%.0f' "$raw_5h")
    [[ "$raw_7d" =~ ^[0-9]+(\.[0-9]+)?$ ]] && claude_7d=$(printf '%.0f' "$raw_7d")
  fi
fi

codex_5h="unknown"
codex_7d="unknown"
read codex_5h codex_7d < <(python3 <<'PY' 2>/dev/null || echo "unknown unknown"
import json, os, glob
pattern = os.path.expanduser('~/.codex/sessions/**/rollout-*.jsonl')
files = sorted(glob.glob(pattern, recursive=True), key=os.path.getmtime, reverse=True)
latest = None
for fp in files[:5]:
    try:
        with open(fp) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    rl = entry.get('payload', {}).get('rate_limits')
                    if rl and rl.get('primary'):
                        ts = entry.get('timestamp', '')
                        if not latest or ts > latest[0]:
                            latest = (ts, rl)
                except Exception:
                    pass
    except Exception:
        pass
if latest:
    _, rl = latest
    p = rl.get('primary', {}).get('used_percent', 'unknown')
    s = rl.get('secondary', {}).get('used_percent', 'unknown')
    p_out = f"{int(round(float(p)))}" if isinstance(p, (int, float)) else "unknown"
    s_out = f"{int(round(float(s)))}" if isinstance(s, (int, float)) else "unknown"
    print(f"{p_out} {s_out}")
else:
    print("unknown unknown")
PY
)

echo "Claude 5hr usage: ${claude_5h}%  |  7-day: ${claude_7d}%"
echo "Codex  5hr usage: ${codex_5h}%  |  7-day: ${codex_7d}%"

warn=0
for p in "$claude_5h" "$claude_7d" "$codex_5h" "$codex_7d"; do
  if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 60 )); then warn=1; fi
done

if (( warn )); then
  echo ""
  echo "WARNING: one or more usage metrics above 60% for the current window."
  echo "/debate-plan may make up to 4 Codex calls + several Claude calls (2-4 min)."
  echo "Press Ctrl+C within 5s to abort, otherwise continuing..."
  sleep 5
fi

echo "=== pre-flight done ==="
