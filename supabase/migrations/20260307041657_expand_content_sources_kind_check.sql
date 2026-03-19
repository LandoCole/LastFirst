
ALTER TABLE content_sources DROP CONSTRAINT content_sources_kind_check;
ALTER TABLE content_sources ADD CONSTRAINT content_sources_kind_check
  CHECK (kind = ANY (ARRAY['rss_feed', 'openlibrary_subject', 'arxiv_category', 'web', 'news_rss', 'wikipedia_feed', 'gutenberg_feed']));
;
