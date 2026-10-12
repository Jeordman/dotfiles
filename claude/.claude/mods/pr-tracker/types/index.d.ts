// Where a PR stands on its way to production. Open PRs: draft, blocked,
// building, conflicts, failing, ready. Merged into release: release, then
// master, rolling (canary at some %), aborted, and finally live (100%).
export type Stage =
  | 'draft'
  | 'blocked'
  | 'building'
  | 'conflicts'
  | 'failing'
  | 'ready'
  | 'release'
  | 'master'
  | 'rolling'
  | 'aborted'
  | 'live'

export type Row = {
  number: number
  title: string
  url: string
  branch: string
  stage: Stage
  // The headline state, drawn in the stage's color
  label: string
  // Secondary facts: check counts, review, which release it shipped in
  detail: string
  // ISO time the age counts from: last update while open, merge time after
  since: string
  // GitHub login, on the team's rows
  author?: string
}

export type Tab = 'mine' | 'team'

// PRs the person hid, by number, with what they looked like then: an open PR
// comes back once it is updated, a merged one once it moves stage
export type Hidden = Record<string, { since: string; stage: Stage }>

export type Snapshot = {
  // Which shape of snapshot this is; another version's is refetched, not reused
  version: number
  fetchedAt: number
  rows: Row[]
  // Coworkers' PRs: open, or merged to release and not yet in master
  team: Row[]
  // What the rollout lookup came to, for the pane's footer
  rollout: string
  error: string | null
}

declare module 'claude-code' {
  interface PluginState {
    'pr-tracker': { snapshot: Snapshot | null; tab: Tab; hidden: Hidden; showHidden: boolean }
  }
}
