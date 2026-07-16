\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000046',
  'level-completion-rate@example.com',
  '{"username":"level_completion_rate","nickname":"Completion Rate"}'::jsonb
);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
values (
  '10000000-0000-0000-0000-000000000046',
  1,
  true,
  now()
);

do $$
declare
  v_user_id constant uuid := '10000000-0000-0000-0000-000000000046';
  v_sense_ids uuid[];
  v_total integer;
  v_expected numeric;
  v_actual numeric;
begin
  select array_agg(sense_id order by sense_id), count(*)
  into v_sense_ids, v_total
  from (
    select distinct sense_id
    from public.level_sense_assignments
    where level_number = 1
  ) assigned;

  if v_total < 4 then
    raise exception 'Level 1 needs at least four assigned senses for this test';
  end if;

  -- Unseen/new contributes zero.
  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, updated_at
  ) values (
    v_user_id, v_sense_ids[1], 'new', 0, now()
  );

  -- learning and reviewing contribute 0.5 each; mastered contributes 1.0.
  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, mastered_at, updated_at
  ) values
    (v_user_id, v_sense_ids[2], 'learning', 1, null, now()),
    (v_user_id, v_sense_ids[3], 'reviewing', 2, null, now()),
    (v_user_id, v_sense_ids[4], 'mastered', 4, now(), now());

  v_expected := 2.0 / v_total;

  select progress into v_actual
  from public.user_level_progress
  where user_id = v_user_id and level_number = 1;

  if abs(v_actual - v_expected) > 0.0001 then
    raise exception 'Expected completion rate %, got %', v_expected, v_actual;
  end if;

  -- Legacy callers cannot overwrite completion rate with an accuracy value.
  update public.user_level_progress
  set progress = 1.0
  where user_id = v_user_id and level_number = 1;

  select progress into v_actual
  from public.user_level_progress
  where user_id = v_user_id and level_number = 1;

  if abs(v_actual - v_expected) > 0.0001 then
    raise exception 'Storage trigger allowed a synthetic progress value: %', v_actual;
  end if;
end;
$$;

rollback;
