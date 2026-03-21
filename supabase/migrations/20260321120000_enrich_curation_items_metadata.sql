-- Enrich curation_items with metadata fields so external items
-- can be displayed with full preview data without a joined content record.

ALTER TABLE curation_items ADD COLUMN IF NOT EXISTS external_word_count INTEGER;
ALTER TABLE curation_items ADD COLUMN IF NOT EXISTS external_estimated_read_minutes INTEGER;
ALTER TABLE curation_items ADD COLUMN IF NOT EXISTS external_file_type TEXT;
ALTER TABLE curation_items ADD COLUMN IF NOT EXISTS external_availability TEXT DEFAULT 'full_text';
ALTER TABLE curation_items ADD COLUMN IF NOT EXISTS external_image_url TEXT;
