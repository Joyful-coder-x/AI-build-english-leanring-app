-- KuaKua Duck: unified Level-round weighted scoring system.
--
-- What changes from the V1.0 round system (migration 009):
--   1. Adds answer_outcome_enum ('full_correct' | 'assisted_correct' |
--      'remediation_completed' | 'wrong') and outcome/scoring columns to
--      practice_round_questions. Backfills existing answered rows.
--   2. Updates save_practice_answer to write answer_outcome and score_points.
--   3. Updates complete_practice_round:
--      - Stars based on weighted accuracy: >=90%=3, >=80%=2, >=60%=1.
--      - Duck power = full_correct_count + floor(assisted_correct_count / 2).
--      - Updates best_star_rating on user_level_progress.
--      - Returns full breakdown (full_correct, assisted, remediation, wrong).
--
-- Backward-compatible: is_correct boolean and correct_count are preserved.
-- answer_outcome is the new authoritative grade; is_correct stays for joins
-- and legacy queries.

begin;

-- 1. Answer outcome enum ------------------------------------------------------

do $$
begin
  create type public.answer_outcome_enum as enum (
    'full_correct',
    'assisted_correct',
    'remediation_completed',
    'wrong'
  );
exception when duplicate_object then null;
end $$;

-- 2. New columns on practice_round_questions ----------------------------------

alter table public.practice_round_questions
  add column if not exists answer_outcome     public.answer_outcome_enum,
  add column if not exists question_type_key  text,
  add column if not exists answer_form        text,
  add column if not exists score_points       numeric(4,2),
  add column if not exists hint_used          boolean not null default false,
  add column if not exists attempt_count      smallint not null default 0,
  add column if not exists revealed_answer_at timestamptz,
  add column if not exists normalized_answer  text;

comment on column public.practice_round_questions.answer_outcome is
  'Authoritative grade: full_correct, assisted_correct, remediation_completed, or wrong.';
comment on column public.practice_round_questions.score_points is
  'Weighted score contribution: full_correct=1.0, assisted_correct=0.5, others=0.';
comment on column public.practice_round_questions.question_type_key is
  'Identifies question type: option_recognition, sentence_cloze_typing, etc.';
comment on column public.practice_round_questions.answer_form is
  'Input modality: option or keyboard.';

-- Backfill existing answered rows from is_correct.
update public.practice_round_questions
set answer_outcome    = case
      when is_correct = true  then 'full_correct'::public.answer_outcome_enum
      when is_correct = false then 'wrong'::public.answer_outcome_enum
      else null
    end,
    question_type_key = coalesce(question_type_key, 'option_recognition'),
    answer_form       = coalesce(answer_form, 'option'),
    score_points      = case when is_correct = true then 1.0 else 0.0 end
where answered_at is not null
  and answer_outcome is null;

-- 3. Updated save_practice_answer: writes answer_outcome ----------------------

