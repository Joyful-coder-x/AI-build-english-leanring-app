\set ON_ERROR_STOP on

-- Requires Band 4.0 content, levels for Band 4.5, and migration
-- 202607060026_band_upgrade_exam_core.sql.
-- All mutations are rolled back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000026',
  'band-upgrade-exam@example.com',
  '{"username":"band_upgrade_exam","nickname":"Band Upgrade Exam"}'::jsonb
);

insert into public.user_level_progress (
  user_id, level_number, is_unlocked, unlocked_at
)
values (
  '10000000-0000-0000-0000-000000000026',
  1,
  true,
  now()
)
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(public.user_level_progress.unlocked_at, now());

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000026',
  true
);
set local role authenticated;

do $$
declare
  v_payload jsonb;
  v_attempt_id uuid;
  v_question jsonb;
  v_position integer;
  v_answer text;
  v_result jsonb;
begin
  v_payload := public.start_band_upgrade_exam(4.5);
  v_attempt_id := (v_payload ->> 'attempt_id')::uuid;

  if jsonb_array_length(v_payload -> 'questions') <> 40 then
    raise exception 'Expected 40 exam questions, got %', jsonb_array_length(v_payload -> 'questions');
  end if;

  if exists (
    select 1
    from (
      select
        item ->> 'category' as category,
        count(*) as count
      from jsonb_array_elements(v_payload -> 'questions') item
      group by item ->> 'category'
    ) category_counts
    where (category = 'meaning' and count <> 10)
       or (category = 'listening' and count <> 10)
       or (category = 'spelling' and count <> 10)
       or (category = 'speaking' and count <> 10)
  ) or (
    select count(distinct item ->> 'category')
    from jsonb_array_elements(v_payload -> 'questions') item
  ) <> 4 then
    raise exception 'Expected 10 questions each for meaning/listening/spelling/speaking: %',
      v_payload -> 'category_counts';
  end if;

  if (
    select count(distinct item ->> 'question_id')
    from jsonb_array_elements(v_payload -> 'questions') item
  ) <> 40 then
    raise exception 'Band upgrade exam should contain 40 unique questions';
  end if;

  for v_question in
    select value
    from jsonb_array_elements(v_payload -> 'questions') with ordinality as q(value, ordinality)
    order by ordinality
  loop
    v_position := (v_question ->> 'position')::integer;

    if v_position <= 36 then
      v_answer := case
        when v_question ->> 'question_type_key' = 'speaking_repeat'
          then 'I said it clearly.'
        else v_question ->> 'headword'
      end;
    else
      v_answer := '__wrong__';
    end if;

    perform public.save_band_upgrade_answer(v_attempt_id, v_position, v_answer, 100);
  end loop;

  v_result := public.complete_band_upgrade_exam(v_attempt_id);

  if (v_result ->> 'correct_count')::integer <> 36 then
    raise exception 'Expected 36 correct on failed attempt, got %', v_result ->> 'correct_count';
  end if;

  if (v_result ->> 'passed')::boolean is true then
    raise exception '36/40 must fail.';
  end if;
end;
$$;

do $$
declare
  v_payload jsonb;
  v_attempt_id uuid;
  v_question jsonb;
  v_position integer;
  v_answer text;
  v_result jsonb;
  v_first_target_level integer;
  v_target_unlocked boolean;
begin
  v_payload := public.start_band_upgrade_exam(4.5);
  v_attempt_id := (v_payload ->> 'attempt_id')::uuid;

  for v_question in
    select value
    from jsonb_array_elements(v_payload -> 'questions') with ordinality as q(value, ordinality)
    order by ordinality
  loop
    v_position := (v_question ->> 'position')::integer;

    if v_position <= 37 then
      v_answer := case
        when v_question ->> 'question_type_key' = 'speaking_repeat'
          then 'I said it clearly.'
        else v_question ->> 'headword'
      end;
    else
      v_answer := '__wrong__';
    end if;

    perform public.save_band_upgrade_answer(v_attempt_id, v_position, v_answer, 100);
  end loop;

  v_result := public.complete_band_upgrade_exam(v_attempt_id);

  if (v_result ->> 'correct_count')::integer <> 37 then
    raise exception 'Expected 37 correct on passing attempt, got %', v_result ->> 'correct_count';
  end if;

  if (v_result ->> 'passed')::boolean is not true then
    raise exception '37/40 must pass.';
  end if;

  select min(l.level_number)
  into v_first_target_level
  from public.levels l
  join public.bands b on b.id = l.band_id
  where b.band_score = 4.5;

  select is_unlocked
  into v_target_unlocked
  from public.user_level_progress
  where user_id = auth.uid()
    and level_number = v_first_target_level;

  if coalesce(v_target_unlocked, false) is not true then
    raise exception 'Passing Band 4 exam did not unlock first Band 4.5 level %', v_first_target_level;
  end if;
end;
$$;

rollback;
