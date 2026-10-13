import { expect, mock, test } from 'claude-code/testing'

import {
  age,
  classifyOpen,
  cleanTitle,
  isSameDay,
  keepMergeability,
  parseTeam,
  releaseName,
  shellExport,
  withTeamReview,
} from '../hooks/track'
import type { OpenPr } from '../hooks/track'

const NOW = Date.UTC(2026, 9, 12, 12)

const pr = (over: Partial<OpenPr>): OpenPr => ({
  number: 1,
  title: 'release <- Something',
  url: 'https://github.com/Unicity/new-shop/pull/1',
  isDraft: false,
  mergeStateStatus: 'CLEAN',
  reviewDecision: '',
  headRefName: 'feat/x',
  updatedAt: '2026-10-12T10:00:00Z',
  statusCheckRollup: [
    { name: 'format-lint-build', status: 'COMPLETED', conclusion: 'SUCCESS' },
    { context: 'Vercel – shop2', state: 'SUCCESS' },
  ],
  ...over,
})

test('open PRs read as failing, conflicts, running, ready, with their checks', async () => {
  expect(classifyOpen(pr({}))).toEqual({ stage: 'ready', label: 'ready to merge', detail: '2/2 checks' })
  expect(
    classifyOpen(
      pr({
        reviewDecision: 'APPROVED',
        statusCheckRollup: [{ name: 'format-lint-build', status: 'COMPLETED', conclusion: 'FAILURE' }],
      }),
    ),
  ).toEqual({ stage: 'failing', label: 'format-lint-build failed', detail: '1/1 failed · approved' })
  expect(classifyOpen(pr({ mergeStateStatus: 'DIRTY' })).stage).toBe('conflicts')
  expect(classifyOpen(pr({ statusCheckRollup: [{ context: 'Vercel', state: 'PENDING' }] })).stage).toBe('building')
  expect(classifyOpen(pr({ isDraft: true, mergeStateStatus: 'DIRTY' })).stage).toBe('draft')
  // GitHub says UNSTABLE while a check is still running
  expect(
    classifyOpen(
      pr({
        mergeStateStatus: 'UNSTABLE',
        statusCheckRollup: [
          { name: 'format-lint-build', status: 'COMPLETED', conclusion: 'SUCCESS' },
          { name: 'Vercel Preview Comments', status: 'IN_PROGRESS', conclusion: null },
        ],
      }),
    ),
  ).toEqual({ stage: 'building', label: 'checks running', detail: '1/2 checks' })
})

test('a PR keeps its last mergeability while GitHub recomputes it', async () => {
  const unknown = { number: 1, title: 't', url: 'u', branch: 'b', since: 'T1', ...classifyOpen(pr({ mergeStateStatus: 'UNKNOWN' })) }
  const conflicted = { ...unknown, stage: 'conflicts' as const, label: 'merge conflicts' }
  expect(unknown.label).toBe('checking mergeability')
  expect(keepMergeability(unknown, conflicted)).toEqual({ ...unknown, stage: 'conflicts', label: 'merge conflicts' })
  // A new push may have fixed it, and a first sighting has nothing to keep
  expect(keepMergeability(unknown, { ...conflicted, since: 'T0' })).toEqual(unknown)
  expect(keepMergeability(unknown, undefined)).toEqual(unknown)
  expect(keepMergeability({ ...unknown, stage: 'ready', label: 'ready to merge' }, conflicted).stage).toBe('ready')
})

