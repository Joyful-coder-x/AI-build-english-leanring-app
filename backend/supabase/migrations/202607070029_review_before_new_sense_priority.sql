-- Phase 1 masterplan Feature E fix: overdue reviews must outrank new senses
-- when both are eligible for the same round position. Migration 020 tried the
-- 'new' sense bucket before the 'review' bucket, so a learner with a handful
-- of due reviews (fewer than the 20-question round size, so migration 028's
-- due_review_new_word_gate never engaged) would still see new senses fill
-- positions ahead of their overdue reviews. This swaps the bucket order to:
-- mistake (unchanged) -> review -> new -> fallback (unchanged).

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
      if v_candidate_sense_id is null and v_new_count < v_new_sense_limit then
        select
          lsa.sense_id,
          'new'::text as source_bucket,
          true as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and usm.user_id is null
          and not (lsa.sense_id = any(v_picked_senses))
        order by lsa.order_in_level
        limit 1;
      end if;

      if v_candidate_sense_id is null then
        select
          usm.sense_id,
          'review'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        left join public.level_sense_assignments lsa
          on lsa.sense_id = usm.sense_id
         and lsa.placement_type = 'new'
        where usm.user_id = v_user_id
          and usm.next_due_at is not null
          and usm.next_due_at <= now()
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (lsa.level_number is null or lsa.level_number <= p_level_number)
        order by usm.next_due_at, usm.priority_boost desc, usm.difficulty_level desc, random()
        limit 1;
      end if;
$old$,
$new$
      if v_candidate_sense_id is null then
        select
          usm.sense_id,
          'review'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        left join public.level_sense_assignments lsa
          on lsa.sense_id = usm.sense_id
         and lsa.placement_type = 'new'
        where usm.user_id = v_user_id
          and usm.next_due_at is not null
          and usm.next_due_at <= now()
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (lsa.level_number is null or lsa.level_number <= p_level_number)
        order by usm.next_due_at, usm.priority_boost desc, usm.difficulty_level desc, random()
        limit 1;
      end if;

      if v_candidate_sense_id is null and v_new_count < v_new_sense_limit then
        select
          lsa.sense_id,
          'new'::text as source_bucket,
          true as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and usm.user_id is null
          and not (lsa.sense_id = any(v_picked_senses))
        order by lsa.order_in_level
        limit 1;
      end if;
$new$
  );

  if v_updated = v_original then
    raise exception 'Could not patch public.start_practice_round(integer) with review-before-new priority';
  end if;

  execute v_updated;
end;
$$;
