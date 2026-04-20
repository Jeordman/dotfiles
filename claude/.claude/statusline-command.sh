#!/usr/bin/env bash
# Claude Code status line
# Shows: model | context bar + % | rate limit

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rate_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_7d_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

effort=""
for f in "${cwd}/.claude/settings.local.json" "${cwd}/.claude/settings.json" "${HOME}/.claude/settings.json"; do
  if [ -n "$f" ] && [ -f "$f" ]; then
    val=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
    if [ -n "$val" ]; then
      effort="$val"
      break
    fi
  fi
done

ESC=$'\033'
DIM="${ESC}[2m"
RED="${ESC}[0;31m"
YLW="${ESC}[0;33m"
GRN="${ESC}[0;32m"
CYN="${ESC}[0;36m"
MAG="${ESC}[0;35m"
BLU="${ESC}[0;34m"
RST="${ESC}[0m"

# Claude intelligence-level palette (truecolor, matches Claude UI)
CC_LOW="${ESC}[38;2;230;160;70m"     # amber
CC_MED="${ESC}[38;2;120;200;110m"    # green
CC_HIGH="${ESC}[38;2;150;165;240m"   # periwinkle
CC_XHIGH="${ESC}[38;2;170;110;245m"  # violet
CC_MAX="${ESC}[38;2;255;110;95m"     # coral

model_lc=$(echo "$model" | tr '[:upper:]' '[:lower:]')
case "$model_lc" in
  *opus*)   model_color="${RED}" ;;
  *sonnet*) model_color="${BLU}" ;;
  *haiku*)  model_color="${GRN}" ;;
  *)        model_color="${DIM}" ;;
esac

build_bar() {
  local pct="$1"
  local filled
  filled=$(echo "$pct" | awk '{printf "%d", ($1 / 10) + 0.5}')
  [ "$filled" -gt 10 ] && filled=10
  local empty=$((10 - filled))
  local bar=""
  for i in $(seq 1 "$filled"); do bar="${bar}█"; done
  for i in $(seq 1 "$empty"); do bar="${bar}░"; done
  printf "%s" "$bar"
}

sep="${DIM}|${RST}"

if [ -n "$used_pct" ]; then
  ctx_pct=$(printf '%.0f' "$used_pct")
  bar=$(build_bar "$ctx_pct")

  if [ "$ctx_pct" -ge 50 ]; then
    ctx_color="${RED}"
  else
    ctx_color="${GRN}"
  fi

  rate_str=""
  if [ -n "$rate_5h" ]; then
    rate_pct=$(printf '%.0f' "$rate_5h")
    if [ "$rate_pct" -ge 50 ]; then
      rate_color="${RED}"
    else
      rate_color="${GRN}"
    fi
    reset_str=""
    if [ -n "$rate_resets" ]; then
      reset_time=$(date -r "$rate_resets" +"%I:%M%p" | tr '[:upper:]' '[:lower:]')
      reset_str=" resets ${reset_time}"
    fi
    rate_str=" ${sep} ${rate_color}usage ${rate_pct}%${DIM}${reset_str}${RST}"
  fi

  weekly_str=""
  if [ -n "$rate_7d" ]; then
    week_pct=$(printf '%.0f' "$rate_7d")
    if [ "$week_pct" -ge 80 ]; then
      week_color="${RED}"
    elif [ "$week_pct" -ge 50 ]; then
      week_color="${YLW}"
    else
      week_color="${GRN}"
    fi
    week_reset_str=""
    if [ -n "$rate_7d_resets" ]; then
      week_reset_time=$(date -r "$rate_7d_resets" +"%b %d" 2>/dev/null)
      [ -n "$week_reset_time" ] && week_reset_str=" resets ${week_reset_time}"
    fi
    weekly_str=" ${sep} ${week_color}week ${week_pct}%${DIM}${week_reset_str}${RST}"
  fi

  effort_str=""
  if [ -n "$effort" ]; then
    case "$effort" in
      max)      effort_color="${CC_MAX}" ;;
      xhigh)    effort_color="${CC_XHIGH}" ;;
      high)     effort_color="${CC_HIGH}" ;;
      medium)   effort_color="${CC_MED}" ;;
      low)      effort_color="${CC_LOW}" ;;
      none|off) effort_color="${DIM}" ;;
      *)        effort_color="${DIM}" ;;
    esac
    effort_str=" ${sep} ${effort_color}effort ${effort}${RST}"
  fi

  printf "%s" "${model_color}${model}${RST} ${sep} ${ctx_color}context ${ctx_pct}% ${bar}${RST}${rate_str}${weekly_str}${effort_str}"
else
  effort_str=""
  if [ -n "$effort" ]; then
    effort_str=" ${sep} ${DIM}effort ${effort}${RST}"
  fi
  printf "%s" "${model_color}${model}${RST} ${sep} ${DIM}context 0% ░░░░░░░░░░${RST}${effort_str}"
fi
