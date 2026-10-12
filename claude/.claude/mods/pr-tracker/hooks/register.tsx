import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Hidden, Row, Snapshot, Stage, Tab } from '../types'
import { URGENCY, age, classifyOpen, cleanTitle, daysAgo, parseTeam, releaseName } from './track'
import type { OpenPr } from './track'

const REPO = 'Unicity/new-shop'
const VERCEL_SERVER = 'claude.ai Vercel'
const VERCEL_TEAM = 'team_FuPVIgn0t46z9XzLhxVNbZlo'
const VERCEL_SCOPE = 'unicity'
const VERCEL_PROJECT = 'shop2'
const GITHUB_PRODUCTION = 'Production – shop2'
const OPEN_DAYS = 14
const MERGED_DAYS = 30
const LIVE_SHOWN_MS = 24 * 60 * 60 * 1000
const POLL_MS = 5 * 60 * 1000
// Another session's snapshot younger than this is reused instead of refetched
const SHARED_FRESH_MS = POLL_MS - 30 * 1000
// A missing or logged-out Vercel CLI is retried this often, not every poll
const VERCEL_CLI_RETRY_MS = 60 * 60 * 1000
const MAX_TOASTS = 3
const PANE = 'prs'
// Bump when Snapshot changes shape, so a snapshot an older version saved is refetched
const SNAPSHOT_VERSION = 2
// Docked right beside the fullscreen transcript, about this many columns wide
const PANE_ARGS = { id: PANE, title: 'PRs', columns: 40 }

// Coworkers on the Team tab, by GitHub login, in the order listed. Read at
// session start from PR_TRACKER_TEAM (`login:Name,login:Name`), which lives in
// ~/.zshrc.local so coworkers' handles stay out of this public repo
let TEAM: Record<string, string> = {}

type MergedPr = {
  number: number
  title: string
  url: string
  headRefName: string
  mergedAt: string
  author?: { login: string }
  mergeCommit: { oid: string } | null
}

type ReleasePr = { title: string; mergedAt: string; mergeCommit: { oid: string } | null; headRefName: string }

type Deploy = { id: string; sha: string }

type Rollout =
  | { state: 'ACTIVE' | 'ABORTED'; pct: number | null; canarySha: string; baseSha: string }
  | { state: 'COMPLETE' | 'NONE'; liveSha: string }

// Facts that never change once true: commits inside a ref, when a PR went
// live (0: already live when first seen), which release carried a PR
type Memory = {
  included: Record<string, true>
  liveAt: Record<string, number>
  releaseOf: Record<string, string>
}

const snapshot = atom({ plugin: 'pr-tracker', key: 'snapshot' } as const, null)
const tab = atom({ plugin: 'pr-tracker', key: 'tab' } as const, 'mine' as Tab)
const hidden = atom({ plugin: 'pr-tracker', key: 'hidden' } as const, {} as Hidden)
const showHidden = atom({ plugin: 'pr-tracker', key: 'showHidden' } as const, false)

// Your palette: herdr's status colors and the softened catppuccin accents in
// nvim (colorschemes/catppuccin.lua), on herdr's neutral grays
const PALETTE = {
  red: '#FF5D62', // herdr blocked
  attention: '#E6C384', // herdr idle / main-branch caution (carpYellow)
  working: '#8A8A8A', // herdr working
  done: '#98BB6C', // herdr done
  green: '#A4CCA1', // catppuccin green, softened
  mauve: '#C0A6DE', // catppuccin mauve, softened
  blue: '#91ADDB', // catppuccin blue, softened
  subtext: '#909090',
  overlay: '#767676',
  faint: '#5A5A5A',
}

const STYLE: Record<Stage, { color: string; dot: string }> = {
  failing: { color: PALETTE.red, dot: '●' },
  aborted: { color: PALETTE.red, dot: '●' },
  conflicts: { color: PALETTE.attention, dot: '●' },
  building: { color: PALETTE.working, dot: '◌' },
  blocked: { color: PALETTE.overlay, dot: '○' },
  draft: { color: PALETTE.faint, dot: '○' },
  ready: { color: PALETTE.green, dot: '●' },
  release: { color: PALETTE.mauve, dot: '●' },
  master: { color: PALETTE.blue, dot: '◐' },
  rolling: { color: PALETTE.blue, dot: '◑' },
  live: { color: PALETTE.done, dot: '✓' },
}

