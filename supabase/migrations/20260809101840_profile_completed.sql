alter table public.profiles
  add column if not exists profile_completed boolean not null default false;
