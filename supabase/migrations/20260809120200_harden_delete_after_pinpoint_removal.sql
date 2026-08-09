create or replace function public.delete_my_data()
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.player_tiles where user_id = (select auth.uid());
  delete from public.activity_sessions where user_id = (select auth.uid());
  delete from public.player_state where user_id = (select auth.uid());
  delete from public.player_progress where user_id = (select auth.uid());
  delete from public.profiles where id = (select auth.uid());
end;
$$;
