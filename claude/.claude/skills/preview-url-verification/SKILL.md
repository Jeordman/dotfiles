---
name: preview-url-verification
description: Verify a feature in a real browser against a deployed Vercel preview URL rather than localhost — resolve a pushed commit to its preview deployment, drive the flow with Playwright, and triage failures into build-broke / feature-broke / pre-existing-flake. Use when verifying a branch that has been pushed and deployed, when a Verification Contract needs executing, when deciding whether a preview deployment is ready to test, or when a preview URL returns something unexpected. Not for localhost verification — that is verifying-changes.
---

# Verifying against a deployed preview URL

Localhost verification and preview verification are not the same job. On a preview you have no dev server, no HMR, no dev console, and every fix costs a full redeploy. What you gain is a real production **build** — minified, bundled, with the middleware and CSP that only exist in a built app.

What you do *not* get is a production **environment**. Preview env vars are a subset of production's, and some resolve to `undefined` rather than being absent cleanly — which shows up as console errors that look like bugs and are not. Production code paths, not production config. Budget for that difference instead of being surprised by it.

Every mechanic below was verified against `Unicity/new-shop` on 2026-07-25, and re-verified end-to-end against a live deployment on 2026-07-26.

## 1. Resolve the commit to a deployment — never trust the branch alias alone

The per-branch alias (`shop2-git-<branch>-unicity.vercel.app`) always serves the **newest** build for that branch. Right after a push it still serves the previous commit, so testing the alias without checking which commit is live will silently verify the wrong code and report a false pass.

Wait for the specific SHA using `deploy-watch`, which polls GitHub commit statuses because they are SHA-exact:

```bash
deploy-watch -s "$(git rev-parse HEAD)"   # 0 ready · 2 failed · 3 timeout · 4 not pushed
```

Two gotchas encoded in that script, both of which bite if you hand-roll it:

- **Five Vercel projects post a status per commit** — `shop2`, `shop-api`, `shop2-storybook`, `new-shop-enroll`, `new-shop-design-previews`. Matching any context called "Vercel" gives false readiness from a sibling project. The storefront is `shop2`.
- That context name contains an **en dash** (`Vercel – shop2`), not a hyphen.

Then resolve the actual URL with the Vercel MCP, matching `meta.githubCommitSha` to the commit you pushed:

```
mcp__claude_ai_Vercel__list_deployments  teamId=team_FuPVIgn0t46z9XzLhxVNbZlo  projectId=shop2
→ pick the entry whose meta.githubCommitSha == your SHA
→ use meta.branchAlias (stable across redeploys) or .url (that exact build)
```

Prefer `.url` when you need certainty about which build you are on, and `branchAlias` when you are looping over fixes and want a stable target.

**Cheaper path — skip `list_deployments` entirely.** The commit status you already polled carries the deployment ID in its `target_url`, so you can go straight to one lookup, and it is SHA-exact by construction because the status hangs off the commit:

```bash
gh api repos/Unicity/new-shop/commits/<SHA>/status \
  | jq -r '.statuses[] | select(.context == "Vercel – shop2") | .target_url'
# → https://vercel.com/unicity/shop2/GJ5yjeJUUP1qEbXNEtMnKFDm2Et1
#                                    └─ deployment ID; prefix it with dpl_
```

```
mcp__claude_ai_Vercel__get_deployment  idOrUrl=dpl_GJ5yjeJUUP1qEbXNEtMnKFDm2Et1  teamId=unicity
→ state, .url (immutable, that exact build), meta.branchAlias, meta.githubCommitSha
```

`teamId` accepts the slug `unicity`, so you do not need the `team_…` id. Confirm `meta.githubCommitSha` starts with your SHA before trusting anything on the page.

**Never derive the alias from the branch name.** Vercel's slug rule is not a simple `/`→`-` substitution, and a derived URL 404s silently. Two real cases from this project:

| Branch | Actual alias fragment |
|---|---|
| `fix/ECOM-6301/mixpanel-bot-blocklist` | `fix-ecom-6301mixpanel-bot-blocklist` — the second `/` disappears rather than becoming a dash |
| `feat/ECOM-6482-buy-now-use-applepay-builder-floating` | `feat-ecom-6482-buy-now-use-applepay-bu-ff1586` — truncated near 48 chars, then hashed |

