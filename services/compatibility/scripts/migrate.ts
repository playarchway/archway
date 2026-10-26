import { neon } from '@neondatabase/serverless';

const databaseURL = process.env.DATABASE_URL;
if (!databaseURL) throw new Error('DATABASE_URL is required');
const sql = neon(databaseURL);
const migration = await Bun.file(new URL('../migration.sql', import.meta.url)).text();
// This migration contains only table/index DDL, with no embedded semicolons.
const statements = migration.split(';').map((statement) => statement.trim()).filter(Boolean);
try {
  await sql.transaction(statements.map((statement) => sql.query(statement)));
  console.log('Compatibility database migration applied.');
} catch {
  console.error('Compatibility database migration failed. Check database access and schema.');
  process.exitCode = 1;
}