const SECTIONS: { title: string; stages: Stage[] }[] = [
  { title: 'Open', stages: ['failing', 'conflicts', 'building', 'blocked', 'ready', 'draft'] },
  { title: 'In release', stages: ['release'] },
  { title: 'Shipping', stages: ['master', 'rolling', 'aborted'] },
  { title: 'Live today', stages: ['live'] },
]

const OPEN_STAGES = new Set<Stage>(['failing', 'conflicts', 'building', 'blocked', 'ready', 'draft'])

// Changes worth a toast when a PR moves into them
const ANNOUNCE: Partial<Record<Stage, string>> = {
  failing: 'build failed',
  ready: 'ready to merge',
  aborted: 'rollout aborted',
  live: 'is live at 100%',
}

let isRefreshing = false
let vercelCliRetryAt = 0
// GitHub deployment id → whether it succeeded, once it is final
const githubDeployOk = new Map<string, boolean>()

async function gh($: EngineInterface, args: string[]): Promise<string> {
  const { exitCode, stdout, stderr } = await $.process.run(['gh', ...args], { timeoutMs: 30_000 })
  if (exitCode !== 0) {
    throw new Error(`gh ${args[0]}: ${stderr.trim().split('\n')[0] || `exit ${exitCode}`}`)
  }

  return stdout
}

// Whether `sha` is already inside `ref` (a branch or a commit). A yes never
// turns back into a no, so yeses are remembered across polls and sessions.
async function contains($: EngineInterface, memory: Memory, ref: string, sha: string): Promise<boolean> {
  const key = `${ref}|${sha}`
  if (ref === sha || memory.included[key]) {
    return true
  }

  const status = (await gh($, ['api', `repos/${REPO}/compare/${ref}...${sha}`, '--jq', '.status'])).trim()
  const isIn = status === 'behind' || status === 'identical'
  if (isIn) {
    memory.included[key] = true
  }

  return isIn
}

async function vercelDeploys($: EngineInterface): Promise<Deploy[]> {
  const result = await $.mcp.call(VERCEL_SERVER, 'list_deployments', {
    projectId: VERCEL_PROJECT,
    teamId: VERCEL_TEAM,
    target: 'production',
    state: 'READY',
    limit: 10,
  })
  const text = result.content.find(block => block.type === 'text')?.text
  if (result.isError || !text) {
    throw new Error(text?.slice(0, 120) || 'no deployments returned')
  }

  const parsed = JSON.parse(text)
  const list: any[] = parsed?.result?.deployments?.deployments ?? parsed?.deployments?.deployments ?? []

  return list
    .map(d => ({ id: String(d.id), sha: String(d.meta?.githubCommitSha ?? '') }))
    .filter(d => d.sha)
}

// Vercel reports each production deploy to GitHub too: the fallback source
async function githubDeploys($: EngineInterface): Promise<Deploy[]> {
  const environment = encodeURIComponent(GITHUB_PRODUCTION)
  const listed = JSON.parse(
    await gh($, ['api', `repos/${REPO}/deployments?environment=${environment}&per_page=8`, '--jq', '[.[] | {id, sha}]']),
  ) as { id: number; sha: string }[]

  const deploys: Deploy[] = []
  for (const { id, sha } of listed) {
    if (deploys.length >= 3) {
      break
    }

    let isOk = githubDeployOk.get(String(id))
    if (isOk === undefined) {
      const state = (
        await gh($, ['api', `repos/${REPO}/deployments/${id}/statuses?per_page=1`, '--jq', '.[0].state // ""'])
      ).trim()
      // GitHub marks a superseded successful deploy inactive
      if (state === 'success' || state === 'inactive') {
        isOk = true
      } else if (state === 'failure' || state === 'error') {
        isOk = false
      }
      if (isOk !== undefined) {
        githubDeployOk.set(String(id), isOk)
      }
    }
    if (isOk) {
      deploys.push({ id: String(id), sha })
    }
  }

  return deploys
}

