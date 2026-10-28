CREATE TABLE desktop_devices (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cloud_id TEXT NOT NULL UNIQUE,
  fingerprint TEXT NOT NULL,
  name TEXT NOT NULL,
  platform TEXT NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX desktop_devices_owner ON desktop_devices(owner_id);
