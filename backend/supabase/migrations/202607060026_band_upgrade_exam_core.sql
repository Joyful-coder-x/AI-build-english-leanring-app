-- Core Band upgrade exam backend for Phase 1.
--
-- Implements the Band 4.0 -> 4.5 prototype path with generic source/target
-- band arguments so later bands can reuse the same RPCs when content exists.

create table if not exists public.band_upgrade_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_band numeric(2,1) not null references public.bands(band_score),
  target_band numeric(2,1) not null references public.bands(band_score),
  status text not null default 'started',
  question_count smallint not null default 40,
  correct_count smallint,
  accuracy numeric(5,2),
  passed boolean,
  category_counts jsonb not null default '{}'::jsonb,
  attempt_version text not null default 'phase1_band_upgrade_v1',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint band_upgrade_attempt_status_valid
    check (status in ('started', 'completed', 'abandoned')),
  constraint band_upgrade_attempt_question_count_valid
    check (question_count = 40),
  constraint band_upgrade_attempt_correct_count_valid
    check (correct_count is null or correct_count between 0 and question_count),
  constraint band_upgrade_attempt_accuracy_valid
    check (accuracy is null or accuracy between 0 and 100),
  constraint band_upgrade_attempt_band_step_valid
    check (target_band = source_band + 0.5)
);

create unique index if not exists band_upgrade_one_started_per_target
  on public.band_upgrade_attempts (user_id, target_band)
  where status = 'started';

create table if not exists public.band_upgrade_attempt_questions (
  attempt_id uuid not null references public.band_upgrade_attempts(id) on delete cascade,
  position smallint not null,
  question_id uuid not null references public.questions(id),
  sense_id uuid not null references public.word_senses(id),
  question_type_key text not null,
  category text not null,
  answer_form text not null,
  option_ids uuid[] not null default '{}',
  correct_option_id uuid,
  generated_payload jsonb not null default '{}'::jsonb,
  correct_answer_payload jsonb not null default '{}'::jsonb,
  answer_given text,
  is_correct boolean,
  response_time_ms integer,
  answered_at timestamptz,
  created_at timestamptz not null default now(),

  primary key (attempt_id, position),
  constraint band_upgrade_position_valid check (position between 1 and 40),
  constraint band_upgrade_category_valid
    check (category in ('meaning', 'listening', 'spelling', 'speaking')),
  constraint band_upgrade_answer_time_valid
    check (response_time_ms is null or response_time_ms >= 0)
);

create index if not exists band_upgrade_attempt_questions_question_idx
  on public.band_upgrade_attempt_questions (question_id);

create index if not exists band_upgrade_attempt_questions_sense_idx
  on public.band_upgrade_attempt_questions (sense_id);

alter table public.band_upgrade_attempts enable row level security;
alter table public.band_upgrade_attempt_questions enable row level security;

drop policy if exists band_upgrade_attempts_own_select on public.band_upgrade_attempts;
create policy band_upgrade_attempts_own_select
on public.band_upgrade_attempts for select to authenticated
using (auth.uid() = user_id);

-- Attempt questions contain correctness payloads. Keep direct table access
-- closed; RPCs return learner-safe payloads only.

grant select on public.band_upgrade_attempts to authenticated;

create or replace function public.band_exam_category_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_question_type_key = 'meaning_choice' then 'meaning'
    when p_question_type_key in ('listening_choice', 'listening_fill') then 'listening'
    when p_question_type_key = 'sentence_cloze_typing' then 'spelling'
    when p_question_type_key = 'speaking_repeat' then 'speaking'
    else 'meaning'
  end;
$$;

create or replace function public.band_exam_public_payload(
  p_attempt_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'attempt_id', a.id,
    'source_band', a.source_band,
    'target_band', a.target_band,
    'status', a.status,
    'question_count', a.question_count,
    'correct_count', a.correct_count,
    'accuracy', a.accuracy,
    'passed', a.passed,
    'category_counts', a.category_counts,
    'questions', coalesce(jsonb_agg(
      jsonb_build_object(
        'position', aq.position,
        'question_id', aq.question_id,
        'question_type_key', aq.question_type_key,
        'category', aq.category,
        'answer_form', aq.answer_form,
        'stem', aq.generated_payload ->> 'stem',
        'prompt_hint', aq.generated_payload ->> 'prompt_hint',
        'translation_zh', aq.generated_payload ->> 'translation_zh',
        'headword', aq.generated_payload ->> 'headword',
        'option_ids', aq.option_ids,
        'options', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', qo.id,
              'text', qo.option_text,
              'sort_order', qo.sort_order
            )
            order by array_position(aq.option_ids, qo.id)
          )
          from public.question_options qo
          where qo.id = any(aq.option_ids)
        ), '[]'::jsonb),
        'answered', aq.answered_at is not null,
        'is_correct', aq.is_correct
      )
      order by aq.position
    ), '[]'::jsonb)
  )
  from public.band_upgrade_attempts a
  join public.band_upgrade_attempt_questions aq on aq.attempt_id = a.id
  where a.id = p_attempt_id
  group by a.id;
