\set ON_ERROR_STOP on

-- Unit-tests compute_skill_band's piecewise mapping (Scoring PDF Table 2,
-- generalized as fractions of max) independent of any user data.

do $$
begin
  if public.compute_skill_band(null, null) is not distinct from null then
    null;
  else
    raise exception 'Expected null band for null max (insufficient data)';
  end if;

  if public.compute_skill_band(0, 0) is not distinct from null then
    null;
  else
    raise exception 'Expected null band when max=0 (insufficient data)';
  end if;

  if public.compute_skill_band(0, 100) <> 0.0 then
    raise exception 'Expected band 0 for 0%% correct, got %', public.compute_skill_band(0, 100);
  end if;

  if public.compute_skill_band(45, 100) <> 4.0 then
    raise exception 'Expected band 4 for 45%% correct, got %', public.compute_skill_band(45, 100);
  end if;

  if public.compute_skill_band(100, 100) <> 9.0 then
    raise exception 'Expected band 9 for 100%% correct, got %', public.compute_skill_band(100, 100);
  end if;

  if public.compute_skill_band(97, 100) <> 9.0 then
    raise exception 'Expected band 9 for 97%% correct (>=96.3%% threshold), got %',
      public.compute_skill_band(97, 100);
  end if;

  if public.compute_skill_band(20, 100) <> 2.0 then
    raise exception 'Expected band 2 for 20%% correct, got %', public.compute_skill_band(20, 100);
  end if;

  -- Difficulty weighting: a Band 4.0 sense should currently be the only
  -- weight in the system (no Band 4.5+ content yet).
  if not exists (
    select 1
    from public.level_sense_assignments lsa
    where lsa.placement_type = 'new'
    limit 1
  ) then
    raise exception 'Requires the Band 4.0 content package to check sense_difficulty_weight';
  end if;

  if (
    select public.sense_difficulty_weight(lsa.sense_id)
    from public.level_sense_assignments lsa
    where lsa.placement_type = 'new'
    limit 1
  ) <> 4.0 then
    raise exception 'Expected Band 4.0 content to weight as 4.0';
  end if;
end;
$$;