// The live percentage is only exposed by the Vercel CLI (the connector 404s)
async function rollingRelease($: EngineInterface, now: number, deploys: Deploy[]): Promise<Rollout | null> {
  if (now < vercelCliRetryAt) {
    return null
  }

  try {
    const { exitCode, stdout } = await $.process.run(
      ['vercel', 'rolling-release', 'fetch', `--project=${VERCEL_PROJECT}`, `--scope=${VERCEL_SCOPE}`],
      { timeoutMs: 20_000, stdin: '' },
    )
    const start = stdout.indexOf('{')
    if (exitCode !== 0 || start === -1) {
      throw new Error('vercel CLI unavailable')
    }

    const json = JSON.parse(stdout.slice(start))
    const rr = json.rollingRelease === undefined ? json : json.rollingRelease
    const shaOf = (id: unknown) => deploys.find(d => d.id === id)?.sha ?? ''

    if (!rr?.state) {
      return { state: 'NONE', liveSha: deploys[0]?.sha ?? '' }
    }
    if (rr.state === 'COMPLETE') {
      return { state: 'COMPLETE', liveSha: shaOf(rr.canaryDeployment?.id) || (deploys[0]?.sha ?? '') }
    }

    const pct = rr.currentCanaryPercentage ?? rr.activeStage?.targetPercentage

    return {
      state: rr.state === 'ABORTED' ? 'ABORTED' : 'ACTIVE',
      pct: typeof pct === 'number' ? pct : null,
      canarySha: shaOf(rr.canaryDeployment?.id),
      baseSha: shaOf(rr.currentDeployment?.id),
    }
  } catch {
    vercelCliRetryAt = now + VERCEL_CLI_RETRY_MS

    return null
  }
}

// Which release (`release 2.6.0`) first carried the PR into master
async function releaseOf($: EngineInterface, memory: Memory, pr: MergedPr, releases: ReleasePr[]): Promise<string> {
  const known = memory.releaseOf[pr.number]
  if (known !== undefined) {
    return known
  }

  for (const release of releases) {
    if (release.mergedAt < pr.mergedAt || !release.mergeCommit) {
      continue
    }
    if (await contains($, memory, release.mergeCommit.oid, pr.mergeCommit!.oid)) {
      const name = releaseName(release.title)
      memory.releaseOf[pr.number] = name

      return name
    }
  }

  return ''
}

async function shippedStage(
  $: EngineInterface,
  memory: Memory,
  sha: string,
  deploys: Deploy[] | null,
  rollout: Rollout | null,
): Promise<{ stage: Stage; label: string }> {
  if (!(await contains($, memory, 'master', sha))) {
    return { stage: 'release', label: 'waiting for release' }
  }

  const pending = { stage: 'master' as Stage, label: 'in master' }
  if (!deploys || deploys.length === 0) {
    return pending
  }

  if (rollout?.state === 'ACTIVE' || rollout?.state === 'ABORTED') {
    if (rollout.baseSha && (await contains($, memory, rollout.baseSha, sha))) {
      return { stage: 'live', label: 'live 100%' }
    }
    if (rollout.canarySha && (await contains($, memory, rollout.canarySha, sha))) {
      return rollout.state === 'ABORTED'
        ? { stage: 'aborted', label: 'rollout aborted' }
        : { stage: 'rolling', label: rollout.pct === null ? 'rolling out' : `rolling out ${rollout.pct}%` }
    }

    return pending
  }

  if (rollout && 'liveSha' in rollout) {
    return rollout.liveSha && (await contains($, memory, rollout.liveSha, sha))
      ? { stage: 'live', label: 'live 100%' }
      : pending
  }

  // No CLI: a newer production deploy means the one before it finished rolling out
  const [latest, previous] = deploys
  if (previous && (await contains($, memory, previous.sha, sha))) {
    return { stage: 'live', label: 'live 100%' }
  }
  if (latest && (await contains($, memory, latest.sha, sha))) {
    return { stage: 'rolling', label: 'rolling out' }
  }

  return pending
}

