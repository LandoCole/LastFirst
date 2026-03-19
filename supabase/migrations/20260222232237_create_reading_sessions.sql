
-- Table: reading_sessions
create table public.reading_sessions (
  id uuid primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  document_id uuid not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_seconds int not null default 0,
  words_read int not null default 0,
  average_wpm int,
  start_token_index int,
  end_token_index int,
  reading_mode text,
  chapters_visited text[] default '{}',
  created_at timestamptz default now()
);

-- RLS
alter table public.reading_sessions enable row level security;

create policy "Users manage own sessions"
  on public.reading_sessions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Indexes
create index idx_reading_sessions_user_date
  on public.reading_sessions (user_id, started_at desc);

create index idx_reading_sessions_user_doc
  on public.reading_sessions (user_id, document_id);

-- View: daily summaries
create view public.reading_daily_summaries as
select
  user_id,
  document_id,
  date(started_at at time zone 'UTC') as reading_date,
  sum(duration_seconds) as total_seconds,
  sum(words_read) as total_words,
  avg(average_wpm)::int as avg_wpm,
  count(*) as session_count
from public.reading_sessions
where ended_at is not null
group by user_id, document_id, reading_date;

-- View: user reading stats
create view public.user_reading_stats as
select
  user_id,
  sum(duration_seconds) as total_reading_seconds,
  sum(words_read) as total_words_read,
  avg(average_wpm)::int as lifetime_avg_wpm,
  count(distinct document_id) as books_touched,
  count(distinct date(started_at at time zone 'UTC')) as days_read,
  max(started_at) as last_read_at
from public.reading_sessions
where ended_at is not null
group by user_id;

-- Function: get_reading_streak
create or replace function public.get_reading_streak(p_user_id uuid)
returns table(current_streak int, longest_streak int) as $$
with daily as (
  select distinct date(started_at at time zone 'UTC') as d
  from public.reading_sessions
  where user_id = p_user_id and ended_at is not null
),
grouped as (
  select d, d - make_interval(days => row_number() over (order by d)::int) as grp
  from daily
),
streaks as (
  select count(*)::int as streak_len, max(d) as streak_end
  from grouped group by grp
)
select
  coalesce((select streak_len from streaks where streak_end >= current_date - 1 order by streak_end desc limit 1), 0),
  coalesce((select max(streak_len) from streaks), 0);
$$ language sql stable security definer;
;
