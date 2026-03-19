
-- Add columns from catalog that content is missing
ALTER TABLE content ADD COLUMN IF NOT EXISTS cover_url TEXT;
ALTER TABLE content ADD COLUMN IF NOT EXISTS download_url TEXT;
ALTER TABLE content ADD COLUMN IF NOT EXISTS file_type TEXT;  -- 'epub', 'pdf', 'web'
ALTER TABLE content ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT false;

-- Scoring columns for recommendation engine
ALTER TABLE content ADD COLUMN IF NOT EXISTS popularity_score FLOAT DEFAULT 0;
ALTER TABLE content ADD COLUMN IF NOT EXISTS quality_score FLOAT DEFAULT 0;
ALTER TABLE content ADD COLUMN IF NOT EXISTS freshness_score FLOAT DEFAULT 0;

-- External identifiers
ALTER TABLE content ADD COLUMN IF NOT EXISTS isbn TEXT;
ALTER TABLE content ADD COLUMN IF NOT EXISTS open_library_key TEXT;
;
