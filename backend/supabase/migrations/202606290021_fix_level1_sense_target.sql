-- KuaKua Duck: fix Level 1 new_sense_target to match actual imported words.
--
-- Problem: migration 003 seeded all 240 levels with new_sense_target = 45.
-- Level 1 currently has only 20 pilot-batch words in level_sense_assignments.
-- refresh_level_completion returns false immediately when
--   assignment_count (20) < new_sense_target (45), so level completion
--   can never trigger regardless of how many rounds the user plays.
--
-- Fix: set Level 1's new_sense_target = actual count of 'new' sense assignments,
-- and adjust review_target to keep the constraint (new + collocation + review = 80).
-- collocation_target is left at its current value.
--
-- This migration is safe to re-run: the update is idempotent if the target
-- already matches the assignment count.

begin;

update public.levels
set new_sense_target = sub.actual_count,
    review_target    = 80 - sub.actual_count - collocation_target
from (
  select count(*)::integer as actual_count
  from public.level_sense_assignments
  where level_number = 1
    and placement_type = 'new'
) sub
where level_number = 1
  and new_sense_target <> sub.actual_count;

commit;
