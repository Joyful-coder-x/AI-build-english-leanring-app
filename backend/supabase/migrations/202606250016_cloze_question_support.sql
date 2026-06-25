-- KuaKua Duck: cloze (sentence_cloze_typing) question support.
--
-- Extends the practice round system (migrations 009 + 015) to support
-- keyboard-input questions in addition to option-select questions.
--
-- What changes:
--   1. Adds question_type_key to questions table; backfills from answer_form.
--   2. Adds normalize_cloze_answer() helper function.
--   3. Updates save_practice_answer to grade keyboard answers by text
--      comparison (normalized lowercase), set has_active_recall_success on
--      cloze full_correct, and store normalized_answer.
--   4. Updates start_practice_round to:
--      - Include eligible cloze questions for seen senses (seen_count >= 1).
--      - Cap cloze at 40% of round (max 8 of 20 questions).
--      - Store and return answer_form + question_type_key per question.
--
-- Cloze question rules (V1):
--   - Brand-new word → option only.
--   - Seen/review word → option or cloze (server picks).
--   - Cloze max = floor(round_size * 0.40).
--   - Grading: normalized text equality = full_correct; else wrong.
--   - has_active_recall_success set to true on cloze full_correct.

begin;

-- 1. question_type_key on questions -----------------------------------------

alter table public.questions
  add column if not exists question_type_key text;

-- Derive question_type_key for existing rows.
update public.questions
set question_type_key = case
  when answer_form::text = 'keyboard' then 'sentence_cloze_typing'
  else 'option_recognition'
end
where question_type_key is null;

comment on column public.questions.question_type_key is
  'Identifies question type: option_recognition, sentence_cloze_typing, etc.';

-- 2. Cloze answer normalizer -------------------------------------------------

create or replace function public.normalize_cloze_answer(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(trim(regexp_replace(p_text, '\s+', ' ', 'g')))
$$;

-- 3. Updated save_practice_answer: option + keyboard support -----------------

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
  v_user_id             uuid := auth.uid();
  v_round               public.practice_rounds%rowtype;
  v_item                public.practice_round_questions%rowtype;
  v_q_answer_form       text;
  v_q_correct_answer    text;
  v_q_type_key          text;
  v_is_correct          boolean;
  v_outcome             public.answer_outcome_enum;
  v_score_points        numeric(4,2);
  v_normalized_answer   text;
  v_set_active_recall   boolean := false;
  v_now                 timestamptz := clock_timestamp();
  v_mastery             public.user_sense_mastery%rowtype;
  v_old_stage           smallint;
  v_new_stage           smallint;
  v_new_state           public.sense_learning_state_enum;
  v_due_advance         boolean := false;
  v_next_due            timestamptz;
  v_spaced_increment    integer := 0;
  v_recent              boolean[];
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

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position',          p_position,
      'answer_outcome',    v_item.answer_outcome,
      'is_correct',        v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'correct_answer',    null,
      'already_saved',     true
    );
  end if;

  -- Load question metadata.
  select q.answer_form::text,
         q.correct_answer,
         coalesce(q.question_type_key, 'option_recognition')
  into v_q_answer_form, v_q_correct_answer, v_q_type_key
  from public.questions q
  where q.id = v_item.question_id;

  -- Grade the answer.
  if v_q_answer_form = 'option' then
    if v_item.correct_option_id is null then
      raise exception 'Option question missing correct_option_id';
    end if;
    if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
      raise exception 'Answer must be an option UUID';
    end if;
    if not (p_answer::uuid = any(v_item.option_ids)) then
      raise exception 'Answer option does not belong to this question';
    end if;
    v_is_correct := p_answer::uuid = v_item.correct_option_id;

  elsif v_q_answer_form = 'keyboard' then
    v_normalized_answer := public.normalize_cloze_answer(p_answer);
    v_is_correct        := v_normalized_answer = public.normalize_cloze_answer(v_q_correct_answer);
    -- Cloze correct on first attempt = active recall success.
    v_set_active_recall := v_is_correct and v_item.attempt_count = 0;

  else
    raise exception 'Unsupported answer_form: %', v_q_answer_form;
  end if;

  -- V1: single attempt per question → full_correct or wrong.
  -- assisted_correct and remediation_completed are placeholders for future multi-attempt flow.
  v_outcome      := case when v_is_correct
                         then 'full_correct'::public.answer_outcome_enum
                         else 'wrong'::public.answer_outcome_enum end;
  v_score_points := case when v_is_correct then 1.0 else 0.0 end;

  update public.practice_round_questions
  set answer_given      = p_answer,
      normalized_answer = v_normalized_answer,
      is_correct        = v_is_correct,
      answer_outcome    = v_outcome,
      question_type_key = v_q_type_key,
      answer_form       = v_q_answer_form,
      score_points      = v_score_points,
      attempt_count     = attempt_count + 1,
      response_time_ms  = p_response_time_ms,
      answered_at       = v_now
  where round_id = p_round_id and position = p_position;

  -- Upsert mastery base row.
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
        has_active_recall_success = has_active_recall_success or v_set_active_recall,
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
    case when v_q_answer_form = 'keyboard' then 'spelling' else 'multiple_choice' end,
    p_answer, v_is_correct, p_response_time_ms, v_now
  )
  on conflict (session_id, question_id) do nothing;

  return jsonb_build_object(
    'position',          p_position,
    'answer_outcome',    v_outcome,
    'is_correct',        v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'correct_answer',    case when v_q_answer_form = 'keyboard' then v_q_correct_answer else null end,
    'already_saved',     false,
    'learning_state',    v_new_state,
    'review_stage',      v_new_stage,
    'next_due_at',       v_next_due
  );
