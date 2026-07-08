-- Phase 1 combo scope practice type policy.
--
-- Levels 1-5 remain the deep eight-type learning slice.
-- Levels 6-54 use a lighter generated set that only depends on core word,
-- definition/translation, and headword data.

create or replace function public.pick_practice_question_type(
  p_sense_id uuid,
  p_is_new boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_word_id uuid;
  v_level_number integer;
  v_types text[] := array['meaning_choice'];
begin
  select word_id into v_word_id
  from public.word_senses
  where id = p_sense_id;

  select min(level_number)
  into v_level_number
  from public.level_sense_assignments
  where sense_id = p_sense_id
    and placement_type = 'new';

  -- First exposure introduces the word by meaning before richer review.
  if p_is_new then
    return 'meaning_choice';
  end if;

  if coalesce(v_level_number, 999) between 1 and 5 then
    v_types := array['meaning_choice', 'speaking_repeat', 'open_speaking'];

    if exists (
      select 1 from public.examples
      where sense_id = p_sense_id
        and not human_review
        and char_length(btrim(sentence_en)) > 0
        and char_length(btrim(target_span)) > 0
    ) then
      v_types := v_types || array['sentence_cloze_typing', 'reading_comprehension'];
    end if;

    if v_word_id is not null then
      v_types := v_types || array['listening_choice', 'listening_fill'];
    end if;

    if exists (
      select 1 from public.word_forms
      where word_id = v_word_id
        and not human_review
        and char_length(btrim(form_text)) > 0
    ) then
      v_types := v_types || array['word_form'];
    end if;
  else
    -- Lightweight Band 4 path: no authored example, collocation, or word-form
    -- dependency. sentence_cloze_typing falls back to a definition prompt in
    -- generate_practice_question when no example exists.
    v_types := array['meaning_choice', 'sentence_cloze_typing', 'speaking_repeat'];

    if v_word_id is not null then
      v_types := v_types || array['listening_choice', 'listening_fill'];
    end if;
  end if;

  return v_types[1 + floor(random() * array_length(v_types, 1))::integer];
end;
$$;

revoke all on function public.pick_practice_question_type(uuid, boolean) from public, anon, authenticated;
grant execute on function public.pick_practice_question_type(uuid, boolean) to authenticated;

