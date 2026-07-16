-- QA test accounts for manually eyeballing level-up and streak behavior in
-- the Android app. The two auth.users rows were created ahead of this script
-- via the same POST /auth/v1/signup call the app's register() flow uses
-- (see app/src/main/java/com/example/firsttest/data/repository/
-- SupabaseAuthRepository.kt), so both accounts are real, password-loggable
-- accounts, not a raw auth.users insert.
--
-- qa_level1_near_up / QaLevelUp2026!  -> id 0fb80de3-87f3-47bf-8ad2-9337711bcdbd
--   Almost done with Level 1: all 45 new-word senses seen, 40 already
--   qualify (learning_state='reviewing', spaced_success_count>=1), 5 seen
--   but not yet qualifying and due for review right now. Level 1 completion
--   needs seen=45 and qualifying>=ceil(45*0.9)=41 (see
--   public.refresh_level_completion), so one more successful spaced review
--   on any of the 5 pending senses completes the level.
--
-- qa_streak_5day / QaStreak2026!      -> id 59825550-bcbe-4624-a9a2-64303f03e010
--   5 completed practice_sessions on 5 consecutive calendar days (today back
--   to 4 days ago) -- this is what the Profile heatmap reads
--   (VocabRepository.getPracticeSessionDates() filters practice_sessions by
--   status='completed'/started_at). profiles.current_streak_days /
--   longest_streak_days / last_practice_date are set directly, because
--   complete_practice_round only advances the streak one day at a time from
--   real now() and can't be backdated through the RPC. Also calls
--   record_login() three times to populate profiles.login_count /
--   user_login_log (a separate feature from the streak -- see
--   backend/supabase/migrations/202607070030_login_tracking.sql, which
--   explicitly does not affect the streak).

begin;

-- Onboarding completion is tracked in onboarding_profiles.flow_state, not
-- just profiles.onboarding_status (see 202606240007_onboarding_starts_at_level_one.sql):
-- save_onboarding_answer() only flips flow_state to 'home_ready' and unlocks
-- Level 1 on the fifth answer. Reproduce both effects directly here.
insert into public.onboarding_profiles (
  user_id, questionnaire_version, answers, flow_state,
  current_question_index, completed_at
)
values
  ('0fb80de3-87f3-47bf-8ad2-9337711bcdbd', 'v1',
   jsonb_build_object(
     'occupation', 'student', 'ielts_reason', 'study_abroad',
     'self_reported_level', 'cet4', 'target_band', '6_0',
     'prep_timeline', '3_to_6_months'
   ),
   'home_ready', 5, now()),
  ('59825550-bcbe-4624-a9a2-64303f03e010', 'v1',
   jsonb_build_object(
     'occupation', 'employed', 'ielts_reason', 'work',
     'self_reported_level', 'cet6', 'target_band', '6_5',
     'prep_timeline', 'under_3_months'
   ),
   'home_ready', 5, now())
on conflict (user_id) do update
set flow_state = excluded.flow_state,
    answers = excluded.answers,
    current_question_index = excluded.current_question_index,
    completed_at = coalesce(public.onboarding_profiles.completed_at, excluded.completed_at);

update public.profiles
set onboarding_status = 'completed'
where id in (
  '0fb80de3-87f3-47bf-8ad2-9337711bcdbd',
  '59825550-bcbe-4624-a9a2-64303f03e010'
);

insert into public.user_level_progress (user_id, level_number, is_unlocked, unlocked_at)
values
  ('0fb80de3-87f3-47bf-8ad2-9337711bcdbd', 1, true, now()),
  ('59825550-bcbe-4624-a9a2-64303f03e010', 1, true, now())
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(public.user_level_progress.unlocked_at, excluded.unlocked_at);

select set_config('request.jwt.claim.sub', '0fb80de3-87f3-47bf-8ad2-9337711bcdbd', true);
set local role authenticated;
select public.get_user_bootstrap_state();
reset role;

select set_config('request.jwt.claim.sub', '59825550-bcbe-4624-a9a2-64303f03e010', true);
set local role authenticated;
select public.get_user_bootstrap_state();
reset role;

