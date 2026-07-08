-- Phase 1 Feature J: login-milestone and level/band-completion badges.
-- check_and_grant_awards() is idempotent (checks actual current state, not
-- incremental events) and is called by the Android client after
-- record_login(), complete_practice_round(), and complete_band_upgrade_exam()
-- rather than embedded inside those RPCs, to avoid touching their
-- already-verified grading/streak logic.

begin;

create table public.award_definitions (
  id              text primary key,
  name_zh         text not null,
  description_zh  text,
  trigger_type    text not null check (trigger_type in ('login_count', 'level_complete', 'band_complete')),
  trigger_value   text not null,
  icon_name       text
);

create table public.user_awards (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  award_id     text not null references public.award_definitions(id),
  awarded_at   timestamptz not null default now(),
  seen_by_user boolean not null default false,
  unique (user_id, award_id)
);

create index on public.user_awards (user_id);

alter table public.award_definitions enable row level security;
alter table public.user_awards enable row level security;

create policy award_definitions_select_all
on public.award_definitions
for select
to authenticated
using (true);

create policy user_awards_select_own
on public.user_awards
for select
to authenticated
using (user_id = auth.uid());

insert into public.award_definitions (id, name_zh, description_zh, trigger_type, trigger_value, icon_name)
values
  ('bronze_duck',    '第一只鸭！',       '完成首次登录',        'login_count',   '1',   'duck_bronze'),
  ('login_streak_3', '初学者连续登录',   '累计登录 3 次',       'login_count',   '3',   'streak_freeze'),
  ('silver_duck',    '坚持一周',         '累计登录 7 次',       'login_count',   '7',   'duck_silver'),
  ('gold_duck',      '学习达人',         '累计登录 30 次',      'login_count',   '30',  'duck_gold'),
  ('platinum_duck',  '坚持不懈',         '累计登录 100 次',     'login_count',   '100', 'duck_platinum'),
  ('first_level',    '初露锋芒',         '完成 Level 1',        'level_complete', '1',   'level_1'),
  ('band4_starter',  'Band 4 通关新星',  '完成 Level 5',        'level_complete', '5',   'level_5');

create or replace function public.check_and_grant_awards(p_user_id uuid)
returns table (new_award_id text, new_award_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_login_count integer;
  v_def record;
begin
  if v_caller is null or v_caller <> p_user_id then
    raise exception 'Authentication required';
  end if;

  select p.login_count into v_login_count
  from public.profiles p
  where p.id = p_user_id;

  for v_def in
    select * from public.award_definitions where trigger_type = 'login_count'
  loop
    if v_login_count >= v_def.trigger_value::integer then
      insert into public.user_awards (user_id, award_id)
      values (p_user_id, v_def.id)
      on conflict (user_id, award_id) do nothing;
    end if;
  end loop;

  for v_def in
    select * from public.award_definitions where trigger_type = 'level_complete'
  loop
    if exists (
      select 1 from public.user_level_progress ulp
      where ulp.user_id = p_user_id
        and ulp.level_number = v_def.trigger_value::integer
        and ulp.is_completed
    ) then
      insert into public.user_awards (user_id, award_id)
      values (p_user_id, v_def.id)
      on conflict (user_id, award_id) do nothing;
    end if;
  end loop;

  for v_def in
    select * from public.award_definitions where trigger_type = 'band_complete'
  loop
    if exists (
      select 1 from public.band_upgrade_attempts bua
      where bua.user_id = p_user_id
        and bua.target_band = v_def.trigger_value::numeric
        and bua.passed
    ) then
      insert into public.user_awards (user_id, award_id)
      values (p_user_id, v_def.id)
      on conflict (user_id, award_id) do nothing;
    end if;
  end loop;

  return query
  select ua.award_id, ad.name_zh
  from public.user_awards ua
  join public.award_definitions ad on ad.id = ua.award_id
  where ua.user_id = p_user_id
    and not ua.seen_by_user;

  update public.user_awards
  set seen_by_user = true
  where user_id = p_user_id
    and not seen_by_user;
end;
$$;

revoke all on function public.check_and_grant_awards(uuid) from public, anon;
grant execute on function public.check_and_grant_awards(uuid) to authenticated;

commit;