async function fetchSnapshot($: EngineInterface, now: number): Promise<Snapshot> {
  const memory: Memory = {
    included: ((await $.store.get('included')) as Memory['included'] | undefined) ?? {},
    liveAt: ((await $.store.get('liveAt')) as Memory['liveAt'] | undefined) ?? {},
    releaseOf: ((await $.store.get('releaseOf')) as Memory['releaseOf'] | undefined) ?? {},
  }
  // A PR counts as news when it goes live only if it was seen shipping first
  const previous = (await $.store.get('shared')) as Snapshot | undefined
  const wasShipping = new Set(previous?.rows.filter(row => row.stage !== 'live').map(row => row.number))

  const [openJson, mergedJson, releasesJson, teamOpenJson, teamMergedJson] = await Promise.all([
    gh($, [
      'pr', 'list', '-R', REPO, '--author', '@me', '--base', 'release', '--state', 'open',
      '--search', `updated:>=${daysAgo(now, OPEN_DAYS)}`, '--limit', '40',
      '--json', 'number,title,url,isDraft,mergeStateStatus,reviewDecision,headRefName,updatedAt,statusCheckRollup',
    ]),
    gh($, [
      'pr', 'list', '-R', REPO, '--author', '@me', '--base', 'release', '--state', 'merged',
      '--search', `merged:>=${daysAgo(now, MERGED_DAYS)}`, '--limit', '80',
      '--json', 'number,title,url,headRefName,mergedAt,mergeCommit',
    ]),
    gh($, [
      'pr', 'list', '-R', REPO, '--base', 'master', '--state', 'merged',
      '--search', `merged:>=${daysAgo(now, MERGED_DAYS)}`, '--limit', '40',
      '--json', 'title,mergedAt,mergeCommit,headRefName',
    ]),
    // Everyone's, filtered to the team below: GitHub ANDs repeated author filters
    gh($, [
      'pr', 'list', '-R', REPO, '--base', 'release', '--state', 'open',
      '--search', `updated:>=${daysAgo(now, OPEN_DAYS)}`, '--limit', '100',
      '--json', 'number,title,url,isDraft,mergeStateStatus,reviewDecision,headRefName,updatedAt,statusCheckRollup,author',
    ]),
    gh($, [
      'pr', 'list', '-R', REPO, '--base', 'release', '--state', 'merged',
      '--search', `merged:>=${daysAgo(now, MERGED_DAYS)}`, '--limit', '200',
      '--json', 'number,title,url,headRefName,mergedAt,mergeCommit,author',
    ]),
  ])
  // `release <- master` syncs are not anyone's work
  const open = (JSON.parse(openJson) as OpenPr[]).filter(pr => pr.headRefName !== 'master')
  const merged = (JSON.parse(mergedJson) as MergedPr[]).filter(pr => pr.headRefName !== 'master' && pr.mergeCommit)
  const releases = (JSON.parse(releasesJson) as ReleasePr[])
    .filter(pr => pr.headRefName === 'release')
    .sort((a, b) => a.mergedAt.localeCompare(b.mergedAt))

  let deploys: Deploy[] | null = null
  let rollout: Rollout | null = null
  let note = ''
  if (merged.some(pr => memory.liveAt[pr.number] === undefined)) {
    try {
      deploys = await vercelDeploys($)
    } catch (error) {
      note = `Vercel connector: ${error instanceof Error ? error.message : String(error)}; using GitHub deploys`
      deploys = await githubDeploys($).catch(() => null)
    }
    if (deploys) {
      rollout = await rollingRelease($, now, deploys)
      note = [note, rollout ? 'rollout % from the Vercel CLI' : 'exact rollout % needs the Vercel CLI']
        .filter(Boolean)
        .join(' · ')
    } else {
      note = 'no deploy info: tracking stops at master'
    }
  }

  const rows: Row[] = open.map(pr => ({
    number: pr.number,
    title: cleanTitle(pr.title),
    url: pr.url,
    branch: pr.headRefName,
    since: pr.updatedAt ?? '',
    ...classifyOpen(pr),
  }))

  for (const pr of merged) {
    const shipped =
      memory.liveAt[pr.number] === undefined
        ? await shippedStage($, memory, pr.mergeCommit!.oid, deploys, rollout)
        : { stage: 'live' as Stage, label: 'live 100%' }

    if (shipped.stage === 'live') {
      const liveAt = memory.liveAt[pr.number] ?? (wasShipping.has(pr.number) ? now : 0)
      memory.liveAt[pr.number] = liveAt
      if (now - liveAt > LIVE_SHOWN_MS) {
        continue
      }
    }

    const release = shipped.stage === 'release' ? '' : await releaseOf($, memory, pr, releases)
    rows.push({
      number: pr.number,
      title: cleanTitle(pr.title),
      url: pr.url,
      branch: pr.headRefName,
      since: pr.mergedAt,
      detail: release,
      ...shipped,
    })
  }

  rows.sort((a, b) => URGENCY.indexOf(a.stage) - URGENCY.indexOf(b.stage) || b.since.localeCompare(a.since))

  const isTeam = (login: string | undefined) => login !== undefined && TEAM[login] !== undefined
  const team: Row[] = (JSON.parse(teamOpenJson) as OpenPr[])
    .filter(pr => isTeam(pr.author?.login) && pr.headRefName !== 'master')
    .map(pr => ({
      number: pr.number,
      title: cleanTitle(pr.title),
      url: pr.url,
      branch: pr.headRefName,
      since: pr.updatedAt ?? '',
      author: pr.author?.login,
      ...classifyOpen(pr),
    }))
  const teamMerged = (JSON.parse(teamMergedJson) as MergedPr[]).filter(
    pr => isTeam(pr.author?.login) && pr.headRefName !== 'master' && pr.mergeCommit,
  )
  for (const pr of teamMerged) {
    if (await contains($, memory, 'master', pr.mergeCommit!.oid)) {
      continue
    }
    team.push({
      number: pr.number,
      title: cleanTitle(pr.title),
      url: pr.url,
      branch: pr.headRefName,
      since: pr.mergedAt,
      author: pr.author?.login,
      stage: 'release',
      label: 'waiting for release',
      detail: '',
    })
  }
  team.sort((a, b) => URGENCY.indexOf(a.stage) - URGENCY.indexOf(b.stage) || b.since.localeCompare(a.since))

  // Keep what is remembered bounded
  await $.store.set('included', Object.fromEntries(Object.entries(memory.included).slice(-800)))
  await $.store.set('liveAt', Object.fromEntries(Object.entries(memory.liveAt).slice(-300)))
  await $.store.set('releaseOf', Object.fromEntries(Object.entries(memory.releaseOf).slice(-300)))

  return { version: SNAPSHOT_VERSION, fetchedAt: now, rows, team, rollout: note, error: null }
}

