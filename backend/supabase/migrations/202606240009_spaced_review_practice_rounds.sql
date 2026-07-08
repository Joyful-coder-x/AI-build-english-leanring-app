-- KuaKua Duck V1.0 spaced review and immutable server-created practice rounds.
--
-- Additive/backward-compatible:
-- - preserves the legacy meaning-choice RPCs and columns;
-- - makes user_sense_mastery the new scheduling source of truth;
-- - keeps mistake_senses as an active/history display index;
-- - does not migrate or delete existing answer history.

begin;

do $$
begin
  create type public.sense_learning_state_enum as enum (
    'new',
    'learning',
    'reviewing',
    'mastered'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.practice_round_status_enum as enum (
    'started',
    'completed',
    'abandoned'
  );
exception when duplicate_object then null;
end $$;

-- Authoritative per-sense memory state ---------------------------------------

alter table public.user_sense_mastery
  add column if not exists learning_state
    public.sense_learning_state_enum not null default 'new',
  add column if not exists wrong_count integer not null default 0,
  add column if not exists consecutive_correct_count integer not null default 0,
  add column if not exists recent_results boolean[] not null default '{}',
  add column if not exists spaced_success_count integer not null default 0,
  add column if not exists has_active_recall_success boolean not null default false,
  add column if not exists difficulty_level integer not null default 0,
  add column if not exists first_seen_at timestamptz,
  add column if not exists first_correct_at timestamptz,
  add column if not exists last_correct_at timestamptz;

update public.user_sense_mastery
set learning_state = case
      when mastered_at is not null then 'mastered'::public.sense_learning_state_enum
      when review_stage >= 2 then 'reviewing'::public.sense_learning_state_enum
      when seen_count > 0 then 'learning'::public.sense_learning_state_enum
      else 'new'::public.sense_learning_state_enum
    end,
    first_seen_at = coalesce(first_seen_at, last_seen_at),
    first_correct_at = case
      when correct_count > 0
      then coalesce(first_correct_at, last_seen_at)
      else first_correct_at
    end,
    last_correct_at = case
      when correct_count > 0
      then coalesce(last_correct_at, last_seen_at)
      else last_correct_at
    end
where learning_state = 'new'
   or first_seen_at is null
   or (correct_count > 0 and (first_correct_at is null or last_correct_at is null));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_wrong_count_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_wrong_count_non_negative
      check (wrong_count >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_consecutive_correct_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_consecutive_correct_non_negative
      check (consecutive_correct_count >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_recent_results_max_six'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_recent_results_max_six
      check (coalesce(array_length(recent_results, 1), 0) <= 6);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_spaced_success_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_spaced_success_non_negative
      check (spaced_success_count >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_difficulty_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_difficulty_non_negative
      check (difficulty_level >= 0);
  end if;
end $$;

comment on column public.user_sense_mastery.review_stage is
  '0 learning, 1 ten_minute, 2 one_day, 3 seven_day, 4 thirty_day, 5 mastered_maintenance';
comment on column public.user_sense_mastery.recent_results is
  'Latest six formal answer results only; oldest result is removed first.';

alter table public.questions
  add column if not exists is_context_hint boolean not null default false,
  add column if not exists context_for_multiple_meaning boolean not null default false;

comment on column public.questions.is_context_hint is
  'Contextual Chinese-definition hint; selected only for multiple meanings or repeated mistakes.';
comment on column public.questions.context_for_multiple_meaning is
  'True when context is required to distinguish explicitly separate meanings.';

-- Mistake notebook display index --------------------------------------------

alter table public.mistake_senses
  add column if not exists first_wrong_at timestamptz,
  add column if not exists is_active boolean not null default true,
  add column if not exists resolved_at timestamptz;

update public.mistake_senses
set first_wrong_at = coalesce(first_wrong_at, created_at, last_wrong_at),
    is_active = case when mastered_at is null then true else false end,
    resolved_at = case
      when mastered_at is not null then coalesce(resolved_at, mastered_at)
      else null
    end
where first_wrong_at is null
   or (mastered_at is not null and is_active)
   or (mastered_at is not null and resolved_at is null);

alter table public.mistake_senses
  alter column first_wrong_at set default now();

update public.mistake_senses
set first_wrong_at = now()
where first_wrong_at is null;

alter table public.mistake_senses
  alter column first_wrong_at set not null;

comment on column public.mistake_senses.review_stage is
  'Legacy compatibility only. Read authoritative review_stage from user_sense_mastery.';
comment on column public.mistake_senses.next_due_at is
  'Legacy compatibility only. Read authoritative next_due_at from user_sense_mastery.';

-- Immutable round snapshots --------------------------------------------------

create table if not exists public.practice_rounds (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles(id) on delete cascade,
  level_number         integer not null references public.levels(level_number),
  session_id           uuid not null unique
                       references public.practice_sessions(id) on delete cascade,
  status               public.practice_round_status_enum not null default 'started',
  question_count       smallint not null,
  correct_count        smallint not null default 0,
  new_sense_count      smallint not null default 0,
  review_sense_count   smallint not null default 0,
  completion_key       uuid not null default gen_random_uuid(),
  started_at           timestamptz not null default now(),
  completed_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint practice_round_question_count_valid
    check (question_count between 1 and 20),
  constraint practice_round_correct_count_valid
    check (correct_count between 0 and question_count),
  constraint practice_round_mix_valid
    check (
      new_sense_count >= 0
      and review_sense_count >= 0
      and new_sense_count + review_sense_count <= question_count
    ),
  constraint practice_round_completion_order
    check (completed_at is null or completed_at >= started_at)
);

create unique index if not exists practice_rounds_one_started_per_level
  on public.practice_rounds (user_id, level_number)
  where status = 'started';

create table if not exists public.practice_round_questions (
  round_id           uuid not null references public.practice_rounds(id) on delete cascade,
  position           smallint not null,
  question_id        uuid not null references public.questions(id),
  sense_id           uuid not null references public.word_senses(id),
  question_skill     text not null default 'recognition',
  option_ids         uuid[] not null default '{}',
  correct_option_id  uuid references public.question_options(id),
  answer_given       text,
  is_correct         boolean,
  response_time_ms   integer,
  answered_at        timestamptz,

  primary key (round_id, position),
  unique (round_id, question_id),
  unique (round_id, sense_id),
  constraint practice_round_position_valid check (position between 1 and 20),
  constraint practice_round_skill_valid check (
    question_skill in ('recognition', 'active_recall', 'listening', 'speaking')
  ),
  constraint practice_round_response_time_valid check (
    response_time_ms is null or response_time_ms >= 0
  ),
  constraint practice_round_answer_consistent check (
    (answered_at is null and is_correct is null and response_time_ms is null)
    or
    (answered_at is not null and is_correct is not null and response_time_ms is not null)
  )
);

drop trigger if exists practice_rounds_set_updated_at on public.practice_rounds;
create trigger practice_rounds_set_updated_at
before update on public.practice_rounds
for each row execute function public.set_updated_at();

create index if not exists practice_rounds_user_started_idx
  on public.practice_rounds (user_id, started_at desc);
create index if not exists practice_round_questions_round_idx
  on public.practice_round_questions (round_id, position);
create index if not exists user_sense_mastery_priority_idx
  on public.user_sense_mastery (
    user_id,
    next_due_at,
    difficulty_level desc,
    review_stage
  );
create index if not exists mistake_senses_active_recent_idx
  on public.mistake_senses (user_id, is_active, last_wrong_at desc);

-- Internal helpers -----------------------------------------------------------

create or replace function public.append_recent_formal_result(
  p_results boolean[],
  p_result boolean
)
returns boolean[]
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(array_length(p_results, 1), 0) < 6
      then coalesce(p_results, '{}'::boolean[]) || p_result
    else p_results[2:6] || p_result
  end;
$$;

create or replace function public.refresh_level_completion(
  p_user_id uuid,
  p_level_number integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target_count integer;
  v_assignment_count integer;
  v_seen_count integer;
  v_qualifying_count integer;
  v_required_count integer;
  v_completed boolean;
  v_band_id smallint;
  v_next_band_id smallint;
begin
  select new_sense_target
  into v_target_count
  from public.levels
  where level_number = p_level_number;

  select count(*)
  into v_assignment_count
  from public.level_sense_assignments
  where level_number = p_level_number
    and placement_type = 'new';

  if coalesce(v_target_count, 0) = 0
     or v_assignment_count < v_target_count then
    return false;
  end if;

  v_required_count := ceil(v_target_count * 0.90)::integer;

  select
    count(*) filter (where usm.seen_count > 0),
    count(*) filter (
      where usm.correct_count > 0
        and usm.spaced_success_count > 0
        and usm.learning_state in ('reviewing', 'mastered')
    )
  into v_seen_count, v_qualifying_count
  from public.level_sense_assignments lsa
  left join public.user_sense_mastery usm
    on usm.user_id = p_user_id
   and usm.sense_id = lsa.sense_id
  where lsa.level_number = p_level_number
    and lsa.placement_type = 'new';

  v_completed :=
    v_seen_count = v_assignment_count
    and v_qualifying_count >= v_required_count;

  insert into public.user_level_progress (
    user_id,
    level_number,
    is_unlocked,
    is_completed,
    progress,
    unlocked_at,
    completed_at,
    updated_at
  )
  values (
    p_user_id,
    p_level_number,
    true,
    v_completed,
    least(1.0, v_qualifying_count::numeric / v_target_count),
    now(),
    case when v_completed then now() else null end,
    now()
  )
  on conflict (user_id, level_number) do update
  set is_completed = public.user_level_progress.is_completed or v_completed,
      progress = greatest(
        public.user_level_progress.progress,
        least(1.0, v_qualifying_count::numeric / v_target_count)
      ),
      completed_at = case
        when public.user_level_progress.completed_at is not null
          then public.user_level_progress.completed_at
        when v_completed then now()
        else null
      end,
      updated_at = now();

  if v_completed then
    select band_id into v_band_id
    from public.levels
    where level_number = p_level_number;

    select band_id into v_next_band_id
    from public.levels
    where level_number = p_level_number + 1;

    -- The upgrade exam owns cross-difficulty progression.
    if v_next_band_id = v_band_id then
      insert into public.user_level_progress (
        user_id,
        level_number,
        is_unlocked,
        unlocked_at
      )
      values (
        p_user_id,
        p_level_number + 1,
        true,
        now()
      )
      on conflict (user_id, level_number) do update
      set is_unlocked = true,
          unlocked_at = coalesce(public.user_level_progress.unlocked_at, now()),
          updated_at = now();
    end if;
  end if;

  return v_completed;
end;
$$;

-- Public RPCs ---------------------------------------------------------------

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round_id uuid;
  v_session_id uuid;
  v_due_count integer;
  v_max_new integer;
  v_question_count integer;
  v_new_count integer;
  v_review_count integer;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    select count(*)
    into v_due_count
    from public.user_sense_mastery
    where user_id = v_user_id
      and next_due_at is not null
      and next_due_at <= now()
      and learning_state <> 'mastered';

    v_max_new := case
      when v_due_count > 20 then 0
      when v_due_count > 0 then 12
      else 20
    end;

    insert into public.practice_sessions (
      user_id,
      level_number,
      session_type,
      status
    )
    values (
      v_user_id,
      p_level_number,
      'daily',
      'started'
    )
    returning id into v_session_id;

    insert into public.practice_rounds (
      user_id,
      level_number,
      session_id,
      question_count
    )
    values (
      v_user_id,
      p_level_number,
      v_session_id,
      1
    )
    returning id into v_round_id;

    with eligible_questions as (
      select
        q.id as question_id,
        q.sense_id,
        q.is_context_hint,
        q.context_for_multiple_meaning,
        (array_agg(qo.id) filter (where qo.is_correct))[1]
          as correct_option_id,
        array_agg(qo.id order by random()) as option_ids
      from public.questions q
      join public.question_options qo on qo.question_id = q.id
      where q.is_active
        and q.answer_form = 'option'
        and q.sense_id is not null
        and not q.human_review
        and not qo.human_review
      group by
        q.id,
        q.sense_id,
        q.is_context_hint,
        q.context_for_multiple_meaning
      having count(*) >= 2
         and count(*) filter (where qo.is_correct) = 1
    ),
    candidate_sources as (
      -- Global due reviews always outrank new material from the selected level.
      select
        usm.sense_id,
        case
          when ms.is_active
           and usm.next_due_at is not null
           and usm.next_due_at <= now() then 1
          else 2
        end as priority,
        usm.difficulty_level,
        usm.wrong_count,
        usm.next_due_at,
        false as is_new
      from public.user_sense_mastery usm
      left join public.mistake_senses ms
        on ms.user_id = v_user_id
       and ms.sense_id = usm.sense_id
      where usm.user_id = v_user_id
        and usm.next_due_at is not null
        and usm.next_due_at <= now()
        and usm.learning_state <> 'mastered'

      union all

      -- Selected-level new and near-due reinforcement candidates.
      select
        lsa.sense_id,
        case
          when usm.user_id is null then 3
          when usm.next_due_at is not null
           and usm.next_due_at <= now() + interval '24 hours' then 4
          else 5
        end,
        coalesce(usm.difficulty_level, 0),
        coalesce(usm.wrong_count, 0),
        coalesce(usm.next_due_at, 'infinity'::timestamptz),
        (usm.user_id is null)
      from public.level_sense_assignments lsa
      left join public.user_sense_mastery usm
        on usm.user_id = v_user_id
       and usm.sense_id = lsa.sense_id
      where lsa.level_number = p_level_number
        and lsa.placement_type = 'new'
    ),
    candidate_senses as (
      select distinct on (sense_id)
        sense_id,
        priority,
        difficulty_level,
        wrong_count,
        next_due_at,
        is_new
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
        row_number() over (
          partition by cs.is_new
          order by cs.priority, cs.next_due_at, cs.difficulty_level desc, random()
        ) as type_rank
      from candidate_senses cs
      where exists (
          select 1 from eligible_questions eq where eq.sense_id = cs.sense_id
        )
    ),
    limited as (
      select *
      from ranked
      where not is_new
         or type_rank <= v_max_new
      order by priority, next_due_at, difficulty_level desc, random()
      limit 20
    ),
    chosen as (
      select
        l.sense_id,
        l.priority,
        l.is_new,
        eq.question_id,
        eq.correct_option_id,
        eq.option_ids,
        row_number() over (
          order by l.priority, l.next_due_at, l.difficulty_level desc, random()
        )::smallint as position
      from limited l
      join lateral (
        select *
        from eligible_questions candidate
        where candidate.sense_id = l.sense_id
          and (
            not candidate.is_context_hint
            or candidate.context_for_multiple_meaning
            or l.wrong_count >= 3
          )
        order by
          case
            when candidate.is_context_hint
             and (
               candidate.context_for_multiple_meaning
               or l.wrong_count >= 3
             ) then 0
            else 1
          end,
          random()
        limit 1
      ) eq on true
    )
    insert into public.practice_round_questions (
      round_id,
      position,
      question_id,
      sense_id,
      question_skill,
      option_ids,
      correct_option_id
    )
    select
      v_round_id,
      position,
      question_id,
      sense_id,
      'recognition',
      option_ids,
      correct_option_id
    from chosen;

    select
      count(*),
      count(*) filter (
        where not exists (
          select 1
          from public.user_sense_mastery usm
          where usm.user_id = v_user_id
            and usm.sense_id = prq.sense_id
        )
      )
    into v_question_count, v_new_count
    from public.practice_round_questions prq
    where prq.round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible reviewed option questions for Level %', p_level_number;
    end if;

    v_review_count := v_question_count - v_new_count;

    update public.practice_rounds
    set question_count = v_question_count,
        new_sense_count = v_new_count,
        review_sense_count = v_review_count
    where id = v_round_id;
  end if;

  select jsonb_build_object(
    'round_id', r.id,
    'level_number', r.level_number,
    'status', r.status,
    'question_count', r.question_count,
    'new_sense_count', r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position', rq.position,
          'question_id', q.id,
          'sense_id', rq.sense_id,
          'stem', q.stem,
          'prompt_hint', q.prompt_hint,
          'translation_zh', q.translation_zh,
          'question_skill', rq.question_skill,
          'options', (
            select jsonb_agg(
              jsonb_build_object(
                'option_id', option_row.id,
                'option_text', option_row.option_text
              )
              order by option_order.ordinality
            )
            from unnest(rq.option_ids) with ordinality option_order(option_id, ordinality)
            join public.question_options option_row
              on option_row.id = option_order.option_id
          ),
          'answer_given', rq.answer_given,
          'is_answered', rq.answered_at is not null
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
  where r.id = v_round_id
    and r.user_id = v_user_id;

  return v_result;
end;
$$;

create or replace function public.save_practice_answer(
  p_round_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_item public.practice_round_questions%rowtype;
  v_is_correct boolean;
  v_now timestamptz := clock_timestamp();
  v_mastery public.user_sense_mastery%rowtype;
  v_old_stage smallint;
  v_new_stage smallint;
  v_new_state public.sense_learning_state_enum;
  v_due_advance boolean := false;
  v_next_due timestamptz;
  v_spaced_increment integer := 0;
  v_recent boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id
    and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position', p_position,
      'is_correct', v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'already_saved', true
    );
  end if;

  if v_item.correct_option_id is null then
    raise exception 'V1.0 only supports server-graded option questions';
  end if;

  if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
    raise exception 'Answer must be an option UUID';
  end if;

  if not (p_answer::uuid = any(v_item.option_ids)) then
    raise exception 'Answer option does not belong to this question';
  end if;

  v_is_correct := p_answer::uuid = v_item.correct_option_id;

  update public.practice_round_questions
  set answer_given = p_answer,
      is_correct = v_is_correct,
      response_time_ms = p_response_time_ms,
      answered_at = v_now
  where round_id = p_round_id
    and position = p_position;

  insert into public.user_sense_mastery (
    user_id,
    sense_id,
    learning_state,
    seen_count,
    correct_count,
    wrong_count,
    consecutive_correct_count,
    recent_results,
    review_stage,
    first_seen_at,
    first_correct_at,
    last_seen_at,
    last_correct_at,
    next_due_at,
    updated_at
  )
  values (
    v_user_id,
    v_item.sense_id,
    'new',
    0,
    0,
    0,
    0,
    '{}',
    0,
    v_now,
    null,
    null,
    null,
    null,
    v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id
    and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent := public.append_recent_formal_result(
    v_mastery.recent_results,
    v_is_correct
  );

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due := v_now + interval '10 minutes';
    elsif v_mastery.next_due_at is not null
       and v_now >= v_mastery.next_due_at then
      v_due_advance := true;
      v_new_stage := least(4, v_old_stage + 1);
      v_new_state := case
        when v_new_stage >= 2 then 'reviewing'
        else 'learning'
      end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '10 minutes'
        when 2 then v_now + interval '1 day'
        when 3 then v_now + interval '7 days'
        when 4 then
          case when v_old_stage = 4
            then v_now + interval '75 days'
            else v_now + interval '30 days'
          end
        else v_now + interval '10 minutes'
      end;
    else
      v_new_stage := v_old_stage;
      v_new_state := case
        when v_mastery.learning_state = 'new' then 'learning'
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        else v_mastery.learning_state
      end;
      v_next_due := v_mastery.next_due_at;
    end if;

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        correct_count = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results = v_recent,
        spaced_success_count = spaced_success_count + v_spaced_increment,
        review_stage = v_new_stage,
        mastery_score = least(0.99, v_new_stage::numeric / 5),
        first_seen_at = coalesce(first_seen_at, v_now),
        first_correct_at = coalesce(first_correct_at, v_now),
        last_seen_at = v_now,
        last_correct_at = v_now,
        next_due_at = v_next_due,
        mastered_at = null,
        updated_at = v_now
    where user_id = v_user_id
      and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active = false,
          resolved_at = v_now,
          last_reviewed_at = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at = v_now
      where user_id = v_user_id
        and sense_id = v_item.sense_id
        and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1 then 0
      when v_old_stage = 2 then 1
      when v_old_stage = 3 then 2
      when v_old_stage in (4, 5) then 3
      else 0
    end;
    v_new_state := case
      when v_new_stage = 0 then 'learning'
      else 'reviewing'
    end;
    v_next_due := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        wrong_count = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results = v_recent,
        review_stage = v_new_stage,
        mastery_score = least(0.99, v_new_stage::numeric / 5),
        difficulty_level = difficulty_level + 1,
        first_seen_at = coalesce(first_seen_at, v_now),
        last_seen_at = v_now,
        next_due_at = v_next_due,
        mastered_at = null,
        updated_at = v_now
    where user_id = v_user_id
      and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id,
      sense_id,
      wrong_count,
      first_wrong_at,
      last_wrong_at,
      is_active,
      resolved_at,
      created_at,
      updated_at
    )
    values (
      v_user_id,
      v_item.sense_id,
      1,
      v_now,
      v_now,
      true,
      null,
      v_now,
      v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        is_active = true,
        resolved_at = null,
        updated_at = v_now;
  end if;

  insert into public.practice_answers (
    user_id,
    session_id,
    question_id,
    sense_id,
    skill_type,
    answer_given,
    is_correct,
    response_time_ms,
    answered_at
  )
  values (
    v_user_id,
    v_round.session_id,
    v_item.question_id,
    v_item.sense_id,
    'multiple_choice',
    p_answer,
    v_is_correct,
    p_response_time_ms,
    v_now
  )
  on conflict (session_id, question_id) do nothing;

  return jsonb_build_object(
    'position', p_position,
    'is_correct', v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'already_saved', false,
    'learning_state', v_new_state,
    'review_stage', v_new_stage,
    'next_due_at', v_next_due
  );
end;
$$;

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

  update public.profiles
  set duck_power = duck_power + v_correct
  where id = v_user_id;

  update public.user_level_progress
  set completed_session_count = completed_session_count + 1,
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

create or replace function public.get_level_learning_status(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select jsonb_build_object(
    'level_number', p_level_number,
    'new_sense_target', (
      select new_sense_target
      from public.levels
      where level_number = p_level_number
    ),
    'assigned_new_sense_count', count(*),
    'required_count', ceil((
      select new_sense_target
      from public.levels
      where level_number = p_level_number
    ) * 0.90)::integer,
    'seen_count', count(*) filter (where usm.seen_count > 0),
    'first_correct_count', count(*) filter (where usm.correct_count > 0),
    'delayed_success_count', count(*) filter (
      where usm.spaced_success_count > 0
        and usm.learning_state in ('reviewing', 'mastered')
    ),
    'reviewing_count', count(*) filter (where usm.learning_state = 'reviewing'),
    'mastered_count', count(*) filter (where usm.learning_state = 'mastered'),
    'due_review_count', count(*) filter (
      where usm.next_due_at is not null and usm.next_due_at <= now()
    ),
    'is_unlocked', coalesce((
      select is_unlocked
      from public.user_level_progress
      where user_id = v_user_id
        and level_number = p_level_number
    ), false),
    'is_completed', coalesce((
      select is_completed
      from public.user_level_progress
      where user_id = v_user_id
        and level_number = p_level_number
    ), false),
    'display_state', case
      when not coalesce((
        select is_unlocked
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = p_level_number
      ), false) then '未解锁'
      when coalesce((
        select is_completed
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = p_level_number
      ), false) then '已通关'
      when count(*) filter (where usm.seen_count > 0) = 0 then '待开始'
      when count(*) filter (where usm.seen_count > 0) < count(*) then '学习中'
      else '巩固中'
    end
  )
  into v_result
  from public.level_sense_assignments lsa
  left join public.user_sense_mastery usm
    on usm.user_id = v_user_id
   and usm.sense_id = lsa.sense_id
  where lsa.level_number = p_level_number
    and lsa.placement_type = 'new';

  return v_result;
end;
$$;

-- Security -------------------------------------------------------------------

alter table public.practice_rounds enable row level security;
alter table public.practice_round_questions enable row level security;

drop policy if exists practice_rounds_own_select on public.practice_rounds;
create policy practice_rounds_own_select
on public.practice_rounds for select to authenticated
using (user_id = auth.uid());

-- Snapshot rows contain correct_option_id and therefore have no direct client
-- policy or grant. They are exposed only through security-definer RPCs.

revoke all on public.practice_rounds from anon, authenticated;
revoke all on public.practice_round_questions from anon, authenticated;
grant select on public.practice_rounds to authenticated;

revoke all on function public.append_recent_formal_result(boolean[], boolean)
  from public, anon, authenticated;
revoke all on function public.refresh_level_completion(uuid, integer)
  from public, anon, authenticated;

revoke all on function public.start_practice_round(integer)
  from public, anon;
revoke all on function public.save_practice_answer(uuid, integer, text, integer)
  from public, anon;
revoke all on function public.complete_practice_round(uuid)
  from public, anon;
revoke all on function public.get_level_learning_status(integer)
  from public, anon;

grant execute on function public.start_practice_round(integer) to authenticated;
grant execute on function public.save_practice_answer(uuid, integer, text, integer)
  to authenticated;
grant execute on function public.complete_practice_round(uuid) to authenticated;
grant execute on function public.get_level_learning_status(integer) to authenticated;

-- New learning mutations are server-owned. Existing SELECT access remains for
-- repository reads and RLS still limits rows to auth.uid().
revoke insert, update, delete on
  public.user_level_progress,
  public.practice_sessions,
  public.practice_answers,
  public.user_sense_mastery,
  public.user_sense_skill_progress,
  public.mistake_senses
from authenticated;

commit;