create or replace function public.save_practice_answer(
  p_round_id         uuid,
  p_position         integer,
  p_answer           text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id          uuid := auth.uid();
  v_round            public.practice_rounds%rowtype;
  v_item             public.practice_round_questions%rowtype;
  v_is_correct       boolean;
  v_outcome          public.answer_outcome_enum;
  v_score_points     numeric(4,2);
  v_now              timestamptz := clock_timestamp();
  v_mastery          public.user_sense_mastery%rowtype;
  v_old_stage        smallint;
  v_new_stage        smallint;
  v_new_state        public.sense_learning_state_enum;
  v_due_advance      boolean := false;
  v_next_due         timestamptz;
  v_spaced_increment integer := 0;
  v_recent           boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  -- Idempotent: already answered.
  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position',          p_position,
      'answer_outcome',    v_item.answer_outcome,
      'is_correct',        v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'already_saved',     true
    );
  end if;

  -- V1.0: option questions only.
  if v_item.correct_option_id is null then
    raise exception 'V1.0 only supports server-graded option questions';
  end if;

  if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
    raise exception 'Answer must be an option UUID';
  end if;

  if not (p_answer::uuid = any(v_item.option_ids)) then
    raise exception 'Answer option does not belong to this question';
  end if;

  v_is_correct   := p_answer::uuid = v_item.correct_option_id;
  v_outcome      := case when v_is_correct
                         then 'full_correct'::public.answer_outcome_enum
                         else 'wrong'::public.answer_outcome_enum end;
  v_score_points := case when v_is_correct then 1.0 else 0.0 end;

  update public.practice_round_questions
  set answer_given      = p_answer,
      is_correct        = v_is_correct,
      answer_outcome    = v_outcome,
      question_type_key = coalesce(question_type_key, 'option_recognition'),
      answer_form       = coalesce(answer_form, 'option'),
      score_points      = v_score_points,
      response_time_ms  = p_response_time_ms,
      answered_at       = v_now
  where round_id = p_round_id and position = p_position;

  -- Upsert mastery row if first time seeing this sense.
  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, correct_count, wrong_count,
    consecutive_correct_count, recent_results, review_stage,
    first_seen_at, first_correct_at, last_seen_at, last_correct_at,
    next_due_at, updated_at
  )
  values (
    v_user_id, v_item.sense_id, 'new', 0, 0, 0, 0, '{}', 0,
    v_now, null, null, null, null, v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent    := public.append_recent_formal_result(v_mastery.recent_results, v_is_correct);

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due  := v_now + interval '10 minutes';
    elsif v_mastery.next_due_at is not null and v_now >= v_mastery.next_due_at then
      v_due_advance      := true;
      v_new_stage        := least(4, v_old_stage + 1);
      v_new_state        := case when v_new_stage >= 2 then 'reviewing' else 'learning' end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '10 minutes'
        when 2 then v_now + interval '1 day'
        when 3 then v_now + interval '7 days'
        when 4 then case when v_old_stage = 4
                         then v_now + interval '75 days'
                         else v_now + interval '30 days' end
        else v_now + interval '10 minutes'
      end;
    else
      v_new_stage := v_old_stage;
      v_new_state := case
        when v_mastery.learning_state = 'new'      then 'learning'
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        else v_mastery.learning_state
      end;
      v_next_due := v_mastery.next_due_at;
    end if;

    update public.user_sense_mastery
    set learning_state            = v_new_state,
        seen_count                = seen_count + 1,
        correct_count             = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results            = v_recent,
        spaced_success_count      = spaced_success_count + v_spaced_increment,
        review_stage              = v_new_stage,
        mastery_score             = least(0.99, v_new_stage::numeric / 5),
        first_seen_at             = coalesce(first_seen_at, v_now),
        first_correct_at          = coalesce(first_correct_at, v_now),
        last_seen_at              = v_now,
        last_correct_at           = v_now,
        next_due_at               = v_next_due,
        mastered_at               = null,
        updated_at                = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active            = false,
          resolved_at          = v_now,
          last_reviewed_at     = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at           = v_now
      where user_id = v_user_id and sense_id = v_item.sense_id and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1       then 0
      when v_old_stage  = 2       then 1
      when v_old_stage  = 3       then 2
      when v_old_stage in (4, 5)  then 3
      else 0
    end;
    v_new_state := case when v_new_stage = 0 then 'learning' else 'reviewing' end;
    v_next_due  := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state            = v_new_state,
        seen_count                = seen_count + 1,
        wrong_count               = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results            = v_recent,
        review_stage              = v_new_stage,
        mastery_score             = least(0.99, v_new_stage::numeric / 5),
        difficulty_level          = difficulty_level + 1,
        first_seen_at             = coalesce(first_seen_at, v_now),
        last_seen_at              = v_now,
        next_due_at               = v_next_due,
        mastered_at               = null,
        updated_at                = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id, sense_id, wrong_count, first_wrong_at, last_wrong_at,
      is_active, resolved_at, created_at, updated_at
    )
    values (
      v_user_id, v_item.sense_id, 1, v_now, v_now, true, null, v_now, v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count   = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        is_active     = true,
        resolved_at   = null,
        updated_at    = v_now;
  end if;

  insert into public.practice_answers (
    user_id, session_id, question_id, sense_id, skill_type,
    answer_given, is_correct, response_time_ms, answered_at
  )
  values (
    v_user_id, v_round.session_id, v_item.question_id, v_item.sense_id,
    'multiple_choice', p_answer, v_is_correct, p_response_time_ms, v_now
  )
  on conflict (session_id, question_id) do nothing;

  return jsonb_build_object(
    'position',          p_position,
    'answer_outcome',    v_outcome,
    'is_correct',        v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'already_saved',     false,
    'learning_state',    v_new_state,
    'review_stage',      v_new_stage,
    'next_due_at',       v_next_due
  );
end;
$$;

-- 4. Updated complete_practice_round: weighted scoring ------------------------
--
-- Scoring formula:
--   score_points = full_correct*1.0 + assisted_correct*0.5
--   weighted_accuracy = score_points / question_count
--   stars: >=90%=3, >=80%=2, >=60%=1, else 0
--   duck_power = full_correct_count + floor(assisted_correct_count / 2)

create or replace function public.complete_practice_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id           uuid := auth.uid();
  v_round             public.practice_rounds%rowtype;
  v_answered          integer;
  v_full_correct      integer;
  v_assisted_correct  integer;
  v_remediation       integer;
  v_wrong             integer;
  v_score_points      numeric(6,2);
  v_weighted_accuracy numeric(5,4);
  v_star_rating       integer;
  v_duck_power        integer;
  v_completed_level   boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status = 'completed' then
    -- Idempotent: re-compute from stored outcome columns.
    select
      count(*) filter (where answer_outcome = 'full_correct'),
      count(*) filter (where answer_outcome = 'assisted_correct'),
      count(*) filter (where answer_outcome = 'remediation_completed'),
      count(*) filter (where answer_outcome = 'wrong'),
      coalesce(sum(score_points), v_round.correct_count::numeric)
    into v_full_correct, v_assisted_correct, v_remediation, v_wrong, v_score_points
    from public.practice_round_questions
    where round_id = p_round_id;

    v_weighted_accuracy := v_score_points / nullif(v_round.question_count, 0);
    v_star_rating := case
      when v_weighted_accuracy >= 0.90 then 3
      when v_weighted_accuracy >= 0.80 then 2
      when v_weighted_accuracy >= 0.60 then 1
      else 0
    end;
    v_duck_power := v_full_correct + floor(v_assisted_correct::numeric / 2)::integer;

    return jsonb_build_object(
      'round_id',               v_round.id,
      'question_count',         v_round.question_count,
      'full_correct_count',     v_full_correct,
      'assisted_correct_count', v_assisted_correct,
      'remediation_count',      v_remediation,
      'wrong_count',            v_wrong,
      'weighted_accuracy',      v_weighted_accuracy,
      'star_rating',            v_star_rating,
      'duck_power_earned',      v_duck_power,
      'already_completed',      true,
      'level_completed', coalesce((
        select is_completed from public.user_level_progress
        where user_id = v_user_id and level_number = v_round.level_number
      ), false)
    );
  end if;

  select count(*) filter (where answered_at is not null)
  into v_answered
  from public.practice_round_questions
  where round_id = p_round_id;

  if v_answered <> v_round.question_count then
    raise exception 'All round questions must be answered before completion';
  end if;

  select
    count(*) filter (where answer_outcome = 'full_correct'),
    count(*) filter (where answer_outcome = 'assisted_correct'),
    count(*) filter (where answer_outcome = 'remediation_completed'),
    count(*) filter (where answer_outcome = 'wrong'),
    coalesce(sum(score_points), count(*) filter (where is_correct)::numeric)
  into v_full_correct, v_assisted_correct, v_remediation, v_wrong, v_score_points
  from public.practice_round_questions
  where round_id = p_round_id;

  v_weighted_accuracy := v_score_points / nullif(v_round.question_count, 0);
  v_star_rating := case
    when v_weighted_accuracy >= 0.90 then 3
    when v_weighted_accuracy >= 0.80 then 2
    when v_weighted_accuracy >= 0.60 then 1
    else 0
  end;
  v_duck_power := v_full_correct + floor(v_assisted_correct::numeric / 2)::integer;

  update public.practice_rounds
  set status        = 'completed',
      correct_count = v_full_correct,
      completed_at  = now()
  where id = p_round_id;

  update public.practice_sessions
  set status            = 'completed',
      completed_at      = now(),
      correct_count     = v_full_correct,
      total_count       = v_round.question_count,
      star_rating       = v_star_rating,
      base_power        = v_duck_power,
      duck_power_earned = v_duck_power
  where id = v_round.session_id;

  update public.profiles
  set duck_power = duck_power + v_duck_power
  where id = v_user_id;

  update public.user_level_progress
  set completed_session_count = completed_session_count + 1,
      best_star_rating        = greatest(best_star_rating, v_star_rating),
      updated_at              = now()
  where user_id = v_user_id and level_number = v_round.level_number;

  v_completed_level := public.refresh_level_completion(v_user_id, v_round.level_number);

  return jsonb_build_object(
    'round_id',               p_round_id,
    'question_count',         v_round.question_count,
    'full_correct_count',     v_full_correct,
    'assisted_correct_count', v_assisted_correct,
    'remediation_count',      v_remediation,
    'wrong_count',            v_wrong,
    'weighted_accuracy',      v_weighted_accuracy,
    'star_rating',            v_star_rating,
    'duck_power_earned',      v_duck_power,
    'already_completed',      false,
    'level_completed',        v_completed_level
  );
end;
$$;

commit;
