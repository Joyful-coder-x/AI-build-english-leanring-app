-- Speaking questions use a client-side positive self-check when an older
-- round snapshot does not contain the corresponding option row. Accept that
-- sentinel only for speaking self-check types; all other option answers must
-- remain UUIDs belonging to the round snapshot.

do $$
declare
  v_original text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.finalize_practice_answer(uuid,integer,text,integer)'::regprocedure
  ) into v_original;

  if position('''__self_check_known__''' in v_original) > 0 then
    return;
  end if;

  v_updated := replace(
    v_original,
$old$
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
$old$,
$new$
  if v_q_answer_form = 'option' then
    if v_item.correct_option_id is null then
      raise exception 'Option question missing correct_option_id';
    end if;
    if p_answer = '__self_check_known__'
       and v_q_type_key in ('speaking_repeat', 'open_speaking') then
      v_is_correct := true;
    else
      if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
        raise exception 'Answer must be an option UUID';
      end if;
      if not (p_answer::uuid = any(v_item.option_ids)) then
        raise exception 'Answer option does not belong to this question';
      end if;
      v_is_correct := p_answer::uuid = v_item.correct_option_id;
    end if;
$new$
  );

  if v_updated = v_original then
    raise exception 'Could not patch speaking self-check answer handling';
  end if;

  execute v_updated;
end;
$$;
