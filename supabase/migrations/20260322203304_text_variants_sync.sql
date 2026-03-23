create table text_variants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  document_id uuid not null,
  unit_id text not null,
  kind text not null,
  name text not null,
  instructions text,
  status text not null default 'queued',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table text_variant_chunks (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid references text_variants on delete cascade not null,
  segment_id text not null,
  unit_id text not null,
  transformed_text text not null,
  status text not null default 'queued',
  updated_at timestamptz default now()
);

-- RLS policies: users can only access their own variants
alter table text_variants enable row level security;
alter table text_variant_chunks enable row level security;

create policy "Users manage own variants" on text_variants
  for all using (auth.uid() = user_id);

create policy "Users manage own chunks" on text_variant_chunks
  for all using (
    variant_id in (select id from text_variants where user_id = auth.uid())
  );

-- Index for fast lookup
create index idx_text_variants_doc on text_variants(user_id, document_id);
