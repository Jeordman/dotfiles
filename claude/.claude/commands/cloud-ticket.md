# /cloud-ticket

Hand a ticket to a cloud session. **Dispatch only — no planning, no approval step.** Invoking this IS the consent.

## Arguments

`$ARGUMENTS` — a ticket ID (e.g. `ECOM-1234`). If empty, ask which ticket; that is the one question allowed here.

## What to do

Run it. That is the entire command:

```bash
cloud-ticket-dispatch $ARGUMENTS
```

Do not read the ticket first, do not research the codebase, do not write a plan. The cloud session clones the repo and reads ClickUp itself, and the steering prompt is already inside the script. Local research would spend this session's context to brief a session that can do it unsupervised — that was the original design and it was dropped for exactly this reason.

Do not try to call `claude --cloud` yourself: it refuses without a TTY and would silently run *locally* instead. The script wraps it in a pty.

The script refuses to run on a protected branch, and proves the branch reached the remote before dispatching — `--cloud` clones from GitHub, so an unpushed branch would give the VM stale code. Let those checks fail loudly rather than working around them; the fix is `gtrc <TICKET>` to get a proper worktree.

## Then report, briefly

- The printed session URL — **the run is managed there or in the mobile app.** Cloud sessions are invisible from the terminal: no status, no transcript, no output.
- A native notification arrives when it finishes.
- Verification is local and comes later: `deploy-watch -s <sha>` to gate on the build, then `claude-unattended` to drive the browser against the preview URL. See the `preview-url-verification` skill.
