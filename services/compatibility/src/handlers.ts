import { createHmac } from 'node:crypto';
import { aggregateRows, foundationNow, parseReport, reportHash } from './model.js';
import type { Store } from './store.js';

const noStore = { 'Cache-Control': 'no-store' };
function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(data, { status, headers: { ...noStore, ...headers } });
}
export function createHandlers(store: Store, secret: string) {
  return {
    async catalog(request: Request): Promise<Response> {
      if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405, { Allow: 'GET' });
      try {
        const aggregates = aggregateRows(await store.summaries());
        if (aggregates.length > 5000 || aggregates.some((aggregate) =>
          [...Object.values(aggregate.counts), ...Object.values(aggregate.features).flatMap(Object.values)]
            .some((count) => count > 1_000_000))) throw new Error('Catalog exceeds client limits');
        const body = JSON.stringify({ schemaVersion: 1, generatedAt: foundationNow(), aggregates });
        if (Buffer.byteLength(body) > 2_000_000) throw new Error('Catalog exceeds client size limit');
        return new Response(body, { status: 200, headers: { 'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=0, s-maxage=60' } });
      } catch (error) {
        console.error('Catalog failed', error);
        return json({ error: 'Catalog unavailable' }, 503);
      }
    },
    async reports(request: Request): Promise<Response> {
      if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405, { Allow: 'POST' });
      if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type') ?? ''))
        return json({ error: 'Content-Type must be application/json' }, 415);
      const statedLength = Number(request.headers.get('content-length'));
      if (statedLength > 16384) return json({ error: 'Report too large' }, 413);
      let bytes: Uint8Array;
      try {
        // Read at most one byte beyond the limit, including when Content-Length is absent or false.
        const reader = request.body?.getReader();
        if (!reader) return json({ error: 'Missing report' }, 400);
        const chunks: Uint8Array[] = [];
        let length = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          length += value.byteLength;
          if (length > 16384) { await reader.cancel(); return json({ error: 'Report too large' }, 413); }
          chunks.push(value);
        }
        bytes = Buffer.concat(chunks);
      } catch { return json({ error: 'Invalid request body' }, 400); }
      let report;
      try { report = parseReport(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes))); }
      catch { return json({ error: 'Invalid JSON' }, 400); }
      if (!report) return json({ error: 'Invalid report' }, 400);
      if (!secret || secret.length < 32) return json({ error: 'Submission unavailable' }, 503);
      const ip = request.headers.get('x-vercel-forwarded-for');
      if (!ip) return json({ error: 'Submission unavailable' }, 503);
      const day = new Date().toISOString().slice(0, 10);
      const digest = createHmac('sha256', secret).update(`${day}:${ip}`).digest('hex');
      try {
        const result = await store.accept(report, reportHash(report), digest, day);
        if (result === 'limited') return json({ error: 'Daily submission limit reached' }, 429,
          { 'Retry-After': String(86400) });
        if (result === 'conflict') return json({ error: 'Report ID already used' }, 409);
        return json({ status: 'pending' }, 202);
      } catch (error) {
        console.error('Report submission failed', error);
        return json({ error: 'Submission unavailable' }, 503);
      }
    },
  };
}
