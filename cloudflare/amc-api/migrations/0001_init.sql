-- App Release Center auth, teams, and shared HTTP Tools.
-- Timestamps are ISO-8601 UTC strings.

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display_name TEXT NOT NULL DEFAULT '',
  password_salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  active_team_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_login_at TEXT
);

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX sessions_user ON sessions(user_id);

CREATE TABLE teams (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_by_uid TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE team_members (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'dev')),
  status TEXT NOT NULL DEFAULT 'active',
  joined_via_invite_id TEXT,
  joined_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (team_id, user_id)
);
CREATE INDEX team_members_user ON team_members(user_id);

CREATE TABLE team_invites (
  id TEXT PRIMARY KEY,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'dev')),
  status TEXT NOT NULL DEFAULT 'active',
  created_by_uid TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  used_by_uid TEXT,
  used_at TEXT
);
CREATE INDEX team_invites_team ON team_invites(team_id);

-- One row per HTTP Tool document; `data` is the client model's toJson().
CREATE TABLE api_tool_documents (
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('collection', 'folder', 'request', 'quickRequest')),
  id TEXT NOT NULL,
  collection_id TEXT NOT NULL DEFAULT '',
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (team_id, kind, id)
);
CREATE INDEX api_tool_documents_collection ON api_tool_documents(team_id, collection_id);
