create table public.weather_cache (
  cell_id text primary key,
  payload jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint weather_cache_cell_id_format check (cell_id ~ '^weather:[0-9]+:-?[0-9]+:-?[0-9]+$'),
  constraint weather_cache_expiry check (expires_at > fetched_at)
);

create index weather_cache_expiry_idx on public.weather_cache (expires_at);

-- Weather is shared server cache data, never account-owned Data API state.
alter table public.weather_cache enable row level security;
revoke all on public.weather_cache from anon, authenticated;
