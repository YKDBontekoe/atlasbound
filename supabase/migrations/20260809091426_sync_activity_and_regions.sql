alter table public.player_state
  add column if not exists activity_history jsonb not null default '{}'::jsonb,
  add column if not exists regions jsonb not null default '{}'::jsonb;
