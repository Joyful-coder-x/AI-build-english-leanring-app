-- Persist daily practice streaks and keep round rewards server-owned.

begin;

alter table public.profiles
  add column if not exists current_streak_days integer not null default 0,
  add column if not exists longest_streak_days integer not null default 0,
  add column if not exists last_practice_date date;

alter table public.profiles
  drop constraint if exists profiles_streak_days_non_negative;

alter table public.profiles
  add constraint profiles_streak_days_non_negative
  check (
    current_streak_days >= 0
    and longest_streak_days >= current_streak_days
  );

-- Preserve useful history for accounts that completed rounds before this
-- migration. This establishes at least today's/most recent one-day streak;
-- future completions maintain the exact consecutive-day count.
with latest_activity as (
  select
    session_row.user_id,
    max(
      timezone(
        coalesce(settings_row.reminder_timezone, 'UTC'),
        session_row.completed_at
      )::date
    ) as activity_date
  from public.practice_sessions session_row
  left join public.user_settings settings_row
    on settings_row.user_id = session_row.user_id
  where session_row.status = 'completed'
    and session_row.completed_at is not null
  group by session_row.user_id
)
update public.profiles profile_row
set last_practice_date = latest_activity.activity_date,
    current_streak_days = case
      when latest_activity.activity_date >=
        timezone(
          coalesce(settings_row.reminder_timezone, 'UTC'),
          now()
        )::date - 1
      then greatest(profile_row.current_streak_days, 1)
      else 0
    end,
    longest_streak_days = greatest(profile_row.longest_streak_days, 1)
from latest_activity
left join public.user_settings settings_row
  on settings_row.user_id = latest_activity.user_id
where profile_row.id = latest_activity.user_id;

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
  v_answered integer;
  v_correct integer;
  v_completed_level boolean;
  v_today date;
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

  select timezone(
    coalesce(settings_row.reminder_timezone, 'UTC'),
    now()
  )::date
  into v_today
  from public.profiles profile_row
  left join public.user_settings settings_row
    on settings_row.user_id = profile_row.id
  where profile_row.id = v_user_id;

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

  update public.profiles profile_row
  set duck_power = profile_row.duck_power + v_correct,
      current_streak_days = case
        when profile_row.last_practice_date = v_today
          then profile_row.current_streak_days
        when profile_row.last_practice_date = v_today - 1
          then profile_row.current_streak_days + 1
        else 1
      end,
      longest_streak_days = greatest(
        profile_row.longest_streak_days,
        case
          when profile_row.last_practice_date = v_today
            then profile_row.current_streak_days
          when profile_row.last_practice_date = v_today - 1
            then profile_row.current_streak_days + 1
          else 1
        end
      ),
      last_practice_date = v_today
  where profile_row.id = v_user_id;

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
    'level_completed', v_completed_level
  );
end;
$$;

revoke all on function public.complete_practice_round(uuid) from public, anon;
grant execute on function public.complete_practice_round(uuid) to authenticated;

commit;
