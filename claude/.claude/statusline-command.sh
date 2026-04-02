#!/usr/bin/env bash
# Claude Code status line
# Shows: model | context bar + % | rate limit

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

ESC=$'\033'
DIM="${ESC}[2m"
RED="${ESC}[0;31m"
GRN="${ESC}[0;32m"
RST="${ESC}[0m"

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

  printf "%s" "${DIM}${model}${RST} ${sep} ${ctx_color}context ${ctx_pct}% ${bar}${RST}${rate_str}"
else
  printf "%s" "${DIM}${model}${RST} ${sep} ${DIM}context 0% ░░░░░░░░░░${RST}"
fi
