#!/usr/bin/env bash
# picker.sh — fzf popup to pick how long to snooze the current Space.
# Opened by the `jeordin.snooze.snooze-picker` action.
#
# The list is a shortcut, not a menu: anything you type that fzf does not
# match is taken as the duration itself, so "1m", "90m" or "thu 9am" work
# without being on it. That is why this does not use the vim NORMAL-mode
# bindings herdr-agent-picker has — j/k have to type here, not navigate.
# Arrows and ctrl-n/ctrl-p move; Esc aborts.
set -euo pipefail

# Popups may launch with a minimal env; make sure the tools are findable.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exported for the header preview below, which fzf runs in its own shell on
# every keystroke and so cannot see this script's variables.
export SNOOZE_PY="$here/snooze.py"
export SNOOZE_HELP='type any duration: 45m · 2h · 3d · 1w · 9am · thu 9am'

# Handed over by cmd_open_picker: a popup is a session singleton with no
# workspace context of its own, so it cannot work these out for itself.
ws="${HERDR_SNOOZE_WS:-}"
label="${HERDR_SNOOZE_LABEL:-this Space}"
current="${HERDR_SNOOZE_CURRENT:-}"   # non-empty when already snoozed

# A bad entry reopens the picker rather than closing it. Typing a stray key
# used to end the popup on a Python traceback, which meant starting over.
retry() {
  printf '\033[1;38;2;255;93;98m%s\033[0m\n' "$1"
  printf '\033[38;2;114;113;105mpress any key to try again\033[0m'
  read -r -n1 _
}

while true; do

# fzf exits non-zero when the query matches nothing, but --print-query still
# emits the query, which is exactly the free-form case. Esc gives an empty
# query and no selection, which is how abort is told apart from it.
out=$(
  {
    # Waking leads when the Space is already asleep, so prefix+z cancels as
    # easily as it snoozes.
    [ -n "$current" ] && printf 'wake\tWake now (%s left)\n' "$current"
    printf '15m\t15 minutes\n'
    printf '30m\t30 minutes\n'
    printf '1h\t1 hour\n'
    printf '2h\t2 hours\n'
    printf '4h\t4 hours\n'
    printf 'tomorrow 9am\ttomorrow morning\n'
    printf 'mon 9am\tMonday morning\n'
    printf '3d\t3 days\n'
    printf '1w\t1 week\n'
  } | awk -F'\t' '
      BEGIN {
        E   = "\033[0m"
        DIM = "\033[38;2;114;113;105m"   # fujiGray
        FG  = "\033[38;2;220;215;186m"   # fujiWhite
      }
      { printf "%s\t%s%-14s%s %s%s%s\n", $1, FG, $1, E, DIM, $2, E }
    ' \
    | fzf --ansi --print-query --exact \
          --delimiter='\t' --with-nth=2 \
          --height=100% --layout=reverse --info=inline \
          --prompt="${current:+[asleep, $current left] }snooze $label for " \
          --header="$SNOOZE_HELP" \
          --bind='start,change,focus:transform-header(printf "%s\n" "$SNOOZE_HELP"; python3 "$SNOOZE_PY" when {q} {1})' \
          --pointer='▸' \
          --bind='esc:abort' \
          --no-mouse
) || true

query=$(printf '%s\n' "$out" | sed -n 1p)
choice=$(printf '%s\n' "$out" | sed -n 2p | cut -f1)

# What you typed wins whenever it is already a valid duration. Otherwise a
# list match would hijack it: "1m" still matches the "15m" row on a substring
# search, and silently snoozing for 15 minutes when 1 was asked for is worse
# than ignoring the list.
sel="$choice"
if [ -n "$query" ] && python3 "$here/snooze.py" check "$query" 2>/dev/null; then
  sel="$query"
fi
sel="${sel:-$query}"
[ -n "$sel" ] || exit 0

# Waking is its own command, not a duration. Without this branch "wake" falls
# through to the duration parser and dies there.
if [ "$sel" = "wake" ]; then
  if ! out=$(python3 "$here/snooze.py" wake ${ws:+"$ws"} 2>&1); then
    retry "$out"; continue
  fi
  exit 0
fi

if ! out=$(python3 "$here/snooze.py" snooze "$sel" ${ws:+"$ws"} 2>&1); then
  retry "$out"; continue
fi
exit 0

done
