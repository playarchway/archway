import { neon } from '@neondatabase/serverless';

const url = process.env.DATABASE_URL;
if (!url) throw new Error('Set DATABASE_URL');
const sql = neon(url);
const reports = await sql`
  DELETE FROM compatibility_reports
  WHERE (status = 'pending' AND received_at < now() - interval '90 days')
     OR (status = 'rejected' AND moderated_at < now() - interval '30 days')
  RETURNING id`;
const buckets = await sql`
  DELETE FROM compatibility_rate_limits
  WHERE bucket_day < current_date - 2 RETURNING ip_digest`;
console.log(`Pruned ${reports.length} reports and ${buckets.length} rate buckets`);