Long ticket branches are exactly the ones that break, so always read `meta.branchAlias` from the API.

## 2. Reaching the page

- The **raw `*.vercel.app` host is directly reachable** — no Cloudflare Access wall, no login gate. Verified.
- The root **307-redirects to a localised path** (`/` → `/usa/en/products`). A 307 is healthy, not a failure.
- Pre-launch or dev-gated markets need `?enableExperimental=true` on the URL.
- Bash inside the sandbox reaches `*.vercel.app` only if the domain is in `sandbox.network.allowedDomains`. Client-side calls the *browser* makes (Hydra, Cosmic, LaunchDarkly, Mixpanel) are not covered by that allowlist, so a page can render while its data calls fail. Check the network panel before concluding the feature is broken.

## 3. Execute the Verification Contract, not a vibe check

A contract is route, market, locale, auth state, the flow to walk, what "working" looks like, and what must not regress. **Usually nobody hands you one** — the cloud dispatch is deliberately minimal and writes no plan file — so derive it yourself from the ticket and from the implementing commits' messages — `git log origin/<branch>` — which is where an unattended cloud run records its assumptions and anything it could not finish. There is no PR yet; that is opened after verification, not before. **Write the contract down before opening a browser**:

```markdown
Route:    /usa/en/shop/products/<slug>
Market:   USA · en · guest (no auth)
Flow:     land → select 90-day → add to cart → open cart → verify line total
Pass:     cart shows 2 line items, subtotal $XXX, no console errors beyond the baseline
Regress:  monthly option still selectable
Unreachable-if: catalog gate blocks guest access → report, never fake a pass
```

**Write it to the path the Stop gate is watching.** `claude-unattended` records that path in the run marker, and the gate refuses to let the session end until the file exists and every `PASS` is backed by a preview URL:

```bash
jq -r .ledger .claude/state/unattended.json   # default: .claude/state/verification-<branch>.md
```

The gate parses rows in exactly this shape — `N | STATUS | anything`, one per assertion:

```markdown
Route:   /usa/en/shop/products/<slug>
Market:  USA · en · guest
Preview: https://shop2-e0drxza2w-unicity.vercel.app  (dpl_…, sha 5837931)

1 | PASS | 90-day option selectable
2 | PASS | cart shows 2 line items, subtotal $118.00
3 | FAIL | monthly option no longer selectable — regression
```

`STATUS` is one of `TODO DOING NEEDS-VERIFY PASS FAIL BLOCKED`. Anything mid-flight blocks the stop; so does all-`TODO` with nothing `BLOCKED`; so does every row `PASS` with no `vercel.app` URL anywhere in the file. **Unreachable is a row, not an omission.**

Writing it first is what makes the run falsifiable instead of a vibe check — a browser session with no stated pass condition will always conclude that things look fine. Answer it line by line, and capture for each assertion:

- a snapshot or an explicit assertion on the rendered result
- console messages
- network failures

Close the browser when done (`browser_close`) — an unattended loop that leaks a browser per cycle degrades the machine over a night.

### The console baseline — never count these as findings

**A clean preview of untouched code logs console errors.** Verified 2026-07-26 against `merge-buynow-jul2526` (`5837931…`) on `/usa/en/products`, a commit with no relevant changes:

| Console output | Cause | Verdict |
|---|---|---|
| `cdn-cookieyes.com/client_data/`**`undefined`**`/script.js` → 403 | CookieYes site key is unset on preview, so the path interpolates the string `undefined` | environment — ignore |
| `vercel.live/_next-live/feedback/feedback.js` violates CSP `script-src` | Vercel injects its **own preview toolbar**; the app's CSP allowlists neither `vercel.live` nor `script-src-elem` | preview-only by construction — ignore |
| `[Meta pixel] … unavailable … traffic permission settings` | pixel domain allowlist excludes preview hosts | environment — ignore |
| `reCAPTCHA couldn't find user-provided function: onloadCallback` | benign load-order warning | ignore |

