-- Ensure listening practice rounds always expose the hidden target word as
-- audio_text. Without this payload the Android client cannot replay audio
-- because listening stems intentionally do not reveal the answer.

do $$
declare
  v_original text;
  v_updated text;
begin
  select pg_get_functiondef('public.start_practice_round(integer)'::regprocedure)
  into v_original;

  if position('''audio_text''' in v_original) > 0 then
    return;
  end if;

  v_updated := replace(
    v_original,
$old$
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
$old$,
$new$
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
          'audio_text', case
            when rq.question_type_key like 'listening_%' then
              coalesce(
                rq.generated_payload ->> 'headword',
                rq.generated_payload ->> 'correct_answer',
                rq.correct_answer_payload ->> 'correct_answer',
                q.correct_answer
              )
            else null
          end,
$new$
  );

  if v_updated = v_original then
    raise exception 'Could not patch public.start_practice_round(integer) with audio_text';
  end if;

  execute v_updated;
end;
$$;
