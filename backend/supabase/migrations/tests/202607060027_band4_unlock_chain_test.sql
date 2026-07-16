\set ON_ERROR_STOP on

-- Requires the complete Band 4.0 content package.
-- Proves that compact Band 4 progression can unlock every next level inside
-- Band 4, while the final Band 4 level still cannot unlock Band 4.5 without
-- the exam.
-- All mutations are rolled back.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000027',
  'band4-unlock-chain@example.com',
  '{"username":"band4_unlock_chain","nickname":"Band 4 Unlock Chain"}'::jsonb
);

do $$
declare
  v_level integer;
  v_next_level integer;
  v_band4_last integer;
  v_band45_first integer;
  v_current_band smallint;
  v_next_band smallint;
begin
  select max(level_number) into v_band4_last from public.levels where band_id = 1;
  select min(level_number) into v_band45_first from public.levels where band_id = 2;

  if v_band4_last is null or v_band45_first is null then
    raise exception 'Band 4 or Band 4.5 level metadata is missing';
  end if;

  for v_level in
    select level_number from public.levels where band_id = 1 order by level_number
  loop
    select band_id
    into v_current_band
    from public.levels
    where level_number = v_level;

    if v_current_band is null then
      raise exception 'Level % is missing from public.levels', v_level;
    end if;

    if v_current_band <> 1 then
      raise exception 'Level % is not in Band 4.0/band_id=1', v_level;
    end if;

    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      unlocked_at
    )
    values (
      '10000000-0000-0000-0000-000000000027',
      v_level,
      true,
      now()
    )
    on conflict (user_id, level_number) do update
    set is_unlocked = true,
        unlocked_at = coalesce(public.user_level_progress.unlocked_at, now());

    insert into public.user_sense_mastery (
      user_id,
      sense_id,
      learning_state,
      review_stage,
      seen_count,
      correct_count,
      spaced_success_count,
      first_seen_at,
      first_correct_at,
      last_seen_at,
      last_correct_at,
      next_due_at
    )
    select
      '10000000-0000-0000-0000-000000000027',
      lsa.sense_id,
      'reviewing'::public.sense_learning_state_enum,
      2,
      2,
      2,
      1,
      now() - interval '20 minutes',
      now() - interval '20 minutes',
      now(),
      now(),
      now() + interval '1 day'
    from public.level_sense_assignments lsa
    where lsa.level_number = v_level
      and lsa.placement_type = 'new'
    on conflict (user_id, sense_id) do update
    set learning_state = 'reviewing'::public.sense_learning_state_enum,
        review_stage = 2,
        seen_count = greatest(public.user_sense_mastery.seen_count, 2),
        correct_count = greatest(public.user_sense_mastery.correct_count, 2),
        spaced_success_count = greatest(public.user_sense_mastery.spaced_success_count, 1),
        first_seen_at = coalesce(public.user_sense_mastery.first_seen_at, excluded.first_seen_at),
        first_correct_at = coalesce(public.user_sense_mastery.first_correct_at, excluded.first_correct_at),
        last_seen_at = excluded.last_seen_at,
        last_correct_at = excluded.last_correct_at,
        next_due_at = excluded.next_due_at,
        updated_at = now();

    if not public.refresh_level_completion(
      '10000000-0000-0000-0000-000000000027',
      v_level
    ) then
      raise exception 'Level % did not complete with all new senses qualified', v_level;
    end if;

    v_next_level := v_level + 1;

    if v_next_level <= v_band4_last then
      select band_id
      into v_next_band
      from public.levels
      where level_number = v_next_level;

      if v_next_band <> v_current_band then
        raise exception 'Unexpected band boundary inside Band 4 at Level % -> %',
          v_level, v_next_level;
      end if;

      if not exists (
        select 1
        from public.user_level_progress
        where user_id = '10000000-0000-0000-0000-000000000027'
          and level_number = v_next_level
          and is_unlocked
      ) then
        raise exception 'Completing Level % did not unlock Level %',
          v_level, v_next_level;
      end if;
    end if;
  end loop;

  if exists (
    select 1
    from public.user_level_progress
    where user_id = '10000000-0000-0000-0000-000000000027'
      and level_number = v_band45_first
      and is_unlocked
  ) then
    raise exception 'Completing final Band 4 Level % bypassed the Band 4 -> 4.5 upgrade exam',
      v_band4_last;
  end if;
end;
$$;

rollback;
