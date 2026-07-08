-- Finalises a new user's placement after the assessment (or skip).
-- Depends on 202606220005_user_bootstrap_and_onboarding.sql.
--
-- Scoring table sourced from ielts_bands.py in
-- github.com/ZainabZaman/IELTS_PracticeAndEvaluation.
--
-- Starting level mapping (240 levels across bands 4–8, 5 whole-band tiers):
--   band < 5.0  → level 1   (band 4 tier)
--   band 5.0–5.9 → level 49  (band 5 tier, first level)
--   band 6.0–6.9 → level 97  (band 6 tier)
--   band 7.0–7.9 → level 145 (band 7 tier)
--   band ≥ 8.0   → level 193 (band 8 tier)

begin;

create or replace function public.finalize_placement(
  p_ielts_band numeric,
  p_skip       boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  start_level     integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  start_level := case
    when p_skip or p_ielts_band < 5.0  then 1
    when p_ielts_band < 6.0            then 49
    when p_ielts_band < 7.0            then 97
    when p_ielts_band < 8.0            then 145
    else                                    193
  end;

  -- Mark onboarding complete
  update public.onboarding_profiles
  set flow_state            = 'home_ready',
      current_question_index = 5,
      completed_at           = now()
  where user_id = current_user_id;

  update public.profiles
  set onboarding_status = 'completed'
  where id = current_user_id;

  -- Unlock the computed starting level
  insert into public.user_level_progress (
    user_id,
    level_number,
    is_unlocked,
    unlocked_at
  )
  values (current_user_id, start_level, true, now())
  on conflict (user_id, level_number) do update
    set is_unlocked  = true,
        unlocked_at  = coalesce(
          public.user_level_progress.unlocked_at,
          excluded.unlocked_at
        );

  -- Always unlock level 1 so there is something to practice
  if start_level > 1 then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      unlocked_at
    )
    values (current_user_id, 1, true, now())
    on conflict (user_id, level_number) do update
      set is_unlocked = true,
          unlocked_at = coalesce(
            public.user_level_progress.unlocked_at,
            excluded.unlocked_at
          );
  end if;

  return public.build_user_bootstrap_state(current_user_id);
end;
$$;

revoke all on function public.finalize_placement(numeric, boolean) from public;
grant execute on function public.finalize_placement(numeric, boolean) to authenticated;

comment on function public.finalize_placement(numeric, boolean) is
  'Completes new-user placement: marks onboarding home_ready and unlocks the starting level derived from the IELTS band score.';

commit;
