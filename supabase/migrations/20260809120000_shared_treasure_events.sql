create table public.shared_treasure_events (
  id uuid primary key default gen_random_uuid(),
  tile_id text not null,
  latitude double precision not null,
  longitude double precision not null,
  name text not null,
  category text not null,
  clue text not null,
  distance_meters double precision not null default 0,
  is_vault boolean not null default false,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_by uuid references auth.users(id) on delete set null,
  claimed_at timestamptz,
  constraint shared_treasure_latitude check (latitude between -90 and 90),
  constraint shared_treasure_longitude check (longitude between -180 and 180),
  constraint shared_treasure_expiry check (expires_at > created_at)
);

create index shared_treasure_active_location_idx
  on public.shared_treasure_events (expires_at, latitude, longitude)
  where claimed_at is null;

alter table public.shared_treasure_events enable row level security;
create policy shared_treasure_nearby_read on public.shared_treasure_events
  for select to authenticated
  using (claimed_at is null and expires_at > now());

grant select on public.shared_treasure_events to authenticated;

create or replace function public.nearby_shared_treasures(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_meters double precision default 5000
)
returns setof public.shared_treasure_events
language sql
security invoker
set search_path = public
as $$
  select e.*
  from public.shared_treasure_events e
  where e.claimed_at is null
    and e.expires_at > now()
    and abs(e.latitude - p_latitude) <= p_radius_meters / 111320.0
    and abs(e.longitude - p_longitude) <= p_radius_meters / greatest(111320.0 * cos(radians(p_latitude)), 1.0)
    and (
      111320.0 * sqrt(
        power(e.latitude - p_latitude, 2)
        + power((e.longitude - p_longitude) * cos(radians(p_latitude)), 2)
      )
    ) <= p_radius_meters
  order by e.created_at desc;
$$;

grant execute on function public.nearby_shared_treasures(double precision, double precision, double precision) to authenticated;
revoke all on function public.nearby_shared_treasures(double precision, double precision, double precision) from public;

create or replace function public.claim_shared_treasure(
  p_event_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.shared_treasure_events;
begin
  if (select auth.uid()) is null then
    return jsonb_build_object('didWin', false);
  end if;

  update public.shared_treasure_events e
     set claimed_by = (select auth.uid()), claimed_at = now()
   where e.id = p_event_id
     and e.claimed_at is null
     and e.expires_at > now()
     and (111320.0 * sqrt(
       power(e.latitude - p_latitude, 2)
       + power((e.longitude - p_longitude) * cos(radians(p_latitude)), 2)
     )) <= 75.0
  returning e.* into claimed;

  if claimed.id is null then
    return jsonb_build_object('didWin', false);
  end if;

  return jsonb_build_object('didWin', true, 'event', to_jsonb(claimed));
end;
$$;

grant execute on function public.claim_shared_treasure(uuid, double precision, double precision) to authenticated;
revoke all on function public.claim_shared_treasure(uuid, double precision, double precision) from public;
