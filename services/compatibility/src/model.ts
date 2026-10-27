import { createHash } from 'node:crypto';

export const FOUNDATION_EPOCH_MS = Date.UTC(2001, 0, 1);
const outcomes = ['works', 'limited', 'unplayable', 'notTested'] as const;
const modes = ['singleplayer', 'multiplayer'] as const;
const features = ['join', 'host', 'invites', 'crossplay', 'voice', 'disconnects'] as const;
const issues = ['start', 'graphics', 'audio', 'performance', 'network'] as const;
const graphicsAPIs = ['gameDefault', 'd3d11', 'd3d12'] as const;
const graphemes = new Intl.Segmenter('en', { granularity: 'grapheme' });
type Outcome = typeof outcomes[number];
type Mode = typeof modes[number];
type Feature = typeof features[number];

export interface Profile { launchArguments: string[]; graphicsAPI: typeof graphicsAPIs[number] }
export interface Context {
  runtimeVersion: string; appVersion: string; macOSVersion: string; chip: string;
  gameVersion: string; graphicsBackend: string; profile: Profile;
}
export interface Report {
  id: string; gameID: number; mode: Mode; outcome: Outcome;
  features: Partial<Record<Feature, Outcome>>; issue?: typeof issues[number];
  note?: string; context: Context; createdAt: number;
}
export interface StoredReport extends Report { status: 'pending' | 'approved' | 'rejected'; bodyHash: string }
export interface SummaryRow {
  gameID: number; mode: Mode; context: Context; outcome: Outcome;
  features: Partial<Record<Feature, Outcome>>; count: number;
}
export interface Aggregate {
  gameID: number; mode: Mode; context: Context;
  counts: Partial<Record<Outcome, number>>;
  features: Partial<Record<Feature, Partial<Record<Outcome, number>>>>;
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function keys(value: Record<string, unknown>, required: string[], optional: string[] = []): boolean {
  return required.every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => required.includes(key) || optional.includes(key));
}
function boundedText(value: unknown, max: number, empty = false): value is string {
  return typeof value === 'string' && [...graphemes.segment(value)].length <= max &&
    (empty || value.trim().length > 0) &&
    !/[\u0000-\u001F\u007F]/u.test(value);
}
function member<T extends string>(value: unknown, members: readonly T[]): value is T {
  return typeof value === 'string' && members.includes(value as T);
}
function validProfile(value: unknown): value is Profile {
  return record(value) && keys(value, ['launchArguments', 'graphicsAPI']) &&
    Array.isArray(value.launchArguments) && value.launchArguments.length <= 12 &&
    value.launchArguments.every((arg: unknown) => boundedText(arg, 100) && Buffer.byteLength(arg) <= 100) &&
    member(value.graphicsAPI, graphicsAPIs);
}
function validContext(value: unknown): value is Context {
  const fields = ['runtimeVersion', 'appVersion', 'macOSVersion', 'chip', 'gameVersion', 'graphicsBackend'];
  return record(value) && keys(value, [...fields, 'profile']) &&
    fields.every((field) => boundedText(value[field], 100)) && validProfile(value.profile);
}
export function parseReport(value: unknown): Report | null {
  if (!record(value) || !keys(value,
    ['id', 'gameID', 'mode', 'outcome', 'features', 'context', 'createdAt'], ['issue', 'note'])) return null;
  const { id, gameID, mode, outcome, features: reportFeatures, issue, note, context, createdAt } = value;
  if (typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id) ||
      !Number.isSafeInteger(gameID) || (gameID as number) < 1 || (gameID as number) > 4294967295 ||
      !member(mode, modes) || !member(outcome, outcomes) || !record(reportFeatures) ||
      !Object.entries(reportFeatures).every(([key, result]) => member(key, features) && member(result, outcomes)) ||
      (mode === 'singleplayer' && Object.keys(reportFeatures).length > 0) ||
      (issue !== undefined && issue !== null && !member(issue, issues)) ||
      (note !== undefined && note !== null &&
        (typeof note !== 'string' || [...graphemes.segment(note)].length > 500 || note.includes('\0'))) ||
      !validContext(context) || typeof createdAt !== 'number' || !Number.isFinite(createdAt)) return null;
  const timestamp = FOUNDATION_EPOCH_MS + createdAt * 1000;
  if (timestamp < Date.now() - 366 * 86400_000 || timestamp > Date.now() + 86400_000) return null;
  return {
    id: id.toLowerCase(), gameID: gameID as number, mode, outcome,
    features: reportFeatures as Report['features'],
    ...(issue && { issue: issue as Report['issue'] }),
    ...(note && { note: note as string }),
    context, createdAt,
  };
}
export function reportHash(report: Report): string {
  // Normalize object key order; the UUID is the idempotency key, not the payload hash.
  function stable(value: unknown): unknown {
    if (Array.isArray(value)) return value.map(stable);
    if (record(value)) return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))
      .map(([key, nested]) => [key, stable(nested)]));
    return value;
  }
  return createHash('sha256').update(JSON.stringify(stable(report))).digest('hex');
}
export function aggregateRows(rows: SummaryRow[]): Aggregate[] {
  const groups = new Map<string, Aggregate>();
  for (const row of rows) {
    const key = JSON.stringify([row.gameID, row.mode, row.context]);
    let aggregate = groups.get(key);
    if (!aggregate) {
      aggregate = { gameID: row.gameID, mode: row.mode, context: row.context, counts: {}, features: {} };
      groups.set(key, aggregate);
    }
    aggregate.counts[row.outcome] = (aggregate.counts[row.outcome] ?? 0) + row.count;
    for (const [feature, outcome] of Object.entries(row.features) as [Feature, Outcome][]) {
      const counts = aggregate.features[feature] ?? {};
      counts[outcome] = (counts[outcome] ?? 0) + row.count;
      aggregate.features[feature] = counts;
    }
  }
  return [...groups.values()];
}
export function foundationNow(): number { return (Date.now() - FOUNDATION_EPOCH_MS) / 1000; }
