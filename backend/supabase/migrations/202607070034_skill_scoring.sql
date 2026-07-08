-- Phase 1 Feature I: skill scoring per
-- "support/Scoring System Design for IELTS-Style Bands.pdf".
--
-- The PDF's Section 1 formula: R_s = sum(w_type(i) * w_diff(d_i) * p_i),
-- where d_i is the item's IELTS-band difficulty label and w_diff(d) = d
-- (linear, higher-difficulty items count more). We use each sense's
-- originating band_score (bands.band_score, via its 'new' placement level)
-- as d_i. In Phase 1 all content is Band 4.0, so this weighting is inert
-- (every item has the same weight) until Band 4.5+ content exists, at which
-- point it activates automatically without further changes here.
--
-- The PDF's Section 2 offers two calibration methods: a logistic S-curve
-- (needs simulation-derived k/m constants we do not have — no real user data
-- exists pre-launch) and piecewise raw-to-band thresholds (Table 2). We use
-- the piecewise table, generalized as fractions of the maximum achievable
-- weighted score, because Table 2's own bins are directly reusable without
-- inventing calibration constants: PDF Table 2 gives cut points
-- 0,10,25,40,55,70,85,100,115,130,135 out of a max of 135, i.e. bands 0-9 at
-- fractions 0, .074, .185, .296, .407, .519, .630, .741, .852, .963, 1.0.

create or replace function public.sense_difficulty_weight(
  p_sense_id uuid
)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (
      select b.band_score
      from public.level_sense_assignments lsa
      join public.levels l on l.level_number = lsa.level_number
      join public.bands b on b.id = l.band_id
      where lsa.sense_id = p_sense_id
        and lsa.placement_type = 'new'
      limit 1
    ),
    4.0
  );
$$;

create or replace function public.compute_skill_band(
  p_weighted_correct numeric,
  p_weighted_max numeric
)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_weighted_max is null or p_weighted_max <= 0 then null
    else (
      case
        when (p_weighted_correct / p_weighted_max) < 0.0741 then 0.0
        when (p_weighted_correct / p_weighted_max) < 0.1852 then 1.0
        when (p_weighted_correct / p_weighted_max) < 0.2963 then 2.0
        when (p_weighted_correct / p_weighted_max) < 0.4074 then 3.0
        when (p_weighted_correct / p_weighted_max) < 0.5185 then 4.0
        when (p_weighted_correct / p_weighted_max) < 0.6296 then 5.0
        when (p_weighted_correct / p_weighted_max) < 0.7407 then 6.0
        when (p_weighted_correct / p_weighted_max) < 0.8519 then 7.0
        when (p_weighted_correct / p_weighted_max) < 0.9630 then 8.0
        else 9.0
      end
    )::numeric(3,1)
  end;
$$;
