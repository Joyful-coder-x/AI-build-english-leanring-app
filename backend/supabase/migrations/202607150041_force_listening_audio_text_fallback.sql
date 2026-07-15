-- Upgrade the existing audio_text projection so rounds created before
-- generated_payload was populated can still play their listening target.

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
          'audio_text', case
            when rq.question_type_key like 'listening_%' then
              coalesce(
                rq.generated_payload ->> 'headword',
                rq.generated_payload ->> 'correct_answer',
                rq.correct_answer_payload ->> 'correct_answer'
              )
            else null
          end,
$old$,
$new$
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
    if position(
$current$
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
$current$
      in v_original
    ) > 0 then
      return;
    end if;

    raise exception 'Could not upgrade public.start_practice_round(integer) audio_text fallback';
  end if;

  execute v_updated;
end;
$$;
