import { neon } from '@neondatabase/serverless';
import type { Report, SummaryRow } from './model.js';

export interface Store {
  getHash(id: string): Promise<string | null>;
  accept(report: Report, hash: string, ipDigest: string, day: string): Promise<'created' | 'duplicate' | 'conflict' | 'limited'>;
  summaries(): Promise<SummaryRow[]>;
}

export function databaseStore(url: string): Store {
  const sql = neon(url);
  return {
    async getHash(id) {
      const rows = await sql`SELECT body_hash FROM compatibility_reports WHERE id = ${id}::uuid`;
      return rows[0]?.body_hash as string | undefined ?? null;
    },
    async accept(report, hash, ipDigest, day) {
      // A retry is acknowledged without spending another rate-limit slot.
      const existing = await this.getHash(report.id);
      if (existing !== null) return existing === hash ? 'duplicate' : 'conflict';
      const inserted = await sql`
        WITH allowance AS (
        INSERT INTO compatibility_rate_limits (bucket_day, ip_digest, submissions)
        VALUES (${day}::date, ${ipDigest}, 1)
        ON CONFLICT (bucket_day, ip_digest) DO UPDATE
          SET submissions = compatibility_rate_limits.submissions + 1
          WHERE compatibility_rate_limits.submissions < 30
        RETURNING submissions)
        INSERT INTO compatibility_reports
          (id, body_hash, game_id, mode, outcome, features, context, note, issue, client_created_at)
        SELECT
          ${report.id}::uuid, ${hash}, ${report.gameID}, ${report.mode}, ${report.outcome},
           ${JSON.stringify(report.features)}::jsonb, ${JSON.stringify(report.context)}::jsonb,
           ${report.note ?? null}, ${report.issue ?? null},
           to_timestamp(${(Date.UTC(2001, 0, 1) / 1000) + report.createdAt})
        FROM allowance
        ON CONFLICT (id) DO NOTHING RETURNING id`;
      if (inserted.length > 0) return 'created';
      const storedHash = await this.getHash(report.id);
      if (storedHash === null) return 'limited';
      return storedHash === hash ? 'duplicate' : 'conflict';
    },
    async summaries() {
      const rows = await sql`
        SELECT game_id, mode, context, outcome, features, count(*)::integer AS report_count
        FROM compatibility_reports WHERE status = 'approved'
        GROUP BY game_id, mode, context, outcome, features
        ORDER BY game_id, mode, context, outcome, features
        LIMIT 100001`;
      if (rows.length > 100000) throw new Error('Catalog summary limit exceeded');
      return rows.map((row) => ({
        gameID: Number(row.game_id), mode: row.mode, context: row.context,
        outcome: row.outcome, features: row.features, count: Number(row.report_count),
      })) as SummaryRow[];
    },
  };
}
