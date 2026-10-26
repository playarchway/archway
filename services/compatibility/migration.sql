CREATE TABLE IF NOT EXISTS compatibility_reports (
  id uuid PRIMARY KEY,
  body_hash text NOT NULL CHECK (length(body_hash) = 64),
  game_id bigint NOT NULL CHECK (game_id BETWEEN 1 AND 4294967295),
  mode text NOT NULL CHECK (mode IN ('singleplayer', 'multiplayer')),
  outcome text NOT NULL CHECK (outcome IN ('works', 'limited', 'unplayable', 'notTested')),
  features jsonb NOT NULL DEFAULT '{}'::jsonb,
  context jsonb NOT NULL,
  note text,
  issue text,
  client_created_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  moderated_at timestamptz,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected'))
);
CREATE INDEX IF NOT EXISTS compatibility_reports_pending_idx
  ON compatibility_reports (received_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS compatibility_reports_approved_idx
  ON compatibility_reports (game_id, mode) WHERE status = 'approved';

CREATE TABLE IF NOT EXISTS compatibility_rate_limits (
  bucket_day date NOT NULL,
  ip_digest text NOT NULL CHECK (length(ip_digest) = 64),
  submissions integer NOT NULL CHECK (submissions BETWEEN 1 AND 30),
  PRIMARY KEY (bucket_day, ip_digest)
);
