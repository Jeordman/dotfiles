// Pure logic: how a PR's GitHub state reads, and how ages and releases read.
// Everything that talks to gh, Vercel or the store lives in register.tsx.
import type { Stage } from '../types'

type Check = {
  name?: string
  context?: string
  status?: string | null
  conclusion?: string | null
  state?: string | null
}

export type OpenPr = {
  number: number
  title: string
  url: string
  isDraft: boolean
  mergeStateStatus: string
  reviewDecision?: string | null
  headRefName: string
  author?: { login: string }
  updatedAt?: string
  statusCheckRollup: Check[]
}

const FAILED = new Set(['FAILURE', 'ERROR', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE'])
const PENDING = new Set(['PENDING', 'EXPECTED', 'QUEUED', 'IN_PROGRESS', 'WAITING', 'REQUESTED'])
const REVIEW: Record<string, string> = {
  APPROVED: 'approved',
  CHANGES_REQUESTED: 'changes requested',
  REVIEW_REQUIRED: 'review required',
}

// Most urgent first: the order rows are listed in
export const URGENCY: Stage[] = [
  'failing',
  'aborted',
  'conflicts',
  'ready',
  'building',
  'blocked',
  'release',
  'master',
  'rolling',
  'draft',
  'live',
]

export function cleanTitle(title: string): string {
  return title.replace(/^release\s*<-\s*/i, '').trim()
}

export function releaseName(message: string | undefined): string {
  const match = /release\s+(v?\d+(?:\.\d+)+)/i.exec(message ?? '')

  return match ? (match[1]!.startsWith('v') ? match[1]! : `v${match[1]}`) : ''
}

// The Team tab's people, from `login:Name,login:Name`; a pair without a name
// shows the login
export function parseTeam(value: string | undefined): Record<string, string> {
  const pairs = (value ?? '')
    .split(',')
    .map(pair => pair.trim())
    .filter(Boolean)
    .map(pair => {
      const [login = '', name = ''] = pair.split(':').map(part => part.trim())

      return [login, name || login] as const
    })

  return Object.fromEntries(pairs.filter(([login]) => login))
}

export function classifyOpen(pr: OpenPr): { stage: Stage; label: string; detail: string } {
  const checks = pr.statusCheckRollup ?? []
  const isFailed = (c: Check) => FAILED.has(c.conclusion ?? '') || FAILED.has(c.state ?? '')
  const isPending = (c: Check) => PENDING.has(c.status ?? '') || PENDING.has(c.state ?? '')
  const failed = checks.filter(isFailed)
  const passed = checks.filter(c => !isFailed(c) && !isPending(c)).length

  const facts = [
    checks.length === 0
      ? 'no checks'
      : failed.length > 0
        ? `${failed.length}/${checks.length} failed`
        : `${passed}/${checks.length} checks`,
    REVIEW[pr.reviewDecision ?? ''] ?? '',
  ]
  const detail = facts.filter(Boolean).join(' · ')
  const read = (stage: Stage, label: string) => ({ stage, label, detail })

  if (pr.isDraft) {
    return read('draft', 'draft')
  }
  if (failed[0]) {
    return read('failing', `${failed[0].name ?? failed[0].context ?? 'build'} failed`)
  }
  if (pr.mergeStateStatus === 'UNSTABLE') {
    return read('failing', 'checks failing')
  }
  if (pr.mergeStateStatus === 'DIRTY') {
    return read('conflicts', 'merge conflicts')
  }
  if (checks.some(isPending)) {
    return read('building', 'checks running')
  }
  if (pr.mergeStateStatus === 'BLOCKED') {
    return read('blocked', pr.reviewDecision === 'CHANGES_REQUESTED' ? 'changes requested' : 'needs review')
  }
  if (pr.mergeStateStatus === 'BEHIND') {
    return read('ready', 'ready to merge (behind)')
  }
  if (pr.mergeStateStatus === 'CLEAN' || pr.mergeStateStatus === 'HAS_HOOKS') {
    return read('ready', 'ready to merge')
  }

  return read('building', 'checking mergeability')
}

export function daysAgo(now: number, days: number): string {
  return new Date(now - days * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
}

// "5m", "3h", "2d": how long since `iso`
export function age(now: number, iso: string): string {
  const minutes = Math.max(0, Math.round((now - Date.parse(iso)) / 60_000))
  if (Number.isNaN(minutes)) {
    return ''
  }
  if (minutes < 60) {
    return `${minutes}m`
  }

  return minutes < 48 * 60 ? `${Math.round(minutes / 60)}h` : `${Math.round(minutes / (24 * 60))}d`
}
