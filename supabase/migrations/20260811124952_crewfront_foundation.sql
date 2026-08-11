-- Crewfront keeps competitive progression relational and server-owned. Tile geometry
-- remains in the existing canonical atlas; shared territory stores only sector IDs.
create table public.card_blueprints (
  id text primary key,
  payload jsonb not null,
  rules_version integer not null default 1,
  created_at timestamptz not null default now()
);

create table public.player_card_blueprints (
  user_id uuid not null references auth.users(id) on delete cascade,
  blueprint_id text not null references public.card_blueprints(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, blueprint_id)
);

create table public.card_instances (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  blueprint_id text not null references public.card_blueprints(id),
  integrity smallint not null default 3 check (integrity between 1 and 3),
  is_protected boolean not null default false,
  is_bound boolean not null default true,
  crafted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.battle_decks (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 32),
  relic_id uuid,
  updated_at timestamptz not null default now()
);

create table public.battle_deck_cards (
  deck_id uuid not null references public.battle_decks(id) on delete cascade,
  card_instance_id uuid not null references public.card_instances(id) on delete cascade,
  slot smallint not null check (slot between 0 and 11),
  primary key (deck_id, slot),
  unique (deck_id, card_instance_id)
);

create table public.crews (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 3 and 24),
  invite_code text not null unique check (char_length(invite_code) between 6 and 16),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.crew_members (
  crew_id uuid not null references public.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'officer', 'member')),
  joined_at timestamptz not null default now(),
  primary key (crew_id, user_id)
);

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.is_crew_member(p_crew_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1 from public.crew_members m
      where m.crew_id = p_crew_id and m.user_id = (select auth.uid())
    );
$$;
revoke all on function private.is_crew_member(uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.is_crew_member(uuid) to authenticated;

create table public.crew_chat_messages (
  id uuid primary key default gen_random_uuid(),
  crew_id uuid not null references public.crews(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500 and body !~* 'https?://'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days'
);

create table public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid references public.crew_chat_messages(id) on delete set null,
  reason text not null check (char_length(reason) between 1 and 300),
  created_at timestamptz not null default now()
);

create table public.crew_seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  is_active boolean not null default false
);

create table public.crew_sector_control (
  season_id uuid not null references public.crew_seasons(id) on delete cascade,
  sector_id text not null,
  crew_id uuid not null references public.crews(id) on delete cascade,
  controlled_at timestamptz not null default now(),
  shield_until timestamptz not null default now(),
  primary key (season_id, sector_id)
);

create table public.battle_rooms (
  id uuid primary key default gen_random_uuid(),
  season_id uuid references public.crew_seasons(id) on delete set null,
  sector_id text,
  status text not null check (status in ('lobby', 'active', 'settled', 'void')),
  rules_version integer not null default 1,
  state jsonb not null default '{}'::jsonb,
  turn_deadline timestamptz,
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create table public.battle_room_players (
  room_id uuid not null references public.battle_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  crew_id uuid references public.crews(id) on delete set null,
  team text not null check (team in ('dawn', 'dusk')),
  deck_id uuid references public.battle_decks(id) on delete set null,
  is_ai boolean not null default false,
  primary key (room_id, user_id)
);

create table public.card_stakes (
  room_id uuid not null references public.battle_rooms(id) on delete cascade,
  card_instance_id uuid not null references public.card_instances(id) on delete restrict,
  owner_id uuid not null references auth.users(id) on delete cascade,
  settled_to uuid references auth.users(id) on delete set null,
  primary key (room_id, card_instance_id)
);

create index card_instances_owner_idx on public.card_instances(owner_id);
create index crew_chat_messages_crew_created_idx on public.crew_chat_messages(crew_id, created_at desc);
create index crew_sector_control_crew_idx on public.crew_sector_control(crew_id);
create index battle_room_players_user_idx on public.battle_room_players(user_id);

alter table public.card_blueprints enable row level security;
alter table public.player_card_blueprints enable row level security;
alter table public.card_instances enable row level security;
alter table public.battle_decks enable row level security;
alter table public.battle_deck_cards enable row level security;
alter table public.crews enable row level security;
alter table public.crew_members enable row level security;
alter table public.crew_chat_messages enable row level security;
alter table public.user_blocks enable row level security;
alter table public.content_reports enable row level security;
alter table public.crew_seasons enable row level security;
alter table public.crew_sector_control enable row level security;
alter table public.battle_rooms enable row level security;
alter table public.battle_room_players enable row level security;
alter table public.card_stakes enable row level security;

create policy card_blueprints_read on public.card_blueprints for select to authenticated using (true);
create policy player_card_blueprints_owner on public.player_card_blueprints for select to authenticated using ((select auth.uid()) = user_id);
create policy card_instances_owner on public.card_instances for select to authenticated using ((select auth.uid()) = owner_id);
create policy battle_decks_owner on public.battle_decks for select to authenticated using ((select auth.uid()) = owner_id);
create policy battle_deck_cards_owner on public.battle_deck_cards for select to authenticated using (exists (select 1 from public.battle_decks d where d.id = deck_id and d.owner_id = (select auth.uid())));
create policy crews_member_read on public.crews for select to authenticated using (private.is_crew_member(id));
create policy crew_members_member_read on public.crew_members for select to authenticated using (private.is_crew_member(crew_id));
create policy crew_chat_member_read on public.crew_chat_messages for select to authenticated using (private.is_crew_member(crew_id));
create policy crew_chat_member_insert on public.crew_chat_messages for insert to authenticated with check (author_id = (select auth.uid()) and private.is_crew_member(crew_id));
create policy user_blocks_owner on public.user_blocks for all to authenticated using ((select auth.uid()) = blocker_id) with check ((select auth.uid()) = blocker_id);
create policy reports_owner_insert on public.content_reports for insert to authenticated with check ((select auth.uid()) = reporter_id);
create policy seasons_read on public.crew_seasons for select to authenticated using (true);
create policy sector_control_read on public.crew_sector_control for select to authenticated using (true);
create policy battle_rooms_participant_read on public.battle_rooms for select to authenticated using (exists (select 1 from public.battle_room_players p where p.room_id = id and p.user_id = (select auth.uid())));
create policy battle_players_participant_read on public.battle_room_players for select to authenticated using (exists (select 1 from public.battle_room_players self where self.room_id = room_id and self.user_id = (select auth.uid())));
create policy card_stakes_participant_read on public.card_stakes for select to authenticated using (exists (select 1 from public.battle_room_players p where p.room_id = card_stakes.room_id and p.user_id = (select auth.uid())));

grant select on public.card_blueprints, public.player_card_blueprints, public.card_instances, public.battle_decks, public.battle_deck_cards, public.crews, public.crew_members, public.crew_chat_messages, public.crew_seasons, public.crew_sector_control, public.battle_rooms, public.battle_room_players, public.card_stakes to authenticated;
grant insert, delete on public.user_blocks to authenticated;
grant insert on public.crew_chat_messages, public.content_reports to authenticated;

-- No client receives INSERT/UPDATE/DELETE permission for competitive state.
-- Edge Functions use server credentials and transactional RPCs to create rooms,
-- validate turns, settle card stakes, and change sector control.