test('a teammate PR is ready once you or an approver approved its head commit', async () => {
  const APPROVERS = { me: 'you', josh: 'Josh' }
  const review = (login: string, state: string, oid: string) => ({ author: { login }, state, commit: { oid } })
  const read = (reviews: ReturnType<typeof review>[], over: Partial<OpenPr> = {}) => {
    const teamPr = pr({ headRefOid: 'head', reviews, ...over })
    const row = { number: 1, title: 't', url: 'u', branch: 'b', since: 'T', ...classifyOpen(teamPr) }
    const reviewed = withTeamReview(row, teamPr, APPROVERS)

    return [reviewed.stage, reviewed.label, reviewed.approvedBy]
  }

  expect(read([])).toEqual(['review', 'needs review', undefined])
  expect(read([review('someone', 'APPROVED', 'head')])).toEqual(['review', 'needs review', undefined])
  expect(read([review('me', 'APPROVED', 'head')])).toEqual(['ready', 'ready to merge', 'you'])
  expect(read([review('josh', 'APPROVED', 'head')])).toEqual(['ready', 'ready to merge', 'Josh'])
  expect(read([review('me', 'APPROVED', 'old')])).toEqual(['review', 're-review: new commits', undefined])
  expect(read([review('me', 'CHANGES_REQUESTED', 'head')])).toEqual(['blocked', 'changes requested', undefined])
  // A later comment does not undo an approval
  expect(read([review('me', 'APPROVED', 'head'), review('me', 'COMMENTED', 'head')])[0]).toBe('ready')
  // A failing build, a conflict or a draft outranks the review
  expect(read([], { mergeStateStatus: 'DIRTY' })[0]).toBe('conflicts')
  expect(
    read([], { statusCheckRollup: [{ name: 'format-lint-build', status: 'COMPLETED', conclusion: 'FAILURE' }] })[0],
  ).toBe('failing')
  expect(read([], { isDraft: true })[0]).toBe('draft')
})

test('titles, releases, ages and the team list read plainly', async () => {
  expect(cleanTitle('release <- ECOM-1: Fix it')).toBe('ECOM-1: Fix it')
  expect(releaseName('release 2.6.0')).toBe('v2.6.0')
  expect(releaseName('Merge pull request #5793 from Unicity/release\n\nrelease 2.6.0')).toBe('v2.6.0')
  expect(releaseName('master <- hotfix')).toBe('')
  expect(age(NOW, '2026-10-12T10:00:00Z')).toBe('2h')
  expect(age(NOW, '2026-10-09T12:00:00Z')).toBe('3d')
  expect(isSameDay(new Date(2026, 9, 12, 0, 5).getTime(), new Date(2026, 9, 12, 23, 55).getTime())).toBe(true)
  expect(isSameDay(new Date(2026, 9, 11, 23, 55).getTime(), new Date(2026, 9, 12, 0, 5).getTime())).toBe(false)
  expect(parseTeam(' dev-a:Ada , dev-b ,, ')).toEqual({ 'dev-a': 'Ada', 'dev-b': 'dev-b' })
  expect(parseTeam(undefined)).toEqual({})
})

test('the team list is read from a shell file', async () => {
  expect(shellExport('alias x=y\nexport PR_TRACKER_TEAM="dev-a:Ada,dev-b:Bo"\n', 'PR_TRACKER_TEAM')).toBe('dev-a:Ada,dev-b:Bo')
  expect(shellExport("PR_TRACKER_TEAM='dev-a:Ada'", 'PR_TRACKER_TEAM')).toBe('dev-a:Ada')
  expect(shellExport('export PR_TRACKER_TEAM=dev-a\nexport PR_TRACKER_TEAM=dev-b', 'PR_TRACKER_TEAM')).toBe('dev-b')
  expect(shellExport('# PR_TRACKER_TEAM="dev-a"\nexport OTHER=1', 'PR_TRACKER_TEAM')).toBeUndefined()
  expect(shellExport('', 'PR_TRACKER_TEAM')).toBeUndefined()
  expect(shellExport('export PR_TRACKER_TEAM=a\nexport PR_TRACKER_APPROVERS=b', 'PR_TRACKER_APPROVERS')).toBe('b')
})