$$;

create or replace function public.start_band_upgrade_exam(
  p_target_band numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_source_band numeric(2,1) := (p_target_band - 0.5)::numeric(2,1);
  v_attempt_id uuid;
  v_question_types text[] := array[
    'meaning_choice',
    'listening_choice',
    'sentence_cloze_typing',
    'speaking_repeat'
  ];
  v_position integer := 1;
  v_type text;
  v_generated record;
  v_item record;
  v_category_counts jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (select 1 from public.bands where band_score = p_target_band) then
    raise exception 'Target band % does not exist', p_target_band;
  end if;

  if not exists (select 1 from public.bands where band_score = v_source_band) then
    raise exception 'Source band % does not exist', v_source_band;
  end if;

  select id into v_attempt_id
  from public.band_upgrade_attempts
  where user_id = v_user_id
    and target_band = p_target_band
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_attempt_id is not null then
    return public.band_exam_public_payload(v_attempt_id);
  end if;

  if (
    select count(*)
    from public.level_sense_assignments lsa
    join public.levels l on l.level_number = lsa.level_number
    join public.bands b on b.id = l.band_id
    where b.band_score = v_source_band
      and lsa.placement_type = 'new'
  ) < 40 then
    raise exception 'Not enough vocabulary in source band % for a 40-question exam', v_source_band;
  end if;

  insert into public.band_upgrade_attempts (
    user_id, source_band, target_band, question_count
  )
  values (v_user_id, v_source_band, p_target_band, 40)
  returning id into v_attempt_id;

  for v_item in
    select lsa.sense_id, lsa.level_number
    from public.level_sense_assignments lsa
    join public.levels l on l.level_number = lsa.level_number
    join public.bands b on b.id = l.band_id
    where b.band_score = v_source_band
      and lsa.placement_type = 'new'
    order by random()
    limit 40
  loop
    v_type := v_question_types[1 + ((v_position - 1) % array_length(v_question_types, 1))];

    begin
      select * into v_generated
      from public.generate_practice_question(
        v_item.sense_id,
        v_item.level_number,
        v_type
      );
    exception when others then
      v_type := 'meaning_choice';
      select * into v_generated
      from public.generate_practice_question(
        v_item.sense_id,
        v_item.level_number,
        v_type
      );
    end;

    insert into public.band_upgrade_attempt_questions (
      attempt_id,
      position,
      question_id,
      sense_id,
      question_type_key,
      category,
      answer_form,
      option_ids,
      correct_option_id,
      generated_payload,
      correct_answer_payload
    )
    values (
      v_attempt_id,
      v_position,
      v_generated.question_id,
      v_item.sense_id,
      v_type,
      public.band_exam_category_for_type(v_type),
      v_generated.answer_form,
      coalesce(v_generated.option_ids, '{}'::uuid[]),
      v_generated.correct_option_id,
      v_generated.generated_payload,
      v_generated.correct_answer_payload
    );

    v_position := v_position + 1;
  end loop;

  select jsonb_object_agg(category, category_count)
  into v_category_counts
  from (
    select category, count(*) as category_count
    from public.band_upgrade_attempt_questions
    where attempt_id = v_attempt_id
    group by category
  ) counts;

  update public.band_upgrade_attempts
  set category_counts = coalesce(v_category_counts, '{}'::jsonb),
      updated_at = now()
  where id = v_attempt_id;

  return public.band_exam_public_payload(v_attempt_id);
end;
$$;

create or replace function public.save_band_upgrade_answer(
  p_attempt_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.band_upgrade_attempts%rowtype;
  v_question public.band_upgrade_attempt_questions%rowtype;
  v_answer text := btrim(coalesce(p_answer, ''));
  v_correct_answer text;
  v_is_correct boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.band_upgrade_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Exam attempt not found';
  end if;

  if v_attempt.status <> 'started' then
    raise exception 'Exam attempt is already completed';
  end if;

  select * into v_question
  from public.band_upgrade_attempt_questions
  where attempt_id = p_attempt_id
    and position = p_position;

  if v_question.attempt_id is null then
    raise exception 'Question position % not found', p_position;
  end if;

  if v_question.answered_at is not null then
    return jsonb_build_object(
      'already_saved', true,
      'position', p_position,
      'is_correct', v_question.is_correct
    );
  end if;

  v_correct_answer := v_question.correct_answer_payload ->> 'correct_answer';

  if v_question.answer_form = 'option' then
    v_is_correct :=
      v_answer = v_question.correct_option_id::text
      or exists (
        select 1
        from public.question_options qo
        where qo.id = v_question.correct_option_id
          and lower(btrim(qo.option_text)) = lower(v_answer)
      );
  else
    v_is_correct := lower(v_answer) = lower(btrim(coalesce(v_correct_answer, '')));
  end if;

  update public.band_upgrade_attempt_questions
  set answer_given = v_answer,
      is_correct = v_is_correct,
      response_time_ms = p_response_time_ms,
      answered_at = now()
  where attempt_id = p_attempt_id
    and position = p_position;

  update public.band_upgrade_attempts
  set updated_at = now()
  where id = p_attempt_id;

  return jsonb_build_object(
    'already_saved', false,
    'position', p_position,
    'is_correct', v_is_correct
  );
end;
$$;

create or replace function public.complete_band_upgrade_exam(
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.band_upgrade_attempts%rowtype;
  v_answered_count integer;
  v_correct_count integer;
  v_accuracy numeric(5,2);
  v_passed boolean;
  v_first_target_level integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.band_upgrade_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Exam attempt not found';
  end if;

  if v_attempt.status = 'completed' then
    return public.band_exam_public_payload(p_attempt_id);
  end if;

  select
    count(*) filter (where answered_at is not null),
    count(*) filter (where is_correct)
  into v_answered_count, v_correct_count
  from public.band_upgrade_attempt_questions
  where attempt_id = p_attempt_id;

  if v_answered_count <> v_attempt.question_count then
    raise exception 'Cannot complete exam until all % questions are answered', v_attempt.question_count;
  end if;

  v_accuracy := round((v_correct_count::numeric / v_attempt.question_count::numeric) * 100, 2);
  v_passed := v_correct_count >= 37;

  update public.band_upgrade_attempts
  set status = 'completed',
      correct_count = v_correct_count,
      accuracy = v_accuracy,
      passed = v_passed,
      completed_at = now(),
      updated_at = now()
  where id = p_attempt_id;

  if v_passed then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      is_completed,
      progress,
      unlocked_at,
      completed_at
    )
    select
      v_user_id,
      l.level_number,
      true,
      true,
      1,
      now(),
      now()
    from public.levels l
    join public.bands b on b.id = l.band_id
    where b.band_score <= v_attempt.source_band
    on conflict (user_id, level_number) do update
    set is_unlocked = true,
        is_completed = true,
        progress = greatest(public.user_level_progress.progress, 1),
        unlocked_at = coalesce(public.user_level_progress.unlocked_at, now()),
        completed_at = coalesce(public.user_level_progress.completed_at, now()),
        updated_at = now();

    select min(l.level_number)
    into v_first_target_level
    from public.levels l
    join public.bands b on b.id = l.band_id
    where b.band_score = v_attempt.target_band;

    if v_first_target_level is not null then
      insert into public.user_level_progress (
        user_id,
        level_number,
        is_unlocked,
        is_completed,
        progress,
        unlocked_at
      )
      values (
        v_user_id,
        v_first_target_level,
        true,
        false,
        0,
        now()
      )
      on conflict (user_id, level_number) do update
      set is_unlocked = true,
          unlocked_at = coalesce(public.user_level_progress.unlocked_at, now()),
          updated_at = now();
    end if;
  end if;

  return public.band_exam_public_payload(p_attempt_id);
end;
$$;

revoke all on function public.band_exam_category_for_type(text) from public, anon, authenticated;
revoke all on function public.band_exam_public_payload(uuid) from public, anon, authenticated;
revoke all on function public.start_band_upgrade_exam(numeric) from public, anon, authenticated;
revoke all on function public.save_band_upgrade_answer(uuid, integer, text, integer) from public, anon, authenticated;
revoke all on function public.complete_band_upgrade_exam(uuid) from public, anon, authenticated;

grant execute on function public.start_band_upgrade_exam(numeric) to authenticated;
grant execute on function public.save_band_upgrade_answer(uuid, integer, text, integer) to authenticated;
grant execute on function public.complete_band_upgrade_exam(uuid) to authenticated;
