
-- Add availability tier to content
ALTER TABLE content ADD COLUMN IF NOT EXISTS availability text NOT NULL DEFAULT 'full_text';

-- Set availability based on existing source_type
UPDATE content SET availability = 'full_text' WHERE source_type = 'rss';
UPDATE content SET availability = 'full_text' WHERE source_type = 'web';
UPDATE content SET availability = 'downloadable' WHERE source_type IN ('openlibrary', 'arxiv');

CREATE INDEX IF NOT EXISTS idx_content_availability ON content (availability);

-- Add default availability to content_sources
ALTER TABLE content_sources ADD COLUMN IF NOT EXISTS availability_default text NOT NULL DEFAULT 'full_text';
;
