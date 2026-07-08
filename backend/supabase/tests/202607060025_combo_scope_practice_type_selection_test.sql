\set ON_ERROR_STOP on

-- Requires the Band 4.0 content package and migration
-- 202607060025_combo_scope_practice_type_selection.sql.
-- All mutations are rolled back.

begin;

do $$
declare
  v_level1_sense uuid;
  v_level6_sense uuid;
  v_type text;
  v_seen_level1_rich boolean := false;
  v_attempt integer;
begin
  select sense_id
  into v_level1_sense
  from public.level_sense_assignments
  where level_number = 1
    and placement_type = 'new'
  order by order_in_level
  limit 1;

  select sense_id
  into v_level6_sense
  from public.level_sense_assignments
  where level_number >= 6
    and placement_type = 'new'
  order by level_number, order_in_level
  limit 1;

  if v_level1_sense is null then
    raise exception 'No Level 1 sense found. Import Band 4.0 or Level 1-5 content first.';
  end if;

  if v_level6_sense is null then
    raise exception 'No Level 6+ sense found. Import the full Band 4.0 package first.';
  end if;

  if public.pick_practice_question_type(v_level1_sense, true) <> 'meaning_choice' then
    raise exception 'New Level 1 sense should begin with meaning_choice.';
  end if;

  if public.pick_practice_question_type(v_level6_sense, true) <> 'meaning_choice' then
    raise exception 'New Level 6+ sense should begin with meaning_choice.';
  end if;

  for v_attempt in 1..80 loop
    v_type := public.pick_practice_question_type(v_level1_sense, false);

    if v_type not in (
      'meaning_choice',
      'sentence_cloze_typing',
      'listening_choice',
      'listening_fill',
      'speaking_repeat',
      'open_speaking',
      'word_form',
      'reading_comprehension'
    ) then
      raise exception 'Unexpected Level 1-5 question type: %', v_type;
    end if;

    if v_type in ('open_speaking', 'word_form', 'reading_comprehension') then
      v_seen_level1_rich := true;
    end if;
  end loop;

  if not v_seen_level1_rich then
    raise exception 'Level 1-5 selector did not expose any rich-only type in 80 attempts.';
  end if;

  for v_attempt in 1..120 loop
    v_type := public.pick_practice_question_type(v_level6_sense, false);

    if v_type not in (
      'meaning_choice',
      'sentence_cloze_typing',
      'listening_choice',
      'listening_fill',
      'speaking_repeat'
    ) then
      raise exception 'Level 6+ selector returned a deep-only type: %', v_type;
    end if;
  end loop;
end;
$$;

rollback;