None of these can occur in production, and none are fixable from the branch.

So **`Pass: no console errors` is never a valid criterion here.** It fails on every run, and a loop told to satisfy it does one of two bad things: patches a non-bug across three deploy cycles and burns the budget, or concludes the console is noise and stops reading it — missing the real error later.

Write the criterion as **"no console errors beyond the baseline above"** and treat any *other* error as a genuine finding. When you cannot tell whether something is baseline, load the same route on the **base branch's** deployment and diff the console. That is the only reliable answer and it costs one navigation.

## 4. Triage — three different failures that look alike

| Symptom | Likely cause | Action |
|---|---|---|
| `deploy-watch` exits 2 | build broke | Read build logs via `get_deployment_build_logs`. This is a code fix, not a test fix. |
| Page renders, feature absent or wrong | the change itself | The only case that means what it appears to mean — **dispatch it** (below), do not fix it here. |
| Page errors in a way unrelated to the change | pre-existing flake or upstream | Compare against the same flow on the base branch's deployment before touching anything. |
| Page renders, data missing | client-side host unreachable, or QA data | Check network panel and whether the market/account actually has the data. |

Runtime failures after a successful build come from `get_runtime_logs` / `get_runtime_errors`, not from the build logs.

### Dispatching a fix — the cloud-always loop

You have the browser; the cloud has only the code. So **you** own the diagnosis and the cloud owns the typing. A findings file that says "cart total is wrong" forces a fresh session to re-derive the cause blind, which is the one thing it cannot do — name the root cause and the `file:line`:

```markdown
## Finding 1 — subtotal ignores the 90-day discount
Root cause: apps/shop/src/lib/pricing/resolve-line-total.ts:48 applies the
  discount to unitPrice but the cart reads priceEach, which is set earlier at :31.
Change: read the discounted value in the cart selector, or set priceEach at :31.
Evidence: /usa/en/... → cart showed $138.00, expected $118.00. No console errors
  beyond baseline. Network: /pricingData 200, correct discount in the payload.
Re-verify: land → select 90-day → add to cart → subtotal reads $118.00
```

Then run the loop. Each step's exit code gates the next, so a failure stops the chain instead of verifying stale code:

```bash
cloud-fix-dispatch .claude/state/findings-<branch>.md
NEW=$(wait-for-push -s "$(jq -r .baseline .claude/state/cloud-fix-<branch>.json)") \
  && deploy-watch -s "$NEW" \
  && echo "re-verify against the new deployment"
```

`cloud-fix-dispatch` commits the findings before dispatching (`-f`, since `.claude/state/` is gitignored) because the VM clones from GitHub and cannot see your disk. It re-reads the baseline *after* that push, so `wait-for-push` waits for the cloud's commit rather than returning instantly on your own.

If `wait-for-push` times out, the cloud session most likely never ran — check the session URL in the Claude UI rather than assuming it is still working. Record that as a `BLOCKED` row; it is not a `FAIL` of the feature.

## 5. Rules that keep the verdict honest

- **Never report a pass for a flow you could not reach.** A gated market, a missing test account, or a 404 is "unreachable" and must be said plainly. An unattended loop that converts unreachable into pass is worse than one that stops.
- **Never edit source here.** This is cloud-always: you diagnose, the cloud implements. The Stop gate blocks on any uncommitted change outside `.claude/state/`, so a local "quick fix" cannot reach the deployed branch anyway.
- **Batch findings.** Each round trip costs ~8–12 minutes (cold clone + install + fix + a ~3.2 min Vercel build), so finish exercising the whole contract and dispatch everything you found at once. Trickling one finding per dispatch is the single most expensive mistake available here.
- **Cap the cycles.** Three round trips, then stop and report — that is already a ~30 minute ceiling. If two attempts at the same root cause fail, stop and write a BLOCKED row; do not keep dispatching.
- A passing agentic run is evidence, not a regression test. If the flow is worth protecting permanently, land a `@smoke`-tagged spec driven by `NEXT_PUBLIC_BASE_URL`, which the existing `vercel.deployment.success` workflow already runs on every preview deploy.
