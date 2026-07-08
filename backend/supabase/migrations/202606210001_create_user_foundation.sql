-- Initial private user-data foundation for Supabase.
-- Run after Supabase Auth is available. Shared content tables are not required.

begin;

create type public.onboarding_status_enum as enum (
  'not_started',
  'in_progress',
  'completed',
  'skipped'
);

create type public.consent_document_enum as enum (
  'terms',
  'privacy',
  'carrier_terms'
);

create sequence public.public_user_code_seq
  as bigint
  start with 1000000001;

revoke all on sequence public.public_user_code_seq from public, anon, authenticated;

create table public.profiles (
  id                    uuid primary key
                        references auth.users(id) on delete cascade,
  public_user_code      text not null unique,
  nickname              text not null,
  avatar_path           text,
  duck_power            integer not null default 0,
  onboarding_status     public.onboarding_status_enum
                        not null default 'not_started',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint profiles_public_user_code_format
    check (public_user_code ~ '^KQ[0-9]{10,}$'),
  constraint profiles_nickname_not_blank
    check (char_length(btrim(nickname)) between 1 and 36),
  constraint profiles_nickname_forbidden_characters
    check (nickname !~ '[@<>/]'),
  constraint profiles_duck_power_non_negative
    check (duck_power >= 0),
  constraint profiles_avatar_path_length
    check (avatar_path is null or char_length(avatar_path) <= 500)
);

comment on column public.profiles.public_user_code is
  'Stable user-facing ID. The auth UUID must not be displayed as the public ID.';
comment on column public.profiles.duck_power is
  'Server-managed lifetime experience total. Clients cannot update this column directly.';

create table public.user_settings (
  user_id                       uuid primary key
                                references public.profiles(id) on delete cascade,
  learning_reminder_enabled     boolean not null default false,
  streak_reminder_enabled       boolean not null default false,
  reminder_timezone             text not null default 'UTC',
  sound_enabled                 boolean not null default true,
  haptics_enabled               boolean not null default true,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),

  constraint user_settings_timezone_not_blank
    check (char_length(btrim(reminder_timezone)) between 1 and 100)
);

create table public.user_consents (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null
                     references public.profiles(id) on delete cascade,
  document_type      public.consent_document_enum not null,
  document_version   text not null,
  accepted_at        timestamptz not null default now(),
  withdrawn_at       timestamptz,

  constraint user_consents_document_version_not_blank
    check (char_length(btrim(document_version)) between 1 and 100),
  constraint user_consents_withdrawal_order
    check (withdrawn_at is null or withdrawn_at >= accepted_at),
  constraint user_consents_acceptance_unique
    unique (user_id, document_type, document_version)
);

create table public.onboarding_profiles (
  user_id                 uuid primary key
                          references public.profiles(id) on delete cascade,
  questionnaire_version   text not null,
  answers                 jsonb not null default '{}'::jsonb,
  started_at              timestamptz not null default now(),
  completed_at            timestamptz,
  skipped_at              timestamptz,
  updated_at              timestamptz not null default now(),

  constraint onboarding_questionnaire_version_not_blank
    check (char_length(btrim(questionnaire_version)) between 1 and 100),
  constraint onboarding_answers_is_object
    check (jsonb_typeof(answers) = 'object'),
  constraint onboarding_single_finish_state
    check (completed_at is null or skipped_at is null),
  constraint onboarding_completed_after_start
    check (completed_at is null or completed_at >= started_at),
  constraint onboarding_skipped_after_start
    check (skipped_at is null or skipped_at >= started_at)
);

