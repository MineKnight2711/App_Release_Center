-- Product analytics is separate from operational logs and QA audit records.
CREATE TABLE analytics_admins (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE
);
CREATE TABLE analytics_subjects (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  subject_id TEXT NOT NULL UNIQUE
);
CREATE TABLE analytics_events (
  subject_id TEXT NOT NULL REFERENCES analytics_subjects(subject_id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  feature_id TEXT NOT NULL,
  event_name TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  day TEXT NOT NULL,
  operation_id TEXT,
  phase TEXT,
  platform TEXT NOT NULL,
  build_id TEXT NOT NULL,
  source TEXT NOT NULL,
  duration_ms INTEGER,
  result_category TEXT,
  error_code TEXT,
  PRIMARY KEY (subject_id, event_id)
);
CREATE UNIQUE INDEX analytics_operation_phase
  ON analytics_events(subject_id, operation_id, phase) WHERE operation_id IS NOT NULL;
CREATE INDEX analytics_scope_date ON analytics_events(team_id, occurred_at);
CREATE INDEX analytics_date ON analytics_events(occurred_at);
CREATE INDEX analytics_received ON analytics_events(received_at);
