-- Restore authenticated read privileges for account-adjacent tables that are
-- protected by RLS policies. Policies alone are not enough; PostgREST also
-- requires table privileges for the authenticated role.

begin;

alter table public.user_props enable row level security;
alter table public.award_definitions enable row level security;
alter table public.user_awards enable row level security;

drop policy if exists user_props_select_own on public.user_props;
create policy user_props_select_own
on public.user_props
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists award_definitions_select_all on public.award_definitions;
create policy award_definitions_select_all
on public.award_definitions
for select
to authenticated
using (true);

drop policy if exists user_awards_select_own on public.user_awards;
create policy user_awards_select_own
on public.user_awards
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_props from anon;
revoke all on public.award_definitions from anon;
revoke all on public.user_awards from anon;

grant select on public.user_props to authenticated;
grant select on public.award_definitions to authenticated;
grant select on public.user_awards to authenticated;

commit;
