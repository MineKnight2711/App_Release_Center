-- Share links for single items of the AMC safe. The item is encrypted in the
-- app with a key that lives only in the link's #fragment (plus the share
-- password, when set); the Worker stores ciphertext it cannot read and decides
-- who may fetch it, for how long and how many times.

CREATE TABLE safe_shares (
  id TEXT PRIMARY KEY,
  owner_uid TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- The safe item's own id, so the owner's app can name the link. Never sent
  -- to anyone opening it.
  item_id TEXT NOT NULL DEFAULT '',
  -- Emptied once the link expires, runs out of views or is locked.
  ciphertext TEXT NOT NULL,
  -- SHA-256 of the access key derived from the link secret and password.
  access_hash TEXT NOT NULL,
  -- PBKDF2 salt; empty when the link has no password.
  password_salt TEXT NOT NULL DEFAULT '',
  kdf_iterations INTEGER NOT NULL DEFAULT 0,
  max_views INTEGER,
  views INTEGER NOT NULL DEFAULT 0,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  last_viewed_at TEXT
);
CREATE INDEX safe_shares_owner ON safe_shares(owner_uid, created_at);
CREATE INDEX safe_shares_expiry ON safe_shares(expires_at);
