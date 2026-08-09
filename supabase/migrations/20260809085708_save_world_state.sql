create or replace function public.save_world_state(
  p_frontier jsonb,
  p_territory jsonb
)
returns bigint
language plpgsql
security invoker
set search_path = public
as $$
declare
  next_revision bigint;
begin
  insert into public.player_state (user_id, frontier, territory, revision)
  values ((select auth.uid()), p_frontier, p_territory, 1)
  on conflict (user_id) do update
    set frontier = excluded.frontier,
        territory = excluded.territory,
        revision = public.player_state.revision + 1,
        updated_at = now()
  returning revision into next_revision;
  return next_revision;
end;
$$;

grant execute on function public.save_world_state(jsonb, jsonb) to authenticated;
