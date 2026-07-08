-- Meaning Choice answer persistence:
--   1. Relax practice_answers.question_id to nullable (dynamic questions have no pre-stored row).
--   2. Add question_type column for finer classification.
--   3. RPC: save one answer + upsert mastery + add mistake if wrong.
--   4. RPC: close session + upsert user_level_progress.

begin;

-- ── 1. Relax question_id ──────────────────────────────────────────────────────
-- Existing UNIQUE (session_id, question_id) stays; PostgreSQL treats NULLs as
-- distinct in unique indexes, so multiple meaning-choice answer rows per session
-- (all with question_id = NULL) are allowed and do not conflict.

alter table public.practice_answers
    alter column question_id drop not null;

-- ── 2. Add question_type ──────────────────────────────────────────────────────
alter table public.practice_answers
    add column if not exists question_type text;

-- ── 3. save_meaning_choice_answer ─────────────────────────────────────────────
-- Lazily finds (or creates) today's practice session for the caller, then saves
-- the answer, upserts user_sense_mastery, and logs a mistake when wrong.

create or replace function public.save_meaning_choice_answer(
    p_level_number       integer,
    p_sense_id           uuid,
    p_selected_sense_id  uuid,
    p_is_correct         boolean,
    p_response_time_ms   integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id    uuid := auth.uid();
    v_session_id uuid;
begin
    -- Find the most recent 'started' session for this user + level today.
    select id into v_session_id
    from public.practice_sessions
    where user_id     = v_user_id
      and level_number = p_level_number
      and status       = 'started'
      and started_at  >= date_trunc('day', now())
    order by started_at desc
    limit 1;

    -- Create one if none exists.
    if v_session_id is null then
        insert into public.practice_sessions (user_id, level_number, session_type, status)
        values (v_user_id, p_level_number, 'daily', 'started')
        returning id into v_session_id;
    end if;

    -- Record the answer (question_id is null for dynamic question types).
    insert into public.practice_answers (
        user_id, session_id, sense_id,
        skill_type, question_type,
        answer_given, is_correct, response_time_ms
    )
    values (
        v_user_id,
        v_session_id,
        p_sense_id,
        'multiple_choice'::public.learning_skill_enum,
        'meaning_choice',
        p_selected_sense_id::text,
        p_is_correct,
        p_response_time_ms
    );

    -- Upsert user_sense_mastery (simple accuracy-based score).
    insert into public.user_sense_mastery
        (user_id, sense_id, seen_count, correct_count, mastery_score, updated_at)
    values (
        v_user_id,
        p_sense_id,
        1,
        case when p_is_correct then 1 else 0 end,
        case when p_is_correct then 0.2 else 0.0 end,
        now()
    )
    on conflict (user_id, sense_id) do update
    set seen_count    = public.user_sense_mastery.seen_count + 1,
        correct_count = public.user_sense_mastery.correct_count
                        + case when p_is_correct then 1 else 0 end,
        mastery_score = least(1.0,
            (public.user_sense_mastery.correct_count
             + case when p_is_correct then 1 else 0 end)::numeric
            / (public.user_sense_mastery.seen_count + 1)),
        updated_at    = now();

    -- Log mistake when wrong.
    if not p_is_correct then
        insert into public.mistake_senses
            (user_id, sense_id, wrong_count, last_wrong_at, created_at, updated_at)
        values (v_user_id, p_sense_id, 1, now(), now(), now())
        on conflict (user_id, sense_id) do update
        set wrong_count   = public.mistake_senses.wrong_count + 1,
            last_wrong_at = now(),
            updated_at    = now();
    end if;
end;
$$;

-- ── 4. complete_meaning_choice_session ────────────────────────────────────────
-- Marks today's session as completed and upserts user_level_progress.

create or replace function public.complete_meaning_choice_session(
    p_level_number      integer,
    p_correct_count     integer,
    p_total_count       integer,
    p_star_rating       smallint,
    p_duck_power_earned integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id    uuid := auth.uid();
    v_session_id uuid;
    v_progress   numeric(5,4);
begin
    select id into v_session_id
    from public.practice_sessions
    where user_id     = v_user_id
      and level_number = p_level_number
      and status       = 'started'
      and started_at  >= date_trunc('day', now())
    order by started_at desc
    limit 1;

    -- Nothing to do if session never started (e.g. all saves failed silently).
    if v_session_id is null then
        return;
    end if;

    update public.practice_sessions
    set status            = 'completed',
        completed_at      = now(),
        correct_count     = p_correct_count,
        total_count       = p_total_count,
        star_rating       = p_star_rating,
        duck_power_earned = p_duck_power_earned,
        base_power        = p_correct_count
                            + case when p_correct_count = p_total_count then 5 else 0 end
    where id = v_session_id;

    v_progress := case when p_total_count > 0
                  then least(1.0, p_correct_count::numeric / p_total_count)
                  else 0.0 end;

    insert into public.user_level_progress
        (user_id, level_number, is_unlocked, is_completed, progress,
         best_star_rating, completed_session_count, unlocked_at)
    values (
        v_user_id,
        p_level_number,
        true,
        p_star_rating >= 3,
        v_progress,
        p_star_rating,
        1,
        now()
    )
    on conflict (user_id, level_number) do update
    set is_completed            = public.user_level_progress.is_completed
                                  or (p_star_rating >= 3),
        progress                = greatest(public.user_level_progress.progress, v_progress),
        best_star_rating        = greatest(public.user_level_progress.best_star_rating, p_star_rating),
        completed_session_count = public.user_level_progress.completed_session_count + 1,
        updated_at              = now();
end;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────
grant execute on function public.save_meaning_choice_answer(
    integer, uuid, uuid, boolean, integer
) to authenticated;

grant execute on function public.complete_meaning_choice_session(
    integer, integer, integer, smallint, integer
) to authenticated;

commit;
