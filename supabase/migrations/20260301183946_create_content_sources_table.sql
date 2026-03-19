
CREATE TABLE content_sources (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind                TEXT NOT NULL CHECK (kind IN ('rss_feed', 'openlibrary_subject', 'arxiv_category', 'web')),
  url                 TEXT NOT NULL UNIQUE,
  label               TEXT,
  topics              TEXT[],
  is_active           BOOLEAN DEFAULT true,
  last_polled_at      TIMESTAMPTZ,
  poll_interval_hours INT DEFAULT 24,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE content_sources ENABLE ROW LEVEL SECURITY;

-- Service role can manage content sources
CREATE POLICY "Service role can manage content sources" ON content_sources
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Authenticated users can read content sources
CREATE POLICY "Authenticated users can read content sources" ON content_sources
  FOR SELECT TO authenticated USING (true);
;
