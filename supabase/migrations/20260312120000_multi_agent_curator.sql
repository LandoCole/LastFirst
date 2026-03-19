-- Multi-Agent Curator Architecture: Schema changes
-- Phase 1: Foundation tables
-- Phase 3: Daily curation config

-- Agent tasks table (observability and findings storage)
CREATE TABLE IF NOT EXISTS agent_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  curation_id UUID NOT NULL REFERENCES curations(id) ON DELETE CASCADE,
  agent_role TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  query TEXT NOT NULL,
  context JSONB DEFAULT '{}',
  findings JSONB DEFAULT '[]',
  tokens_used INT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_tasks_curation ON agent_tasks(curation_id);

-- Daily curation config table
CREATE TABLE IF NOT EXISTS daily_curation_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  enabled BOOLEAN DEFAULT true,
  generation_hour INT DEFAULT 6,
  max_items INT DEFAULT 5,
  last_generated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_daily_curation_config_user ON daily_curation_config(user_id);

-- Add multi-agent columns to curations
ALTER TABLE curations ADD COLUMN IF NOT EXISTS complexity TEXT DEFAULT 'simple';
ALTER TABLE curations ADD COLUMN IF NOT EXISTS agent_count INT DEFAULT 1;

-- RLS policies for agent_tasks
ALTER TABLE agent_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view agent tasks for their curations" ON agent_tasks
  FOR SELECT USING (
    curation_id IN (
      SELECT id FROM curations WHERE user_id = auth.uid()
    )
  );

-- RLS policies for daily_curation_config
ALTER TABLE daily_curation_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own daily curation config" ON daily_curation_config
  FOR ALL USING (user_id = auth.uid());

-- pg_cron schedule for daily curations (run manually or uncomment after deploy)
-- Requires pg_cron and pg_net extensions
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- CREATE EXTENSION IF NOT EXISTS pg_net;
--
-- SELECT cron.schedule(
--   'daily-curation-generation',
--   '0 6 * * *',
--   $$ SELECT net.http_post(
--     url := current_setting('app.settings.supabase_url') || '/functions/v1/curator-daily',
--     headers := jsonb_build_object(
--       'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
--       'Content-Type', 'application/json'
--     ),
--     body := '{}'::jsonb
--   ); $$
-- );
