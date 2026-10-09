-- QA Desk demo-account vault. Account secrets are encrypted on the client with
-- the team passphrase; the Worker only stores ciphertext and enforces who may
-- read, change, or hold an account.

CREATE TABLE qa_vault_meta (
  team_id TEXT PRIMARY KEY REFERENCES teams(id) ON DELETE CASCADE,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE qa_accounts (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (team_id, id)
);

-- The last login result, written by whoever ran with the account.
CREATE TABLE qa_account_status (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  account_id TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (team_id, account_id)
);

-- Who is using an account until when; compared against server time.
CREATE TABLE qa_account_leases (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  account_id TEXT NOT NULL,
  holder_uid TEXT NOT NULL,
  holder_name TEXT NOT NULL DEFAULT '',
  machine TEXT NOT NULL DEFAULT '',
  run_id TEXT NOT NULL DEFAULT '',
  expires_at TEXT NOT NULL,
  PRIMARY KEY (team_id, account_id)
);

-- Append-only: who changed, revealed or used which account.
CREATE TABLE qa_account_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  data TEXT NOT NULL,
  server_at TEXT NOT NULL
);
CREATE INDEX qa_account_audit_team ON qa_account_audit(team_id, server_at);
