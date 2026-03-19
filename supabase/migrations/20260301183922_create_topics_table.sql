
CREATE TABLE topics (
  slug        TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  parent_slug TEXT REFERENCES topics(slug),
  description TEXT,
  embedding   vector(1536)
);

-- Enable RLS
ALTER TABLE topics ENABLE ROW LEVEL SECURITY;

-- Topics are readable by everyone
CREATE POLICY "Topics are publicly readable" ON topics
  FOR SELECT USING (true);
;
