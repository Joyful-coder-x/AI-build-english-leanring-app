-- Persist 我的道具 (streak protection / challenge key) and let a missed day
-- auto-consume 连胜保护 instead of resetting the streak.

begin;

create table public.user_props (
  user_id uuid not null references public.profiles(id) on delete cascade,
  prop_type text not null check (prop_type in ('streak_protection', 'challenge_key')),
  count integer not null default 0 check (count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, prop_type)
);

alter table public.user_props enable row level security;

create policy user_props_select_own
on public.user_props
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.grant_prop(
  p_prop_type text,
  p_count integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_new_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if p_prop_type not in ('streak_protection', 'challenge_key') then
    raise exception 'Invalid prop_type: %', p_prop_type;
  end if;
  if p_count <= 0 then
    raise exception 'p_count must be positive';
  end if;

  insert into public.user_props (user_id, prop_type, count, updated_at)
  values (v_user_id, p_prop_type, p_count, now())
  on conflict (user_id, prop_type)
  do update set count = public.user_props.count + excluded.count,
                updated_at = now()
  returning count into v_new_count;

  return jsonb_build_object('prop_type', p_prop_type, 'count', v_new_count);
end;
$$;

revoke all on function public.grant_prop(text, integer) from public, anon;
grant execute on function public.grant_prop(text, integer) to authenticated;

-- Recreate complete_practice_round: same behavior, plus a one-day-gap
-- streak-protection consumption so 连胜保护 actually does something.
create or replace function public.complete_practice_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_profile public.profiles%rowtype;
  v_answered integer;
  v_correct integer;
  v_completed_level boolean;
  v_today date;
  v_new_streak integer;
  v_protection_consumed boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status = 'completed' then
    return jsonb_build_object(
      'round_id', v_round.id,
      'correct_count', v_round.correct_count,
      'question_count', v_round.question_count,
      'star_rating', case
        when v_round.correct_count = v_round.question_count then 3
        when v_round.correct_count::numeric / v_round.question_count >= 0.80 then 2
        when v_round.correct_count::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      'duck_power_earned', v_round.correct_count,
      'already_completed', true,
      'level_completed', (
        select is_completed
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = v_round.level_number
      )
    );
  end if;

  select
    count(*) filter (where answered_at is not null),
    count(*) filter (where is_correct)
  into v_answered, v_correct
  from public.practice_round_questions
  where round_id = p_round_id;

  if v_answered <> v_round.question_count then
    raise exception 'All round questions must be answered before completion';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  select timezone(
    coalesce(settings_row.reminder_timezone, 'UTC'),
    now()
  )::date
  into v_today
  from public.user_settings settings_row
  where settings_row.user_id = v_user_id;

  if v_today is null then
    v_today := (now() at time zone 'UTC')::date;
  end if;

  if v_profile.last_practice_date = v_today then
    v_new_streak := v_profile.current_streak_days;
  elsif v_profile.last_practice_date = v_today - 1 then
    v_new_streak := v_profile.current_streak_days + 1;
  elsif v_profile.last_practice_date = v_today - 2 then
    update public.user_props
    set count = count - 1,
        updated_at = now()
    where user_id = v_user_id
      and prop_type = 'streak_protection'
      and count > 0
    returning true into v_protection_consumed;

    v_new_streak := case
      when v_protection_consumed then v_profile.current_streak_days + 1
      else 1
    end;
  else
    v_new_streak := 1;
  end if;

  update public.practice_rounds
  set status = 'completed',
      correct_count = v_correct,
      completed_at = now()
  where id = p_round_id;

  update public.practice_sessions
  set status = 'completed',
      completed_at = now(),
      correct_count = v_correct,
      total_count = v_round.question_count,
      star_rating = case
        when v_correct = v_round.question_count then 3
        when v_correct::numeric / v_round.question_count >= 0.80 then 2
        when v_correct::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      base_power = v_correct,
      duck_power_earned = v_correct
  where id = v_round.session_id;

  update public.profiles
  set duck_power = v_profile.duck_power + v_correct,
      current_streak_days = v_new_streak,
      longest_streak_days = greatest(v_profile.longest_streak_days, v_new_streak),
      last_practice_date = v_today
  where id = v_user_id;

  update public.user_level_progress
  set progress = greatest(
        progress,
        case
          when v_round.question_count > 0
            then v_correct::numeric / v_round.question_count
          else 0
        end
      ),
      best_star_rating = greatest(
        best_star_rating,
        case
          when v_correct = v_round.question_count then 3
          when v_correct::numeric / v_round.question_count >= 0.80 then 2
          when v_correct::numeric / v_round.question_count >= 0.60 then 1
          else 0
        end
      ),
      completed_session_count = completed_session_count + 1,
      updated_at = now()
  where user_id = v_user_id
    and level_number = v_round.level_number;

  v_completed_level := public.refresh_level_completion(
    v_user_id,
    v_round.level_number
  );

  return jsonb_build_object(
    'round_id', p_round_id,
    'correct_count', v_correct,
    'question_count', v_round.question_count,
    'star_rating', case
      when v_correct = v_round.question_count then 3
      when v_correct::numeric / v_round.question_count >= 0.80 then 2
      when v_correct::numeric / v_round.question_count >= 0.60 then 1
      else 0
    end,
    'duck_power_earned', v_correct,
    'already_completed', false,
    'level_completed', v_completed_level,
    'streak_protection_consumed', v_protection_consumed
  );
end;
$$;

revoke all on function public.complete_practice_round(uuid) from public, anon;
grant execute on function public.complete_practice_round(uuid) to authenticated;

commit;
