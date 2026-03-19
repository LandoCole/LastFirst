CREATE TABLE public.catalog (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    author TEXT,
    cover_url TEXT,
    download_url TEXT,
    file_type TEXT DEFAULT 'epub',
    word_count INT,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Catalog is publicly readable"
    ON public.catalog FOR SELECT
    USING (true);;
