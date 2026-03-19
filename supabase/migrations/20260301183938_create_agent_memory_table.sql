
CREATE TABLE agent_memory (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('observation', 'preference_learned', 'recommendation_outcome', 'pattern')),
  content    TEXT NOT NULL,
  importance FLOAT DEFAULT 0.5,
  embedding  vector(1536),
  metadata   JSONB DEFAULT '{}',
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_agent_memory_user_id ON agent_memory(user_id);
CREATE INDEX idx_agent_memory_kind ON agent_memory(user_id, kind);
CREATE INDEX idx_agent_memory_importance ON agent_memory(user_id, importance DESC);

-- Enable RLS
ALTER TABLE agent_memory ENABLE ROW LEVEL SECURITY;

-- Users can read their own memories
CREATE POLICY "Users can read own agent memories" ON agent_memory
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Service role can manage all memories
CREATE POLICY "Service role can manage agent memories" ON agent_memory
  FOR ALL TO service_role USING (true) WITH CHECK (true);
;