test('a session tracks PRs to production without opening the pane', async ($, on) => {
  mock.clock(on, { now: NOW })
  mock.env(on, { PR_TRACKER_TEAM: 'dev-a:Ada,dev-b:Bo,dev-c:Cy' })

  const open = [
    pr({ number: 1, title: 'release <- Ready one' }),
    pr({
      number: 2,
      title: 'release <- Broken one',
      mergeStateStatus: 'UNSTABLE',
      statusCheckRollup: [{ name: 'format-lint-build', status: 'COMPLETED', conclusion: 'FAILURE' }],
    }),
  ]
  const merged = [
    { number: 3, title: 'release <- Waiting one', url: 'https://x/3', headRefName: 'c', mergedAt: '2026-10-11T12:00:00Z', mergeCommit: { oid: 'sha3' } },
    { number: 4, title: 'release <- Shipping one', url: 'https://x/4', headRefName: 'd', mergedAt: '2026-10-09T12:00:00Z', mergeCommit: { oid: 'sha4' } },
    { number: 5, title: 'release <- master', url: 'https://x/5', headRefName: 'master', mergedAt: '2026-10-09T12:00:00Z', mergeCommit: { oid: 'sha5' } },
  ]
  // The team's: everyone's PRs into release, the tracker keeps the team's
  const everyoneOpen = [
    {
      ...pr({
        number: 6,
        title: 'release <- Team open one',
        headRefOid: 'head6',
        reviews: [{ author: { login: 'me-login' }, state: 'APPROVED', commit: { oid: 'head6' } }],
      }),
      author: { login: 'dev-a' },
    },
    { ...pr({ number: 9, title: 'release <- Not a teammate' }), author: { login: 'app/dependabot' } },
  ]
  const everyoneMerged = [
    { number: 7, title: 'release <- Team waiting', url: 'https://x/7', headRefName: 'g', mergedAt: '2026-10-11T12:00:00Z', mergeCommit: { oid: 'sha7' }, author: { login: 'dev-b' } },
    { number: 8, title: 'release <- Team shipped', url: 'https://x/8', headRefName: 'h', mergedAt: '2026-10-01T12:00:00Z', mergeCommit: { oid: 'sha8' }, author: { login: 'dev-c' } },
  ]
  const releases = [
    { title: 'release 2.6.0', mergedAt: '2026-10-10T12:00:00Z', mergeCommit: { oid: 'rel260' }, headRefName: 'release' },
  ]
  // sha3 is only on release; sha4 went out in 2.6.0 and is on the 25% canary
  const inside: Record<string, string> = {
    'master...sha3': 'ahead',
    'master...sha4': 'behind',
    'baseSha...sha4': 'diverged',
    'canarySha...sha4': 'behind',
    'rel260...sha4': 'behind',
    'master...sha7': 'ahead',
    'master...sha8': 'behind',
  }

  on('process.run', ($, e) => {
    const [tool, ...args] = e.argv
    const ok = (stdout: string) => ({
      value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    })

    if (tool === 'vercel') {
      return ok(
        JSON.stringify({
          rollingRelease: {
            state: 'ACTIVE',
            currentCanaryPercentage: 25,
            canaryDeployment: { id: 'dpl_canary' },
            currentDeployment: { id: 'dpl_base' },
          },
        }),
      )
    }
    if (args[0] === 'api' && args[1] === 'user') {
      return ok('me-login\n')
    }
    if (args[0] === 'api') {
      const range = String(args[1]).split('/compare/')[1] ?? ''

      return ok(`${inside[range] ?? 'diverged'}\n`)
    }
    if (args.includes('master')) {
      return ok(JSON.stringify(releases))
    }
    if (!args.includes('@me')) {
      return ok(JSON.stringify(args.includes('open') ? everyoneOpen : everyoneMerged))
    }

    return ok(JSON.stringify(args.includes('open') ? open : merged))
  })
  on('mcp.call', () => ({
    value: {
      isError: false,
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            result: {
              deployments: {
                deployments: [
                  { id: 'dpl_canary', meta: { githubCommitSha: 'canarySha' } },
                  { id: 'dpl_base', meta: { githubCommitSha: 'baseSha' } },
                ],
              },
            },
          }),
        },
      ],
    },
  }))

  // The store, answered here: it starts with a snapshot an older version saved
  // moments ago, without team data, which must be refetched rather than reused
  const store = new Map<string, unknown>([['shared', { fetchedAt: NOW, rows: [], rollout: '', error: null }]])
  let refreshed: () => void = () => {}
  const isRefreshed = new Promise<void>(resolve => (refreshed = resolve))
  on('store.get', ($, e) => ({ value: store.get(e.key) }))
  on('store.set', ($, e) => {
    store.set(e.key, e.value)

    return { value: undefined }
  })
  // A refresh ends by publishing its snapshot to the drawings
  on('state.set', async ($, e, next) => {
    const set = await next(e)
    if (e.key === 'snapshot') {
      refreshed()
    }

    return set
  })

  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  const opened: unknown[] = []
  on('ui.open', ($, e) => {
    opened.push(e)

    return { value: { isPlaced: true } }
  })

  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  await isRefreshed
  expect(opened).toEqual([])

  type Stored = { number: number; stage: string; label: string; detail: string; author?: string; approvedBy?: string }
  const shared = store.get('shared') as { rows: Stored[]; team: Stored[] }
  expect(shared.team.map(row => [row.number, row.author, row.stage, row.approvedBy])).toEqual([
    [6, 'dev-a', 'ready', 'you'],
    [7, 'dev-b', 'release', undefined],
  ])
  expect(shared.rows.map(row => [row.number, row.stage, row.label, row.detail])).toEqual([
    [2, 'failing', 'format-lint-build failed', '1/1 failed'],
    [1, 'ready', 'ready to merge', '2/2 checks'],
    [3, 'release', 'waiting for release', ''],
    [4, 'rolling', 'rolling out 25%', 'v2.6.0'],
  ])

  const PANE = {
    plugin: 'pr-tracker',
    component: 'Pane',
    props: {
      title: 'PRs',
      isFocused: false,
      bodyColumns: 38,
      placement: 'dock',
      scroll: { offset: 0, bodyRows: 30 },
      view: {},
    },
    requestId: 'prs',
  } as const

  for (const surface of ['terminal', 'desktop'] as const) {
    const pane = await $.ui.mount({ ...PANE, surface })
    expect(await pane.find({ text: /SHIPPING 1/ })).toBeDefined()
    expect(await pane.find({ type: 'Button', text: /Mine 4/ })).toBeDefined()
    expect(await pane.find({ type: 'Button', key: 'all-Open' })).toBeDefined()
    expect(await pane.find({ type: 'Button', key: 'all-In release' })).toBeUndefined()
    expect(await pane.find({ type: 'Button', text: /#2 Broken one/ })).toBeDefined()
    expect(await pane.find({ text: /rolling out 25% · 3d · v2\.6\.0/ })).toBeDefined()
    expect(await pane.find({ text: /https:/ })).toBeUndefined()
    expect(await pane.find({ text: /release <- master/ })).toBeUndefined()
    await pane.unmount()
  }

  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })

  // The Team tab groups by person under the names PR_TRACKER_TEAM gives
  await pane.press({ key: 'tab-team' })
  expect(await pane.find({ text: /ADA 1/ })).toBeDefined()
  expect(await pane.find({ text: /BO 1/ })).toBeDefined()
  expect(await pane.find({ text: /Not a teammate/ })).toBeUndefined()
  await pane.press({ key: 'tab-mine' })

  // Hiding: the PR leaves the list and the counts, and can be brought back
  await pane.press({ key: 'hide-2' })
  expect(await pane.find({ type: 'Button', text: /#2 Broken one/ })).toBeUndefined()
  expect(await pane.find({ type: 'Button', text: /Mine 3/ })).toBeDefined()
  expect(await pane.find({ text: /1 hidden/ })).toBeDefined()
  expect(store.get('hidden')).toEqual({ 2: { since: '2026-10-12T10:00:00Z', stage: 'failing' } })

  await pane.press({ key: 'toggle-hidden' })
  expect(await pane.find({ type: 'Button', text: /#2 Broken one/ })).toBeDefined()
  await pane.press({ key: 'hide-2' })
  expect(store.get('hidden')).toEqual({})
  await pane.unmount()
})
