import { expect, test } from 'bun:test';
import { createHandlers } from '../src/handlers.js';
import { aggregateRows, foundationNow, parseReport, reportHash } from '../src/model.js';
import type { Report, SummaryRow } from '../src/model.js';
import type { Store } from '../src/store.js';

function sample(): Report {
  return {
    id: '6f62b02b-e6bc-47b5-a5e1-ce87e7038860', gameID: 1144200,
    mode: 'multiplayer', outcome: 'limited', features: { join: 'works', voice: 'notTested' },
    issue: 'network', note: 'Disconnected once', createdAt: foundationNow(),
    context: { runtimeVersion: '11.20', appVersion: '1.0', macOSVersion: '15.1',
      chip: 'Apple M4', gameVersion: '123', graphicsBackend: 'd3dmetal',
      profile: { launchArguments: ['-dx11'], graphicsAPI: 'gameDefault' } },
  };
}
class MemoryStore implements Store {
  hashes = new Map<string, string>();
  saved: Report[] = [];
  rows: SummaryRow[] = [];
  async getHash(id: string): Promise<string | null> { return this.hashes.get(id) ?? null; }
  async accept(report: Report, hash: string): Promise<'created' | 'duplicate' | 'conflict'> {
    const previous = this.hashes.get(report.id);
    if (previous) return previous === hash ? 'duplicate' : 'conflict';
    this.hashes.set(report.id, hash); this.saved.push(report); return 'created';
  }
  async summaries(): Promise<SummaryRow[]> { return this.rows; }
}
function request(report: unknown): Request {
  return new Request('https://example.vercel.app/api/reports', { method: 'POST',
    headers: { 'content-type': 'application/json', 'x-vercel-forwarded-for': '192.0.2.1' },
    body: JSON.stringify(report) });
}
test('strict report validation matches Swift wire format', () => {
  const valid = sample();
  expect(parseReport(valid)).not.toBeNull();
  expect(parseReport({ ...valid, gameID: -4 })).toBeNull();
  expect(parseReport({ ...valid, context: { ...valid.context, extra: 'bad' } })).toBeNull();
  expect(parseReport({ ...valid, createdAt: Date.now() / 1000 })).toBeNull();
  expect(parseReport({ ...valid, context: { ...valid.context,
    profile: { launchArguments: [], graphicsAPI: 'd3d12' } } })).toBeNull();
  expect(parseReport({ ...valid, features: { unknown: 'works' } })).toBeNull();
  expect(parseReport({ ...valid, note: 'x'.repeat(501) })).toBeNull();
});
test('same UUID retry is acknowledged once and changed payload conflicts', async () => {
  const store = new MemoryStore();
  const handlers = createHandlers(store, 'x'.repeat(32));
  const first = sample();
  expect((await handlers.reports(request(first))).status).toBe(202);
  expect((await handlers.reports(request(first))).status).toBe(202);
  expect((await handlers.reports(request({ ...first, outcome: 'works' }))).status).toBe(409);
  expect(store.saved).toHaveLength(1);
  expect(store.hashes.get(first.id)).toBe(reportHash(first));
});
test('method, type and size limits', async () => {
  const handlers = createHandlers(new MemoryStore(), 'x'.repeat(32));
  expect((await handlers.reports(new Request('https://example.test/api/reports'))).status).toBe(405);
  expect((await handlers.reports(new Request('https://example.test/api/reports',
    { method: 'POST', body: '{}' }))).status).toBe(415);
  expect((await handlers.reports(request({ ...sample(), note: 'x'.repeat(17_000) }))).status).toBe(413);
});
test('catalog groups each game, mode and full context separately', async () => {
  const store = new MemoryStore();
  const report = sample();
  store.rows = [
    { gameID: report.gameID, mode: report.mode, context: report.context,
      outcome: 'works', features: { join: 'works' }, count: 2 },
    { gameID: report.gameID, mode: report.mode, context: report.context,
      outcome: 'limited', features: { join: 'limited' }, count: 1 },
    { gameID: report.gameID, mode: 'singleplayer', context: report.context,
      outcome: 'works', features: {}, count: 3 },
    { gameID: report.gameID, mode: report.mode, context: { ...report.context, gameVersion: 'new' },
      outcome: 'unplayable', features: {}, count: 1 },
  ];
  const body = await createHandlers(store, 'x'.repeat(32))
    .catalog(new Request('https://example.test/api/catalog')).then((response) => response.json());
  expect(body.schemaVersion).toBe(1);
  expect(body.aggregates).toHaveLength(3);
  expect(body.aggregates[0].counts).toEqual({ works: 2, limited: 1 });
  expect(body.aggregates[0].features.join).toEqual({ works: 2, limited: 1 });
  expect(body.aggregates[0].note).toBeUndefined();
  expect(aggregateRows(store.rows)).toHaveLength(3);
});