async function refresh($: EngineInterface, isForced: boolean): Promise<void> {
  if (isRefreshing) {
    return
  }
  isRefreshing = true

  try {
    const now = await $.clock.now()
    const previous = await read($, snapshot)
    const shared = (await $.store.get('shared')) as Snapshot | undefined

    let next: Snapshot
    const isReusable =
      shared && shared.version === SNAPSHOT_VERSION && !shared.error && now - shared.fetchedAt < SHARED_FRESH_MS
    if (!isForced && isReusable) {
      next = shared
    } else {
      try {
        next = await fetchSnapshot($, now)
        await $.store.set('shared', next)
      } catch (error) {
        next = {
          version: SNAPSHOT_VERSION,
          fetchedAt: now,
          rows: previous?.rows ?? [],
          team: previous?.team ?? [],
          rollout: previous?.rollout ?? '',
          error: error instanceof Error ? error.message : String(error),
        }
      }
    }

    if (previous) {
      const before = new Map(previous.rows.map(row => [row.number, row.stage]))
      const news = next.rows.filter(row => {
        const was = before.get(row.number)

        return ANNOUNCE[row.stage] && was !== undefined && was !== row.stage
      })
      // A flood means the data changed shape, not that PRs moved
      if (news.length <= MAX_TOASTS) {
        for (const row of news) {
          $.ui.toast(`#${row.number} ${ANNOUNCE[row.stage]}: ${row.title}`)
        }
      }
    }

    await update($, snapshot, () => next)

    // Forget hidden PRs that left the lists for good (closed, released)
    const listed = new Set([...next.rows, ...(next.team ?? [])].map(row => String(row.number)))
    const all = await read($, hidden)
    if (Object.keys(all).some(number => !listed.has(number))) {
      const kept = Object.fromEntries(Object.entries(all).filter(([number]) => listed.has(number)))
      await update($, hidden, () => kept)
      await $.store.set('hidden', kept)
    }
  } finally {
    isRefreshing = false
  }
}

