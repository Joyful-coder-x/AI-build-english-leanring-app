-- Make user_level_progress.progress a level completion rate derived only from
-- the current state of every sense assigned to the level:
--   mastered = 1.0, learning/reviewing = 0.5, new/unseen = 0.0.

begin;

create or replace function public.calculate_level_completion_rate(
  p_user_id uuid,
  p_level_number integer
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    sum(
      case
        when mastery.learning_state = 'mastered' then 1.0
        when mastery.learning_state in ('learning', 'reviewing')
          or coalesce(mastery.seen_count, 0) > 0 then 0.5
        else 0.0
      end
    ) / nullif(count(*), 0),
    0.0
  )
  from (
    select distinct assignment.sense_id
    from public.level_sense_assignments assignment
    where assignment.level_number = p_level_number
  ) level_sense
  left join public.user_sense_mastery mastery
    on mastery.user_id = p_user_id
   and mastery.sense_id = level_sense.sense_id;
$$;

comment on function public.calculate_level_completion_rate(uuid, integer) is
  'Completion rate across every distinct sense assigned to a level: mastered=1, in-progress=0.5, unseen=0.';

-- Enforce the meaning of progress at the storage boundary. This also protects
-- against legacy session-completion and band-upgrade code that writes accuracy
-- or a synthetic value into the same column.
create or replace function public.enforce_level_completion_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.progress := public.calculate_level_completion_rate(
    new.user_id,
    new.level_number
  );
  return new;
end;
$$;

drop trigger if exists user_level_progress_completion_rate
  on public.user_level_progress;
create trigger user_level_progress_completion_rate
before insert or update on public.user_level_progress
for each row execute function public.enforce_level_completion_rate();

-- Keep completion rates current even if a learner leaves a round before its
-- normal completion RPC updates user_level_progress.
create or replace function public.refresh_affected_level_completion_rates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.user_level_progress progress_row
  set progress = public.calculate_level_completion_rate(
        new.user_id,
        progress_row.level_number
      ),
      updated_at = now()
  where progress_row.user_id = new.user_id
    and exists (
      select 1
      from public.level_sense_assignments assignment
      where assignment.level_number = progress_row.level_number
        and assignment.sense_id = new.sense_id
    );

  return new;
end;
$$;

drop trigger if exists user_sense_mastery_refresh_level_completion_rates
  on public.user_sense_mastery;
create trigger user_sense_mastery_refresh_level_completion_rates
after insert or update of learning_state, seen_count, mastered_at
on public.user_sense_mastery
for each row execute function public.refresh_affected_level_completion_rates();

-- Replace historical accuracy/mastery-ratio values for existing users.
update public.user_level_progress progress_row
set progress = public.calculate_level_completion_rate(
      progress_row.user_id,
      progress_row.level_number
    ),
    updated_at = now();

revoke all on function public.calculate_level_completion_rate(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.enforce_level_completion_rate()
  from public, anon, authenticated;
revoke all on function public.refresh_affected_level_completion_rates()
  from public, anon, authenticated;

commit;
