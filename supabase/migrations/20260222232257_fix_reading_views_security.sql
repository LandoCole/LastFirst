
-- Fix views to use security invoker (RLS of querying user)
drop view if exists public.reading_daily_summaries;
create view public.reading_daily_summaries with (security_invoker = true) as
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

drop view if exists public.user_reading_stats;
create view public.user_reading_stats with (security_invoker = true) as
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

-- Fix function search_path
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
$$ language sql stable security definer
set search_path = public;
;