-- ---------------------------------------------------------------------
-- qa_level1_near_up: 40 qualifying senses + 5 pending-review senses
-- ---------------------------------------------------------------------
with level1_senses as (
  select sense_id, row_number() over (order by order_in_level) as rn
  from public.level_sense_assignments
  where level_number = 1 and placement_type = 'new'
)
insert into public.user_sense_mastery (
  user_id, sense_id, seen_count, correct_count, wrong_count,
  consecutive_correct_count, recent_results, review_stage, mastery_score,
  learning_state, spaced_success_count, has_active_recall_success,
  difficulty_level, first_seen_at, first_correct_at, last_correct_at,
  last_seen_at, next_due_at, mastered_at, updated_at
)
select
  '0fb80de3-87f3-47bf-8ad2-9337711bcdbd'::uuid, sense_id,
  3, 3, 0, 3, array[true, true, true], 2, 0.75,
  'reviewing'::sense_learning_state_enum, 1, true, 0,
  now() - interval '3 days', now() - interval '3 days', now() - interval '1 day',
  now() - interval '1 day', now() + interval '7 days', null::timestamptz, now()
from level1_senses where rn <= 40
union all
select
  '0fb80de3-87f3-47bf-8ad2-9337711bcdbd'::uuid, sense_id,
  1, 0, 1, 0, array[false], 0, 0.1,
  'learning'::sense_learning_state_enum, 0, false, 0,
  now() - interval '1 day', null::timestamptz, null::timestamptz,
  now() - interval '1 day', now() - interval '1 hour', null::timestamptz, now()
from level1_senses where rn > 40
on conflict (user_id, sense_id) do update
set seen_count = excluded.seen_count,
    correct_count = excluded.correct_count,
    wrong_count = excluded.wrong_count,
    consecutive_correct_count = excluded.consecutive_correct_count,
    recent_results = excluded.recent_results,
    review_stage = excluded.review_stage,
    mastery_score = excluded.mastery_score,
    learning_state = excluded.learning_state,
    spaced_success_count = excluded.spaced_success_count,
    has_active_recall_success = excluded.has_active_recall_success,
    first_seen_at = excluded.first_seen_at,
    first_correct_at = excluded.first_correct_at,
    last_correct_at = excluded.last_correct_at,
    last_seen_at = excluded.last_seen_at,
    next_due_at = excluded.next_due_at,
    updated_at = now();

-- ---------------------------------------------------------------------
-- qa_streak_5day: 5 consecutive completed practice days + streak counters
-- ---------------------------------------------------------------------
insert into public.practice_sessions (
  user_id, level_number, session_type, status, started_at, completed_at,
  correct_count, total_count, star_rating, base_power
)
select
  '59825550-bcbe-4624-a9a2-64303f03e010', 1, 'daily', 'completed',
  (current_date - offs)::timestamptz + interval '10 hours',
  (current_date - offs)::timestamptz + interval '10 hours 15 minutes',
  18, 20, 3, 40
from generate_series(0, 4) as offs;

update public.profiles
set current_streak_days = 5,
    longest_streak_days = greatest(longest_streak_days, 5),
    last_practice_date = current_date
where id = '59825550-bcbe-4624-a9a2-64303f03e010';

select set_config('request.jwt.claim.sub', '59825550-bcbe-4624-a9a2-64303f03e010', true);
set local role authenticated;
select public.record_login();
select public.record_login();
select public.record_login();
reset role;

commit;

-- Sanity check after running the block above:
select
  p.id, p.nickname, p.onboarding_status, ob.flow_state,
  ulp.is_unlocked as level1_unlocked, ulp.is_completed as level1_completed,
  ulp.progress as level1_progress,
  p.current_streak_days, p.longest_streak_days, p.last_practice_date, p.login_count
from public.profiles p
left join public.onboarding_profiles ob on ob.user_id = p.id
left join public.user_level_progress ulp on ulp.user_id = p.id and ulp.level_number = 1
where p.id in (
  '0fb80de3-87f3-47bf-8ad2-9337711bcdbd',
  '59825550-bcbe-4624-a9a2-64303f03e010'
);
