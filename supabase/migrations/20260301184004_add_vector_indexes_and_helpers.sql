
-- HNSW index on content embeddings for fast similarity search
CREATE INDEX IF NOT EXISTS idx_content_embedding_hnsw ON content
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- HNSW index on agent_memory embeddings
CREATE INDEX IF NOT EXISTS idx_agent_memory_embedding_hnsw ON agent_memory
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- Function: match content by embedding with exclusion set
CREATE OR REPLACE FUNCTION match_content_candidates(
  query_embedding vector(1536),
  match_count INT DEFAULT 30,
  exclude_ids UUID[] DEFAULT '{}'
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  author TEXT,
  summary TEXT,
  topics TEXT[],
  difficulty_level TEXT,
  word_count INT,
  source_type TEXT,
  similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.title,
    c.author,
    c.summary,
    c.topics,
    c.difficulty_level,
    c.word_count,
    c.source_type,
    1 - (c.embedding <=> query_embedding) AS similarity
  FROM content c
  WHERE c.embedding IS NOT NULL
    AND c.id != ALL(exclude_ids)
  ORDER BY c.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- Function: match agent memories by embedding
CREATE OR REPLACE FUNCTION match_agent_memories(
  p_user_id UUID,
  query_embedding vector(1536),
  match_count INT DEFAULT 10
)
RETURNS TABLE (
  id UUID,
  kind TEXT,
  content TEXT,
  importance FLOAT,
  metadata JSONB,
  similarity FLOAT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    am.id,
    am.kind,
    am.content,
    am.importance,
    am.metadata,
    1 - (am.embedding <=> query_embedding) AS similarity,
    am.created_at
  FROM agent_memory am
  WHERE am.user_id = p_user_id
    AND am.embedding IS NOT NULL
    AND (am.expires_at IS NULL OR am.expires_at > now())
  ORDER BY am.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
;
