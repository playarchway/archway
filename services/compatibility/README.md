# Archway compatibility API

Two Vercel Node.js functions backed by Neon Postgres. `vercel.json` serves them under `/v1`:

- `GET /v1/catalog` returns v1 aggregates from **approved** reports only.
- `POST /v1/reports` accepts a single report for moderation and returns `202`; repeating the same UUID and payload also returns `202` without adding a report. A changed payload with the same UUID returns `409`.

The wire format matches `Sources/ArchwayCore/Compatibility.swift` and `docs/compatibility-api.md` at the repository root. `generatedAt` and `createdAt` are numeric seconds since 2001-01-01 UTC. A catalog has no suggested profile and contains no report notes or identifiers. It groups by exact game ID, mode, and all context fields, including profile.

## Self-hosting

The steps below target your own Vercel project and database. Production account identifiers, database connection strings, and credentials do not belong in this repository. Public API addresses are visible in the app and are not authentication credentials.

1. Create a Vercel project with this directory (`services/compatibility`) as its **Root Directory**, using the **Other** framework preset. Use `bun install --frozen-lockfile` as the install command. `vercel.json` supplies an empty build command, the `public` output directory, and the Frankfurt function region. Only the public directory and API handlers are served.
2. Connect a Neon Postgres database to the project through the Vercel Marketplace and expose its `DATABASE_URL` to the environments you deploy. Keep preview and production databases separate.
3. Generate a secret with `openssl rand -hex 32` and set `RATE_LIMIT_SECRET` as a server-side Vercel environment variable in each environment. The API rejects submissions if it is missing or shorter than 32 characters. Do not put it in the macOS app.
4. Apply `migration.sql` to each database **before** enabling the deployment. With `DATABASE_URL` exported or in the ignored `.env.local`, run `bun run migrate` from this directory. The migration is repeatable.
5. Deploy the project. Build the app with `ARCHWAY_API_BASE_URL=https://<your-deployment-domain>`, or set its catalog and report URLs to `https://<your-deployment-domain>/v1/catalog` and `https://<your-deployment-domain>/v1/reports` under the app’s Service settings.

For local checks, run `bun install --frozen-lockfile`, `bun run typecheck`, and `bun run test`. Do not commit `.env.local` or database credentials.

To verify your own deployment, set `COMPATIBILITY_SMOKE_URL` to its HTTPS origin and `DATABASE_URL` to that deployment's database, then run `bun run smoke`. It submits a synthetic pending report, verifies idempotency and rejection paths, and removes that report without publishing it. Do not run this check against the shared Archway service or an unrelated database.

## Moderation and retention

New reports have `pending` status and never appear in the catalog until approved. These commands require operator access to your database; they do not grant access to the shared Archway service. With `DATABASE_URL` exported in an operator shell, use an actual pending report ID in place of `<report-id>`:

```sh
bun run moderate list
bun run moderate approve <report-id>
bun run moderate reject <report-id>
bun run prune
```

`list` shows at most 50 oldest pending reports, including the private note and context, for human review. Before approval, inspect all fields for personal data, paths, malicious launch arguments, and implausible values. Reject such reports. Approval or rejection clears the private note. There is no public moderation endpoint. Run `prune` regularly (for example daily from a trusted operator job): it deletes pending reports after 90 days, rejected reports after 30 days, and rate buckets older than two days. Approved rows remain so their UUIDs continue to deduplicate retries and their counts remain available; remove an approved row manually if a deletion request warrants it.

The POST endpoint validates input and caps the request body at 16 KiB. It uses Vercel's `x-vercel-forwarded-for` header only to make a daily HMAC digest with `RATE_LIMIT_SECRET`; the raw address is never stored. The database permits at most 30 new submission attempts per address per UTC day. This is basic abuse control, not identity verification. Keep the deployment on Vercel so the forwarded address is provided by the platform. Review Vercel logs and database usage separately for abuse.

The catalog fails with `503` rather than truncating groups or counts if it would exceed the Swift client's 5,000-group, 1,000,000-count, or 2 MB limits. Clients can keep their last successful local catalog in that case.
