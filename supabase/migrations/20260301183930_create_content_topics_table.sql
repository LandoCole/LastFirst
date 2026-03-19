
CREATE TABLE content_topics (
  content_id UUID REFERENCES content(id) ON DELETE CASCADE,
  topic_slug TEXT REFERENCES topics(slug) ON DELETE CASCADE,
  relevance  FLOAT DEFAULT 1.0,
  source     TEXT,  -- 'author_tag', 'ai_inferred', 'user_tagged'
  PRIMARY KEY (content_id, topic_slug)
);

-- Enable RLS
ALTER TABLE content_topics ENABLE ROW LEVEL SECURITY;

-- Readable by authenticated users
CREATE POLICY "Content topics are readable by authenticated users" ON content_topics
  FOR SELECT TO authenticated USING (true);
;
