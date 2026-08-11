-- Shared, short-lived environmental interpretation. Clients use Edge Functions;
-- raw provider features and geometry never enter the Data API or player saves.
create table public.biome_cache (
  cell_id text primary key,
  payload jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint biome_cache_cell_id_format check (cell_id ~ '^biome:[0-9]+:-?[0-9]+:-?[0-9]+$'),
  constraint biome_cache_expiry check (expires_at > fetched_at)
);

create index biome_cache_expiry_idx on public.biome_cache (expires_at);
alter table public.biome_cache enable row level security;
revoke all on public.biome_cache from anon, authenticated;

-- Event definitions and score aggregation are deliberately server-owned. A
-- future event function can publish summaries with Broadcast without exposing
-- claims or contribution rows through PostgREST.
create table public.regional_events (
  id uuid primary key default gen_random_uuid(),
  region_key text not null,
  event_type text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint regional_events_window check (ends_at > starts_at)
);

create table public.regional_event_contributions (
  event_id uuid not null references public.regional_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  contribution integer not null default 0 check (contribution >= 0),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.regional_events enable row level security;
alter table public.regional_event_contributions enable row level security;
revoke all on public.regional_events, public.regional_event_contributions from anon, authenticated;
