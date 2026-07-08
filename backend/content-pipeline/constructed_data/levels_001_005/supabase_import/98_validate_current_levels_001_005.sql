-- Validate current Level 1-5 Supabase content after running
-- 99_upsert_current_levels_001_005.sql or all
-- 99_upsert_current_levels_001_005_part_*.sql files in numeric order.

-- 1. Level 1-5 assignment counts: expect 45 each.
select level_number, count(*) as new_sense_count
from public.level_sense_assignments
where level_number between 1 and 5
  and placement_type = 'new'
group by level_number
order by level_number;

-- 2. Every Level 1-5 sense has all 8 generated question types: expect 0 rows.
with expected(type_key) as (
  values
    ('meaning_choice'),
    ('sentence_cloze_typing'),
    ('listening_choice'),
    ('listening_fill'),
    ('speaking_repeat'),
    ('open_speaking'),
    ('word_form'),
    ('reading_comprehension')
), assigned as (
  select level_number, sense_id
  from public.level_sense_assignments
  where level_number between 1 and 5
    and placement_type = 'new'
), missing as (
  select a.level_number, a.sense_id, e.type_key
  from assigned a
  cross join expected e
  where not exists (
    select 1
    from public.questions q
    where q.sense_id = a.sense_id
      and q.question_type_key = e.type_key
      and q.generation_version = 'level_1_5_eight_type_v2'
      and q.is_active
      and not q.human_review
  )
)
select * from missing
order by level_number, sense_id, type_key;

-- 3. Option questions must have exactly 4 options and 1 correct option: expect 0 rows.
select q.id, q.question_type_key, count(o.id) as option_count,
       count(*) filter (where o.is_correct) as correct_count
from public.questions q
left join public.question_options o on o.question_id = q.id
where q.generation_version = 'level_1_5_eight_type_v2'
  and q.answer_form = 'option'
group by q.id, q.question_type_key
having count(o.id) <> 4
    or count(*) filter (where o.is_correct) <> 1;

-- 4. Question type coverage: expect 225 each.
select question_type_key, count(*)
from public.questions
where generation_version = 'level_1_5_eight_type_v2'
group by question_type_key
order by question_type_key;
