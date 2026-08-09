create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Explorer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (char_length(display_name) between 1 and 40)
);

create table public.player_tiles (
  user_id uuid not null references auth.users(id) on delete cascade,
  tile_id text not null,
  q integer not null,
  r integer not null,
  state integer not null,
  mastery_xp integer not null default 0,
  visit_count integer not null default 0,
  unique_visit_days integer not null default 0,
  activity_stamps jsonb not null default '[]'::jsonb,
  first_visited_at timestamptz,
  last_visited_at timestamptz,
  weekly_charge integer not null default 0,
  region_ids jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, tile_id),
  constraint player_tiles_id_format check (tile_id like 'hex:%'),
  constraint player_tiles_nonnegative check (mastery_xp >= 0 and visit_count >= 0 and unique_visit_days >= 0)
);

create table public.player_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  discovery_xp integer not null default 0,
  familiarity_xp integer not null default 0,
  activities_completed integer not null default 0,
  save_revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint player_progress_nonnegative check (discovery_xp >= 0 and familiarity_xp >= 0 and activities_completed >= 0)
);

create table public.player_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0,
  frontier jsonb not null default '{}'::jsonb,
  territory jsonb not null default '{}'::jsonb,
  treasure jsonb not null default '{}'::jsonb,
  inventory jsonb not null default '{}'::jsonb,
  factory jsonb not null default '{}'::jsonb,
  idle jsonb not null default '{}'::jsonb,
  skills jsonb not null default '{}'::jsonb,
  pinpoint jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.activity_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  started_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create table public.pinpoint_games (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  ended_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create index player_tiles_user_updated_idx on public.player_tiles (user_id, updated_at);
create index activity_sessions_user_started_idx on public.activity_sessions (user_id, started_at desc);
create index pinpoint_games_user_ended_idx on public.pinpoint_games (user_id, ended_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger player_tiles_set_updated_at before update on public.player_tiles
for each row execute function public.set_updated_at();
create trigger player_progress_set_updated_at before update on public.player_progress
for each row execute function public.set_updated_at();
create trigger player_state_set_updated_at before update on public.player_state
for each row execute function public.set_updated_at();
create trigger activity_sessions_set_updated_at before update on public.activity_sessions
for each row execute function public.set_updated_at();
create trigger pinpoint_games_set_updated_at before update on public.pinpoint_games
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  insert into public.player_progress (user_id) values (new.id) on conflict (user_id) do nothing;
  insert into public.player_state (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.player_tiles enable row level security;
alter table public.player_progress enable row level security;
alter table public.player_state enable row level security;
alter table public.activity_sessions enable row level security;
alter table public.pinpoint_games enable row level security;

create policy profiles_owner on public.profiles for all to authenticated
using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy tiles_owner on public.player_tiles for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy progress_owner on public.player_progress for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy state_owner on public.player_state for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy sessions_owner on public.activity_sessions for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy games_owner on public.pinpoint_games for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.delete_my_data()
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.player_tiles where user_id = (select auth.uid());
  delete from public.activity_sessions where user_id = (select auth.uid());
  delete from public.pinpoint_games where user_id = (select auth.uid());
  delete from public.player_state where user_id = (select auth.uid());
  delete from public.player_progress where user_id = (select auth.uid());
  delete from public.profiles where id = (select auth.uid());
end;
$$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.player_tiles,
  public.player_progress, public.player_state, public.activity_sessions,
  public.pinpoint_games to authenticated;
grant execute on function public.delete_my_data() to authenticated;