create index user_consents_user_accepted_idx
  on public.user_consents (user_id, accepted_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger user_settings_set_updated_at
before update on public.user_settings
for each row execute function public.set_updated_at();

create trigger onboarding_profiles_set_updated_at
before update on public.onboarding_profiles
for each row execute function public.set_updated_at();

revoke all on function public.set_updated_at() from public;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_code text;
  requested_nickname text;
  requested_timezone text;
begin
  generated_code :=
    'KQ' || nextval('public.public_user_code_seq'::regclass)::text;

  requested_nickname := btrim(coalesce(new.raw_user_meta_data ->> 'nickname', ''));
  if char_length(requested_nickname) not between 1 and 36
     or requested_nickname ~ '[@<>/]' then
    requested_nickname := generated_code;
  end if;

  requested_timezone := btrim(coalesce(new.raw_user_meta_data ->> 'timezone', ''));
  if char_length(requested_timezone) not between 1 and 100 then
    requested_timezone := 'UTC';
  end if;

  insert into public.profiles (
    id,
    public_user_code,
    nickname
  )
  values (
    new.id,
    generated_code,
    requested_nickname
  );

  insert into public.user_settings (
    user_id,
    reminder_timezone
  )
  values (
    new.id,
    requested_timezone
  );

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

revoke all on function public.handle_new_auth_user() from public;

create or replace function public.record_user_consent(
  requested_document_type public.consent_document_enum,
  requested_document_version text
)
returns public.user_consents
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.user_consents;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if char_length(btrim(requested_document_version)) not between 1 and 100 then
    raise exception 'Invalid document version';
  end if;

  insert into public.user_consents (
    user_id,
    document_type,
    document_version
  )
  values (
    auth.uid(),
    requested_document_type,
    btrim(requested_document_version)
  )
  on conflict (user_id, document_type, document_version)
  do update set withdrawn_at = null
  returning * into result;

  return result;
end;
$$;

create or replace function public.save_onboarding_profile(
  requested_questionnaire_version text,
  requested_answers jsonb,
  requested_status public.onboarding_status_enum
)
returns public.onboarding_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  result public.onboarding_profiles;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if requested_status not in ('in_progress', 'completed', 'skipped') then
    raise exception 'Invalid onboarding status';
  end if;

  if char_length(btrim(requested_questionnaire_version)) not between 1 and 100 then
    raise exception 'Invalid questionnaire version';
  end if;

  if requested_answers is null or jsonb_typeof(requested_answers) <> 'object' then
    raise exception 'Answers must be a JSON object';
  end if;

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    completed_at,
    skipped_at
  )
  values (
    current_user_id,
    btrim(requested_questionnaire_version),
    requested_answers,
    case when requested_status = 'completed' then now() else null end,
    case when requested_status = 'skipped' then now() else null end
  )
  on conflict (user_id) do update
  set questionnaire_version = excluded.questionnaire_version,
      answers = excluded.answers,
      completed_at = excluded.completed_at,
      skipped_at = excluded.skipped_at
  returning * into result;

  update public.profiles
  set onboarding_status = requested_status
  where id = current_user_id;

  return result;
end;
$$;

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.user_consents enable row level security;
alter table public.onboarding_profiles enable row level security;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy user_settings_select_own
on public.user_settings
for select
to authenticated
using (user_id = auth.uid());

create policy user_settings_update_own
on public.user_settings
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy user_consents_select_own
on public.user_consents
for select
to authenticated
using (user_id = auth.uid());

create policy onboarding_profiles_select_own
on public.onboarding_profiles
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.profiles from anon, authenticated;
revoke all on public.user_settings from anon, authenticated;
revoke all on public.user_consents from anon, authenticated;
revoke all on public.onboarding_profiles from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (nickname, avatar_path) on public.profiles to authenticated;

grant select on public.user_settings to authenticated;
grant update (
  learning_reminder_enabled,
  streak_reminder_enabled,
  reminder_timezone,
  sound_enabled,
  haptics_enabled
) on public.user_settings to authenticated;

grant select on public.user_consents to authenticated;
grant select on public.onboarding_profiles to authenticated;

revoke all on function public.record_user_consent(
  public.consent_document_enum,
  text
) from public;
grant execute on function public.record_user_consent(
  public.consent_document_enum,
  text
) to authenticated;

revoke all on function public.save_onboarding_profile(
  text,
  jsonb,
  public.onboarding_status_enum
) from public;
grant execute on function public.save_onboarding_profile(
  text,
  jsonb,
  public.onboarding_status_enum
) to authenticated;

commit;