end;
$$;

-- 4. Updated start_practice_round: option + eligible cloze questions ---------
--
-- Rules:
--   - New (unseen) senses: option questions only.
--   - Seen/review senses: eligible for cloze (server picks based on random).
--   - Cloze cap: at most floor(round_size * 0.40) = 8 of 20 questions.
--   - Eligible cloze: keyboard question exists AND sense seen_count >= 1.

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id       uuid := auth.uid();
  v_round_id      uuid;
  v_session_id    uuid;
  v_due_count     integer;
  v_max_new       integer;
  v_question_count integer;
  v_new_count     integer;
  v_review_count  integer;
  v_result        jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  -- Resume an already-started round for this level.
  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    -- Count global overdue senses to determine new-content cap.
    select count(*)
    into v_due_count
    from public.user_sense_mastery
    where user_id = v_user_id
      and next_due_at is not null
      and next_due_at <= now()
      and learning_state <> 'mastered';

    v_max_new := case
      when v_due_count > 20 then 0
      when v_due_count > 0  then 12
      else 20
    end;

    insert into public.practice_sessions (user_id, level_number, session_type, status)
    values (v_user_id, p_level_number, 'daily', 'started')
    returning id into v_session_id;

    insert into public.practice_rounds (user_id, level_number, session_id, question_count)
    values (v_user_id, p_level_number, v_session_id, 1)
    returning id into v_round_id;

    with eligible_option_questions as (
      -- Option (MCQ) questions: need >= 2 options, exactly 1 correct, reviewed.
      select
        q.id                  as question_id,
        q.sense_id,
        'option'              as answer_form,
        coalesce(q.question_type_key, 'option_recognition') as question_type_key,
        q.is_context_hint,
        q.context_for_multiple_meaning,
        (array_agg(qo.id) filter (where qo.is_correct))[1] as correct_option_id,
        array_agg(qo.id order by random())                   as option_ids
      from public.questions q
      join public.question_options qo on qo.question_id = q.id
      where q.is_active
        and q.answer_form = 'option'
        and q.sense_id is not null
        and not q.human_review
        and not qo.human_review
      group by q.id, q.sense_id, q.is_context_hint, q.context_for_multiple_meaning,
               q.question_type_key
      having count(*) >= 2 and count(*) filter (where qo.is_correct) = 1
    ),
    eligible_cloze_questions as (
      -- Cloze (keyboard) questions: no option rows required; correct_answer in questions table.
      select
        q.id                  as question_id,
        q.sense_id,
        'keyboard'            as answer_form,
        coalesce(q.question_type_key, 'sentence_cloze_typing') as question_type_key,
        q.is_context_hint,
        q.context_for_multiple_meaning,
        null::uuid            as correct_option_id,
        '{}'::uuid[]          as option_ids
      from public.questions q
      where q.is_active
        and q.answer_form = 'keyboard'
        and q.sense_id is not null
        and not q.human_review
    ),
    eligible_questions as (
      select * from eligible_option_questions
      union all
      select * from eligible_cloze_questions
    ),
    candidate_sources as (
      -- Global overdue reviews always outrank new content.
      select
        usm.sense_id,
        case
          when ms.is_active and usm.next_due_at is not null
               and usm.next_due_at <= now() then 1
          else 2
        end                      as priority,
        usm.difficulty_level,
        usm.wrong_count,
        usm.next_due_at,
        false                    as is_new,
        usm.seen_count           as seen_count
      from public.user_sense_mastery usm
      left join public.mistake_senses ms
        on ms.user_id = v_user_id and ms.sense_id = usm.sense_id
      where usm.user_id = v_user_id
        and usm.next_due_at is not null
        and usm.next_due_at <= now()
        and usm.learning_state <> 'mastered'

      union all

      -- New + near-due senses from the selected level.
      select
        lsa.sense_id,
        case
          when usm.user_id is null                                   then 3
          when usm.next_due_at is not null
               and usm.next_due_at <= now() + interval '24 hours'   then 4
          else 5
        end,
        coalesce(usm.difficulty_level, 0),
        coalesce(usm.wrong_count, 0),
        coalesce(usm.next_due_at, 'infinity'::timestamptz),
        (usm.user_id is null),
        coalesce(usm.seen_count, 0)
      from public.level_sense_assignments lsa
      left join public.user_sense_mastery usm
        on usm.user_id = v_user_id and usm.sense_id = lsa.sense_id
      where lsa.level_number = p_level_number
        and lsa.placement_type = 'new'
    ),
    candidate_senses as (
      select distinct on (sense_id)
        sense_id, priority, difficulty_level, wrong_count, next_due_at,
        is_new, seen_count
      from candidate_sources
      order by sense_id, priority, next_due_at
    ),
    ranked as (
      select
        cs.sense_id,
        cs.priority,
        cs.difficulty_level,
        cs.wrong_count,
        cs.next_due_at,
        cs.is_new,
        cs.seen_count,
        row_number() over (
          partition by cs.is_new
          order by cs.priority, cs.next_due_at, cs.difficulty_level desc, random()
        ) as type_rank
      from candidate_senses cs
      where exists (
        select 1 from eligible_questions eq
        where eq.sense_id = cs.sense_id
          -- New senses must have an option question.
          and (not cs.is_new or eq.answer_form = 'option')
      )
    ),
    limited as (
      select *
      from ranked
      where not is_new or type_rank <= v_max_new
      order by priority, next_due_at, difficulty_level desc, random()
      limit 20
    ),
    chosen_raw as (
      -- For each sense, pick one question.
      -- New senses: option only.
      -- Seen senses: prefer cloze when eligible (seen_count >= 1), else option.
      -- Context hint selection logic preserved from migration 009.
      select
        l.sense_id,
        l.priority,
        l.is_new,
        l.seen_count,
        eq.question_id,
        eq.answer_form,
        eq.question_type_key,
        eq.correct_option_id,
        eq.option_ids,
        row_number() over (
          order by l.priority, l.next_due_at, l.difficulty_level desc, random()
        )::smallint as raw_position
      from limited l
      join lateral (
        select *
        from eligible_questions candidate
        where candidate.sense_id = l.sense_id
          -- New senses: option only.
          and (not l.is_new or candidate.answer_form = 'option')
          -- Cloze only for seen senses.
          and (candidate.answer_form = 'option' or l.seen_count >= 1)
          -- Context hint eligibility.
          and (
            not candidate.is_context_hint
            or candidate.context_for_multiple_meaning
            or l.wrong_count >= 3
          )
        order by
          -- Favour context hint when appropriate.
          case when candidate.is_context_hint
               and (candidate.context_for_multiple_meaning or l.wrong_count >= 3)
               then 0 else 1 end,
          random()
        limit 1
      ) eq on true
    ),
    cloze_numbered as (
      -- Number cloze rows so we can apply the 40% cap.
      select *,
        row_number() over (
          partition by case when answer_form = 'keyboard' then 'cloze' else 'option' end
          order by raw_position
        ) as form_rank
      from chosen_raw
    ),
    chosen as (
      -- Keep all option questions; cap cloze at 8 (40% of 20).
      select
        sense_id, is_new, question_id, answer_form, question_type_key,
        correct_option_id, option_ids,
        row_number() over (
          order by raw_position
        )::smallint as position
      from cloze_numbered
      where answer_form = 'option' or form_rank <= 8
    )
    insert into public.practice_round_questions (
      round_id, position, question_id, sense_id,
      question_skill, answer_form, question_type_key,
      option_ids, correct_option_id
    )
    select
      v_round_id,
      position,
      question_id,
      sense_id,
      case when answer_form = 'keyboard' then 'active_recall' else 'recognition' end,
      answer_form,
      question_type_key,
      option_ids,
      correct_option_id
    from chosen;

    select
      count(*),
      count(*) filter (
        where not exists (
          select 1 from public.user_sense_mastery usm
          where usm.user_id = v_user_id and usm.sense_id = prq.sense_id
        )
      )
    into v_question_count, v_new_count
    from public.practice_round_questions prq
    where prq.round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds  where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible reviewed questions for Level %', p_level_number;
    end if;

    v_review_count := v_question_count - v_new_count;

    update public.practice_rounds
    set question_count     = v_question_count,
        new_sense_count    = v_new_count,
        review_sense_count = v_review_count
    where id = v_round_id;
  end if;

  -- Build the response JSON.
  select jsonb_build_object(
    'round_id',          r.id,
    'level_number',      r.level_number,
    'status',            r.status,
    'question_count',    r.question_count,
    'new_sense_count',   r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position',         rq.position,
          'question_id',      q.id,
          'sense_id',         rq.sense_id,
          'stem',             q.stem,
          'prompt_hint',      q.prompt_hint,
          'translation_zh',   q.translation_zh,
          'question_skill',   rq.question_skill,
          'answer_form',      rq.answer_form,
          'question_type_key', rq.question_type_key,
          'options',
            case when rq.answer_form = 'option' then (
              select jsonb_agg(
                jsonb_build_object(
                  'option_id',   opt.id,
                  'option_text', opt.option_text
                )
                order by ord.ordinality
              )
              from unnest(rq.option_ids) with ordinality ord(option_id, ordinality)
              join public.question_options opt on opt.id = ord.option_id
            ) else '[]'::jsonb end,
          'answer_given',  rq.answer_given,
          'is_answered',   rq.answered_at is not null
        )
        order by rq.position
      )
      from public.practice_round_questions rq
      join public.questions q on q.id = rq.question_id
      where rq.round_id = r.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.practice_rounds r
  where r.id = v_round_id and r.user_id = v_user_id;

  return v_result;
end;
$$;

-- 5. Security -----------------------------------------------------------------

revoke all on function public.normalize_cloze_answer(text) from public, anon, authenticated;

commit;
