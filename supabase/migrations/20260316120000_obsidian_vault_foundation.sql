-- Obsidian-first agent architecture: per-user vault foundation

CREATE TABLE IF NOT EXISTS vaults (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT 'lastfirst_managed',
  connection_type TEXT NOT NULL DEFAULT 'managed',
  status TEXT NOT NULL DEFAULT 'active',
  root_path TEXT,
  is_primary BOOLEAN NOT NULL DEFAULT true,
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_vaults_primary_per_user
  ON vaults(user_id)
  WHERE is_primary = true;

CREATE INDEX IF NOT EXISTS idx_vaults_user_id ON vaults(user_id);

CREATE TABLE IF NOT EXISTS vault_sync_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
  trigger_source TEXT NOT NULL DEFAULT 'manual',
  status TEXT NOT NULL DEFAULT 'pending',
  notes_total INT NOT NULL DEFAULT 0,
  chunks_total INT NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vault_sync_runs_vault_id ON vault_sync_runs(vault_id);
CREATE INDEX IF NOT EXISTS idx_vault_sync_runs_started_at ON vault_sync_runs(started_at DESC);

CREATE TABLE IF NOT EXISTS vault_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  slug TEXT,
  title TEXT NOT NULL,
  folder_path TEXT,
  note_type TEXT NOT NULL DEFAULT 'note',
  tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  frontmatter JSONB NOT NULL DEFAULT '{}'::jsonb,
  outbound_link_paths TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  content_markdown TEXT NOT NULL DEFAULT '',
  source_hash TEXT,
  word_count INT NOT NULL DEFAULT 0,
  token_estimate INT NOT NULL DEFAULT 0,
  last_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(vault_id, path)
);

CREATE INDEX IF NOT EXISTS idx_vault_notes_vault_id ON vault_notes(vault_id);
CREATE INDEX IF NOT EXISTS idx_vault_notes_user_id ON vault_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_vault_notes_tags ON vault_notes USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_vault_notes_frontmatter ON vault_notes USING GIN(frontmatter);
CREATE INDEX IF NOT EXISTS idx_vault_notes_outbound_link_paths ON vault_notes USING GIN(outbound_link_paths);

CREATE TABLE IF NOT EXISTS vault_note_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
  source_note_id UUID NOT NULL REFERENCES vault_notes(id) ON DELETE CASCADE,
  target_note_id UUID REFERENCES vault_notes(id) ON DELETE SET NULL,
  target_path TEXT NOT NULL,
  link_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vault_note_links_source_note_id ON vault_note_links(source_note_id);
CREATE INDEX IF NOT EXISTS idx_vault_note_links_target_note_id ON vault_note_links(target_note_id);
CREATE INDEX IF NOT EXISTS idx_vault_note_links_target_path ON vault_note_links(vault_id, target_path);

CREATE TABLE IF NOT EXISTS vault_note_chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
  note_id UUID NOT NULL REFERENCES vault_notes(id) ON DELETE CASCADE,
  chunk_index INT NOT NULL,
  content TEXT NOT NULL,
  token_estimate INT NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(note_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS idx_vault_note_chunks_note_id ON vault_note_chunks(note_id);
CREATE INDEX IF NOT EXISTS idx_vault_note_chunks_vault_id ON vault_note_chunks(vault_id);

ALTER TABLE vaults ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_sync_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_note_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_note_chunks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own vaults" ON vaults
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can view sync runs for their vaults" ON vault_sync_runs
  FOR SELECT USING (
    vault_id IN (
      SELECT id FROM vaults WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage sync runs" ON vault_sync_runs
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Users can manage notes in their own vaults" ON vault_notes
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can view links in their own vaults" ON vault_note_links
  FOR SELECT USING (
    vault_id IN (
      SELECT id FROM vaults WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage links" ON vault_note_links
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Users can view chunks in their own vaults" ON vault_note_chunks
  FOR SELECT USING (
    vault_id IN (
      SELECT id FROM vaults WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage chunks" ON vault_note_chunks
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