// Keeps the ages honest while something shows them
async function tick($: EngineInterface): Promise<void> {
  $.ui.invalidate('ui.render')
}

// The PR in the browser: the pane's rows are buttons, since a multiplexer
// may not pass terminal hyperlinks through
async function openPr($: EngineInterface, url: string): Promise<void> {
  await $.process.run(['open', url])
}

// A whole section at once, as browser tabs; capped so a slip opens a sane few
async function openPrs($: EngineInterface, urls: string[]): Promise<void> {
  await $.process.run(['open', ...urls.slice(0, 20)])
}

// Still hidden while the PR looks as it did when hidden (see Hidden)
function isHiddenRow(all: Hidden, row: Row): boolean {
  const entry = all[row.number]
  if (!entry) {
    return false
  }

  return OPEN_STAGES.has(row.stage) ? entry.since === row.since : entry.stage === row.stage
}

// Hides (or with `isHiding` false, brings back) a PR, kept across sessions
async function setHidden($: EngineInterface, row: Row, isHiding: boolean): Promise<void> {
  await update($, hidden, all => {
    const next = { ...all }
    if (isHiding) {
      next[row.number] = { since: row.since, stage: row.stage }
    } else {
      delete next[row.number]
    }

    return next
  })
  await $.store.set('hidden', await read($, hidden))
}

