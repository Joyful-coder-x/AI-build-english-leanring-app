-- Read-only Level word list for the practice result screen.

begin;

create or replace function public.get_level_word_statuses(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.levels
    where level_number = p_level_number
  ) then
    raise exception 'Level % does not exist', p_level_number;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'sense_id', sense_row.id,
        'word', word_row.headword,
        'definition_zh', sense_row.definition_zh,
        'status', case
          when mastery.learning_state = 'mastered' then '已掌握'
          when mastery.learning_state = 'reviewing' then '复习中'
          when mastery.seen_count > 0 then '学习中'
          else '未学习'
        end,
        'wrong_count', coalesce(mastery.wrong_count, 0),
        'is_due', coalesce(mastery.next_due_at <= now(), false)
      )
      order by assignment.order_in_level, word_row.headword
    ),
    '[]'::jsonb
  )
  into v_result
  from public.level_sense_assignments assignment
  join public.word_senses sense_row
    on sense_row.id = assignment.sense_id
  join public.words word_row
    on word_row.id = sense_row.word_id
  left join public.user_sense_mastery mastery
    on mastery.user_id = v_user_id
   and mastery.sense_id = assignment.sense_id
  where assignment.level_number = p_level_number
    and assignment.placement_type = 'new';

  return v_result;
end;
$$;

revoke all on function public.get_level_word_statuses(integer)
  from public, anon;
grant execute on function public.get_level_word_statuses(integer)
  to authenticated;

commit;
