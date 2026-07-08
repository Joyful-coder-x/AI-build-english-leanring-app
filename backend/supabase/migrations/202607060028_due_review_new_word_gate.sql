-- Phase 1 practice policy: when a learner has more than one full round of
-- due reviews, do not introduce new words in that round.

do $$
declare
  v_original text;
  v_updated text;
begin
  select pg_get_functiondef('public.start_practice_round(integer)'::regprocedure)
  into v_original;

  v_updated := replace(
    v_original,
$old$
  v_question_count integer;
begin
$old$,
$new$
  v_question_count integer;
  v_due_review_count integer := 0;
  v_new_sense_limit integer := 7;
begin
$new$
  );

  v_updated := replace(
    v_updated,
$old$
    while v_position <= v_target_count loop
$old$,
$new$
    select count(*)
    into v_due_review_count
    from public.user_sense_mastery usm
    left join public.level_sense_assignments lsa
      on lsa.sense_id = usm.sense_id
     and lsa.placement_type = 'new'
    where usm.user_id = v_user_id
      and usm.next_due_at is not null
      and usm.next_due_at <= now()
      and usm.learning_state <> 'mastered'
      and (lsa.level_number is null or lsa.level_number <= p_level_number);

    if v_due_review_count > v_target_count then
      v_new_sense_limit := 0;
    end if;

    while v_position <= v_target_count loop
$new$
  );

  v_updated := replace(
    v_updated,
    'if v_candidate_sense_id is null and v_new_count < 7 then',
    'if v_candidate_sense_id is null and v_new_count < v_new_sense_limit then'
  );

  if v_updated = v_original then
    raise exception 'Could not patch public.start_practice_round(integer) with due review new-word gate';
  end if;

  execute v_updated;
end;
$$;