// Cut to `width` cells with an ellipsis, so a narrow pane stays one line a fact
function fit(text: string, width: number): string {
  const chars = Array.from(text)

  return chars.length <= width ? text : `${chars.slice(0, Math.max(1, width - 1)).join('')}…`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({
      name: 'prs',
      description: 'Show or hide the PR tracker docked on the right',
    })
    // Earlier versions drew a status line; clear any left behind
    $.ui.status(undefined)
    // Unasked, the engine seats it from 144 columns and waits below that
    void $.ui.open(PANE_ARGS)
    TEAM = parseTeam(await $.env.get('PR_TRACKER_TEAM'))
    const stored = ((await $.store.get('hidden')) as Hidden | undefined) ?? {}
    await update($, hidden, () => stored)
    void refresh($, false)
    $.clock.every(POLL_MS, () => void refresh($, false))
    $.clock.every(60 * 1000, () => void tick($))

    return started
  })

  on('command.run', { command: 'prs' }, async $ => {
    if ((await $.ui.panes()).some(pane => pane.id === PANE && pane.isPlaced)) {
      await $.ui.close({ id: PANE })
    } else {
      await $.ui.open(PANE_ARGS)
      void refresh($, true)
    }

    return {}
  })

  // Two lines a PR: what it is, then where it stands and since when
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const snap = await read($, snapshot)
    const now = await $.clock.now()
    const width = Math.max(20, e.props.bodyColumns - 2)

    if (!snap) {
      return <Text color={PALETTE.subtext}>Loading your PRs…</Text>
    }

    const shown = await read($, tab)
    const all = await read($, hidden)
    const isShowingHidden = await read($, showHidden)
    const visible = (rows: Row[]) => rows.filter(row => isShowingHidden || !isHiddenRow(all, row))
    const countOf = (rows: Row[]) => rows.filter(row => !isHiddenRow(all, row)).length
    const mine = snap.rows
    const team = snap.team ?? []
    const hiddenHere = (shown === 'team' ? team : mine).filter(row => isHiddenRow(all, row)).length
    // Mine groups by stage; Team groups by person, most urgent PR first
    const sections =
      shown === 'team'
        ? Object.entries(TEAM).map(([login, name]) => ({
            title: name,
            rows: visible(team.filter(row => row.author === login)),
          }))
        : SECTIONS.map(section => ({
            title: section.title,
            rows: visible(mine.filter(row => section.stages.includes(row.stage))),
          }))
    const filled = sections.filter(section => section.rows.length > 0)

    const entry = (row: Row) => {
      const isHidden = isHiddenRow(all, row)
      const style = isHidden ? { color: PALETTE.faint, dot: STYLE[row.stage].dot } : STYLE[row.stage]
      const number = `#${row.number}`
      const title = fit(row.title, width - number.length - 5)
      const facts = fit([row.label, age(now, row.since), row.detail].filter(Boolean).join(' · '), width - 2)
      const [label = '', rest = ''] = facts.startsWith(row.label)
        ? [row.label, facts.slice(row.label.length)]
        : [facts, '']

      return (
        <Box key={`pr-${row.number}`} flexDirection="column">
          {/* One plain label, so the focus and pointer highlight is one even bar */}
          <Box flexDirection="row" gap={1}>
            <Text color={style.color}>{style.dot}</Text>
            <Box flexGrow={1}>
              <Button
                key={`open-${row.number}`}
                plain
                dimColor={isHidden ? true : undefined}
                label={`${number} ${title}`}
                onPress={() => openPr($, row.url)}
              />
            </Box>
            <Button
              key={`hide-${row.number}`}
              plain
              dimColor
              label={isHidden ? '↺' : '✕'}
              onPress={() => setHidden($, row, !isHidden)}
            />
          </Box>
          <Box paddingLeft={2}>
            <Text>
              <Text color={style.color}>{label}</Text>
              <Text color={PALETTE.subtext}>{rest}</Text>
            </Text>
          </Box>
        </Box>
      )
    }

    return (
      <Box flexDirection="column" paddingX={1}>
        <Box flexDirection="row" gap={2} marginBottom={1}>
          <Button
            key="tab-mine"
            plain
            dimColor={shown !== 'mine' ? true : undefined}
            label={`Mine ${countOf(mine)}`}
            onPress={() => update($, tab, () => 'mine' as Tab)}
          />
          <Button
            key="tab-team"
            plain
            dimColor={shown !== 'team' ? true : undefined}
            label={`Team ${countOf(team)}`}
            onPress={() => update($, tab, () => 'team' as Tab)}
          />
        </Box>
        {filled.length === 0 && (
          <Text color={PALETTE.subtext}>
            {shown !== 'team'
              ? 'Nothing in flight.'
              : Object.keys(TEAM).length === 0
                ? 'Set PR_TRACKER_TEAM in ~/.zshrc.local.'
                : 'Nothing open or waiting for release.'}
          </Text>
        )}
        {filled.map(section => (
          <Box key={`section-${section.title}`} flexDirection="column" marginBottom={1}>
            <Box flexDirection="row" justifyContent="space-between">
              <Text color={PALETTE.overlay} bold>
                {section.title.toUpperCase()} {countOf(section.rows)}
              </Text>
              {countOf(section.rows) > 1 && (
                <Button
                  key={`all-${section.title}`}
                  plain
                  dimColor
                  label="open all ↗"
                  onPress={() => openPrs($, section.rows.filter(row => !isHiddenRow(all, row)).map(row => row.url))}
                />
              )}
            </Box>
            {section.rows.map(entry)}
          </Box>
        ))}
        {hiddenHere > 0 && (
          <Box flexDirection="row" gap={1}>
            <Text color={PALETTE.faint}>{hiddenHere} hidden ·</Text>
            <Button
              key="toggle-hidden"
              plain
              dimColor
              label={isShowingHidden ? 'hide them' : 'show'}
              onPress={() => update($, showHidden, is => !is)}
            />
          </Box>
        )}
        {snap.error && <Text color={PALETTE.red}>{fit(`⚠ ${snap.error}`, width)}</Text>}
      </Box>
    )
  })
}
