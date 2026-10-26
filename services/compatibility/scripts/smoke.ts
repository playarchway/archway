import { neon } from '@neondatabase/serverless';
import { foundationNow } from '../src/model.js';

const databaseURL = process.env.DATABASE_URL;
const baseURL = process.env.COMPATIBILITY_SMOKE_URL;
if (!databaseURL || !baseURL) throw new Error('DATABASE_URL and COMPATIBILITY_SMOKE_URL are required');
const sql = neon(databaseURL);
const id = crypto.randomUUID();
const report = {
  id, gameID: 1144200, mode: 'multiplayer', outcome: 'notTested', features: {},
  context: {
    runtimeVersion: 'Unknown', appVersion: 'integration-smoke', macOSVersion: 'Unknown',
    chip: 'Unknown', gameVersion: 'Unknown', graphicsBackend: 'd3dmetal',
    profile: { launchArguments: [], graphicsAPI: 'gameDefault' },
  },
  createdAt: foundationNow(), note: 'Synthetic API check; never approve.',
};
async function post(body: unknown, expected: number): Promise<void> {
  const response = await fetch(new URL('/api/reports', baseURL), {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  if (response.status !== expected) throw new Error(`Expected ${expected}, received ${response.status}`);
}
try {
  const catalog = await fetch(new URL('/api/catalog', baseURL), { signal: AbortSignal.timeout(20000) });
  if (catalog.status !== 200) throw new Error(`Catalog returned ${catalog.status}`);
  const payload: unknown = await catalog.json();
  if (typeof payload !== 'object' || payload === null || !('schemaVersion' in payload) || payload.schemaVersion !== 1)
    throw new Error('Invalid catalog format');
  await post(report, 202);
  await post(report, 202);
  await post({ ...report, outcome: 'works' }, 409);
  await post({ ...report, id: crypto.randomUUID(), gameID: -1 }, 400);
  const rows = await sql`SELECT status FROM compatibility_reports WHERE id = ${id}::uuid`;
  if (rows.length !== 1 || rows[0]?.status !== 'pending') throw new Error('Expected one pending report');
  console.log('Live catalog, submission, deduplication, conflict, and validation checks passed.');
} finally {
  await sql`DELETE FROM compatibility_reports WHERE id = ${id}::uuid
    AND context->>'appVersion' = 'integration-smoke' AND status = 'pending'`;
  console.log('Synthetic report removed.');
}
