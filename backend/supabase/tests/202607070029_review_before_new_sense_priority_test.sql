\set ON_ERROR_STOP on

-- Requires the complete Band 4.0 content package (Level 1 with its 45 new
-- senses from level_sense_assignments).
-- Proves migration 202607070029 fixed Feature E: overdue reviews must be
-- placed at earlier round positions than new senses in the same round.
-- All mutations are rolled back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000029',
  'review-before-new@example.com',
  '{"username":"review_before_new","nickname":"Review Before New"}'::jsonb
);

do $$
declare
  v_user_id uuid := '10000000-0000-0000-0000-000000000029';
  v_sense_id uuid;
  v_max_review_position integer;
  v_min_new_position integer;
  v_review_row_count integer;
  v_new_row_count integer;
begin
  insert into public.user_level_progress (user_id, level_number, is_unlocked, unlocked_at)
  values (v_user_id, 1, true, now())
  on conflict (user_id, level_number) do update
  set is_unlocked = true,
      unlocked_at = coalesce(public.user_level_progress.unlocked_at, now());

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);

  -- Mark 5 of Level 1's new senses as already-learned and due for review right
  -- now, leaving the rest of Level 1's new senses untouched (still eligible
  -- for the 'new' bucket).
  for v_sense_id in
    select sense_id
    from public.level_sense_assignments
    where level_number = 1 and placement_type = 'new'
    order by order_in_level
    limit 5
  loop
    insert into public.user_sense_mastery (
      user_id, sense_id, learning_state, review_stage,
      seen_count, correct_count, spaced_success_count,
      first_seen_at, first_correct_at, last_seen_at, last_correct_at,
      next_due_at
    )
    values (
      v_user_id, v_sense_id, 'reviewing'::public.sense_learning_state_enum, 2,
      2, 2, 1,
      now() - interval '2 days', now() - interval '2 days', now() - interval '1 day', now() - interval '1 day',
      now() - interval '1 minute'
    )
    on conflict (user_id, sense_id) do update
    set learning_state = 'reviewing'::public.sense_learning_state_enum,
        review_stage = 2,
        spaced_success_count = greatest(public.user_sense_mastery.spaced_success_count, 1),
        next_due_at = now() - interval '1 minute';
  end loop;

  perform public.start_practice_round(1);

  select max(position) into v_max_review_position
  from public.practice_round_questions prq
  join public.practice_rounds pr on pr.id = prq.round_id
  where pr.user_id = v_user_id and prq.source_bucket = 'review';

  select min(position) into v_min_new_position
  from public.practice_round_questions prq
  join public.practice_rounds pr on pr.id = prq.round_id
  where pr.user_id = v_user_id and prq.source_bucket = 'new';

  select count(*) into v_review_row_count
  from public.practice_round_questions prq
  join public.practice_rounds pr on pr.id = prq.round_id
  where pr.user_id = v_user_id and prq.source_bucket = 'review';

  select count(*) into v_new_row_count
  from public.practice_round_questions prq
  join public.practice_rounds pr on pr.id = prq.round_id
  where pr.user_id = v_user_id and prq.source_bucket = 'new';

  if v_review_row_count <> 5 then
    raise exception 'Expected 5 review-bucket questions from the 5 due senses, got %', v_review_row_count;
  end if;

  if v_new_row_count = 0 then
    raise exception 'Expected at least one new-bucket question to compare ordering against';
  end if;

  if v_max_review_position >= v_min_new_position then
    raise exception
      'Review-before-new priority not applied: last review position % is not before first new position %',
      v_max_review_position, v_min_new_position;
  end if;
end;
$$;

rollback;
