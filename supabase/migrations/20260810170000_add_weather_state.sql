alter table public.player_state
  add column if not exists weather jsonb not null default '{}'::jsonb;

-- Weather is part of the owner's cloud snapshot; the existing player_state
-- owner policy covers this JSON payload and no new exposed table is needed.
