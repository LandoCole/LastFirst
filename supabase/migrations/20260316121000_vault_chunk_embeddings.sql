-- Semantic retrieval foundation for vault note chunks

ALTER TABLE vault_note_chunks
  ADD COLUMN IF NOT EXISTS embedding JSONB,
  ADD COLUMN IF NOT EXISTS embedding_model TEXT,
  ADD COLUMN IF NOT EXISTS embedded_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_vault_note_chunks_embedding_model
  ON vault_note_chunks(embedding_model);
