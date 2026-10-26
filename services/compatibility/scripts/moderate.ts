import { neon } from '@neondatabase/serverless';

const url = process.env.DATABASE_URL;
if (!url) throw new Error('Set DATABASE_URL');
const sql = neon(url);
const [action, id] = process.argv.slice(2);
if (action === 'list' && !id) {
  const rows = await sql`
    SELECT id, game_id, mode, outcome, issue, note, context, received_at
    FROM compatibility_reports WHERE status = 'pending'
    ORDER BY received_at ASC LIMIT 50`;
  for (const row of rows) console.log(JSON.stringify(row));
} else if ((action === 'approve' || action === 'reject') &&
    typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
  const rows = await sql`
    UPDATE compatibility_reports
    SET status = ${action === 'approve' ? 'approved' : 'rejected'},
        note = NULL, moderated_at = now()
    WHERE id = ${id}::uuid AND status = 'pending'
    RETURNING id`;
  if (rows.length !== 1) throw new Error('Pending report not found');
  console.log(`${action === 'approve' ? 'approved' : 'rejected'} ${id}`);
} else {
  throw new Error('Usage: bun run moderate list | approve <uuid> | reject <uuid>');
}
