-- Phase 1 Feature B: login tracking. Every session start (app open / session
-- restore / sign-in) calls record_login(), which logs the event and updates
-- profiles.login_count. Distinct from the daily streak: a login alone does
-- not earn a streak day (only completing a practice round does, per
-- complete_practice_round in migration 202607050024).

begin;

alter table public.profiles
  add column if not exists login_count integer not null default 0,
  add column if not exists first_login_at timestamptz,
  add column if not exists last_login_at timestamptz;

create table public.user_login_log (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  logged_in_at timestamptz not null default now(),
  platform     text not null default 'android'
);

create index on public.user_login_log (user_id, logged_in_at desc);

alter table public.user_login_log enable row level security;

create policy user_login_log_select_own
on public.user_login_log
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.record_login()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_login_count integer;
  v_first_login_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  insert into public.user_login_log (user_id, logged_in_at, platform)
  values (v_user_id, now(), 'android');

  update public.profiles
  set login_count = coalesce(login_count, 0) + 1,
      last_login_at = now(),
      first_login_at = coalesce(first_login_at, now())
  where id = v_user_id
  returning login_count, first_login_at into v_login_count, v_first_login_at;

  if not found then
    raise exception 'Profile not found for authenticated user';
  end if;

  return jsonb_build_object(
    'login_count', v_login_count,
    'first_login_at', v_first_login_at
  );
end;
$$;

revoke all on function public.record_login() from public, anon;
grant execute on function public.record_login() to authenticated;

commit;
