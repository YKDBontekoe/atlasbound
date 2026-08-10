alter table public.player_state
  add column if not exists pulse jsonb not null default '{}'::jsonb;
