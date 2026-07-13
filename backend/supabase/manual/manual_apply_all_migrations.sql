-- Generated manual migration bundle.
-- Paste this whole file into Supabase SQL Editor only after confirming the target public schema is empty.
-- Source folder: backend/supabase/migrations

-- ============================================================================
-- Migration: 202606210001_create_user_foundation.sql
-- ============================================================================

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


-- ============================================================================
-- Migration: 202606210002_add_profile_username.sql
-- ============================================================================

-- Adds a unique public username used during email/password registration.
-- Run this after 202606210001_create_user_foundation.sql.

begin;

alter table public.profiles
  add column username text;

update public.profiles
set username = lower(public_user_code)
where username is null;

alter table public.profiles
  alter column username set not null;

alter table public.profiles
  add constraint profiles_username_format
  check (username ~ '^[a-z][a-z0-9_]{2,23}$');

create unique index profiles_username_lower_unique
  on public.profiles (lower(username));

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_code text;
  requested_username text;
  requested_nickname text;
  requested_timezone text;
begin
  generated_code :=
    'KQ' || nextval('public.public_user_code_seq'::regclass)::text;

  requested_username :=
    lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  if requested_username !~ '^[a-z][a-z0-9_]{2,23}$' then
    raise exception 'Invalid username';
  end if;

  requested_nickname :=
    btrim(coalesce(new.raw_user_meta_data ->> 'nickname', requested_username));
  if char_length(requested_nickname) not between 1 and 36
     or requested_nickname ~ '[@<>/]' then
    requested_nickname := requested_username;
  end if;

  requested_timezone :=
    btrim(coalesce(new.raw_user_meta_data ->> 'timezone', ''));
  if char_length(requested_timezone) not between 1 and 100 then
    requested_timezone := 'UTC';
  end if;

  insert into public.profiles (
    id,
    public_user_code,
    username,
    nickname
  )
  values (
    new.id,
    generated_code,
    requested_username,
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

  insert into public.user_consents (
    user_id,
    document_type,
    document_version
  )
  values
    (
      new.id,
      'terms',
      coalesce(new.raw_user_meta_data ->> 'terms_version', '2026-06-01')
    ),
    (
      new.id,
      'privacy',
      coalesce(new.raw_user_meta_data ->> 'privacy_version', '2026-06-01')
    );

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

comment on column public.profiles.username is
  'Unique case-insensitive public username. Authentication still uses email/password.';

commit;


-- ============================================================================
-- Migration: 202606210003_create_ielts_vocabulary_schema.sql
-- ============================================================================

-- Normalized IELTS vocabulary, curriculum, question, and sense-level progress schema.
-- Additive migration: preserves legacy words/questions columns used by the Android app.

begin;

create extension if not exists pgcrypto;

do $$
begin
  create type public.vocabulary_role_enum as enum (
    'foundation',
    'general_ielts',
    'topic_recognition'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.placement_type_enum as enum ('new', 'review');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.content_review_status_enum as enum (
    'pending',
    'approved',
    'rejected'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.lexical_relation_type_enum as enum (
    'synonym',
    'antonym',
    'confusable',
    'related'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.learning_skill_enum as enum (
    'spelling',
    'meaning',
    'synonym',
    'antonym',
    'listening',
    'speaking',
    'reading',
    'writing',
    'multiple_choice'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.example_origin_enum as enum (
    'sourced_reusable',
    'sourced_private_study',
    'ai_generated_from_sources',
    'human_written',
    'legacy'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.session_type_enum as enum (
    'daily',
    'mistake_review',
    'assessment',
    'challenge'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.session_status_enum as enum (
    'started',
    'completed',
    'abandoned'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.question_category as enum (
    'new_word',
    'listening',
    'speaking',
    'reading',
    'writing'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.answer_form as enum ('option', 'keyboard', 'voice');
exception when duplicate_object then null;
end $$;

-- Curriculum -----------------------------------------------------------------

create table if not exists public.bands (
  id                  smallint primary key,
  band_score          numeric(2,1) not null unique,
  display_name        text not null,
  sort_order          smallint not null unique,
  curriculum_version  integer not null default 1,
  created_at          timestamptz not null default now(),

  constraint bands_score_range check (band_score between 4.0 and 8.0),
  constraint bands_score_half_step check ((band_score * 2) = trunc(band_score * 2)),
  constraint bands_display_name_not_blank check (char_length(btrim(display_name)) > 0),
  constraint bands_curriculum_version_positive check (curriculum_version > 0)
);

insert into public.bands (id, band_score, display_name, sort_order)
values
  (1, 4.0, 'IELTS 4.0', 1),
  (2, 4.5, 'IELTS 4.5', 2),
  (3, 5.0, 'IELTS 5.0', 3),
  (4, 5.5, 'IELTS 5.5', 4),
  (5, 6.0, 'IELTS 6.0', 5),
  (6, 6.5, 'IELTS 6.5', 6),
  (7, 7.0, 'IELTS 7.0', 7),
  (8, 7.5, 'IELTS 7.5', 8),
  (9, 8.0, 'IELTS 8.0', 9)
on conflict (id) do update
set band_score = excluded.band_score,
    display_name = excluded.display_name,
    sort_order = excluded.sort_order;

create table if not exists public.topic_clusters (
  id                        text primary key,
  topic                     text not null,
  subtopic                  text not null,
  paper_types               text[] not null default '{}',
  band_min                  numeric(2,1) not null,
  band_max                  numeric(2,1) not null,
  word_goal                 integer not null,
  candidate_goal            integer not null,
  chinese_learner_priority  text,
  curriculum_version        integer not null default 1,
  human_review              boolean not null default true,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint topic_clusters_id_format check (id ~ '^[a-z0-9_]+$'),
  constraint topic_clusters_topic_not_blank check (char_length(btrim(topic)) > 0),
  constraint topic_clusters_subtopic_not_blank check (char_length(btrim(subtopic)) > 0),
  constraint topic_clusters_band_order check (band_min <= band_max),
  constraint topic_clusters_band_range check (band_min >= 4.0 and band_max <= 8.0),
  constraint topic_clusters_goals_positive check (
    word_goal > 0 and candidate_goal >= word_goal
  ),
  constraint topic_clusters_priority_valid check (
    chinese_learner_priority is null
    or chinese_learner_priority in ('low', 'medium', 'high')
  )
);

create table if not exists public.levels (
  level_number        integer primary key,
  band_id             smallint references public.bands(id),
  topic_cluster_id    text references public.topic_clusters(id),
  title               text,
  order_in_band       integer,
  new_sense_target    integer not null default 45,
  collocation_target  integer not null default 5,
  review_target       integer not null default 30,
  curriculum_version  integer not null default 1,
  human_review        boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint levels_number_range check (level_number between 1 and 240),
  constraint levels_targets_non_negative check (
    new_sense_target >= 0
    and collocation_target >= 0
    and review_target >= 0
  ),
  constraint levels_target_total check (
    new_sense_target + collocation_target + review_target = 80
  )
);

-- Add normalized columns when a legacy levels table already exists.
alter table public.levels
  add column if not exists band_id smallint references public.bands(id),
  add column if not exists topic_cluster_id text references public.topic_clusters(id),
  add column if not exists title text,
  add column if not exists new_sense_target integer not null default 45,
  add column if not exists collocation_target integer not null default 5,
  add column if not exists review_target integer not null default 30,
  add column if not exists curriculum_version integer not null default 1,
  add column if not exists human_review boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Legacy curriculum labels are retained for compatibility, but normalized
-- inserts must not be forced to populate them.
do $$
declare
  legacy_column text;
begin
  foreach legacy_column in array array['ielts_band', 'band_name', 'title_name']
  loop
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'levels'
        and column_name = legacy_column
        and is_nullable = 'NO'
    ) then
      execute format(
        'alter table public.levels alter column %I drop not null',
        legacy_column
      );
    end if;
  end loop;
end $$;

insert into public.levels (
  level_number,
  band_id,
  title,
  order_in_band,
  new_sense_target,
  collocation_target,
  review_target
)
select
  n,
  case
    when n <= 54 then 1
    when n <= 81 then 2
    when n <= 99 then 3
    when n <= 126 then 4
    when n <= 144 then 5
    when n <= 162 then 6
    when n <= 180 then 7
    when n <= 210 then 8
    else 9
  end,
  'Level ' || n,
  n - case
    when n <= 54 then 0
    when n <= 81 then 54
    when n <= 99 then 81
    when n <= 126 then 99
    when n <= 144 then 126
    when n <= 162 then 144
    when n <= 180 then 162
    when n <= 210 then 180
    else 210
  end,
  case when n <= 99 then 45 when n <= 162 then 50 else 55 end,
  case when n <= 99 then 5 when n <= 162 then 10 else 15 end,
  case when n <= 99 then 30 when n <= 162 then 20 else 10 end
from generate_series(1, 240) as n
on conflict (level_number) do update
set band_id = excluded.band_id,
    title = coalesce(public.levels.title, excluded.title),
    order_in_band = coalesce(public.levels.order_in_band, excluded.order_in_band),
    new_sense_target = excluded.new_sense_target,
    collocation_target = excluded.collocation_target,
    review_target = excluded.review_target;

alter table public.levels alter column band_id set not null;
alter table public.levels alter column title set not null;
alter table public.levels alter column order_in_band set not null;

-- Dictionary/content ----------------------------------------------------------

create table if not exists public.content_sources (
  id                uuid primary key default gen_random_uuid(),
  source_key        text not null unique,
  name              text not null,
  source_url        text,
  license_name      text,
  copyright_status  text not null default 'unknown',
  attribution_text  text,
  notes             text,
  human_review      boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint content_sources_key_format check (source_key ~ '^[a-z0-9_]+$'),
  constraint content_sources_name_not_blank check (char_length(btrim(name)) > 0),
  constraint content_sources_copyright_valid check (
    copyright_status in (
      'public_domain',
      'cc0',
      'cc_by',
      'cc_by_sa',
      'licensed',
      'private_study_only',
      'unknown'
    )
  )
);

create table if not exists public.words (
  id               uuid primary key default gen_random_uuid(),
  headword         text not null,
  display_spelling text not null,
  frequency_rank   integer,
  human_review     boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint words_headword_not_blank check (char_length(btrim(headword)) > 0),
  constraint words_display_spelling_not_blank check (
    char_length(btrim(display_spelling)) > 0
  ),
  constraint words_frequency_positive check (
    frequency_rank is null or frequency_rank > 0
  )
);

alter table public.words
  add column if not exists display_spelling text,
  add column if not exists frequency_rank integer,
  add column if not exists human_review boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.words
set display_spelling = headword
where display_spelling is null;

alter table public.words alter column display_spelling set not null;

-- Legacy content columns remain readable by the current app. They are no
-- longer mandatory because normalized inserts only require the headword.
do $$
declare
  legacy_column text;
begin
  foreach legacy_column in array array[
    'level_number',
    'phonetic',
    'pronunciation_path',
    'mnemonic',
    'pos_primary'
  ]
  loop
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'words'
        and column_name = legacy_column
        and is_nullable = 'NO'
    ) then
      execute format(
        'alter table public.words alter column %I drop not null',
        legacy_column
      );
    end if;
  end loop;
end $$;

create unique index if not exists words_headword_lower_unique
  on public.words (lower(headword));

create table if not exists public.word_senses (
  id                uuid primary key default gen_random_uuid(),
  word_id           uuid not null references public.words(id) on delete cascade,
  part_of_speech    text not null,
  sense_number      integer not null,
  definition_en     text not null,
  definition_zh     text not null,
  vocabulary_role   public.vocabulary_role_enum not null,
  difficulty_band   numeric(2,1) references public.bands(band_score),
  cefr_level        text,
  register          text,
  is_primary        boolean not null default false,
  source_id         uuid references public.content_sources(id),
  human_review      boolean not null default true,
  review_status     public.content_review_status_enum not null default 'pending',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint word_senses_pos_not_blank check (
    char_length(btrim(part_of_speech)) > 0
  ),
  constraint word_senses_number_positive check (sense_number > 0),
  constraint word_senses_definition_en_not_blank check (
    char_length(btrim(definition_en)) > 0
  ),
  constraint word_senses_definition_zh_not_blank check (
    char_length(btrim(definition_zh)) > 0
  ),
  constraint word_senses_cefr_valid check (
    cefr_level is null or cefr_level in ('A1', 'A2', 'B1', 'B2', 'C1', 'C2')
  ),
  unique (word_id, part_of_speech, sense_number)
);

create unique index if not exists word_senses_one_primary_per_word_pos
  on public.word_senses (word_id, part_of_speech)
  where is_primary;

create table if not exists public.level_sense_assignments (
  level_number     integer not null references public.levels(level_number) on delete cascade,
  sense_id         uuid not null references public.word_senses(id) on delete cascade,
  placement_type   public.placement_type_enum not null,
  order_in_level   integer not null,
  vocabulary_role public.vocabulary_role_enum not null,
  is_required      boolean not null default true,
  human_review     boolean not null default true,
  created_at       timestamptz not null default now(),

  primary key (level_number, sense_id, placement_type),
  constraint level_sense_assignment_order_positive check (order_in_level > 0),
  unique (level_number, placement_type, order_in_level)
);

create unique index if not exists one_new_assignment_per_sense
  on public.level_sense_assignments (sense_id)
  where placement_type = 'new';

create table if not exists public.word_forms (
  id            uuid primary key default gen_random_uuid(),
  word_id       uuid not null references public.words(id) on delete cascade,
  sense_id      uuid references public.word_senses(id) on delete cascade,
  form_type     text not null,
  form_text     text not null,
  source_id     uuid references public.content_sources(id),
  human_review  boolean not null default true,
  created_at    timestamptz not null default now(),

  constraint word_forms_type_not_blank check (char_length(btrim(form_type)) > 0),
  constraint word_forms_text_not_blank check (char_length(btrim(form_text)) > 0),
  unique (word_id, sense_id, form_type, form_text)
);

alter table public.word_forms
  add column if not exists sense_id uuid references public.word_senses(id) on delete cascade,
  add column if not exists form_type text,
  add column if not exists human_review boolean not null default true,
  add column if not exists source_id uuid references public.content_sources(id),
  add column if not exists created_at timestamptz not null default now();

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'word_forms' and column_name = 'form_label'
  ) then
    execute 'update public.word_forms set form_type = form_label where form_type is null';
    execute 'alter table public.word_forms alter column form_label drop not null';
  end if;
end $$;

alter table public.word_forms alter column form_type set not null;

create table if not exists public.pronunciations (
  id            uuid primary key default gen_random_uuid(),
  word_id       uuid not null references public.words(id) on delete cascade,
  sense_id      uuid references public.word_senses(id) on delete cascade,
  ipa_us        text not null,
  audio_path    text,
  source_id     uuid references public.content_sources(id),
  human_review  boolean not null default true,
  created_at    timestamptz not null default now(),

  constraint pronunciations_ipa_not_blank check (char_length(btrim(ipa_us)) > 0)
);

create table if not exists public.examples (
  id                uuid primary key default gen_random_uuid(),
  sense_id          uuid references public.word_senses(id) on delete cascade,
  sentence_en       text not null,
  translation_zh    text not null,
  target_span       text not null,
  origin            public.example_origin_enum not null default 'human_written',
  difficulty_band   numeric(2,1) references public.bands(band_score),
  source_id         uuid references public.content_sources(id),
  review_status     public.content_review_status_enum not null default 'pending',
  human_review      boolean not null default true,
  audio_path        text,
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint examples_sentence_not_blank check (char_length(btrim(sentence_en)) > 0),
  constraint examples_translation_not_blank check (
    char_length(btrim(translation_zh)) > 0
  ),
  constraint examples_target_not_blank check (char_length(btrim(target_span)) > 0),
  constraint examples_target_present check (
    position(lower(target_span) in lower(sentence_en)) > 0
  ),
  constraint examples_sense_required_for_new_content check (
    sense_id is not null or origin = 'legacy'
  )
);

alter table public.examples
  add column if not exists sense_id uuid references public.word_senses(id) on delete cascade,
  add column if not exists origin public.example_origin_enum,
  add column if not exists difficulty_band numeric(2,1) references public.bands(band_score),
  add column if not exists source_id uuid references public.content_sources(id),
  add column if not exists review_status public.content_review_status_enum not null default 'pending',
  add column if not exists human_review boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.examples
set origin = 'legacy'
where origin is null;

alter table public.examples alter column origin set not null;
alter table public.examples alter column origin set default 'human_written';

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'examples'
      and column_name = 'word_id'
      and is_nullable = 'NO'
  ) then
    execute 'alter table public.examples alter column word_id drop not null';
  end if;
end $$;

create table if not exists public.collocations (
  id                uuid primary key default gen_random_uuid(),
  sense_id          uuid not null references public.word_senses(id) on delete cascade,
  collocation       text not null,
  translation_zh    text,
  difficulty_band   numeric(2,1) references public.bands(band_score),
  source_id         uuid references public.content_sources(id),
  human_review      boolean not null default true,
  review_status     public.content_review_status_enum not null default 'pending',
  created_at        timestamptz not null default now(),

  constraint collocations_text_not_blank check (
    char_length(btrim(collocation)) > 0
  ),
  unique (sense_id, collocation)
);

create table if not exists public.lexical_relations (
  id                uuid primary key default gen_random_uuid(),
  source_sense_id   uuid not null references public.word_senses(id) on delete cascade,
  target_sense_id   uuid not null references public.word_senses(id) on delete cascade,
  relation_type     public.lexical_relation_type_enum not null,
  strength          numeric(3,2),
  source_id         uuid references public.content_sources(id),
  human_review      boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint lexical_relations_not_self check (source_sense_id <> target_sense_id),
  constraint lexical_relations_strength_range check (
    strength is null or strength between 0 and 1
  ),
  unique (source_sense_id, target_sense_id, relation_type)
);

create table if not exists public.usage_evidence (
  id                uuid primary key default gen_random_uuid(),
  sense_id          uuid not null references public.word_senses(id) on delete cascade,
  source_id         uuid not null references public.content_sources(id),
  quoted_text       text not null,
  matched_span      text,
  source_locator    text,
  usage_analysis    text,
  paper_types       text[] not null default '{}',
  copyright_status  text not null default 'unknown',
  human_review      boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint usage_evidence_quote_not_blank check (
    char_length(btrim(quoted_text)) > 0
  ),
  constraint usage_evidence_copyright_valid check (
    copyright_status in (
      'public_domain',
      'cc0',
      'cc_by',
      'cc_by_sa',
      'licensed',
      'private_study_only',
      'unknown'
    )
  )
);

-- Questions ------------------------------------------------------------------

create table if not exists public.question_types (
  type_code    integer primary key,
  category     public.question_category not null,
  name         text,
  name_zh      text not null,
  answer_form  public.answer_form not null,
  skill_type   public.learning_skill_enum,
  notes        text,

  constraint question_types_name_not_blank check (char_length(btrim(name_zh)) > 0)
);

alter table public.question_types
  add column if not exists category public.question_category,
  add column if not exists name text,
  add column if not exists name_zh text,
  add column if not exists answer_form public.answer_form,
  add column if not exists skill_type public.learning_skill_enum,
  add column if not exists notes text;

insert into public.question_types (
  type_code,
  category,
  name,
  name_zh,
  answer_form,
  skill_type,
  notes
)
values
  (1, 'new_word', 'initial_letter_fill', '首字母填空', 'keyboard', 'spelling', 'Example sentence with target blank'),
  (2, 'new_word', 'word_choice', '单词选择', 'option', 'multiple_choice', 'Example sentence with distractors'),
  (3, 'listening', 'listening_choice', '听力选择', 'option', 'listening', 'Audio recognition'),
  (4, 'listening', 'listening_fill', '听力填空', 'keyboard', 'listening', 'Audio spelling'),
  (5, 'listening', 'listening_comprehension', '听力理解', 'option', 'listening', 'Audio comprehension'),
  (6, 'speaking', 'guided_repeat', '选择并复述', 'voice', 'speaking', 'Guided production'),
  (7, 'speaking', 'open_speaking', '理解并口述', 'voice', 'speaking', 'Open production'),
  (8, 'speaking', 'sentence_repeat', '填空并复述', 'voice', 'speaking', 'Sentence production'),
  (9, 'reading', 'definition_choice', '英文释义选择', 'option', 'meaning', 'Definition recognition'),
  (10, 'reading', 'word_form', '词形变化', 'keyboard', 'reading', 'Inflected form'),
  (11, 'reading', 'synonym_choice', '同义词选择', 'option', 'synonym', 'Generated from lexical relations'),
  (12, 'reading', 'antonym_choice', '反义词选择', 'option', 'antonym', 'Generated from lexical relations'),
  (13, 'reading', 'reading_comprehension', '阅读理解', 'option', 'reading', 'Context comprehension'),
  (14, 'writing', 'translation_fill', '翻译补全', 'keyboard', 'writing', 'Chinese-to-English production')
on conflict (type_code) do update
set category = excluded.category,
    name = excluded.name,
    name_zh = excluded.name_zh,
    answer_form = excluded.answer_form,
    skill_type = excluded.skill_type,
    notes = excluded.notes;

create table if not exists public.questions (
  id                  uuid primary key default gen_random_uuid(),
  sense_id            uuid references public.word_senses(id),
  question_type_id    integer references public.question_types(type_code),
  type_code           integer references public.question_types(type_code),
  category            public.question_category,
  answer_form         public.answer_form,
  word_id             uuid references public.words(id),
  example_id          uuid references public.examples(id),
  stem                text not null,
  correct_answer      text not null,
  difficulty          numeric(2,1),
  is_active           boolean not null default true,
  generation_version  text not null default 'v1',
  human_review        boolean not null default true,
  prompt_hint         text not null default '',
  translation_zh      text not null default '',
  expected_time_ms    integer not null default 20000,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint questions_stem_not_blank check (char_length(btrim(stem)) > 0),
  constraint questions_answer_not_blank check (char_length(btrim(correct_answer)) > 0),
  constraint questions_time_positive check (expected_time_ms > 0),
  constraint questions_type_consistent check (
    question_type_id is null
    or type_code is null
    or question_type_id = type_code
  ),
  constraint questions_sense_required_for_new_content check (
    sense_id is not null or generation_version = 'legacy'
  )
);

alter table public.questions
  add column if not exists sense_id uuid references public.word_senses(id),
  add column if not exists question_type_id integer references public.question_types(type_code),
  add column if not exists category public.question_category,
  add column if not exists answer_form public.answer_form,
  add column if not exists word_id uuid references public.words(id),
  add column if not exists example_id uuid references public.examples(id),
  add column if not exists difficulty numeric(2,1),
  add column if not exists generation_version text not null default 'legacy',
  add column if not exists human_review boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

update public.questions
set question_type_id = type_code
where question_type_id is null and type_code is not null;

alter table public.questions
  alter column generation_version set default 'v1';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.questions'::regclass
      and conname = 'questions_type_required'
  ) then
    alter table public.questions
      add constraint questions_type_required
      check (question_type_id is not null or type_code is not null);
  end if;
end $$;

create or replace function public.sync_question_type_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.question_type_id is null then
    new.question_type_id := new.type_code;
  elsif new.type_code is null then
    new.type_code := new.question_type_id;
  elsif new.question_type_id <> new.type_code then
    raise exception 'question_type_id and type_code must match';
  end if;
  return new;
end;
$$;

drop trigger if exists questions_sync_type_columns on public.questions;
create trigger questions_sync_type_columns
before insert or update of question_type_id, type_code on public.questions
for each row execute function public.sync_question_type_columns();

create table if not exists public.question_options (
  id               uuid primary key default gen_random_uuid(),
  question_id      uuid not null references public.questions(id) on delete cascade,
  option_text      text not null,
  target_sense_id  uuid references public.word_senses(id),
  is_correct       boolean not null default false,
  sort_order       integer not null default 0,
  human_review     boolean not null default true,

  constraint question_options_text_not_blank check (
    char_length(btrim(option_text)) > 0
  ),
  unique (question_id, sort_order)
);

alter table public.question_options
  add column if not exists target_sense_id uuid references public.word_senses(id),
  add column if not exists human_review boolean not null default true;

-- User learning data ----------------------------------------------------------

create table if not exists public.user_level_progress (
  user_id                  uuid not null references public.profiles(id) on delete cascade,
  level_number             integer not null references public.levels(level_number),
  is_unlocked              boolean not null default false,
  is_completed             boolean not null default false,
  progress                 numeric(5,4) not null default 0,
  best_star_rating         smallint not null default 0,
  completed_session_count  integer not null default 0,
  unlocked_at              timestamptz,
  completed_at             timestamptz,
  updated_at               timestamptz not null default now(),

  primary key (user_id, level_number),
  constraint user_level_progress_range check (progress between 0 and 1),
  constraint user_level_stars_range check (best_star_rating between 0 and 3),
  constraint user_level_sessions_non_negative check (completed_session_count >= 0)
);

create table if not exists public.practice_sessions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles(id) on delete cascade,
  level_number       integer references public.levels(level_number),
  session_type       public.session_type_enum not null default 'daily',
  status             public.session_status_enum not null default 'started',
  started_at         timestamptz not null default now(),
  completed_at       timestamptz,
  correct_count      integer not null default 0,
  total_count        integer not null default 0,
  star_rating        smallint not null default 0,
  base_power         integer not null default 0,
  combo_bonus        integer not null default 0,
  speed_bonus        integer not null default 0,
  duck_power_earned  integer not null default 0,

  constraint practice_sessions_counts_valid check (
    correct_count >= 0 and total_count >= 0 and correct_count <= total_count
  ),
  constraint practice_sessions_stars_valid check (star_rating between 0 and 3),
  constraint practice_sessions_rewards_non_negative check (
    base_power >= 0
    and combo_bonus >= 0
    and speed_bonus >= 0
    and duck_power_earned >= 0
  ),
  constraint practice_sessions_completion_order check (
    completed_at is null or completed_at >= started_at
  )
);

create table if not exists public.practice_answers (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  session_id        uuid not null references public.practice_sessions(id) on delete cascade,
  question_id       uuid not null references public.questions(id),
  sense_id          uuid not null references public.word_senses(id),
  skill_type        public.learning_skill_enum not null,
  answer_given      text,
  is_correct        boolean not null,
  response_time_ms  integer not null,
  answered_at       timestamptz not null default now(),

  constraint practice_answers_time_non_negative check (response_time_ms >= 0),
  unique (session_id, question_id)
);

create table if not exists public.user_sense_mastery (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  sense_id      uuid not null references public.word_senses(id) on delete cascade,
  seen_count    integer not null default 0,
  correct_count integer not null default 0,
  mastery_score numeric(5,4) not null default 0,
  review_stage  smallint not null default 0,
  last_seen_at  timestamptz,
  next_due_at   timestamptz,
  mastered_at   timestamptz,
  updated_at    timestamptz not null default now(),

  primary key (user_id, sense_id),
  constraint user_sense_counts_valid check (
    seen_count >= 0 and correct_count >= 0 and correct_count <= seen_count
  ),
  constraint user_sense_mastery_range check (mastery_score between 0 and 1),
  constraint user_sense_review_stage_range check (review_stage between 0 and 5)
);

create table if not exists public.user_sense_skill_progress (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  sense_id        uuid not null references public.word_senses(id) on delete cascade,
  skill_type      public.learning_skill_enum not null,
  attempt_count   integer not null default 0,
  correct_count   integer not null default 0,
  last_attempt_at timestamptz,
  mastery_score   numeric(5,4) not null default 0,
  updated_at      timestamptz not null default now(),

  primary key (user_id, sense_id, skill_type),
  constraint user_skill_counts_valid check (
    attempt_count >= 0 and correct_count >= 0 and correct_count <= attempt_count
  ),
  constraint user_skill_mastery_range check (mastery_score between 0 and 1)
);

create table if not exists public.mistake_senses (
  user_id              uuid not null references public.profiles(id) on delete cascade,
  sense_id             uuid not null references public.word_senses(id) on delete cascade,
  wrong_count          integer not null default 1,
  correct_review_count integer not null default 0,
  review_stage         smallint not null default 0,
  last_wrong_at        timestamptz not null default now(),
  last_reviewed_at     timestamptz,
  next_due_at          timestamptz,
  mastered_at          timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  primary key (user_id, sense_id),
  constraint mistake_senses_counts_valid check (
    wrong_count > 0 and correct_review_count >= 0
  ),
  constraint mistake_senses_review_stage_range check (review_stage between 0 and 5)
);

-- Derived validation and progress views --------------------------------------

create or replace view public.content_validation_issues
with (security_invoker = true)
as
select
  'topic_recognition_missing_evidence'::text as issue_type,
  ws.id as record_id,
  w.headword,
  'Topic-recognition sense requires approved IELTS Reading/Listening evidence.'::text
    as issue_message
from public.word_senses ws
join public.words w on w.id = ws.word_id
where ws.vocabulary_role = 'topic_recognition'
  and not exists (
    select 1
    from public.usage_evidence ue
    where ue.sense_id = ws.id
      and ue.human_review = false
      and (
        'Reading' = any(ue.paper_types)
        or 'Listening' = any(ue.paper_types)
      )
  )
union all
select
  'approved_content_still_flagged'::text,
  ws.id,
  w.headword,
  'Approved sense still has human_review=true.'::text
from public.word_senses ws
join public.words w on w.id = ws.word_id
where ws.review_status = 'approved' and ws.human_review;

create or replace view public.user_band_summary
with (security_invoker = true)
as
with sense_band as (
  select
    lsa.sense_id,
    min(l.band_id) as band_id
  from public.level_sense_assignments lsa
  join public.levels l on l.level_number = lsa.level_number
  where lsa.placement_type = 'new'
  group by lsa.sense_id
),
introduced as (
  select
    ulp.user_id,
    l.band_id,
    count(distinct lsa.sense_id) as introduced_sense_count
  from public.user_level_progress ulp
  join public.levels l on l.level_number = ulp.level_number
  join public.level_sense_assignments lsa
    on lsa.level_number = ulp.level_number
   and lsa.placement_type = 'new'
  where ulp.is_unlocked
  group by ulp.user_id, l.band_id
),
mastered as (
  select
    usm.user_id,
    sb.band_id,
    count(*) filter (where usm.mastered_at is not null) as mastered_sense_count
  from public.user_sense_mastery usm
  join sense_band sb on sb.sense_id = usm.sense_id
  group by usm.user_id, sb.band_id
),
answers as (
  select
    pa.user_id,
    sb.band_id,
    count(*) as overall_attempt_count,
    count(*) filter (where pa.is_correct) as overall_correct_count,
    count(*) filter (where pa.skill_type = 'reading') as reading_attempt_count,
    count(*) filter (
      where pa.skill_type = 'reading' and pa.is_correct
    ) as reading_correct_count,
    count(*) filter (where pa.skill_type = 'writing') as writing_attempt_count,
    count(*) filter (
      where pa.skill_type = 'writing' and pa.is_correct
    ) as writing_correct_count,
    count(*) filter (where pa.skill_type = 'spelling') as spelling_attempt_count,
    count(*) filter (
      where pa.skill_type = 'spelling' and pa.is_correct
    ) as spelling_correct_count,
    count(*) filter (
      where pa.skill_type = 'multiple_choice'
    ) as multiple_choice_attempt_count,
    count(*) filter (
      where pa.skill_type = 'multiple_choice' and pa.is_correct
    ) as multiple_choice_correct_count
  from public.practice_answers pa
  join sense_band sb on sb.sense_id = pa.sense_id
  group by pa.user_id, sb.band_id
)
select
  p.id as user_id,
  b.id as band_id,
  b.band_score,
  coalesce(i.introduced_sense_count, 0) as introduced_sense_count,
  coalesce(m.mastered_sense_count, 0) as mastered_sense_count,
  case when coalesce(a.reading_attempt_count, 0) = 0 then null
    else a.reading_correct_count::numeric / a.reading_attempt_count end
    as reading_accuracy,
  case when coalesce(a.writing_attempt_count, 0) = 0 then null
    else a.writing_correct_count::numeric / a.writing_attempt_count end
    as writing_accuracy,
  case when coalesce(a.spelling_attempt_count, 0) = 0 then null
    else a.spelling_correct_count::numeric / a.spelling_attempt_count end
    as spelling_accuracy,
  case when coalesce(a.multiple_choice_attempt_count, 0) = 0 then null
    else a.multiple_choice_correct_count::numeric
      / a.multiple_choice_attempt_count end
    as multiple_choice_accuracy,
  coalesce(a.overall_correct_count, 0) as overall_correct_count,
  coalesce(a.overall_attempt_count, 0) as overall_attempt_count,
  case when coalesce(a.overall_attempt_count, 0) = 0 then null
    else a.overall_correct_count::numeric / a.overall_attempt_count end
    as overall_accuracy
from public.profiles p
cross join public.bands b
left join introduced i on i.user_id = p.id and i.band_id = b.id
left join mastered m on m.user_id = p.id and m.band_id = b.id
left join answers a on a.user_id = p.id and a.band_id = b.id;

-- Timestamps -----------------------------------------------------------------

drop trigger if exists topic_clusters_set_updated_at on public.topic_clusters;
create trigger topic_clusters_set_updated_at
before update on public.topic_clusters
for each row execute function public.set_updated_at();

drop trigger if exists levels_set_updated_at on public.levels;
create trigger levels_set_updated_at
before update on public.levels
for each row execute function public.set_updated_at();

drop trigger if exists content_sources_set_updated_at on public.content_sources;
create trigger content_sources_set_updated_at
before update on public.content_sources
for each row execute function public.set_updated_at();

drop trigger if exists words_set_updated_at on public.words;
create trigger words_set_updated_at
before update on public.words
for each row execute function public.set_updated_at();

drop trigger if exists word_senses_set_updated_at on public.word_senses;
create trigger word_senses_set_updated_at
before update on public.word_senses
for each row execute function public.set_updated_at();

drop trigger if exists examples_set_updated_at on public.examples;
create trigger examples_set_updated_at
before update on public.examples
for each row execute function public.set_updated_at();

drop trigger if exists questions_set_updated_at on public.questions;
create trigger questions_set_updated_at
before update on public.questions
for each row execute function public.set_updated_at();

drop trigger if exists user_level_progress_set_updated_at on public.user_level_progress;
create trigger user_level_progress_set_updated_at
before update on public.user_level_progress
for each row execute function public.set_updated_at();

drop trigger if exists user_sense_mastery_set_updated_at on public.user_sense_mastery;
create trigger user_sense_mastery_set_updated_at
before update on public.user_sense_mastery
for each row execute function public.set_updated_at();

drop trigger if exists user_sense_skill_progress_set_updated_at on public.user_sense_skill_progress;
create trigger user_sense_skill_progress_set_updated_at
before update on public.user_sense_skill_progress
for each row execute function public.set_updated_at();

drop trigger if exists mistake_senses_set_updated_at on public.mistake_senses;
create trigger mistake_senses_set_updated_at
before update on public.mistake_senses
for each row execute function public.set_updated_at();

-- Indexes --------------------------------------------------------------------

create index if not exists word_senses_word_idx
  on public.word_senses (word_id, sense_number);
create index if not exists level_sense_assignments_level_idx
  on public.level_sense_assignments (level_number, placement_type, order_in_level);
create index if not exists examples_sense_idx
  on public.examples (sense_id, sort_order);
create index if not exists collocations_sense_idx
  on public.collocations (sense_id);
create index if not exists usage_evidence_sense_idx
  on public.usage_evidence (sense_id);
create index if not exists questions_sense_active_idx
  on public.questions (sense_id, is_active);
create index if not exists question_options_question_idx
  on public.question_options (question_id, sort_order);
create index if not exists practice_sessions_user_started_idx
  on public.practice_sessions (user_id, started_at desc);
create index if not exists practice_answers_user_answered_idx
  on public.practice_answers (user_id, answered_at desc);
create index if not exists user_sense_mastery_due_idx
  on public.user_sense_mastery (user_id, next_due_at);
create index if not exists mistake_senses_due_idx
  on public.mistake_senses (user_id, mastered_at, next_due_at);

-- RLS and grants --------------------------------------------------------------

alter table public.bands enable row level security;
alter table public.topic_clusters enable row level security;
alter table public.levels enable row level security;
alter table public.content_sources enable row level security;
alter table public.words enable row level security;
alter table public.word_senses enable row level security;
alter table public.level_sense_assignments enable row level security;
alter table public.word_forms enable row level security;
alter table public.pronunciations enable row level security;
alter table public.examples enable row level security;
alter table public.collocations enable row level security;
alter table public.lexical_relations enable row level security;
alter table public.usage_evidence enable row level security;
alter table public.question_types enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;
alter table public.user_level_progress enable row level security;
alter table public.practice_sessions enable row level security;
alter table public.practice_answers enable row level security;
alter table public.user_sense_mastery enable row level security;
alter table public.user_sense_skill_progress enable row level security;
alter table public.mistake_senses enable row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'bands',
    'topic_clusters',
    'levels',
    'content_sources',
    'words',
    'word_senses',
    'level_sense_assignments',
    'word_forms',
    'pronunciations',
    'examples',
    'collocations',
    'lexical_relations',
    'usage_evidence',
    'question_types',
    'questions',
    'question_options'
  ]
  loop
    begin
      execute format(
        'create policy authenticated_read_%I on public.%I for select to authenticated using (true)',
        table_name,
        table_name
      );
    exception when duplicate_object then
      null;
    end;
  end loop;
end $$;

drop policy if exists user_level_progress_own on public.user_level_progress;
create policy user_level_progress_own
on public.user_level_progress for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists practice_sessions_own on public.practice_sessions;
create policy practice_sessions_own
on public.practice_sessions for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists practice_answers_own on public.practice_answers;
create policy practice_answers_own
on public.practice_answers for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists user_sense_mastery_own on public.user_sense_mastery;
create policy user_sense_mastery_own
on public.user_sense_mastery for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists user_sense_skill_progress_own on public.user_sense_skill_progress;
create policy user_sense_skill_progress_own
on public.user_sense_skill_progress for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists mistake_senses_own on public.mistake_senses;
create policy mistake_senses_own
on public.mistake_senses for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select on public.bands,
  public.topic_clusters,
  public.levels,
  public.content_sources,
  public.words,
  public.word_senses,
  public.level_sense_assignments,
  public.word_forms,
  public.pronunciations,
  public.examples,
  public.collocations,
  public.lexical_relations,
  public.usage_evidence,
  public.question_types,
  public.questions,
  public.question_options,
  public.content_validation_issues
to authenticated;

grant select, insert, update, delete on
  public.user_level_progress,
  public.practice_sessions,
  public.practice_answers,
  public.user_sense_mastery,
  public.user_sense_skill_progress,
  public.mistake_senses
to authenticated;

grant select on public.user_band_summary to authenticated;

commit;


-- ============================================================================
-- Migration: 202606210004_meaning_choice_answer_rpc.sql
-- ============================================================================

-- Meaning Choice answer persistence:
--   1. Relax practice_answers.question_id to nullable (dynamic questions have no pre-stored row).
--   2. Add question_type column for finer classification.
--   3. RPC: save one answer + upsert mastery + add mistake if wrong.
--   4. RPC: close session + upsert user_level_progress.

begin;

-- ── 1. Relax question_id ──────────────────────────────────────────────────────
-- Existing UNIQUE (session_id, question_id) stays; PostgreSQL treats NULLs as
-- distinct in unique indexes, so multiple meaning-choice answer rows per session
-- (all with question_id = NULL) are allowed and do not conflict.

alter table public.practice_answers
    alter column question_id drop not null;

-- ── 2. Add question_type ──────────────────────────────────────────────────────
alter table public.practice_answers
    add column if not exists question_type text;

-- ── 3. save_meaning_choice_answer ─────────────────────────────────────────────
-- Lazily finds (or creates) today's practice session for the caller, then saves
-- the answer, upserts user_sense_mastery, and logs a mistake when wrong.

create or replace function public.save_meaning_choice_answer(
    p_level_number       integer,
    p_sense_id           uuid,
    p_selected_sense_id  uuid,
    p_is_correct         boolean,
    p_response_time_ms   integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id    uuid := auth.uid();
    v_session_id uuid;
begin
    -- Find the most recent 'started' session for this user + level today.
    select id into v_session_id
    from public.practice_sessions
    where user_id     = v_user_id
      and level_number = p_level_number
      and status       = 'started'
      and started_at  >= date_trunc('day', now())
    order by started_at desc
    limit 1;

    -- Create one if none exists.
    if v_session_id is null then
        insert into public.practice_sessions (user_id, level_number, session_type, status)
        values (v_user_id, p_level_number, 'daily', 'started')
        returning id into v_session_id;
    end if;

    -- Record the answer (question_id is null for dynamic question types).
    insert into public.practice_answers (
        user_id, session_id, sense_id,
        skill_type, question_type,
        answer_given, is_correct, response_time_ms
    )
    values (
        v_user_id,
        v_session_id,
        p_sense_id,
        'multiple_choice'::public.learning_skill_enum,
        'meaning_choice',
        p_selected_sense_id::text,
        p_is_correct,
        p_response_time_ms
    );

    -- Upsert user_sense_mastery (simple accuracy-based score).
    insert into public.user_sense_mastery
        (user_id, sense_id, seen_count, correct_count, mastery_score, updated_at)
    values (
        v_user_id,
        p_sense_id,
        1,
        case when p_is_correct then 1 else 0 end,
        case when p_is_correct then 0.2 else 0.0 end,
        now()
    )
    on conflict (user_id, sense_id) do update
    set seen_count    = public.user_sense_mastery.seen_count + 1,
        correct_count = public.user_sense_mastery.correct_count
                        + case when p_is_correct then 1 else 0 end,
        mastery_score = least(1.0,
            (public.user_sense_mastery.correct_count
             + case when p_is_correct then 1 else 0 end)::numeric
            / (public.user_sense_mastery.seen_count + 1)),
        updated_at    = now();

    -- Log mistake when wrong.
    if not p_is_correct then
        insert into public.mistake_senses
            (user_id, sense_id, wrong_count, last_wrong_at, created_at, updated_at)
        values (v_user_id, p_sense_id, 1, now(), now(), now())
        on conflict (user_id, sense_id) do update
        set wrong_count   = public.mistake_senses.wrong_count + 1,
            last_wrong_at = now(),
            updated_at    = now();
    end if;
end;
$$;

-- ── 4. complete_meaning_choice_session ────────────────────────────────────────
-- Marks today's session as completed and upserts user_level_progress.

create or replace function public.complete_meaning_choice_session(
    p_level_number      integer,
    p_correct_count     integer,
    p_total_count       integer,
    p_star_rating       smallint,
    p_duck_power_earned integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id    uuid := auth.uid();
    v_session_id uuid;
    v_progress   numeric(5,4);
begin
    select id into v_session_id
    from public.practice_sessions
    where user_id     = v_user_id
      and level_number = p_level_number
      and status       = 'started'
      and started_at  >= date_trunc('day', now())
    order by started_at desc
    limit 1;

    -- Nothing to do if session never started (e.g. all saves failed silently).
    if v_session_id is null then
        return;
    end if;

    update public.practice_sessions
    set status            = 'completed',
        completed_at      = now(),
        correct_count     = p_correct_count,
        total_count       = p_total_count,
        star_rating       = p_star_rating,
        duck_power_earned = p_duck_power_earned,
        base_power        = p_correct_count
                            + case when p_correct_count = p_total_count then 5 else 0 end
    where id = v_session_id;

    v_progress := case when p_total_count > 0
                  then least(1.0, p_correct_count::numeric / p_total_count)
                  else 0.0 end;

    insert into public.user_level_progress
        (user_id, level_number, is_unlocked, is_completed, progress,
         best_star_rating, completed_session_count, unlocked_at)
    values (
        v_user_id,
        p_level_number,
        true,
        p_star_rating >= 3,
        v_progress,
        p_star_rating,
        1,
        now()
    )
    on conflict (user_id, level_number) do update
    set is_completed            = public.user_level_progress.is_completed
                                  or (p_star_rating >= 3),
        progress                = greatest(public.user_level_progress.progress, v_progress),
        best_star_rating        = greatest(public.user_level_progress.best_star_rating, p_star_rating),
        completed_session_count = public.user_level_progress.completed_session_count + 1,
        updated_at              = now();
end;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────
grant execute on function public.save_meaning_choice_answer(
    integer, uuid, uuid, boolean, integer
) to authenticated;

grant execute on function public.complete_meaning_choice_session(
    integer, integer, integer, smallint, integer
) to authenticated;

commit;


-- ============================================================================
-- Migration: 202606220004_questions_import_compatibility.sql
-- ============================================================================

-- Compatibility columns required by both the pilot and normalized question importer.

begin;

alter table public.questions
  add column if not exists category public.question_category,
  add column if not exists answer_form public.answer_form,
  add column if not exists word_id uuid references public.words(id);

update public.questions q
set category = qt.category,
    answer_form = qt.answer_form
from public.question_types qt
where qt.type_code = coalesce(q.question_type_id, q.type_code)
  and (
    q.category is null
    or q.answer_form is null
  );

update public.questions q
set word_id = ws.word_id
from public.word_senses ws
where ws.id = q.sense_id
  and q.word_id is null;

commit;


-- ============================================================================
-- Migration: 202606220005_user_bootstrap_and_onboarding.sql
-- ============================================================================

-- Server-owned authentication bootstrap and resumable onboarding flow.
-- Depends on:
--   202606210001_create_user_foundation.sql
--   202606210002_add_profile_username.sql
--   202606210003_create_ielts_vocabulary_schema.sql

begin;

create type public.onboarding_flow_state_enum as enum (
  'questionnaire_pending',
  'assessment_pending',
  'placement_finalized',
  'home_ready'
);

alter table public.onboarding_profiles
  add column flow_state public.onboarding_flow_state_enum,
  add column current_question_index smallint;

update public.onboarding_profiles op
set flow_state = case
      when p.onboarding_status in ('completed', 'skipped') then 'home_ready'
      when op.answers ?& array[
        'occupation',
        'ielts_reason',
        'self_reported_level',
        'target_band',
        'prep_timeline'
      ] then 'assessment_pending'
      else 'questionnaire_pending'
    end::public.onboarding_flow_state_enum,
    current_question_index = case
      when p.onboarding_status in ('completed', 'skipped') then 5
      when not (op.answers ? 'occupation') then 0
      when not (op.answers ? 'ielts_reason') then 1
      when not (op.answers ? 'self_reported_level') then 2
      when not (op.answers ? 'target_band') then 3
      when not (op.answers ? 'prep_timeline') then 4
      else 5
    end
from public.profiles p
where p.id = op.user_id;

insert into public.onboarding_profiles (
  user_id,
  questionnaire_version,
  answers,
  flow_state,
  current_question_index,
  completed_at,
  skipped_at
)
select
  p.id,
  '1',
  '{}'::jsonb,
  case
    when p.onboarding_status in ('completed', 'skipped') then
      'home_ready'::public.onboarding_flow_state_enum
    else 'questionnaire_pending'::public.onboarding_flow_state_enum
  end,
  case when p.onboarding_status in ('completed', 'skipped') then 5 else 0 end,
  case when p.onboarding_status = 'completed' then now() else null end,
  case when p.onboarding_status = 'skipped' then now() else null end
from public.profiles p
where not exists (
  select 1
  from public.onboarding_profiles op
  where op.user_id = p.id
);

alter table public.onboarding_profiles
  alter column flow_state set default 'questionnaire_pending',
  alter column flow_state set not null,
  alter column current_question_index set default 0,
  alter column current_question_index set not null,
  add constraint onboarding_question_index_range
    check (current_question_index between 0 and 5);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
select
  op.user_id,
  1,
  true,
  now()
from public.onboarding_profiles op
where op.flow_state = 'home_ready'
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(public.user_level_progress.unlocked_at, excluded.unlocked_at);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_code text;
  requested_username text;
  requested_nickname text;
  requested_timezone text;
begin
  generated_code :=
    'KQ' || nextval('public.public_user_code_seq'::regclass)::text;

  requested_username :=
    lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  if requested_username !~ '^[a-z][a-z0-9_]{2,23}$' then
    raise exception 'Invalid username';
  end if;

  requested_nickname :=
    btrim(coalesce(new.raw_user_meta_data ->> 'nickname', requested_username));
  if char_length(requested_nickname) not between 1 and 36
     or requested_nickname ~ '[@<>/]' then
    requested_nickname := requested_username;
  end if;

  requested_timezone :=
    btrim(coalesce(new.raw_user_meta_data ->> 'timezone', ''));
  if char_length(requested_timezone) not between 1 and 100 then
    requested_timezone := 'UTC';
  end if;

  insert into public.profiles (
    id,
    public_user_code,
    username,
    nickname
  )
  values (
    new.id,
    generated_code,
    requested_username,
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

  insert into public.user_consents (
    user_id,
    document_type,
    document_version
  )
  values
    (
      new.id,
      'terms',
      coalesce(new.raw_user_meta_data ->> 'terms_version', '2026-06-01')
    ),
    (
      new.id,
      'privacy',
      coalesce(new.raw_user_meta_data ->> 'privacy_version', '2026-06-01')
    );

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index
  )
  values (
    new.id,
    '1',
    '{}'::jsonb,
    'questionnaire_pending',
    0
  );

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

create or replace function public.build_user_bootstrap_state(target_user_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'public_user_code', p.public_user_code,
      'username', p.username,
      'nickname', p.nickname,
      'avatar_path', p.avatar_path,
      'duck_power', p.duck_power,
      'onboarding_status', p.onboarding_status
    ),
    'flow_state', op.flow_state,
    'current_question_index', op.current_question_index,
    'onboarding_answers', op.answers,
    'placement_status', case
      when op.flow_state = 'home_ready' then 'legacy_level_1'
      when op.flow_state = 'placement_finalized' then 'finalized'
      else 'pending'
    end,
    'current_level', progress.current_level,
    'highest_unlocked_level', progress.highest_unlocked_level
  )
  from public.profiles p
  join public.onboarding_profiles op on op.user_id = p.id
  left join lateral (
    select
      max(ulp.level_number) filter (where ulp.is_unlocked) as highest_unlocked_level,
      coalesce(
        min(ulp.level_number) filter (
          where ulp.is_unlocked and not ulp.is_completed
        ),
        max(ulp.level_number) filter (where ulp.is_unlocked)
      ) as current_level
    from public.user_level_progress ulp
    where ulp.user_id = p.id
  ) progress on true
  where p.id = target_user_id;
$$;

revoke all on function public.build_user_bootstrap_state(uuid) from public;

create or replace function public.get_user_bootstrap_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  legacy_status public.onboarding_status_enum;
  result jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select onboarding_status
  into legacy_status
  from public.profiles
  where id = current_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index,
    completed_at,
    skipped_at
  )
  values (
    current_user_id,
    '1',
    '{}'::jsonb,
    case
      when legacy_status in ('completed', 'skipped') then
        'home_ready'::public.onboarding_flow_state_enum
      else 'questionnaire_pending'::public.onboarding_flow_state_enum
    end,
    case when legacy_status in ('completed', 'skipped') then 5 else 0 end,
    case when legacy_status = 'completed' then now() else null end,
    case when legacy_status = 'skipped' then now() else null end
  )
  on conflict (user_id) do nothing;

  if exists (
    select 1
    from public.onboarding_profiles
    where user_id = current_user_id
      and flow_state = 'home_ready'
  ) then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      unlocked_at
    )
    values (
      current_user_id,
      1,
      true,
      now()
    )
    on conflict (user_id, level_number) do update
    set is_unlocked = true,
        unlocked_at = coalesce(
          public.user_level_progress.unlocked_at,
          excluded.unlocked_at
        );
  end if;

  result := public.build_user_bootstrap_state(current_user_id);
  return result;
end;
$$;

create or replace function public.save_onboarding_answer(
  requested_questionnaire_version text,
  requested_answer_key text,
  requested_answer_value text,
  requested_expected_question_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  expected_key text;
  current_row public.onboarding_profiles;
  allowed_values text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if char_length(btrim(requested_questionnaire_version)) not between 1 and 100 then
    raise exception 'Invalid questionnaire version';
  end if;

  if requested_expected_question_index not between 0 and 4 then
    raise exception 'Invalid question index';
  end if;

  if char_length(btrim(requested_answer_value)) not between 1 and 64 then
    raise exception 'Invalid answer value';
  end if;

  expected_key := (array[
    'occupation',
    'ielts_reason',
    'self_reported_level',
    'target_band',
    'prep_timeline'
  ])[requested_expected_question_index + 1];

  if requested_answer_key <> expected_key then
    raise exception 'Answer key does not match question index';
  end if;

  allowed_values := case requested_answer_key
    when 'occupation' then
      array['student', 'employed', 'freelancer', 'full_time_parent', 'other']
    when 'ielts_reason' then
      array['study_abroad', 'work', 'self_improvement', 'migration', 'accompany_child', 'other']
    when 'self_reported_level' then
      array['weak', 'cet4', 'cet6', 'unsure']
    when 'target_band' then
      array['5_0', '5_5', '6_0', '6_5', '7_0_plus']
    when 'prep_timeline' then
      array['under_3_months', '3_to_6_months', 'over_6_months', 'unsure']
    else array[]::text[]
  end;

  if not (requested_answer_value = any(allowed_values)) then
    raise exception 'Invalid answer value for %', requested_answer_key;
  end if;

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index
  )
  values (
    current_user_id,
    btrim(requested_questionnaire_version),
    '{}'::jsonb,
    'questionnaire_pending',
    0
  )
  on conflict (user_id) do nothing;

  select *
  into current_row
  from public.onboarding_profiles
  where user_id = current_user_id
  for update;

  if current_row.flow_state in ('placement_finalized', 'home_ready') then
    raise exception 'Onboarding is already finalized';
  end if;

  if current_row.questionnaire_version <> btrim(requested_questionnaire_version) then
    raise exception 'Questionnaire version mismatch';
  end if;

  if current_row.current_question_index > requested_expected_question_index then
    if current_row.answers ->> requested_answer_key = requested_answer_value then
      return public.build_user_bootstrap_state(current_user_id);
    end if;
    raise exception 'Answer was already submitted with a different value';
  end if;

  if current_row.current_question_index <> requested_expected_question_index
     or current_row.flow_state <> 'questionnaire_pending' then
    raise exception 'Out-of-order onboarding answer';
  end if;

  update public.onboarding_profiles
  set answers = current_row.answers ||
        jsonb_build_object(requested_answer_key, requested_answer_value),
      current_question_index = requested_expected_question_index + 1,
      flow_state = case
        when requested_expected_question_index = 4 then
          'assessment_pending'::public.onboarding_flow_state_enum
        else 'questionnaire_pending'::public.onboarding_flow_state_enum
      end
  where user_id = current_user_id;

  update public.profiles
  set onboarding_status = 'in_progress'
  where id = current_user_id
    and onboarding_status in ('not_started', 'in_progress');

  return public.build_user_bootstrap_state(current_user_id);
end;
$$;

-- The old whole-object RPC could bypass ordered answers and finalization rules.
revoke execute on function public.save_onboarding_profile(
  text,
  jsonb,
  public.onboarding_status_enum
) from authenticated;

revoke all on function public.get_user_bootstrap_state() from public;
grant execute on function public.get_user_bootstrap_state() to authenticated;

revoke all on function public.save_onboarding_answer(
  text,
  text,
  text,
  integer
) from public;
grant execute on function public.save_onboarding_answer(
  text,
  text,
  text,
  integer
) to authenticated;

comment on column public.onboarding_profiles.flow_state is
  'Server-owned routing state. Authenticated clients may only change it through approved RPCs.';
comment on column public.onboarding_profiles.current_question_index is
  'Zero-based index of the next questionnaire answer expected by the server; 5 means complete.';
comment on function public.get_user_bootstrap_state() is
  'Returns and defensively repairs the authenticated user startup state.';
comment on function public.save_onboarding_answer(text, text, text, integer) is
  'Validates and atomically persists one ordered onboarding answer.';

commit;


-- ============================================================================
-- Migration: 202606220006_finalize_placement_rpc.sql
-- ============================================================================

-- Finalises a new user's placement after the assessment (or skip).
-- Depends on 202606220005_user_bootstrap_and_onboarding.sql.
--
-- Scoring table sourced from ielts_bands.py in
-- github.com/ZainabZaman/IELTS_PracticeAndEvaluation.
--
-- Starting level mapping (240 levels across bands 4–8, 5 whole-band tiers):
--   band < 5.0  → level 1   (band 4 tier)
--   band 5.0–5.9 → level 49  (band 5 tier, first level)
--   band 6.0–6.9 → level 97  (band 6 tier)
--   band 7.0–7.9 → level 145 (band 7 tier)
--   band ≥ 8.0   → level 193 (band 8 tier)

begin;

create or replace function public.finalize_placement(
  p_ielts_band numeric,
  p_skip       boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  start_level     integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  start_level := case
    when p_skip or p_ielts_band < 5.0  then 1
    when p_ielts_band < 6.0            then 49
    when p_ielts_band < 7.0            then 97
    when p_ielts_band < 8.0            then 145
    else                                    193
  end;

  -- Mark onboarding complete
  update public.onboarding_profiles
  set flow_state            = 'home_ready',
      current_question_index = 5,
      completed_at           = now()
  where user_id = current_user_id;

  update public.profiles
  set onboarding_status = 'completed'
  where id = current_user_id;

  -- Unlock the computed starting level
  insert into public.user_level_progress (
    user_id,
    level_number,
    is_unlocked,
    unlocked_at
  )
  values (current_user_id, start_level, true, now())
  on conflict (user_id, level_number) do update
    set is_unlocked  = true,
        unlocked_at  = coalesce(
          public.user_level_progress.unlocked_at,
          excluded.unlocked_at
        );

  -- Always unlock level 1 so there is something to practice
  if start_level > 1 then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      unlocked_at
    )
    values (current_user_id, 1, true, now())
    on conflict (user_id, level_number) do update
      set is_unlocked = true,
          unlocked_at = coalesce(
            public.user_level_progress.unlocked_at,
            excluded.unlocked_at
          );
  end if;

  return public.build_user_bootstrap_state(current_user_id);
end;
$$;

revoke all on function public.finalize_placement(numeric, boolean) from public;
grant execute on function public.finalize_placement(numeric, boolean) to authenticated;

comment on function public.finalize_placement(numeric, boolean) is
  'Completes new-user placement: marks onboarding home_ready and unlocks the starting level derived from the IELTS band score.';

commit;


-- ============================================================================
-- Migration: 202606240007_onboarding_starts_at_level_one.sql
-- ============================================================================

-- Removes the initial placement-assessment gate.
-- Completing the fifth onboarding answer now atomically:
--   1. marks onboarding home_ready,
--   2. marks the profile completed,
--   3. unlocks Level 1,
--   4. returns the updated bootstrap state.
--
-- Existing users stopped at assessment_pending are migrated to Level 1.
-- Depends on 202606220005_user_bootstrap_and_onboarding.sql.

begin;

update public.onboarding_profiles
set flow_state = 'home_ready',
    completed_at = coalesce(completed_at, now())
where flow_state = 'assessment_pending';

update public.profiles profile
set onboarding_status = 'completed'
where exists (
  select 1
  from public.onboarding_profiles onboarding
  where onboarding.user_id = profile.id
    and onboarding.flow_state = 'home_ready'
);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
select
  onboarding.user_id,
  1,
  true,
  now()
from public.onboarding_profiles onboarding
where onboarding.flow_state = 'home_ready'
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(
      public.user_level_progress.unlocked_at,
      excluded.unlocked_at
    );

create or replace function public.save_onboarding_answer(
  requested_questionnaire_version text,
  requested_answer_key text,
  requested_answer_value text,
  requested_expected_question_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  expected_key text;
  current_row public.onboarding_profiles;
  allowed_values text[];
  is_final_answer boolean := requested_expected_question_index = 4;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if char_length(btrim(requested_questionnaire_version)) not between 1 and 100 then
    raise exception 'Invalid questionnaire version';
  end if;

  if requested_expected_question_index not between 0 and 4 then
    raise exception 'Invalid question index';
  end if;

  if char_length(btrim(requested_answer_value)) not between 1 and 64 then
    raise exception 'Invalid answer value';
  end if;

  expected_key := (array[
    'occupation',
    'ielts_reason',
    'self_reported_level',
    'target_band',
    'prep_timeline'
  ])[requested_expected_question_index + 1];

  if requested_answer_key <> expected_key then
    raise exception 'Answer key does not match question index';
  end if;

  allowed_values := case requested_answer_key
    when 'occupation' then
      array['student', 'employed', 'freelancer', 'full_time_parent', 'other']
    when 'ielts_reason' then
      array['study_abroad', 'work', 'self_improvement', 'migration', 'accompany_child', 'other']
    when 'self_reported_level' then
      array['weak', 'cet4', 'cet6', 'unsure']
    when 'target_band' then
      array['5_0', '5_5', '6_0', '6_5', '7_0_plus']
    when 'prep_timeline' then
      array['under_3_months', '3_to_6_months', 'over_6_months', 'unsure']
    else array[]::text[]
  end;

  if not (requested_answer_value = any(allowed_values)) then
    raise exception 'Invalid answer value for %', requested_answer_key;
  end if;

  insert into public.onboarding_profiles (
    user_id,
    questionnaire_version,
    answers,
    flow_state,
    current_question_index
  )
  values (
    current_user_id,
    btrim(requested_questionnaire_version),
    '{}'::jsonb,
    'questionnaire_pending',
    0
  )
  on conflict (user_id) do nothing;

  select *
  into current_row
  from public.onboarding_profiles
  where user_id = current_user_id
  for update;

  if current_row.questionnaire_version <> btrim(requested_questionnaire_version) then
    raise exception 'Questionnaire version mismatch';
  end if;

  -- Exact retries are idempotent, including retrying the fifth answer after
  -- the first request already finalized onboarding.
  if current_row.current_question_index > requested_expected_question_index then
    if current_row.answers ->> requested_answer_key = requested_answer_value then
      return public.build_user_bootstrap_state(current_user_id);
    end if;
    raise exception 'Answer was already submitted with a different value';
  end if;

  if current_row.flow_state in ('placement_finalized', 'home_ready') then
    raise exception 'Onboarding is already finalized';
  end if;

  if current_row.current_question_index <> requested_expected_question_index
     or current_row.flow_state <> 'questionnaire_pending' then
    raise exception 'Out-of-order onboarding answer';
  end if;

  update public.onboarding_profiles
  set answers = current_row.answers ||
        jsonb_build_object(requested_answer_key, requested_answer_value),
      current_question_index = requested_expected_question_index + 1,
      flow_state = case
        when is_final_answer then 'home_ready'::public.onboarding_flow_state_enum
        else 'questionnaire_pending'::public.onboarding_flow_state_enum
      end,
      completed_at = case when is_final_answer then now() else completed_at end
  where user_id = current_user_id;

  update public.profiles
  set onboarding_status = case
    when is_final_answer then 'completed'::public.onboarding_status_enum
    else 'in_progress'::public.onboarding_status_enum
  end
  where id = current_user_id;

  if is_final_answer then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      unlocked_at
    )
    values (
      current_user_id,
      1,
      true,
      now()
    )
    on conflict (user_id, level_number) do update
    set is_unlocked = true,
        unlocked_at = coalesce(
          public.user_level_progress.unlocked_at,
          excluded.unlocked_at
        );
  end if;

  return public.build_user_bootstrap_state(current_user_id);
end;
$$;

revoke all on function public.save_onboarding_answer(
  text,
  text,
  text,
  integer
) from public;
grant execute on function public.save_onboarding_answer(
  text,
  text,
  text,
  integer
) to authenticated;

comment on function public.save_onboarding_answer(text, text, text, integer) is
  'Validates and atomically persists one ordered onboarding answer. The fifth answer completes onboarding and unlocks Level 1.';

commit;


-- ============================================================================
-- Migration: 202606240008_fix_level_one_old_sense.sql
-- ============================================================================

-- Corrects the stale Level 1 sense for "old" that was imported before the
-- reviewed content export was regenerated.

begin;

update public.word_senses sense_row
set definition_en = 'having lived for many years; no longer young',
    definition_zh = '年老的',
    difficulty_band = 4.0,
    cefr_level = 'A1',
    review_status = 'approved'
from public.words word_row
where word_row.id = sense_row.word_id
  and word_row.headword = 'old'
  and sense_row.part_of_speech = 'adj.'
  and sense_row.sense_number = 1;

update public.questions question_row
set stem = 'Which word means: having lived for many years; no longer young?',
    translation_zh = '年老的'
from public.word_senses sense_row
join public.words word_row on word_row.id = sense_row.word_id
where question_row.sense_id = sense_row.id
  and word_row.headword = 'old'
  and question_row.type_code = 2
  and question_row.example_id is null;

commit;


-- ============================================================================
-- Migration: 202606240009_spaced_review_practice_rounds.sql
-- ============================================================================

-- KuaKua Duck V1.0 spaced review and immutable server-created practice rounds.
--
-- Additive/backward-compatible:
-- - preserves the legacy meaning-choice RPCs and columns;
-- - makes user_sense_mastery the new scheduling source of truth;
-- - keeps mistake_senses as an active/history display index;
-- - does not migrate or delete existing answer history.

begin;

do $$
begin
  create type public.sense_learning_state_enum as enum (
    'new',
    'learning',
    'reviewing',
    'mastered'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.practice_round_status_enum as enum (
    'started',
    'completed',
    'abandoned'
  );
exception when duplicate_object then null;
end $$;

-- Authoritative per-sense memory state ---------------------------------------

alter table public.user_sense_mastery
  add column if not exists learning_state
    public.sense_learning_state_enum not null default 'new',
  add column if not exists wrong_count integer not null default 0,
  add column if not exists consecutive_correct_count integer not null default 0,
  add column if not exists recent_results boolean[] not null default '{}',
  add column if not exists spaced_success_count integer not null default 0,
  add column if not exists has_active_recall_success boolean not null default false,
  add column if not exists difficulty_level integer not null default 0,
  add column if not exists first_seen_at timestamptz,
  add column if not exists first_correct_at timestamptz,
  add column if not exists last_correct_at timestamptz;

update public.user_sense_mastery
set learning_state = case
      when mastered_at is not null then 'mastered'::public.sense_learning_state_enum
      when review_stage >= 2 then 'reviewing'::public.sense_learning_state_enum
      when seen_count > 0 then 'learning'::public.sense_learning_state_enum
      else 'new'::public.sense_learning_state_enum
    end,
    first_seen_at = coalesce(first_seen_at, last_seen_at),
    first_correct_at = case
      when correct_count > 0
      then coalesce(first_correct_at, last_seen_at)
      else first_correct_at
    end,
    last_correct_at = case
      when correct_count > 0
      then coalesce(last_correct_at, last_seen_at)
      else last_correct_at
    end
where learning_state = 'new'
   or first_seen_at is null
   or (correct_count > 0 and (first_correct_at is null or last_correct_at is null));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_wrong_count_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_wrong_count_non_negative
      check (wrong_count >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_consecutive_correct_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_consecutive_correct_non_negative
      check (consecutive_correct_count >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_recent_results_max_six'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_recent_results_max_six
      check (coalesce(array_length(recent_results, 1), 0) <= 6);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_spaced_success_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_spaced_success_non_negative
      check (spaced_success_count >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_difficulty_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_difficulty_non_negative
      check (difficulty_level >= 0);
  end if;
end $$;

comment on column public.user_sense_mastery.review_stage is
  '0 learning, 1 ten_minute, 2 one_day, 3 seven_day, 4 thirty_day, 5 mastered_maintenance';
comment on column public.user_sense_mastery.recent_results is
  'Latest six formal answer results only; oldest result is removed first.';

alter table public.questions
  add column if not exists is_context_hint boolean not null default false,
  add column if not exists context_for_multiple_meaning boolean not null default false;

comment on column public.questions.is_context_hint is
  'Contextual Chinese-definition hint; selected only for multiple meanings or repeated mistakes.';
comment on column public.questions.context_for_multiple_meaning is
  'True when context is required to distinguish explicitly separate meanings.';

-- Mistake notebook display index --------------------------------------------

alter table public.mistake_senses
  add column if not exists first_wrong_at timestamptz,
  add column if not exists is_active boolean not null default true,
  add column if not exists resolved_at timestamptz;

update public.mistake_senses
set first_wrong_at = coalesce(first_wrong_at, created_at, last_wrong_at),
    is_active = case when mastered_at is null then true else false end,
    resolved_at = case
      when mastered_at is not null then coalesce(resolved_at, mastered_at)
      else null
    end
where first_wrong_at is null
   or (mastered_at is not null and is_active)
   or (mastered_at is not null and resolved_at is null);

alter table public.mistake_senses
  alter column first_wrong_at set default now();

update public.mistake_senses
set first_wrong_at = now()
where first_wrong_at is null;

alter table public.mistake_senses
  alter column first_wrong_at set not null;

comment on column public.mistake_senses.review_stage is
  'Legacy compatibility only. Read authoritative review_stage from user_sense_mastery.';
comment on column public.mistake_senses.next_due_at is
  'Legacy compatibility only. Read authoritative next_due_at from user_sense_mastery.';

-- Immutable round snapshots --------------------------------------------------

create table if not exists public.practice_rounds (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles(id) on delete cascade,
  level_number         integer not null references public.levels(level_number),
  session_id           uuid not null unique
                       references public.practice_sessions(id) on delete cascade,
  status               public.practice_round_status_enum not null default 'started',
  question_count       smallint not null,
  correct_count        smallint not null default 0,
  new_sense_count      smallint not null default 0,
  review_sense_count   smallint not null default 0,
  completion_key       uuid not null default gen_random_uuid(),
  started_at           timestamptz not null default now(),
  completed_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint practice_round_question_count_valid
    check (question_count between 1 and 20),
  constraint practice_round_correct_count_valid
    check (correct_count between 0 and question_count),
  constraint practice_round_mix_valid
    check (
      new_sense_count >= 0
      and review_sense_count >= 0
      and new_sense_count + review_sense_count <= question_count
    ),
  constraint practice_round_completion_order
    check (completed_at is null or completed_at >= started_at)
);

create unique index if not exists practice_rounds_one_started_per_level
  on public.practice_rounds (user_id, level_number)
  where status = 'started';

create table if not exists public.practice_round_questions (
  round_id           uuid not null references public.practice_rounds(id) on delete cascade,
  position           smallint not null,
  question_id        uuid not null references public.questions(id),
  sense_id           uuid not null references public.word_senses(id),
  question_skill     text not null default 'recognition',
  option_ids         uuid[] not null default '{}',
  correct_option_id  uuid references public.question_options(id),
  answer_given       text,
  is_correct         boolean,
  response_time_ms   integer,
  answered_at        timestamptz,

  primary key (round_id, position),
  unique (round_id, question_id),
  unique (round_id, sense_id),
  constraint practice_round_position_valid check (position between 1 and 20),
  constraint practice_round_skill_valid check (
    question_skill in ('recognition', 'active_recall', 'listening', 'speaking')
  ),
  constraint practice_round_response_time_valid check (
    response_time_ms is null or response_time_ms >= 0
  ),
  constraint practice_round_answer_consistent check (
    (answered_at is null and is_correct is null and response_time_ms is null)
    or
    (answered_at is not null and is_correct is not null and response_time_ms is not null)
  )
);

drop trigger if exists practice_rounds_set_updated_at on public.practice_rounds;
create trigger practice_rounds_set_updated_at
before update on public.practice_rounds
for each row execute function public.set_updated_at();

create index if not exists practice_rounds_user_started_idx
  on public.practice_rounds (user_id, started_at desc);
create index if not exists practice_round_questions_round_idx
  on public.practice_round_questions (round_id, position);
create index if not exists user_sense_mastery_priority_idx
  on public.user_sense_mastery (
    user_id,
    next_due_at,
    difficulty_level desc,
    review_stage
  );
create index if not exists mistake_senses_active_recent_idx
  on public.mistake_senses (user_id, is_active, last_wrong_at desc);

-- Internal helpers -----------------------------------------------------------

create or replace function public.append_recent_formal_result(
  p_results boolean[],
  p_result boolean
)
returns boolean[]
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(array_length(p_results, 1), 0) < 6
      then coalesce(p_results, '{}'::boolean[]) || p_result
    else p_results[2:6] || p_result
  end;
$$;

create or replace function public.refresh_level_completion(
  p_user_id uuid,
  p_level_number integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target_count integer;
  v_assignment_count integer;
  v_seen_count integer;
  v_qualifying_count integer;
  v_required_count integer;
  v_completed boolean;
  v_band_id smallint;
  v_next_band_id smallint;
begin
  select new_sense_target
  into v_target_count
  from public.levels
  where level_number = p_level_number;

  select count(*)
  into v_assignment_count
  from public.level_sense_assignments
  where level_number = p_level_number
    and placement_type = 'new';

  if coalesce(v_target_count, 0) = 0
     or v_assignment_count < v_target_count then
    return false;
  end if;

  v_required_count := ceil(v_target_count * 0.90)::integer;

  select
    count(*) filter (where usm.seen_count > 0),
    count(*) filter (
      where usm.correct_count > 0
        and usm.spaced_success_count > 0
        and usm.learning_state in ('reviewing', 'mastered')
    )
  into v_seen_count, v_qualifying_count
  from public.level_sense_assignments lsa
  left join public.user_sense_mastery usm
    on usm.user_id = p_user_id
   and usm.sense_id = lsa.sense_id
  where lsa.level_number = p_level_number
    and lsa.placement_type = 'new';

  v_completed :=
    v_seen_count = v_assignment_count
    and v_qualifying_count >= v_required_count;

  insert into public.user_level_progress (
    user_id,
    level_number,
    is_unlocked,
    is_completed,
    progress,
    unlocked_at,
    completed_at,
    updated_at
  )
  values (
    p_user_id,
    p_level_number,
    true,
    v_completed,
    least(1.0, v_qualifying_count::numeric / v_target_count),
    now(),
    case when v_completed then now() else null end,
    now()
  )
  on conflict (user_id, level_number) do update
  set is_completed = public.user_level_progress.is_completed or v_completed,
      progress = greatest(
        public.user_level_progress.progress,
        least(1.0, v_qualifying_count::numeric / v_target_count)
      ),
      completed_at = case
        when public.user_level_progress.completed_at is not null
          then public.user_level_progress.completed_at
        when v_completed then now()
        else null
      end,
      updated_at = now();

  if v_completed then
    select band_id into v_band_id
    from public.levels
    where level_number = p_level_number;

    select band_id into v_next_band_id
    from public.levels
    where level_number = p_level_number + 1;

    -- The upgrade exam owns cross-difficulty progression.
    if v_next_band_id = v_band_id then
      insert into public.user_level_progress (
        user_id,
        level_number,
        is_unlocked,
        unlocked_at
      )
      values (
        p_user_id,
        p_level_number + 1,
        true,
        now()
      )
      on conflict (user_id, level_number) do update
      set is_unlocked = true,
          unlocked_at = coalesce(public.user_level_progress.unlocked_at, now()),
          updated_at = now();
    end if;
  end if;

  return v_completed;
end;
$$;

-- Public RPCs ---------------------------------------------------------------

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round_id uuid;
  v_session_id uuid;
  v_due_count integer;
  v_max_new integer;
  v_question_count integer;
  v_new_count integer;
  v_review_count integer;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    select count(*)
    into v_due_count
    from public.user_sense_mastery
    where user_id = v_user_id
      and next_due_at is not null
      and next_due_at <= now()
      and learning_state <> 'mastered';

    v_max_new := case
      when v_due_count > 20 then 0
      when v_due_count > 0 then 12
      else 20
    end;

    insert into public.practice_sessions (
      user_id,
      level_number,
      session_type,
      status
    )
    values (
      v_user_id,
      p_level_number,
      'daily',
      'started'
    )
    returning id into v_session_id;

    insert into public.practice_rounds (
      user_id,
      level_number,
      session_id,
      question_count
    )
    values (
      v_user_id,
      p_level_number,
      v_session_id,
      1
    )
    returning id into v_round_id;

    with eligible_questions as (
      select
        q.id as question_id,
        q.sense_id,
        q.is_context_hint,
        q.context_for_multiple_meaning,
        (array_agg(qo.id) filter (where qo.is_correct))[1]
          as correct_option_id,
        array_agg(qo.id order by random()) as option_ids
      from public.questions q
      join public.question_options qo on qo.question_id = q.id
      where q.is_active
        and q.answer_form = 'option'
        and q.sense_id is not null
        and not q.human_review
        and not qo.human_review
      group by
        q.id,
        q.sense_id,
        q.is_context_hint,
        q.context_for_multiple_meaning
      having count(*) >= 2
         and count(*) filter (where qo.is_correct) = 1
    ),
    candidate_sources as (
      -- Global due reviews always outrank new material from the selected level.
      select
        usm.sense_id,
        case
          when ms.is_active
           and usm.next_due_at is not null
           and usm.next_due_at <= now() then 1
          else 2
        end as priority,
        usm.difficulty_level,
        usm.wrong_count,
        usm.next_due_at,
        false as is_new
      from public.user_sense_mastery usm
      left join public.mistake_senses ms
        on ms.user_id = v_user_id
       and ms.sense_id = usm.sense_id
      where usm.user_id = v_user_id
        and usm.next_due_at is not null
        and usm.next_due_at <= now()
        and usm.learning_state <> 'mastered'

      union all

      -- Selected-level new and near-due reinforcement candidates.
      select
        lsa.sense_id,
        case
          when usm.user_id is null then 3
          when usm.next_due_at is not null
           and usm.next_due_at <= now() + interval '24 hours' then 4
          else 5
        end,
        coalesce(usm.difficulty_level, 0),
        coalesce(usm.wrong_count, 0),
        coalesce(usm.next_due_at, 'infinity'::timestamptz),
        (usm.user_id is null)
      from public.level_sense_assignments lsa
      left join public.user_sense_mastery usm
        on usm.user_id = v_user_id
       and usm.sense_id = lsa.sense_id
      where lsa.level_number = p_level_number
        and lsa.placement_type = 'new'
    ),
    candidate_senses as (
      select distinct on (sense_id)
        sense_id,
        priority,
        difficulty_level,
        wrong_count,
        next_due_at,
        is_new
      from candidate_sources
      order by sense_id, priority, next_due_at
    ),
    ranked as (
      select
        cs.sense_id,
        cs.priority,
        cs.difficulty_level,
        cs.wrong_count,
        cs.next_due_at,
        cs.is_new,
        row_number() over (
          partition by cs.is_new
          order by cs.priority, cs.next_due_at, cs.difficulty_level desc, random()
        ) as type_rank
      from candidate_senses cs
      where exists (
          select 1 from eligible_questions eq where eq.sense_id = cs.sense_id
        )
    ),
    limited as (
      select *
      from ranked
      where not is_new
         or type_rank <= v_max_new
      order by priority, next_due_at, difficulty_level desc, random()
      limit 20
    ),
    chosen as (
      select
        l.sense_id,
        l.priority,
        l.is_new,
        eq.question_id,
        eq.correct_option_id,
        eq.option_ids,
        row_number() over (
          order by l.priority, l.next_due_at, l.difficulty_level desc, random()
        )::smallint as position
      from limited l
      join lateral (
        select *
        from eligible_questions candidate
        where candidate.sense_id = l.sense_id
          and (
            not candidate.is_context_hint
            or candidate.context_for_multiple_meaning
            or l.wrong_count >= 3
          )
        order by
          case
            when candidate.is_context_hint
             and (
               candidate.context_for_multiple_meaning
               or l.wrong_count >= 3
             ) then 0
            else 1
          end,
          random()
        limit 1
      ) eq on true
    )
    insert into public.practice_round_questions (
      round_id,
      position,
      question_id,
      sense_id,
      question_skill,
      option_ids,
      correct_option_id
    )
    select
      v_round_id,
      position,
      question_id,
      sense_id,
      'recognition',
      option_ids,
      correct_option_id
    from chosen;

    select
      count(*),
      count(*) filter (
        where not exists (
          select 1
          from public.user_sense_mastery usm
          where usm.user_id = v_user_id
            and usm.sense_id = prq.sense_id
        )
      )
    into v_question_count, v_new_count
    from public.practice_round_questions prq
    where prq.round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible reviewed option questions for Level %', p_level_number;
    end if;

    v_review_count := v_question_count - v_new_count;

    update public.practice_rounds
    set question_count = v_question_count,
        new_sense_count = v_new_count,
        review_sense_count = v_review_count
    where id = v_round_id;
  end if;

  select jsonb_build_object(
    'round_id', r.id,
    'level_number', r.level_number,
    'status', r.status,
    'question_count', r.question_count,
    'new_sense_count', r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position', rq.position,
          'question_id', q.id,
          'sense_id', rq.sense_id,
          'stem', q.stem,
          'prompt_hint', q.prompt_hint,
          'translation_zh', q.translation_zh,
          'question_skill', rq.question_skill,
          'options', (
            select jsonb_agg(
              jsonb_build_object(
                'option_id', option_row.id,
                'option_text', option_row.option_text
              )
              order by option_order.ordinality
            )
            from unnest(rq.option_ids) with ordinality option_order(option_id, ordinality)
            join public.question_options option_row
              on option_row.id = option_order.option_id
          ),
          'answer_given', rq.answer_given,
          'is_answered', rq.answered_at is not null
        )
        order by rq.position
      )
      from public.practice_round_questions rq
      join public.questions q on q.id = rq.question_id
      where rq.round_id = r.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.practice_rounds r
  where r.id = v_round_id
    and r.user_id = v_user_id;

  return v_result;
end;
$$;

create or replace function public.save_practice_answer(
  p_round_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_item public.practice_round_questions%rowtype;
  v_is_correct boolean;
  v_now timestamptz := clock_timestamp();
  v_mastery public.user_sense_mastery%rowtype;
  v_old_stage smallint;
  v_new_stage smallint;
  v_new_state public.sense_learning_state_enum;
  v_due_advance boolean := false;
  v_next_due timestamptz;
  v_spaced_increment integer := 0;
  v_recent boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id
    and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position', p_position,
      'is_correct', v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'already_saved', true
    );
  end if;

  if v_item.correct_option_id is null then
    raise exception 'V1.0 only supports server-graded option questions';
  end if;

  if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
    raise exception 'Answer must be an option UUID';
  end if;

  if not (p_answer::uuid = any(v_item.option_ids)) then
    raise exception 'Answer option does not belong to this question';
  end if;

  v_is_correct := p_answer::uuid = v_item.correct_option_id;

  update public.practice_round_questions
  set answer_given = p_answer,
      is_correct = v_is_correct,
      response_time_ms = p_response_time_ms,
      answered_at = v_now
  where round_id = p_round_id
    and position = p_position;

  insert into public.user_sense_mastery (
    user_id,
    sense_id,
    learning_state,
    seen_count,
    correct_count,
    wrong_count,
    consecutive_correct_count,
    recent_results,
    review_stage,
    first_seen_at,
    first_correct_at,
    last_seen_at,
    last_correct_at,
    next_due_at,
    updated_at
  )
  values (
    v_user_id,
    v_item.sense_id,
    'new',
    0,
    0,
    0,
    0,
    '{}',
    0,
    v_now,
    null,
    null,
    null,
    null,
    v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id
    and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent := public.append_recent_formal_result(
    v_mastery.recent_results,
    v_is_correct
  );

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due := v_now + interval '10 minutes';
    elsif v_mastery.next_due_at is not null
       and v_now >= v_mastery.next_due_at then
      v_due_advance := true;
      v_new_stage := least(4, v_old_stage + 1);
      v_new_state := case
        when v_new_stage >= 2 then 'reviewing'
        else 'learning'
      end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '10 minutes'
        when 2 then v_now + interval '1 day'
        when 3 then v_now + interval '7 days'
        when 4 then
          case when v_old_stage = 4
            then v_now + interval '75 days'
            else v_now + interval '30 days'
          end
        else v_now + interval '10 minutes'
      end;
    else
      v_new_stage := v_old_stage;
      v_new_state := case
        when v_mastery.learning_state = 'new' then 'learning'
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        else v_mastery.learning_state
      end;
      v_next_due := v_mastery.next_due_at;
    end if;

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        correct_count = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results = v_recent,
        spaced_success_count = spaced_success_count + v_spaced_increment,
        review_stage = v_new_stage,
        mastery_score = least(0.99, v_new_stage::numeric / 5),
        first_seen_at = coalesce(first_seen_at, v_now),
        first_correct_at = coalesce(first_correct_at, v_now),
        last_seen_at = v_now,
        last_correct_at = v_now,
        next_due_at = v_next_due,
        mastered_at = null,
        updated_at = v_now
    where user_id = v_user_id
      and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active = false,
          resolved_at = v_now,
          last_reviewed_at = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at = v_now
      where user_id = v_user_id
        and sense_id = v_item.sense_id
        and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1 then 0
      when v_old_stage = 2 then 1
      when v_old_stage = 3 then 2
      when v_old_stage in (4, 5) then 3
      else 0
    end;
    v_new_state := case
      when v_new_stage = 0 then 'learning'
      else 'reviewing'
    end;
    v_next_due := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        wrong_count = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results = v_recent,
        review_stage = v_new_stage,
        mastery_score = least(0.99, v_new_stage::numeric / 5),
        difficulty_level = difficulty_level + 1,
        first_seen_at = coalesce(first_seen_at, v_now),
        last_seen_at = v_now,
        next_due_at = v_next_due,
        mastered_at = null,
        updated_at = v_now
    where user_id = v_user_id
      and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id,
      sense_id,
      wrong_count,
      first_wrong_at,
      last_wrong_at,
      is_active,
      resolved_at,
      created_at,
      updated_at
    )
    values (
      v_user_id,
      v_item.sense_id,
      1,
      v_now,
      v_now,
      true,
      null,
      v_now,
      v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        is_active = true,
        resolved_at = null,
        updated_at = v_now;
  end if;

  insert into public.practice_answers (
    user_id,
    session_id,
    question_id,
    sense_id,
    skill_type,
    answer_given,
    is_correct,
    response_time_ms,
    answered_at
  )
  values (
    v_user_id,
    v_round.session_id,
    v_item.question_id,
    v_item.sense_id,
    'multiple_choice',
    p_answer,
    v_is_correct,
    p_response_time_ms,
    v_now
  )
  on conflict (session_id, question_id) do nothing;

  return jsonb_build_object(
    'position', p_position,
    'is_correct', v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'already_saved', false,
    'learning_state', v_new_state,
    'review_stage', v_new_stage,
    'next_due_at', v_next_due
  );
end;
$$;

create or replace function public.complete_practice_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_answered integer;
  v_correct integer;
  v_completed_level boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status = 'completed' then
    return jsonb_build_object(
      'round_id', v_round.id,
      'correct_count', v_round.correct_count,
      'question_count', v_round.question_count,
      'star_rating', case
        when v_round.correct_count = v_round.question_count then 3
        when v_round.correct_count::numeric / v_round.question_count >= 0.80 then 2
        when v_round.correct_count::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      'duck_power_earned', v_round.correct_count,
      'already_completed', true,
      'level_completed', (
        select is_completed
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = v_round.level_number
      )
    );
  end if;

  select
    count(*) filter (where answered_at is not null),
    count(*) filter (where is_correct)
  into v_answered, v_correct
  from public.practice_round_questions
  where round_id = p_round_id;

  if v_answered <> v_round.question_count then
    raise exception 'All round questions must be answered before completion';
  end if;

  update public.practice_rounds
  set status = 'completed',
      correct_count = v_correct,
      completed_at = now()
  where id = p_round_id;

  update public.practice_sessions
  set status = 'completed',
      completed_at = now(),
      correct_count = v_correct,
      total_count = v_round.question_count,
      star_rating = case
        when v_correct = v_round.question_count then 3
        when v_correct::numeric / v_round.question_count >= 0.80 then 2
        when v_correct::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      base_power = v_correct,
      duck_power_earned = v_correct
  where id = v_round.session_id;

  update public.profiles
  set duck_power = duck_power + v_correct
  where id = v_user_id;

  update public.user_level_progress
  set completed_session_count = completed_session_count + 1,
      updated_at = now()
  where user_id = v_user_id
    and level_number = v_round.level_number;

  v_completed_level := public.refresh_level_completion(
    v_user_id,
    v_round.level_number
  );

  return jsonb_build_object(
    'round_id', p_round_id,
    'correct_count', v_correct,
    'question_count', v_round.question_count,
    'star_rating', case
      when v_correct = v_round.question_count then 3
      when v_correct::numeric / v_round.question_count >= 0.80 then 2
      when v_correct::numeric / v_round.question_count >= 0.60 then 1
      else 0
    end,
    'duck_power_earned', v_correct,
    'already_completed', false,
    'level_completed', v_completed_level
  );
end;
$$;

create or replace function public.get_level_learning_status(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select jsonb_build_object(
    'level_number', p_level_number,
    'new_sense_target', (
      select new_sense_target
      from public.levels
      where level_number = p_level_number
    ),
    'assigned_new_sense_count', count(*),
    'required_count', ceil((
      select new_sense_target
      from public.levels
      where level_number = p_level_number
    ) * 0.90)::integer,
    'seen_count', count(*) filter (where usm.seen_count > 0),
    'first_correct_count', count(*) filter (where usm.correct_count > 0),
    'delayed_success_count', count(*) filter (
      where usm.spaced_success_count > 0
        and usm.learning_state in ('reviewing', 'mastered')
    ),
    'reviewing_count', count(*) filter (where usm.learning_state = 'reviewing'),
    'mastered_count', count(*) filter (where usm.learning_state = 'mastered'),
    'due_review_count', count(*) filter (
      where usm.next_due_at is not null and usm.next_due_at <= now()
    ),
    'is_unlocked', coalesce((
      select is_unlocked
      from public.user_level_progress
      where user_id = v_user_id
        and level_number = p_level_number
    ), false),
    'is_completed', coalesce((
      select is_completed
      from public.user_level_progress
      where user_id = v_user_id
        and level_number = p_level_number
    ), false),
    'display_state', case
      when not coalesce((
        select is_unlocked
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = p_level_number
      ), false) then '未解锁'
      when coalesce((
        select is_completed
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = p_level_number
      ), false) then '已通关'
      when count(*) filter (where usm.seen_count > 0) = 0 then '待开始'
      when count(*) filter (where usm.seen_count > 0) < count(*) then '学习中'
      else '巩固中'
    end
  )
  into v_result
  from public.level_sense_assignments lsa
  left join public.user_sense_mastery usm
    on usm.user_id = v_user_id
   and usm.sense_id = lsa.sense_id
  where lsa.level_number = p_level_number
    and lsa.placement_type = 'new';

  return v_result;
end;
$$;

-- Security -------------------------------------------------------------------

alter table public.practice_rounds enable row level security;
alter table public.practice_round_questions enable row level security;

drop policy if exists practice_rounds_own_select on public.practice_rounds;
create policy practice_rounds_own_select
on public.practice_rounds for select to authenticated
using (user_id = auth.uid());

-- Snapshot rows contain correct_option_id and therefore have no direct client
-- policy or grant. They are exposed only through security-definer RPCs.

revoke all on public.practice_rounds from anon, authenticated;
revoke all on public.practice_round_questions from anon, authenticated;
grant select on public.practice_rounds to authenticated;

revoke all on function public.append_recent_formal_result(boolean[], boolean)
  from public, anon, authenticated;
revoke all on function public.refresh_level_completion(uuid, integer)
  from public, anon, authenticated;

revoke all on function public.start_practice_round(integer)
  from public, anon;
revoke all on function public.save_practice_answer(uuid, integer, text, integer)
  from public, anon;
revoke all on function public.complete_practice_round(uuid)
  from public, anon;
revoke all on function public.get_level_learning_status(integer)
  from public, anon;

grant execute on function public.start_practice_round(integer) to authenticated;
grant execute on function public.save_practice_answer(uuid, integer, text, integer)
  to authenticated;
grant execute on function public.complete_practice_round(uuid) to authenticated;
grant execute on function public.get_level_learning_status(integer) to authenticated;

-- New learning mutations are server-owned. Existing SELECT access remains for
-- repository reads and RLS still limits rows to auth.uid().
revoke insert, update, delete on
  public.user_level_progress,
  public.practice_sessions,
  public.practice_answers,
  public.user_sense_mastery,
  public.user_sense_skill_progress,
  public.mistake_senses
from authenticated;

commit;


-- ============================================================================
-- Migration: 202606240011_profile_streak_and_reward_refresh.sql
-- ============================================================================

-- Persist daily practice streaks and keep round rewards server-owned.

begin;

alter table public.profiles
  add column if not exists current_streak_days integer not null default 0,
  add column if not exists longest_streak_days integer not null default 0,
  add column if not exists last_practice_date date;

alter table public.profiles
  drop constraint if exists profiles_streak_days_non_negative;

alter table public.profiles
  add constraint profiles_streak_days_non_negative
  check (
    current_streak_days >= 0
    and longest_streak_days >= current_streak_days
  );

-- Preserve useful history for accounts that completed rounds before this
-- migration. This establishes at least today's/most recent one-day streak;
-- future completions maintain the exact consecutive-day count.
with latest_activity as (
  select
    session_row.user_id,
    max(
      timezone(
        coalesce(settings_row.reminder_timezone, 'UTC'),
        session_row.completed_at
      )::date
    ) as activity_date
  from public.practice_sessions session_row
  left join public.user_settings settings_row
    on settings_row.user_id = session_row.user_id
  where session_row.status = 'completed'
    and session_row.completed_at is not null
  group by session_row.user_id
)
update public.profiles profile_row
set last_practice_date = latest_activity.activity_date,
    current_streak_days = case
      when latest_activity.activity_date >=
        timezone(
          coalesce(settings_row.reminder_timezone, 'UTC'),
          now()
        )::date - 1
      then greatest(profile_row.current_streak_days, 1)
      else 0
    end,
    longest_streak_days = greatest(profile_row.longest_streak_days, 1)
from latest_activity
left join public.user_settings settings_row
  on settings_row.user_id = latest_activity.user_id
where profile_row.id = latest_activity.user_id;

create or replace function public.complete_practice_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_answered integer;
  v_correct integer;
  v_completed_level boolean;
  v_today date;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status = 'completed' then
    return jsonb_build_object(
      'round_id', v_round.id,
      'correct_count', v_round.correct_count,
      'question_count', v_round.question_count,
      'star_rating', case
        when v_round.correct_count = v_round.question_count then 3
        when v_round.correct_count::numeric / v_round.question_count >= 0.80 then 2
        when v_round.correct_count::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      'duck_power_earned', v_round.correct_count,
      'already_completed', true,
      'level_completed', (
        select is_completed
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = v_round.level_number
      )
    );
  end if;

  select
    count(*) filter (where answered_at is not null),
    count(*) filter (where is_correct)
  into v_answered, v_correct
  from public.practice_round_questions
  where round_id = p_round_id;

  if v_answered <> v_round.question_count then
    raise exception 'All round questions must be answered before completion';
  end if;

  select timezone(
    coalesce(settings_row.reminder_timezone, 'UTC'),
    now()
  )::date
  into v_today
  from public.profiles profile_row
  left join public.user_settings settings_row
    on settings_row.user_id = profile_row.id
  where profile_row.id = v_user_id;

  update public.practice_rounds
  set status = 'completed',
      correct_count = v_correct,
      completed_at = now()
  where id = p_round_id;

  update public.practice_sessions
  set status = 'completed',
      completed_at = now(),
      correct_count = v_correct,
      total_count = v_round.question_count,
      star_rating = case
        when v_correct = v_round.question_count then 3
        when v_correct::numeric / v_round.question_count >= 0.80 then 2
        when v_correct::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      base_power = v_correct,
      duck_power_earned = v_correct
  where id = v_round.session_id;

  update public.profiles profile_row
  set duck_power = profile_row.duck_power + v_correct,
      current_streak_days = case
        when profile_row.last_practice_date = v_today
          then profile_row.current_streak_days
        when profile_row.last_practice_date = v_today - 1
          then profile_row.current_streak_days + 1
        else 1
      end,
      longest_streak_days = greatest(
        profile_row.longest_streak_days,
        case
          when profile_row.last_practice_date = v_today
            then profile_row.current_streak_days
          when profile_row.last_practice_date = v_today - 1
            then profile_row.current_streak_days + 1
          else 1
        end
      ),
      last_practice_date = v_today
  where profile_row.id = v_user_id;

  update public.user_level_progress
  set progress = greatest(
        progress,
        case
          when v_round.question_count > 0
            then v_correct::numeric / v_round.question_count
          else 0
        end
      ),
      best_star_rating = greatest(
        best_star_rating,
        case
          when v_correct = v_round.question_count then 3
          when v_correct::numeric / v_round.question_count >= 0.80 then 2
          when v_correct::numeric / v_round.question_count >= 0.60 then 1
          else 0
        end
      ),
      completed_session_count = completed_session_count + 1,
      updated_at = now()
  where user_id = v_user_id
    and level_number = v_round.level_number;

  v_completed_level := public.refresh_level_completion(
    v_user_id,
    v_round.level_number
  );

  return jsonb_build_object(
    'round_id', p_round_id,
    'correct_count', v_correct,
    'question_count', v_round.question_count,
    'star_rating', case
      when v_correct = v_round.question_count then 3
      when v_correct::numeric / v_round.question_count >= 0.80 then 2
      when v_correct::numeric / v_round.question_count >= 0.60 then 1
      else 0
    end,
    'duck_power_earned', v_correct,
    'already_completed', false,
    'level_completed', v_completed_level
  );
end;
$$;

revoke all on function public.complete_practice_round(uuid) from public, anon;
grant execute on function public.complete_practice_round(uuid) to authenticated;

commit;


-- ============================================================================
-- Migration: 202606240012_conditional_context_hints.sql
-- ============================================================================

-- Serve contextual Chinese-definition questions only when context is useful:
--   1. the source definition explicitly contains alternative meanings; or
--   2. this learner has answered the sense incorrectly at least three times.

begin;

alter table public.questions
  add column if not exists is_context_hint boolean not null default false,
  add column if not exists context_for_multiple_meaning boolean not null default false;

comment on column public.questions.is_context_hint is
  'Contextual Chinese-definition hint; not part of ordinary random practice.';
comment on column public.questions.context_for_multiple_meaning is
  'Context is preferred even before mistakes because the definition contains explicit alternative meanings.';

-- Convert the generated Chinese-to-English option question into a reserved
-- contextual hint. The reviewed Levels 1-5 conversion already uses the target
-- prompt and is included by the same update.
with context_candidates as (
  select
    question_row.id as question_id,
    question_row.sense_id,
    sense_row.definition_en,
    sense_row.definition_zh,
    word_row.headword,
    case word_row.headword
      when 'since' then 'I have lived here since 2020.'
      when 'dry' then 'The clothes are dry now.'
      when 'hit' then 'The new song became a hit around the world.'
      when 'run' then 'She can run a small restaurant near the station.'
      when 'shoot' then 'They will shoot the video tomorrow.'
      else coalesce(
        linked_example.sentence_en,
        fallback_example.sentence_en
      )
    end as sentence_en,
    coalesce(linked_example.id, fallback_example.id) as example_id
  from public.questions question_row
  join public.word_senses sense_row
    on sense_row.id = question_row.sense_id
  join public.words word_row
    on word_row.id = sense_row.word_id
  left join public.examples linked_example
    on linked_example.id = question_row.example_id
  left join lateral (
    select example_row.id, example_row.sentence_en
    from public.examples example_row
    where example_row.sense_id = question_row.sense_id
    order by example_row.sort_order, example_row.id
    limit 1
  ) fallback_example on true
  where question_row.answer_form = 'option'
    and (
      question_row.prompt_hint = '根据句子选择目标单词的完整中文释义。'
      or question_row.prompt_hint = '选择正确的英文单词。'
      or question_row.prompt_hint =
        'Choose the word that completes the sentence.'
    )
)
update public.questions question_row
set stem =
      candidates.sentence_en
      || E'\n\n句中“'
      || candidates.headword
      || '”是什么意思？',
    prompt_hint = '根据句子选择目标单词的完整中文释义。',
    example_id = candidates.example_id,
    correct_answer = candidates.definition_zh,
    translation_zh = candidates.definition_zh,
    is_active = true,
    is_context_hint = true,
    context_for_multiple_meaning =
      candidates.definition_en ~* ';\s*or\s+'
from context_candidates candidates
where candidates.question_id = question_row.id
  and candidates.sentence_en is not null;

-- Context choices are definitions, not competing English headwords.
update public.question_options option_row
set option_text = option_sense.definition_zh
from public.questions question_row,
     public.word_senses option_sense
where question_row.id = option_row.question_id
  and question_row.is_context_hint
  and option_sense.id = option_row.target_sense_id;

-- Any round created under the previous unrestricted random-selection rule is
-- abandoned. The next Start/Review click creates a correctly selected round.
update public.practice_sessions session_row
set status = 'abandoned',
    completed_at = coalesce(session_row.completed_at, now())
where session_row.status = 'started'
  and exists (
    select 1
    from public.practice_rounds round_row
    where round_row.session_id = session_row.id
      and round_row.status = 'started'
  );

update public.practice_rounds
set status = 'abandoned',
    completed_at = coalesce(completed_at, now())
where status = 'started';

create or replace function public.enforce_conditional_context_hint()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_wrong_count integer;
  v_use_context boolean;
  v_question_id uuid;
  v_correct_option_id uuid;
  v_option_ids uuid[];
begin
  select round_row.user_id
  into v_user_id
  from public.practice_rounds round_row
  where round_row.id = new.round_id;

  select coalesce(mastery.wrong_count, 0)
  into v_wrong_count
  from public.user_sense_mastery mastery
  where mastery.user_id = v_user_id
    and mastery.sense_id = new.sense_id;

  v_wrong_count := coalesce(v_wrong_count, 0);

  v_use_context :=
    v_wrong_count >= 3
    or exists (
      select 1
      from public.questions question_row
      where question_row.sense_id = new.sense_id
        and question_row.is_active
        and question_row.is_context_hint
        and question_row.context_for_multiple_meaning
    );

  select
    question_row.id,
    (array_agg(option_row.id) filter (where option_row.is_correct))[1],
    array_agg(option_row.id order by random())
  into
    v_question_id,
    v_correct_option_id,
    v_option_ids
  from public.questions question_row
  join public.question_options option_row
    on option_row.question_id = question_row.id
  where question_row.sense_id = new.sense_id
    and question_row.is_active
    and question_row.answer_form = 'option'
    and not question_row.human_review
    and not option_row.human_review
    and question_row.is_context_hint = v_use_context
  group by question_row.id
  having count(*) >= 2
     and count(*) filter (where option_row.is_correct) = 1
  order by random()
  limit 1;

  -- If a contextual hint has not been authored for a difficult word, safely
  -- fall back to a direct recognition question.
  if v_question_id is null and v_use_context then
    select
      question_row.id,
      (array_agg(option_row.id) filter (where option_row.is_correct))[1],
      array_agg(option_row.id order by random())
    into
      v_question_id,
      v_correct_option_id,
      v_option_ids
    from public.questions question_row
    join public.question_options option_row
      on option_row.question_id = question_row.id
    where question_row.sense_id = new.sense_id
      and question_row.is_active
      and question_row.answer_form = 'option'
      and not question_row.is_context_hint
      and not question_row.human_review
      and not option_row.human_review
    group by question_row.id
    having count(*) >= 2
       and count(*) filter (where option_row.is_correct) = 1
    order by random()
    limit 1;
  end if;

  if v_question_id is null then
    raise exception 'No eligible conditional practice question for sense %',
      new.sense_id;
  end if;

  new.question_id := v_question_id;
  new.correct_option_id := v_correct_option_id;
  new.option_ids := v_option_ids;
  return new;
end;
$$;

drop trigger if exists practice_round_question_context_hint
  on public.practice_round_questions;

create trigger practice_round_question_context_hint
before insert on public.practice_round_questions
for each row execute function public.enforce_conditional_context_hint();

revoke all on function public.enforce_conditional_context_hint()
  from public, anon, authenticated;

commit;

select
  count(*) filter (where is_context_hint) as context_hint_questions,
  count(*) filter (
    where is_context_hint and context_for_multiple_meaning
  ) as multiple_meaning_questions
from public.questions;


-- ============================================================================
-- Migration: 202606240013_simplify_english_meaning_stems.sql
-- ============================================================================

-- The prompt already says "Choose the word that matches the meaning."
-- Keep the large question text to the definition only.

begin;

update public.questions
set stem = regexp_replace(
  stem,
  '^Which word means:\s*(.*?)\?$',
  '\1',
  'i'
)
where stem ~* '^Which word means:\s*.*\?$';

commit;

select
  count(*) filter (
    where stem ~* '^Which word means:'
  ) as remaining_redundant_stems,
  count(*) filter (
    where prompt_hint in (
      'Choose the word that matches the meaning.',
      'Choose the word that matches the English meaning.'
    )
  ) as direct_english_meaning_questions
from public.questions;


-- ============================================================================
-- Migration: 202606240014_level_word_statuses.sql
-- ============================================================================

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


-- ============================================================================
-- Migration: 202606240015_level_round_weighted_scoring.sql
-- ============================================================================

-- KuaKua Duck: unified Level-round weighted scoring system.
--
-- What changes from the V1.0 round system (migration 009):
--   1. Adds answer_outcome_enum ('full_correct' | 'assisted_correct' |
--      'remediation_completed' | 'wrong') and outcome/scoring columns to
--      practice_round_questions. Backfills existing answered rows.
--   2. Updates save_practice_answer to write answer_outcome and score_points.
--   3. Updates complete_practice_round:
--      - Stars based on weighted accuracy: >=90%=3, >=80%=2, >=60%=1.
--      - Duck power = full_correct_count + floor(assisted_correct_count / 2).
--      - Updates best_star_rating on user_level_progress.
--      - Returns full breakdown (full_correct, assisted, remediation, wrong).
--
-- Backward-compatible: is_correct boolean and correct_count are preserved.
-- answer_outcome is the new authoritative grade; is_correct stays for joins
-- and legacy queries.

begin;

-- 1. Answer outcome enum ------------------------------------------------------

do $$
begin
  create type public.answer_outcome_enum as enum (
    'full_correct',
    'assisted_correct',
    'remediation_completed',
    'wrong'
  );
exception when duplicate_object then null;
end $$;

-- 2. New columns on practice_round_questions ----------------------------------

alter table public.practice_round_questions
  add column if not exists answer_outcome     public.answer_outcome_enum,
  add column if not exists question_type_key  text,
  add column if not exists answer_form        text,
  add column if not exists score_points       numeric(4,2),
  add column if not exists hint_used          boolean not null default false,
  add column if not exists attempt_count      smallint not null default 0,
  add column if not exists revealed_answer_at timestamptz,
  add column if not exists normalized_answer  text;

comment on column public.practice_round_questions.answer_outcome is
  'Authoritative grade: full_correct, assisted_correct, remediation_completed, or wrong.';
comment on column public.practice_round_questions.score_points is
  'Weighted score contribution: full_correct=1.0, assisted_correct=0.5, others=0.';
comment on column public.practice_round_questions.question_type_key is
  'Identifies question type: option_recognition, sentence_cloze_typing, etc.';
comment on column public.practice_round_questions.answer_form is
  'Input modality: option or keyboard.';

-- Backfill existing answered rows from is_correct.
update public.practice_round_questions
set answer_outcome    = case
      when is_correct = true  then 'full_correct'::public.answer_outcome_enum
      when is_correct = false then 'wrong'::public.answer_outcome_enum
      else null
    end,
    question_type_key = coalesce(question_type_key, 'option_recognition'),
    answer_form       = coalesce(answer_form, 'option'),
    score_points      = case when is_correct = true then 1.0 else 0.0 end
where answered_at is not null
  and answer_outcome is null;

-- 3. Updated save_practice_answer: writes answer_outcome ----------------------

create or replace function public.save_practice_answer(
  p_round_id         uuid,
  p_position         integer,
  p_answer           text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id          uuid := auth.uid();
  v_round            public.practice_rounds%rowtype;
  v_item             public.practice_round_questions%rowtype;
  v_is_correct       boolean;
  v_outcome          public.answer_outcome_enum;
  v_score_points     numeric(4,2);
  v_now              timestamptz := clock_timestamp();
  v_mastery          public.user_sense_mastery%rowtype;
  v_old_stage        smallint;
  v_new_stage        smallint;
  v_new_state        public.sense_learning_state_enum;
  v_due_advance      boolean := false;
  v_next_due         timestamptz;
  v_spaced_increment integer := 0;
  v_recent           boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  -- Idempotent: already answered.
  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position',          p_position,
      'answer_outcome',    v_item.answer_outcome,
      'is_correct',        v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'already_saved',     true
    );
  end if;

  -- V1.0: option questions only.
  if v_item.correct_option_id is null then
    raise exception 'V1.0 only supports server-graded option questions';
  end if;

  if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
    raise exception 'Answer must be an option UUID';
  end if;

  if not (p_answer::uuid = any(v_item.option_ids)) then
    raise exception 'Answer option does not belong to this question';
  end if;

  v_is_correct   := p_answer::uuid = v_item.correct_option_id;
  v_outcome      := case when v_is_correct
                         then 'full_correct'::public.answer_outcome_enum
                         else 'wrong'::public.answer_outcome_enum end;
  v_score_points := case when v_is_correct then 1.0 else 0.0 end;

  update public.practice_round_questions
  set answer_given      = p_answer,
      is_correct        = v_is_correct,
      answer_outcome    = v_outcome,
      question_type_key = coalesce(question_type_key, 'option_recognition'),
      answer_form       = coalesce(answer_form, 'option'),
      score_points      = v_score_points,
      response_time_ms  = p_response_time_ms,
      answered_at       = v_now
  where round_id = p_round_id and position = p_position;

  -- Upsert mastery row if first time seeing this sense.
  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, correct_count, wrong_count,
    consecutive_correct_count, recent_results, review_stage,
    first_seen_at, first_correct_at, last_seen_at, last_correct_at,
    next_due_at, updated_at
  )
  values (
    v_user_id, v_item.sense_id, 'new', 0, 0, 0, 0, '{}', 0,
    v_now, null, null, null, null, v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent    := public.append_recent_formal_result(v_mastery.recent_results, v_is_correct);

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due  := v_now + interval '10 minutes';
    elsif v_mastery.next_due_at is not null and v_now >= v_mastery.next_due_at then
      v_due_advance      := true;
      v_new_stage        := least(4, v_old_stage + 1);
      v_new_state        := case when v_new_stage >= 2 then 'reviewing' else 'learning' end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '10 minutes'
        when 2 then v_now + interval '1 day'
        when 3 then v_now + interval '7 days'
        when 4 then case when v_old_stage = 4
                         then v_now + interval '75 days'
                         else v_now + interval '30 days' end
        else v_now + interval '10 minutes'
      end;
    else
      v_new_stage := v_old_stage;
      v_new_state := case
        when v_mastery.learning_state = 'new'      then 'learning'
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        else v_mastery.learning_state
      end;
      v_next_due := v_mastery.next_due_at;
    end if;

    update public.user_sense_mastery
    set learning_state            = v_new_state,
        seen_count                = seen_count + 1,
        correct_count             = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results            = v_recent,
        spaced_success_count      = spaced_success_count + v_spaced_increment,
        review_stage              = v_new_stage,
        mastery_score             = least(0.99, v_new_stage::numeric / 5),
        first_seen_at             = coalesce(first_seen_at, v_now),
        first_correct_at          = coalesce(first_correct_at, v_now),
        last_seen_at              = v_now,
        last_correct_at           = v_now,
        next_due_at               = v_next_due,
        mastered_at               = null,
        updated_at                = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active            = false,
          resolved_at          = v_now,
          last_reviewed_at     = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at           = v_now
      where user_id = v_user_id and sense_id = v_item.sense_id and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1       then 0
      when v_old_stage  = 2       then 1
      when v_old_stage  = 3       then 2
      when v_old_stage in (4, 5)  then 3
      else 0
    end;
    v_new_state := case when v_new_stage = 0 then 'learning' else 'reviewing' end;
    v_next_due  := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state            = v_new_state,
        seen_count                = seen_count + 1,
        wrong_count               = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results            = v_recent,
        review_stage              = v_new_stage,
        mastery_score             = least(0.99, v_new_stage::numeric / 5),
        difficulty_level          = difficulty_level + 1,
        first_seen_at             = coalesce(first_seen_at, v_now),
        last_seen_at              = v_now,
        next_due_at               = v_next_due,
        mastered_at               = null,
        updated_at                = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id, sense_id, wrong_count, first_wrong_at, last_wrong_at,
      is_active, resolved_at, created_at, updated_at
    )
    values (
      v_user_id, v_item.sense_id, 1, v_now, v_now, true, null, v_now, v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count   = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        is_active     = true,
        resolved_at   = null,
        updated_at    = v_now;
  end if;

  insert into public.practice_answers (
    user_id, session_id, question_id, sense_id, skill_type,
    answer_given, is_correct, response_time_ms, answered_at
  )
  values (
    v_user_id, v_round.session_id, v_item.question_id, v_item.sense_id,
    'multiple_choice', p_answer, v_is_correct, p_response_time_ms, v_now
  )
  on conflict (session_id, question_id) do nothing;

  return jsonb_build_object(
    'position',          p_position,
    'answer_outcome',    v_outcome,
    'is_correct',        v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'already_saved',     false,
    'learning_state',    v_new_state,
    'review_stage',      v_new_stage,
    'next_due_at',       v_next_due
  );
end;
$$;

-- 4. Updated complete_practice_round: weighted scoring ------------------------
--
-- Scoring formula:
--   score_points = full_correct*1.0 + assisted_correct*0.5
--   weighted_accuracy = score_points / question_count
--   stars: >=90%=3, >=80%=2, >=60%=1, else 0
--   duck_power = full_correct_count + floor(assisted_correct_count / 2)

create or replace function public.complete_practice_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id           uuid := auth.uid();
  v_round             public.practice_rounds%rowtype;
  v_answered          integer;
  v_full_correct      integer;
  v_assisted_correct  integer;
  v_remediation       integer;
  v_wrong             integer;
  v_score_points      numeric(6,2);
  v_weighted_accuracy numeric(5,4);
  v_star_rating       integer;
  v_duck_power        integer;
  v_completed_level   boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status = 'completed' then
    -- Idempotent: re-compute from stored outcome columns.
    select
      count(*) filter (where answer_outcome = 'full_correct'),
      count(*) filter (where answer_outcome = 'assisted_correct'),
      count(*) filter (where answer_outcome = 'remediation_completed'),
      count(*) filter (where answer_outcome = 'wrong'),
      coalesce(sum(score_points), v_round.correct_count::numeric)
    into v_full_correct, v_assisted_correct, v_remediation, v_wrong, v_score_points
    from public.practice_round_questions
    where round_id = p_round_id;

    v_weighted_accuracy := v_score_points / nullif(v_round.question_count, 0);
    v_star_rating := case
      when v_weighted_accuracy >= 0.90 then 3
      when v_weighted_accuracy >= 0.80 then 2
      when v_weighted_accuracy >= 0.60 then 1
      else 0
    end;
    v_duck_power := v_full_correct + floor(v_assisted_correct::numeric / 2)::integer;

    return jsonb_build_object(
      'round_id',               v_round.id,
      'question_count',         v_round.question_count,
      'full_correct_count',     v_full_correct,
      'assisted_correct_count', v_assisted_correct,
      'remediation_count',      v_remediation,
      'wrong_count',            v_wrong,
      'weighted_accuracy',      v_weighted_accuracy,
      'star_rating',            v_star_rating,
      'duck_power_earned',      v_duck_power,
      'already_completed',      true,
      'level_completed', coalesce((
        select is_completed from public.user_level_progress
        where user_id = v_user_id and level_number = v_round.level_number
      ), false)
    );
  end if;

  select count(*) filter (where answered_at is not null)
  into v_answered
  from public.practice_round_questions
  where round_id = p_round_id;

  if v_answered <> v_round.question_count then
    raise exception 'All round questions must be answered before completion';
  end if;

  select
    count(*) filter (where answer_outcome = 'full_correct'),
    count(*) filter (where answer_outcome = 'assisted_correct'),
    count(*) filter (where answer_outcome = 'remediation_completed'),
    count(*) filter (where answer_outcome = 'wrong'),
    coalesce(sum(score_points), count(*) filter (where is_correct)::numeric)
  into v_full_correct, v_assisted_correct, v_remediation, v_wrong, v_score_points
  from public.practice_round_questions
  where round_id = p_round_id;

  v_weighted_accuracy := v_score_points / nullif(v_round.question_count, 0);
  v_star_rating := case
    when v_weighted_accuracy >= 0.90 then 3
    when v_weighted_accuracy >= 0.80 then 2
    when v_weighted_accuracy >= 0.60 then 1
    else 0
  end;
  v_duck_power := v_full_correct + floor(v_assisted_correct::numeric / 2)::integer;

  update public.practice_rounds
  set status        = 'completed',
      correct_count = v_full_correct,
      completed_at  = now()
  where id = p_round_id;

  update public.practice_sessions
  set status            = 'completed',
      completed_at      = now(),
      correct_count     = v_full_correct,
      total_count       = v_round.question_count,
      star_rating       = v_star_rating,
      base_power        = v_duck_power,
      duck_power_earned = v_duck_power
  where id = v_round.session_id;

  update public.profiles
  set duck_power = duck_power + v_duck_power
  where id = v_user_id;

  update public.user_level_progress
  set completed_session_count = completed_session_count + 1,
      best_star_rating        = greatest(best_star_rating, v_star_rating),
      updated_at              = now()
  where user_id = v_user_id and level_number = v_round.level_number;

  v_completed_level := public.refresh_level_completion(v_user_id, v_round.level_number);

  return jsonb_build_object(
    'round_id',               p_round_id,
    'question_count',         v_round.question_count,
    'full_correct_count',     v_full_correct,
    'assisted_correct_count', v_assisted_correct,
    'remediation_count',      v_remediation,
    'wrong_count',            v_wrong,
    'weighted_accuracy',      v_weighted_accuracy,
    'star_rating',            v_star_rating,
    'duck_power_earned',      v_duck_power,
    'already_completed',      false,
    'level_completed',        v_completed_level
  );
end;
$$;

commit;


-- ============================================================================
-- Migration: 202606250016_cloze_question_support.sql
-- ============================================================================

-- KuaKua Duck: cloze (sentence_cloze_typing) question support.
--
-- Extends the practice round system (migrations 009 + 015) to support
-- keyboard-input questions in addition to option-select questions.
--
-- What changes:
--   1. Adds question_type_key to questions table; backfills from answer_form.
--   2. Adds normalize_cloze_answer() helper function.
--   3. Updates save_practice_answer to grade keyboard answers by text
--      comparison (normalized lowercase), set has_active_recall_success on
--      cloze full_correct, and store normalized_answer.
--   4. Updates start_practice_round to:
--      - Include eligible cloze questions for seen senses (seen_count >= 1).
--      - Cap cloze at 40% of round (max 8 of 20 questions).
--      - Store and return answer_form + question_type_key per question.
--
-- Cloze question rules (V1):
--   - Brand-new word → option only.
--   - Seen/review word → option or cloze (server picks).
--   - Cloze max = floor(round_size * 0.40).
--   - Grading: normalized text equality = full_correct; else wrong.
--   - has_active_recall_success set to true on cloze full_correct.

begin;

-- 1. question_type_key on questions -----------------------------------------

update public.question_types
set category = 'new_word',
    name = 'sentence_cloze_typing',
    name_zh = '句子填空输入',
    answer_form = 'keyboard',
    skill_type = 'spelling',
    notes = 'Sentence blank with Chinese hint and staged memory retype'
where type_code = 3;

alter table public.questions
  add column if not exists question_type_key text;

-- Derive question_type_key for existing rows.
update public.questions
set question_type_key = case
  when type_code = 3 then 'sentence_cloze_typing'
  when answer_form::text = 'keyboard' then 'keyboard_recall'
  else 'option_recognition'
end
where question_type_key is null;

alter table public.practice_round_questions
  add column if not exists cumulative_response_time_ms integer not null default 0,
  add column if not exists near_meaning_count smallint not null default 0,
  add column if not exists duck_points numeric(4,2);

-- Migration 012's option-selection trigger predates keyboard rounds. Keep it
-- for option rows, but never let it replace a selected cloze snapshot.
drop trigger if exists practice_round_question_context_hint
  on public.practice_round_questions;
create trigger practice_round_question_context_hint
before insert on public.practice_round_questions
for each row
when (new.answer_form is distinct from 'keyboard')
execute function public.enforce_conditional_context_hint();

comment on column public.questions.question_type_key is
  'Identifies question type: option_recognition, sentence_cloze_typing, etc.';

-- 2. Cloze answer normalizer -------------------------------------------------

create or replace function public.normalize_cloze_answer(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(trim(regexp_replace(p_text, '\s+', ' ', 'g')))
$$;

-- 3. Updated save_practice_answer: option + keyboard support -----------------

create or replace function public.save_practice_answer(
  p_round_id         uuid,
  p_position         integer,
  p_answer           text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id             uuid := auth.uid();
  v_round               public.practice_rounds%rowtype;
  v_item                public.practice_round_questions%rowtype;
  v_q_answer_form       text;
  v_q_correct_answer    text;
  v_q_type_key          text;
  v_is_correct          boolean;
  v_outcome             public.answer_outcome_enum;
  v_score_points        numeric(4,2);
  v_normalized_answer   text;
  v_set_active_recall   boolean := false;
  v_now                 timestamptz := clock_timestamp();
  v_mastery             public.user_sense_mastery%rowtype;
  v_old_stage           smallint;
  v_new_stage           smallint;
  v_new_state           public.sense_learning_state_enum;
  v_due_advance         boolean := false;
  v_next_due            timestamptz;
  v_spaced_increment    integer := 0;
  v_recent              boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position',          p_position,
      'answer_outcome',    v_item.answer_outcome,
      'is_correct',        v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'correct_answer',    null,
      'already_saved',     true
    );
  end if;

  -- Load question metadata.
  select q.answer_form::text,
         q.correct_answer,
         coalesce(q.question_type_key, 'option_recognition')
  into v_q_answer_form, v_q_correct_answer, v_q_type_key
  from public.questions q
  where q.id = v_item.question_id;

  -- Grade the answer.
  if v_q_answer_form = 'option' then
    if v_item.correct_option_id is null then
      raise exception 'Option question missing correct_option_id';
    end if;
    if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
      raise exception 'Answer must be an option UUID';
    end if;
    if not (p_answer::uuid = any(v_item.option_ids)) then
      raise exception 'Answer option does not belong to this question';
    end if;
    v_is_correct := p_answer::uuid = v_item.correct_option_id;

  elsif v_q_answer_form = 'keyboard' then
    v_normalized_answer := public.normalize_cloze_answer(p_answer);
    v_is_correct        := v_normalized_answer = public.normalize_cloze_answer(v_q_correct_answer);
    -- Cloze correct on first attempt = active recall success.
    v_set_active_recall := v_is_correct and v_item.attempt_count = 0;

  else
    raise exception 'Unsupported answer_form: %', v_q_answer_form;
  end if;

  -- V1: single attempt per question → full_correct or wrong.
  -- assisted_correct and remediation_completed are placeholders for future multi-attempt flow.
  v_outcome      := case when v_is_correct
                         then 'full_correct'::public.answer_outcome_enum
                         else 'wrong'::public.answer_outcome_enum end;
  v_score_points := case when v_is_correct then 1.0 else 0.0 end;

  update public.practice_round_questions
  set answer_given      = p_answer,
      normalized_answer = v_normalized_answer,
      is_correct        = v_is_correct,
      answer_outcome    = v_outcome,
      question_type_key = v_q_type_key,
      answer_form       = v_q_answer_form,
      score_points      = v_score_points,
      attempt_count     = attempt_count + 1,
      response_time_ms  = p_response_time_ms,
      answered_at       = v_now
  where round_id = p_round_id and position = p_position;

  -- Upsert mastery base row.
  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, correct_count, wrong_count,
    consecutive_correct_count, recent_results, review_stage,
    first_seen_at, first_correct_at, last_seen_at, last_correct_at,
    next_due_at, updated_at
  )
  values (
    v_user_id, v_item.sense_id, 'new', 0, 0, 0, 0, '{}', 0,
    v_now, null, null, null, null, v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent    := public.append_recent_formal_result(v_mastery.recent_results, v_is_correct);

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due  := v_now + interval '10 minutes';
    elsif v_mastery.next_due_at is not null and v_now >= v_mastery.next_due_at then
      v_due_advance      := true;
      v_new_stage        := least(4, v_old_stage + 1);
      v_new_state        := case when v_new_stage >= 2 then 'reviewing' else 'learning' end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '10 minutes'
        when 2 then v_now + interval '1 day'
        when 3 then v_now + interval '7 days'
        when 4 then case when v_old_stage = 4
                         then v_now + interval '75 days'
                         else v_now + interval '30 days' end
        else v_now + interval '10 minutes'
      end;
    else
      v_new_stage := v_old_stage;
      v_new_state := case
        when v_mastery.learning_state = 'new'      then 'learning'
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        else v_mastery.learning_state
      end;
      v_next_due := v_mastery.next_due_at;
    end if;

    update public.user_sense_mastery
    set learning_state            = v_new_state,
        seen_count                = seen_count + 1,
        correct_count             = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results            = v_recent,
        spaced_success_count      = spaced_success_count + v_spaced_increment,
        review_stage              = v_new_stage,
        mastery_score             = least(0.99, v_new_stage::numeric / 5),
        has_active_recall_success = has_active_recall_success or v_set_active_recall,
        first_seen_at             = coalesce(first_seen_at, v_now),
        first_correct_at          = coalesce(first_correct_at, v_now),
        last_seen_at              = v_now,
        last_correct_at           = v_now,
        next_due_at               = v_next_due,
        mastered_at               = null,
        updated_at                = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active            = false,
          resolved_at          = v_now,
          last_reviewed_at     = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at           = v_now
      where user_id = v_user_id and sense_id = v_item.sense_id and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1       then 0
      when v_old_stage  = 2       then 1
      when v_old_stage  = 3       then 2
      when v_old_stage in (4, 5)  then 3
      else 0
    end;
    v_new_state := case when v_new_stage = 0 then 'learning' else 'reviewing' end;
    v_next_due  := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state            = v_new_state,
        seen_count                = seen_count + 1,
        wrong_count               = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results            = v_recent,
        review_stage              = v_new_stage,
        mastery_score             = least(0.99, v_new_stage::numeric / 5),
        difficulty_level          = difficulty_level + 1,
        first_seen_at             = coalesce(first_seen_at, v_now),
        last_seen_at              = v_now,
        next_due_at               = v_next_due,
        mastered_at               = null,
        updated_at                = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id, sense_id, wrong_count, first_wrong_at, last_wrong_at,
      is_active, resolved_at, created_at, updated_at
    )
    values (
      v_user_id, v_item.sense_id, 1, v_now, v_now, true, null, v_now, v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count   = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        is_active     = true,
        resolved_at   = null,
        updated_at    = v_now;
  end if;

  insert into public.practice_answers (
    user_id, session_id, question_id, sense_id, skill_type,
    answer_given, is_correct, response_time_ms, answered_at
  )
  values (
    v_user_id, v_round.session_id, v_item.question_id, v_item.sense_id,
    (
      case when v_q_answer_form = 'keyboard'
        then 'spelling'
        else 'multiple_choice'
      end
    )::public.learning_skill_enum,
    p_answer, v_is_correct, p_response_time_ms, v_now
  )
  on conflict (session_id, question_id) do nothing;

  return jsonb_build_object(
    'position',          p_position,
    'answer_outcome',    v_outcome,
    'is_correct',        v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'correct_answer',    case when v_q_answer_form = 'keyboard' then v_q_correct_answer else null end,
    'already_saved',     false,
    'learning_state',    v_new_state,
    'review_stage',      v_new_stage,
    'next_due_at',       v_next_due
  );
end;
$$;

-- 3b. Staged type-3 dispatcher ----------------------------------------------
--
-- Keep the terminal persistence/mastery implementation above under an
-- internal name. The public function below handles intermediate cloze states
-- and calls it exactly once when a formal outcome is reached.

alter function public.save_practice_answer(uuid, integer, text, integer)
  rename to finalize_practice_answer;

create or replace function public.save_practice_answer(
  p_round_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_item public.practice_round_questions%rowtype;
  v_question public.questions%rowtype;
  v_answer text := public.normalize_cloze_answer(coalesce(p_answer, ''));
  v_correct text;
  v_result jsonb;
  v_total_response integer;
  v_is_near boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;
  if not found or v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id and position = p_position
  for update;
  if not found then
    raise exception 'Question position not found';
  end if;

  select * into v_question
  from public.questions
  where id = v_item.question_id;

  -- Option questions retain the migration-015 behavior.
  if v_item.answer_form <> 'keyboard'
     or v_item.question_type_key <> 'sentence_cloze_typing' then
    return public.finalize_practice_answer(
      p_round_id, p_position, p_answer, p_response_time_ms
    );
  end if;

  if v_answer = '' then
    raise exception 'Answer must not be blank';
  end if;

  v_correct := public.normalize_cloze_answer(v_question.correct_answer);

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position', p_position,
      'action', 'completed',
      'answer_outcome', v_item.answer_outcome,
      'is_correct', v_item.is_correct,
      'attempt_count', least(v_item.attempt_count, 2),
      'revealed_answer', case when v_item.revealed_answer_at is not null
        then v_question.correct_answer else null end,
      'already_saved', true
    );
  end if;

  select exists (
    select 1
    from public.question_options qo
    where qo.question_id = v_item.question_id
      and not qo.is_correct
      and public.normalize_cloze_answer(qo.option_text) = v_answer
  )
  into v_is_near;

  if v_item.revealed_answer_at is null
     and v_answer <> v_correct
     and v_is_near then
    update public.practice_round_questions
    set near_meaning_count = near_meaning_count + 1,
        cumulative_response_time_ms =
          cumulative_response_time_ms + p_response_time_ms
    where round_id = p_round_id and position = p_position;

    return jsonb_build_object(
      'position', p_position,
      'action', 'near_meaning',
      'attempt_count', v_item.attempt_count,
      'feedback', '意思接近，但本题练的是本关目标词。',
      'already_saved', false
    );
  end if;

  if v_item.revealed_answer_at is null and v_answer <> v_correct then
    if v_item.attempt_count = 0 then
      update public.practice_round_questions
      set attempt_count = 1,
          hint_used = true,
          cumulative_response_time_ms =
            cumulative_response_time_ms + p_response_time_ms
      where round_id = p_round_id and position = p_position;

      return jsonb_build_object(
        'position', p_position,
        'action', 'retry_with_hint',
        'attempt_count', 1,
        'letter_count', char_length(v_question.correct_answer),
        'already_saved', false
      );
    end if;

    update public.practice_round_questions
    set attempt_count = 2,
        revealed_answer_at = clock_timestamp(),
        cumulative_response_time_ms =
          cumulative_response_time_ms + p_response_time_ms
    where round_id = p_round_id and position = p_position;

    return jsonb_build_object(
      'position', p_position,
      'action', 'reveal_answer',
      'attempt_count', 2,
      'revealed_answer', v_question.correct_answer,
      'already_saved', false
    );
  end if;

  v_total_response := v_item.cumulative_response_time_ms + p_response_time_ms;

  if v_item.revealed_answer_at is not null then
    -- Remediation never becomes a formal correct result. A correct memory
    -- retype is stored as remediation_completed after the formal wrong update.
    v_result := public.finalize_practice_answer(
      p_round_id,
      p_position,
      case when v_answer = v_correct then '__remediation__' else p_answer end,
      v_total_response
    );

    if v_answer = v_correct then
      update public.practice_round_questions
      set answer_given = p_answer,
          normalized_answer = v_answer,
          answer_outcome = 'remediation_completed',
          score_points = 0,
          duck_points = 0,
          attempt_count = 2,
          cumulative_response_time_ms = v_total_response
      where round_id = p_round_id and position = p_position;

      update public.practice_answers
      set answer_given = p_answer
      where session_id = v_round.session_id
        and question_id = v_item.question_id;

      return jsonb_build_object(
        'position', p_position,
        'action', 'completed',
        'answer_outcome', 'remediation_completed',
        'is_correct', false,
        'attempt_count', 2,
        'revealed_answer', v_question.correct_answer,
        'already_saved', false
      );
    end if;

    update public.practice_round_questions
    set attempt_count = 2,
        cumulative_response_time_ms = v_total_response
    where round_id = p_round_id and position = p_position;

    return v_result || jsonb_build_object(
      'action', 'completed',
      'attempt_count', 2,
      'revealed_answer', v_question.correct_answer
    );
  end if;

  -- Correct before reveal: first try is full; hint try is assisted.
  v_result := public.finalize_practice_answer(
    p_round_id, p_position, p_answer, v_total_response
  );

  if v_item.attempt_count = 1 then
    update public.practice_round_questions
    set answer_outcome = 'assisted_correct',
        score_points = 0.5,
        duck_points = 0.5,
        cumulative_response_time_ms = v_total_response
    where round_id = p_round_id and position = p_position;

    return v_result || jsonb_build_object(
      'action', 'completed',
      'answer_outcome', 'assisted_correct',
      'attempt_count', 1
    );
  end if;

  update public.practice_round_questions
  set cumulative_response_time_ms = v_total_response
  where round_id = p_round_id and position = p_position;

  return v_result || jsonb_build_object(
    'action', 'completed',
    'answer_outcome', 'full_correct',
    'attempt_count', 0
  );
end;
$$;

-- 4. Updated start_practice_round: option + eligible cloze questions ---------
--
-- Rules:
--   - New (unseen) senses: option questions only.
--   - Seen/review senses: eligible for cloze (server picks based on random).
--   - Cloze cap: at most floor(round_size * 0.40) = 8 of 20 questions.
--   - Eligible cloze: keyboard question exists AND sense seen_count >= 1.

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id       uuid := auth.uid();
  v_round_id      uuid;
  v_session_id    uuid;
  v_due_count     integer;
  v_max_new       integer;
  v_question_count integer;
  v_new_count     integer;
  v_review_count  integer;
  v_result        jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  -- Resume an already-started round for this level.
  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    -- Count global overdue senses to determine new-content cap.
    select count(*)
    into v_due_count
    from public.user_sense_mastery
    where user_id = v_user_id
      and next_due_at is not null
      and next_due_at <= now()
      and learning_state <> 'mastered';

    v_max_new := case
      when v_due_count > 20 then 0
      when v_due_count > 0  then 12
      else 20
    end;

    insert into public.practice_sessions (user_id, level_number, session_type, status)
    values (v_user_id, p_level_number, 'daily', 'started')
    returning id into v_session_id;

    insert into public.practice_rounds (user_id, level_number, session_id, question_count)
    values (v_user_id, p_level_number, v_session_id, 1)
    returning id into v_round_id;

    with eligible_option_questions as (
      -- Option (MCQ) questions: need >= 2 options, exactly 1 correct, reviewed.
      select
        q.id                  as question_id,
        q.sense_id,
        'option'              as answer_form,
        coalesce(q.question_type_key, 'option_recognition') as question_type_key,
        q.is_context_hint,
        q.context_for_multiple_meaning,
        (array_agg(qo.id) filter (where qo.is_correct))[1] as correct_option_id,
        array_agg(qo.id order by random())                   as option_ids
      from public.questions q
      join public.question_options qo on qo.question_id = q.id
      where q.is_active
        and q.answer_form = 'option'
        and q.sense_id is not null
        and not q.human_review
        and not qo.human_review
      group by q.id, q.sense_id, q.is_context_hint, q.context_for_multiple_meaning,
               q.question_type_key
      having count(*) >= 2 and count(*) filter (where qo.is_correct) = 1
    ),
    eligible_cloze_questions as (
      -- Cloze (keyboard) questions: no option rows required; correct_answer in questions table.
      select
        q.id                  as question_id,
        q.sense_id,
        'keyboard'            as answer_form,
        coalesce(q.question_type_key, 'sentence_cloze_typing') as question_type_key,
        q.is_context_hint,
        q.context_for_multiple_meaning,
        null::uuid            as correct_option_id,
        '{}'::uuid[]          as option_ids
      from public.questions q
      where q.is_active
        and q.type_code = 3
        and q.answer_form = 'keyboard'
        and q.question_type_key = 'sentence_cloze_typing'
        and q.sense_id is not null
        and not q.human_review
    ),
    eligible_questions as (
      select * from eligible_option_questions
      union all
      select * from eligible_cloze_questions
    ),
    candidate_sources as (
      -- Global overdue reviews always outrank new content.
      select
        usm.sense_id,
        case
          when ms.is_active and usm.next_due_at is not null
               and usm.next_due_at <= now() then 1
          else 2
        end                      as priority,
        usm.difficulty_level,
        usm.wrong_count,
        usm.next_due_at,
        false                    as is_new,
        usm.seen_count           as seen_count
      from public.user_sense_mastery usm
      left join public.mistake_senses ms
        on ms.user_id = v_user_id and ms.sense_id = usm.sense_id
      where usm.user_id = v_user_id
        and usm.next_due_at is not null
        and usm.next_due_at <= now()
        and usm.learning_state <> 'mastered'

      union all

      -- New + near-due senses from the selected level.
      select
        lsa.sense_id,
        case
          when usm.user_id is null                                   then 3
          when usm.next_due_at is not null
               and usm.next_due_at <= now() + interval '24 hours'   then 4
          else 5
        end,
        coalesce(usm.difficulty_level, 0),
        coalesce(usm.wrong_count, 0),
        coalesce(usm.next_due_at, 'infinity'::timestamptz),
        (usm.user_id is null),
        coalesce(usm.seen_count, 0)
      from public.level_sense_assignments lsa
      left join public.user_sense_mastery usm
        on usm.user_id = v_user_id and usm.sense_id = lsa.sense_id
      where lsa.level_number = p_level_number
        and lsa.placement_type = 'new'
    ),
    candidate_senses as (
      select distinct on (sense_id)
        sense_id, priority, difficulty_level, wrong_count, next_due_at,
        is_new, seen_count
      from candidate_sources
      order by sense_id, priority, next_due_at
    ),
    ranked as (
      select
        cs.sense_id,
        cs.priority,
        cs.difficulty_level,
        cs.wrong_count,
        cs.next_due_at,
        cs.is_new,
        cs.seen_count,
        row_number() over (
          partition by cs.is_new
          order by cs.priority, cs.next_due_at, cs.difficulty_level desc, random()
        ) as type_rank
      from candidate_senses cs
      where exists (
        select 1 from eligible_questions eq
        where eq.sense_id = cs.sense_id
          -- New senses must have an option question.
          and (not cs.is_new or eq.answer_form = 'option')
      )
    ),
    limited as (
      select *
      from ranked
      where not is_new or type_rank <= v_max_new
      order by priority, next_due_at, difficulty_level desc, random()
      limit 20
    ),
    chosen_raw as (
      -- For each sense, pick one question.
      -- New senses: option only.
      -- Seen senses: prefer cloze when eligible (seen_count >= 1), else option.
      -- Context hint selection logic preserved from migration 009.
      select
        l.sense_id,
        l.priority,
        l.is_new,
        l.seen_count,
        eq.question_id,
        eq.answer_form,
        eq.question_type_key,
        eq.correct_option_id,
        eq.option_ids,
        row_number() over (
          order by l.priority, l.next_due_at, l.difficulty_level desc, random()
        )::smallint as raw_position
      from limited l
      join lateral (
        select *
        from eligible_questions candidate
        where candidate.sense_id = l.sense_id
          -- New senses: option only.
          and (not l.is_new or candidate.answer_form = 'option')
          -- Cloze only for seen senses, capped before selection so rows beyond
          -- the cap fall back to option questions instead of disappearing.
          and (
            candidate.answer_form = 'option'
            or (l.seen_count >= 1 and l.type_rank <= 8)
          )
          -- Context hint eligibility.
          and (
            not candidate.is_context_hint
            or candidate.context_for_multiple_meaning
            or l.wrong_count >= 3
          )
        order by
          case
            when candidate.answer_form = 'keyboard'
             and l.seen_count >= 1
             and l.type_rank <= 8 then 0
            else 1
          end,
          -- Favour context hint when appropriate.
          case when candidate.is_context_hint
               and (candidate.context_for_multiple_meaning or l.wrong_count >= 3)
               then 0 else 1 end,
          random()
        limit 1
      ) eq on true
    ),
    cloze_numbered as (
      -- Number cloze rows so we can apply the 40% cap.
      select *,
        row_number() over (
          partition by case when answer_form = 'keyboard' then 'cloze' else 'option' end
          order by raw_position
        ) as form_rank
      from chosen_raw
    ),
    chosen as (
      -- Cloze was capped during per-sense selection; retain every chosen row.
      select
        sense_id, is_new, question_id, answer_form, question_type_key,
        correct_option_id, option_ids,
        row_number() over (
          order by raw_position
        )::smallint as position
      from cloze_numbered
    )
    insert into public.practice_round_questions (
      round_id, position, question_id, sense_id,
      question_skill, answer_form, question_type_key,
      option_ids, correct_option_id
    )
    select
      v_round_id,
      position,
      question_id,
      sense_id,
      case when answer_form = 'keyboard' then 'active_recall' else 'recognition' end,
      answer_form,
      question_type_key,
      option_ids,
      correct_option_id
    from chosen;

    select
      count(*),
      count(*) filter (
        where not exists (
          select 1 from public.user_sense_mastery usm
          where usm.user_id = v_user_id and usm.sense_id = prq.sense_id
        )
      )
    into v_question_count, v_new_count
    from public.practice_round_questions prq
    where prq.round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds  where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible reviewed questions for Level %', p_level_number;
    end if;

    v_review_count := v_question_count - v_new_count;

    update public.practice_rounds
    set question_count     = v_question_count,
        new_sense_count    = v_new_count,
        review_sense_count = v_review_count
    where id = v_round_id;
  end if;

  -- Build the response JSON.
  select jsonb_build_object(
    'round_id',          r.id,
    'level_number',      r.level_number,
    'status',            r.status,
    'question_count',    r.question_count,
    'new_sense_count',   r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position',         rq.position,
          'question_id',      q.id,
          'sense_id',         rq.sense_id,
          'stem',             q.stem,
          'prompt_hint',      q.prompt_hint,
          'translation_zh',   q.translation_zh,
          'question_skill',   rq.question_skill,
          'type_code',        q.type_code,
          'answer_form',      rq.answer_form,
          'question_type_key', rq.question_type_key,
          'expected_time_ms', q.expected_time_ms,
          'attempt_count',    rq.attempt_count,
          'hint_used',        rq.hint_used,
          'letter_count',     case
            when rq.hint_used then char_length(q.correct_answer)
            else null
          end,
          'revealed_answer',  case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
          'options',
            case when rq.answer_form = 'option' then (
              select jsonb_agg(
                jsonb_build_object(
                  'option_id',   opt.id,
                  'option_text', opt.option_text
                )
                order by ord.ordinality
              )
              from unnest(rq.option_ids) with ordinality ord(option_id, ordinality)
              join public.question_options opt on opt.id = ord.option_id
            ) else '[]'::jsonb end,
          'answer_given',  rq.answer_given,
          'is_answered',   rq.answered_at is not null
        )
        order by rq.position
      )
      from public.practice_round_questions rq
      join public.questions q on q.id = rq.question_id
      where rq.round_id = r.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.practice_rounds r
  where r.id = v_round_id and r.user_id = v_user_id;

  return v_result;
end;
$$;

-- 5. Security -----------------------------------------------------------------

revoke all on function public.normalize_cloze_answer(text) from public, anon, authenticated;
revoke all on function public.finalize_practice_answer(uuid, integer, text, integer)
  from public, anon, authenticated;
grant execute on function public.save_practice_answer(uuid, integer, text, integer)
  to authenticated;

commit;


-- ============================================================================
-- Migration: 202606250017_repair_practice_round_question_metadata.sql
-- ============================================================================

-- Repair legacy started-round snapshots created before answer_form and
-- question_type_key were populated on practice_round_questions.
--
-- start_practice_round resumes an existing started round. Without this repair,
-- its JSON contains explicit null values that cannot be decoded into the
-- Android client's non-null practice question model.

begin;

update public.practice_round_questions snapshot
set
  answer_form = coalesce(
    snapshot.answer_form,
    question_row.answer_form::text,
    case when question_row.type_code = 3 then 'keyboard' else 'option' end
  ),
  question_type_key = coalesce(
    snapshot.question_type_key,
    question_row.question_type_key,
    case
      when question_row.type_code = 3 then 'sentence_cloze_typing'
      when question_row.answer_form::text = 'keyboard' then 'keyboard_recall'
      else 'option_recognition'
    end
  )
from public.questions question_row
where question_row.id = snapshot.question_id
  and (
    snapshot.answer_form is null
    or snapshot.question_type_key is null
  );

alter table public.practice_round_questions
  alter column answer_form set default 'option',
  alter column answer_form set not null,
  alter column question_type_key set default 'option_recognition',
  alter column question_type_key set not null;

commit;


-- ============================================================================
-- Migration: 202606250018_remove_redundant_meaning_stem_prefix.sql
-- ============================================================================

-- Remove legacy wording duplicated by the prompt hint.
--
-- The UI already displays "Choose the word that matches the meaning." above
-- the stem, so "Which word means:" must not also appear in the stem. This is
-- intentionally idempotent because a later content import may reintroduce
-- legacy stems after the original cleanup migration has run.

begin;

update public.questions
set stem = trim(
  regexp_replace(
    stem,
    '^Which\s+word\s+means\s*:\s*',
    '',
    'i'
  )
)
where stem ~* '^Which\s+word\s+means\s*:';

commit;

select count(*) as remaining_redundant_meaning_stems
from public.questions
where stem ~* '^Which\s+word\s+means\s*:';


-- ============================================================================
-- Migration: 202606260019_eight_question_type_level_one_support.sql
-- ============================================================================

begin;

-- KuaKua Duck: reduced 8-question-type practice support.
--
-- This migration keeps the existing mastery/review pipeline intact. It adds a
-- Level 1 test package for the people/family words and broadens practice-round
-- assembly so reviewed words can be tested with all 8 reduced types.

insert into public.question_types (
  type_code, category, name, name_zh, answer_form, skill_type, notes
)
values
  (101, 'new_word',  'meaning_choice',          'meaning choice',          'option',   'meaning',         'Choose the English word that matches the meaning'),
  (102, 'new_word',  'sentence_cloze_typing',   'sentence cloze typing',   'keyboard', 'spelling',        'Type the target word in a sentence blank'),
  (103, 'listening', 'listening_choice',        'listening choice',        'option',   'listening',       'Choose the word heard in the prompt'),
  (104, 'listening', 'listening_fill',          'listening fill',          'keyboard', 'listening',       'Type the word heard in the prompt'),
  (105, 'speaking',  'speaking_repeat',         'speaking repeat',         'option',   'speaking',        'Repeat the word and self-check'),
  (106, 'speaking',  'open_speaking',           'open speaking',           'option',   'speaking',        'Use the word aloud and self-check'),
  (107, 'reading',   'word_form',               'word form',               'keyboard', 'reading',         'Type the target word/form'),
  (108, 'reading',   'reading_comprehension',   'reading comprehension',   'option',   'reading',         'Choose the word that completes the context')
on conflict (type_code) do update
set category = excluded.category,
    name = excluded.name,
    name_zh = excluded.name_zh,
    answer_form = excluded.answer_form,
    skill_type = excluded.skill_type,
    notes = excluded.notes;

-- Keep the newer key-based contract populated for seeded rows.
alter table public.questions
  add column if not exists question_type_key text;

with level_one_words as (
  select
    lsa.sense_id,
    ws.word_id,
    w.headword,
    ws.definition_en,
    ws.definition_zh,
    row_number() over (order by lsa.order_in_level, w.headword) as rn
  from public.level_sense_assignments lsa
  join public.word_senses ws on ws.id = lsa.sense_id
  join public.words w on w.id = ws.word_id
  where lsa.level_number = 1
    and lsa.placement_type = 'new'
),
seed_specs as (
  select * from (values
    (101, 'meaning_choice',        'option'::public.answer_form,   'new_word'::public.question_category,  'meaning'::public.learning_skill_enum,         12000),
    (102, 'sentence_cloze_typing', 'keyboard'::public.answer_form, 'new_word'::public.question_category,  'spelling'::public.learning_skill_enum,        18000),
    (103, 'listening_choice',      'option'::public.answer_form,   'listening'::public.question_category, 'listening'::public.learning_skill_enum,       12000),
    (104, 'listening_fill',        'keyboard'::public.answer_form, 'listening'::public.question_category, 'listening'::public.learning_skill_enum,       18000),
    (105, 'speaking_repeat',       'option'::public.answer_form,   'speaking'::public.question_category,  'speaking'::public.learning_skill_enum,        15000),
    (106, 'open_speaking',         'option'::public.answer_form,   'speaking'::public.question_category,  'speaking'::public.learning_skill_enum,        20000),
    (107, 'word_form',             'keyboard'::public.answer_form, 'reading'::public.question_category,   'reading'::public.learning_skill_enum,         18000),
    (108, 'reading_comprehension', 'option'::public.answer_form,   'reading'::public.question_category,   'reading'::public.learning_skill_enum,         15000)
  ) as spec(type_code, question_type_key, answer_form, category, skill_type, expected_time_ms)
),
seed_questions as (
  select
    lw.sense_id,
    lw.word_id,
    lw.headword,
    lw.definition_en,
    lw.definition_zh,
    spec.type_code,
    spec.question_type_key,
    spec.answer_form,
    spec.category,
    spec.skill_type,
    spec.expected_time_ms,
    case spec.question_type_key
      when 'meaning_choice' then
        'Which word means: ' || coalesce(nullif(lw.definition_zh, ''), lw.definition_en) || '?'
      when 'sentence_cloze_typing' then
        'Type the missing family word: ' || upper(substr(lw.headword, 1, 1)) ||
        repeat('_', greatest(char_length(lw.headword) - 1, 1)) || ' means "' || lw.definition_en || '".'
      when 'listening_choice' then
        'Listening demo: your tester says "' || lw.headword || '". Which word did you hear?'
      when 'listening_fill' then
        'Listening demo: your tester says the target word. Type the word you heard.'
      when 'speaking_repeat' then
        'Say this word aloud: "' || lw.headword || '". Then self-check your pronunciation.'
      when 'open_speaking' then
        'Say one short sentence aloud using "' || lw.headword || '". Then self-check.'
      when 'word_form' then
        'Type the family/people word that matches this meaning: ' || lw.definition_en || '.'
      when 'reading_comprehension' then
        'Choose the word that best fits this context: This people-and-family word means "' ||
        lw.definition_en || '".'
      else lw.headword
    end as stem,
    case spec.question_type_key
      when 'meaning_choice' then 'Choose the correct word.'
      when 'sentence_cloze_typing' then 'Fill the blank by typing the word.'
      when 'listening_choice' then 'Listen to the tester and choose.'
      when 'listening_fill' then 'Listen to the tester and type.'
      when 'speaking_repeat' then 'Repeat aloud, then self-check.'
      when 'open_speaking' then 'Speak aloud, then self-check.'
      when 'word_form' then 'Type the correct word/form.'
      when 'reading_comprehension' then 'Read the context and choose.'
      else 'Answer the question.'
    end as prompt_hint
  from level_one_words lw
  cross join seed_specs spec
)
insert into public.questions (
  sense_id, question_type_id, type_code, category, answer_form, word_id,
  stem, correct_answer, difficulty, is_active, generation_version, human_review,
  prompt_hint, translation_zh, expected_time_ms, question_type_key,
  is_context_hint, context_for_multiple_meaning
)
select
  sq.sense_id,
  sq.type_code,
  sq.type_code,
  sq.category,
  sq.answer_form,
  sq.word_id,
  sq.stem,
  sq.headword,
  4.0,
  true,
  'eight_type_level1_seed_v1',
  false,
  sq.prompt_hint,
  sq.definition_zh,
  sq.expected_time_ms,
  sq.question_type_key,
  false,
  false
from seed_questions sq
where not exists (
  select 1
  from public.questions existing
  where existing.sense_id = sq.sense_id
    and existing.question_type_key = sq.question_type_key
    and existing.generation_version = 'eight_type_level1_seed_v1'
);

-- Multiple-choice options for recognition/listening/speaking/reading types.
with level_one_words as (
  select
    lsa.sense_id,
    w.headword,
    row_number() over (order by lsa.order_in_level, w.headword) as rn
  from public.level_sense_assignments lsa
  join public.word_senses ws on ws.id = lsa.sense_id
  join public.words w on w.id = ws.word_id
  where lsa.level_number = 1
    and lsa.placement_type = 'new'
),
option_questions as (
  select
    q.id as question_id,
    q.sense_id,
    q.question_type_key,
    lw.headword,
    lw.rn
  from public.questions q
  join level_one_words lw on lw.sense_id = q.sense_id
  where q.generation_version = 'eight_type_level1_seed_v1'
    and q.answer_form = 'option'
)
insert into public.question_options (
  question_id, option_text, target_sense_id, is_correct, sort_order, human_review
)
select
  oq.question_id,
  oq.headword,
  oq.sense_id,
  true,
  1,
  false
from option_questions oq
where oq.question_type_key not in ('speaking_repeat', 'open_speaking')
  and not exists (
    select 1 from public.question_options existing
    where existing.question_id = oq.question_id and existing.sort_order = 1
  );

with level_one_words as (
  select
    lsa.sense_id,
    w.headword,
    row_number() over (order by lsa.order_in_level, w.headword) as rn
  from public.level_sense_assignments lsa
  join public.word_senses ws on ws.id = lsa.sense_id
  join public.words w on w.id = ws.word_id
  where lsa.level_number = 1
    and lsa.placement_type = 'new'
),
option_questions as (
  select
    q.id as question_id,
    q.sense_id,
    q.question_type_key,
    lw.rn
  from public.questions q
  join level_one_words lw on lw.sense_id = q.sense_id
  where q.generation_version = 'eight_type_level1_seed_v1'
    and q.answer_form = 'option'
    and q.question_type_key not in ('speaking_repeat', 'open_speaking')
),
distractors as (
  select
    oq.question_id,
    lw.sense_id,
    lw.headword,
    row_number() over (
      partition by oq.question_id
      order by ((lw.rn - oq.rn + 1000) % 1000), lw.rn
    ) as option_rank
  from option_questions oq
  join level_one_words lw on lw.sense_id <> oq.sense_id
)
insert into public.question_options (
  question_id, option_text, target_sense_id, is_correct, sort_order, human_review
)
select
  question_id,
  headword,
  sense_id,
  false,
  option_rank + 1,
  false
from distractors
where option_rank <= 3
  and not exists (
    select 1 from public.question_options existing
    where existing.question_id = distractors.question_id
      and existing.sort_order = distractors.option_rank + 1
  );

-- Speaking self-check options. The correct option is a tester/learner
-- confirmation so the question is runnable without speech-recognition infra.
with speaking_options as (
  select
    q.id as question_id,
    opt.option_text,
    opt.is_correct,
    opt.sort_order
  from public.questions q
  cross join (values
    ('I said it clearly.', true, 1),
    ('I need more practice.', false, 2),
    ('I skipped speaking.', false, 3),
    ('I am not sure.', false, 4)
  ) as opt(option_text, is_correct, sort_order)
  where q.generation_version = 'eight_type_level1_seed_v1'
    and q.question_type_key in ('speaking_repeat', 'open_speaking')
)
insert into public.question_options (
  question_id, option_text, is_correct, sort_order, human_review
)
select question_id, option_text, is_correct, sort_order, false
from speaking_options so
where not exists (
  select 1 from public.question_options existing
  where existing.question_id = so.question_id
    and existing.sort_order = so.sort_order
);

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id        uuid := auth.uid();
  v_round_id       uuid;
  v_session_id     uuid;
  v_due_count      integer;
  v_max_new        integer;
  v_question_count integer;
  v_new_count      integer;
  v_review_count   integer;
  v_result         jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    select count(*)
    into v_due_count
    from public.user_sense_mastery
    where user_id = v_user_id
      and next_due_at is not null
      and next_due_at <= now()
      and learning_state <> 'mastered';

    v_max_new := case
      when v_due_count > 20 then 0
      when v_due_count > 0  then 12
      else 20
    end;

    insert into public.practice_sessions (user_id, level_number, session_type, status)
    values (v_user_id, p_level_number, 'daily', 'started')
    returning id into v_session_id;

    insert into public.practice_rounds (user_id, level_number, session_id, question_count)
    values (v_user_id, p_level_number, v_session_id, 1)
    returning id into v_round_id;

    with eligible_option_questions as (
      select
        q.id as question_id,
        q.sense_id,
        'option' as answer_form,
        coalesce(q.question_type_key, 'option_recognition') as question_type_key,
        coalesce(q.is_context_hint, false) as is_context_hint,
        coalesce(q.context_for_multiple_meaning, false) as context_for_multiple_meaning,
        (array_agg(qo.id) filter (where qo.is_correct))[1] as correct_option_id,
        array_agg(qo.id order by random()) as option_ids
      from public.questions q
      join public.question_options qo on qo.question_id = q.id
      where q.is_active
        and q.answer_form = 'option'
        and q.sense_id is not null
        and not q.human_review
        and not qo.human_review
      group by q.id, q.sense_id, q.question_type_key, q.is_context_hint,
               q.context_for_multiple_meaning
      having count(*) >= 2 and count(*) filter (where qo.is_correct) = 1
    ),
    eligible_keyboard_questions as (
      select
        q.id as question_id,
        q.sense_id,
        'keyboard' as answer_form,
        coalesce(q.question_type_key, 'keyboard_recall') as question_type_key,
        coalesce(q.is_context_hint, false) as is_context_hint,
        coalesce(q.context_for_multiple_meaning, false) as context_for_multiple_meaning,
        null::uuid as correct_option_id,
        '{}'::uuid[] as option_ids
      from public.questions q
      where q.is_active
        and q.answer_form = 'keyboard'
        and q.sense_id is not null
        and not q.human_review
    ),
    eligible_questions as (
      select * from eligible_option_questions
      union all
      select * from eligible_keyboard_questions
    ),
    candidate_sources as (
      select
        usm.sense_id,
        case
          when ms.is_active and usm.next_due_at is not null
               and usm.next_due_at <= now() then 1
          else 2
        end as priority,
        usm.difficulty_level,
        usm.wrong_count,
        usm.next_due_at,
        false as is_new,
        usm.seen_count as seen_count
      from public.user_sense_mastery usm
      left join public.mistake_senses ms
        on ms.user_id = v_user_id and ms.sense_id = usm.sense_id
      where usm.user_id = v_user_id
        and usm.next_due_at is not null
        and usm.next_due_at <= now()
        and usm.learning_state <> 'mastered'

      union all

      select
        lsa.sense_id,
        case
          when usm.user_id is null then 3
          when usm.next_due_at is not null
               and usm.next_due_at <= now() + interval '24 hours' then 4
          else 5
        end,
        coalesce(usm.difficulty_level, 0),
        coalesce(usm.wrong_count, 0),
        coalesce(usm.next_due_at, 'infinity'::timestamptz),
        (usm.user_id is null),
        coalesce(usm.seen_count, 0)
      from public.level_sense_assignments lsa
      left join public.user_sense_mastery usm
        on usm.user_id = v_user_id and usm.sense_id = lsa.sense_id
      where lsa.level_number = p_level_number
        and lsa.placement_type = 'new'
    ),
    candidate_senses as (
      select distinct on (sense_id)
        sense_id, priority, difficulty_level, wrong_count, next_due_at,
        is_new, seen_count
      from candidate_sources
      order by sense_id, priority, next_due_at
    ),
    ranked as (
      select
        cs.sense_id,
        cs.priority,
        cs.difficulty_level,
        cs.wrong_count,
        cs.next_due_at,
        cs.is_new,
        cs.seen_count,
        row_number() over (
          partition by cs.is_new
          order by cs.priority, cs.next_due_at, cs.difficulty_level desc, random()
        ) as type_rank
      from candidate_senses cs
      where exists (
        select 1 from eligible_questions eq
        where eq.sense_id = cs.sense_id
      )
    ),
    limited as (
      select *
      from ranked
      where not is_new or type_rank <= v_max_new
      order by priority, next_due_at, difficulty_level desc, random()
      limit 20
    ),
    chosen_raw as (
      select
        l.sense_id,
        l.priority,
        l.is_new,
        l.seen_count,
        eq.question_id,
        eq.answer_form,
        eq.question_type_key,
        eq.correct_option_id,
        eq.option_ids,
        row_number() over (
          order by l.priority, l.next_due_at, l.difficulty_level desc, random()
        )::smallint as raw_position
      from limited l
      join lateral (
        select *
        from eligible_questions candidate
        where candidate.sense_id = l.sense_id
          and (
            not candidate.is_context_hint
            or candidate.context_for_multiple_meaning
            or l.wrong_count >= 3
          )
        order by
          case candidate.question_type_key
            when (array[
              'meaning_choice',
              'sentence_cloze_typing',
              'listening_choice',
              'listening_fill',
              'speaking_repeat',
              'open_speaking',
              'word_form',
              'reading_comprehension'
            ])[(((l.type_rank - 1) % 8) + 1)::integer] then 0
            else 1
          end,
          case when candidate.is_context_hint
               and (candidate.context_for_multiple_meaning or l.wrong_count >= 3)
               then 0 else 1 end,
          random()
        limit 1
      ) eq on true
    ),
    chosen as (
      select
        sense_id, is_new, question_id, answer_form, question_type_key,
        correct_option_id, option_ids,
        row_number() over (order by raw_position)::smallint as position
      from chosen_raw
    )
    insert into public.practice_round_questions (
      round_id, position, question_id, sense_id,
      question_skill, answer_form, question_type_key,
      option_ids, correct_option_id
    )
    select
      v_round_id,
      position,
      question_id,
      sense_id,
      case
        when question_type_key like 'listening_%' then 'listening'
        when question_type_key like 'speaking_%' then 'speaking'
        when answer_form = 'keyboard' then 'active_recall'
        else 'recognition'
      end,
      answer_form,
      question_type_key,
      option_ids,
      correct_option_id
    from chosen;

    select
      count(*),
      count(*) filter (
        where not exists (
          select 1 from public.user_sense_mastery usm
          where usm.user_id = v_user_id and usm.sense_id = prq.sense_id
        )
      )
    into v_question_count, v_new_count
    from public.practice_round_questions prq
    where prq.round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible reviewed questions for Level %', p_level_number;
    end if;

    v_review_count := v_question_count - v_new_count;

    update public.practice_rounds
    set question_count = v_question_count,
        new_sense_count = v_new_count,
        review_sense_count = v_review_count
    where id = v_round_id;
  end if;

  select jsonb_build_object(
    'round_id', r.id,
    'level_number', r.level_number,
    'status', r.status,
    'question_count', r.question_count,
    'new_sense_count', r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position', rq.position,
          'question_id', q.id,
          'sense_id', rq.sense_id,
          'stem', q.stem,
          'prompt_hint', q.prompt_hint,
          'translation_zh', q.translation_zh,
          'question_skill', rq.question_skill,
          'type_code', q.type_code,
          'answer_form', rq.answer_form,
          'question_type_key', rq.question_type_key,
          'expected_time_ms', q.expected_time_ms,
          'attempt_count', rq.attempt_count,
          'hint_used', rq.hint_used,
          'letter_count', case
            when rq.hint_used then char_length(q.correct_answer)
            else null
          end,
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
          'options',
            case when rq.answer_form = 'option' then (
              select jsonb_agg(
                jsonb_build_object(
                  'option_id', opt.id,
                  'option_text', opt.option_text
                )
                order by ord.ordinality
              )
              from unnest(rq.option_ids) with ordinality ord(option_id, ordinality)
              join public.question_options opt on opt.id = ord.option_id
            ) else '[]'::jsonb end,
          'answer_given', rq.answer_given,
          'is_answered', rq.answered_at is not null
        )
        order by rq.position
      )
      from public.practice_round_questions rq
      join public.questions q on q.id = rq.question_id
      where rq.round_id = r.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.practice_rounds r
  where r.id = v_round_id and r.user_id = v_user_id;

  return v_result;
end;
$$;

grant execute on function public.start_practice_round(integer) to authenticated;

commit;


-- ============================================================================
-- Migration: 202606260020_generated_practice_round_logic.sql
-- ============================================================================

begin;

-- KuaKua Duck: generated 20-slot practice rounds.
--
-- This migration keeps the Android RPC contract stable:
--   start_practice_round(level) -> round JSON
--   save_practice_answer(round, position, answer, ms) -> grading JSON
--   complete_practice_round(round) -> result JSON
--
-- The implementation changes the backend model to:
--   1. pick vocabulary by priority per slot;
--   2. pick a question type after the vocabulary is known;
--   3. generate and snapshot the delivered question at round start;
--   4. log formal attempts and update both sense and skill progress.

-- ---------------------------------------------------------------------------
-- Schema additions

alter table public.practice_round_questions
  add column if not exists source_bucket text,
  add column if not exists generated_payload jsonb not null default '{}'::jsonb,
  add column if not exists correct_answer_payload jsonb not null default '{}'::jsonb;

comment on column public.practice_round_questions.source_bucket is
  'Round-selection source: mistake, new, review, or fallback.';
comment on column public.practice_round_questions.generated_payload is
  'Immutable frontend payload generated for this round item.';
comment on column public.practice_round_questions.correct_answer_payload is
  'Immutable answer/options payload used for scoring/debugging.';

alter table public.user_sense_mastery
  add column if not exists last_wrong_at timestamptz,
  add column if not exists priority_boost integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.user_sense_mastery'::regclass
      and conname = 'user_sense_priority_boost_non_negative'
  ) then
    alter table public.user_sense_mastery
      add constraint user_sense_priority_boost_non_negative
      check (priority_boost >= 0);
  end if;
end $$;

create table if not exists public.question_attempts (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles(id) on delete cascade,
  round_id            uuid not null references public.practice_rounds(id) on delete cascade,
  session_id          uuid not null references public.practice_sessions(id) on delete cascade,
  position            smallint not null,
  question_id         uuid not null references public.questions(id),
  sense_id            uuid not null references public.word_senses(id) on delete cascade,
  word_id             uuid references public.words(id) on delete set null,
  question_type_key   text not null,
  skill_key           text not null,
  answer_form         text not null,
  presented_at        timestamptz not null,
  answered_at         timestamptz not null default now(),
  response_time_ms    integer not null,
  was_correct         boolean,
  answer_outcome      text not null,
  presented_payload   jsonb not null default '{}'::jsonb,
  answer_payload      jsonb not null default '{}'::jsonb,
  generator_version   text not null default 'generated_round_v1',
  scoring_version     text not null default 'sense_review_v2',

  unique (round_id, position),
  constraint question_attempts_response_time_non_negative check (response_time_ms >= 0),
  constraint question_attempts_skill_valid check (
    skill_key in ('meaning', 'spelling', 'listening', 'speaking', 'reading')
  )
);

create table if not exists public.user_skill_progress (
  user_id           uuid not null references public.profiles(id) on delete cascade,
  skill_key         text not null,
  total_attempts    integer not null default 0,
  correct_attempts  integer not null default 0,
  wrong_attempts    integer not null default 0,
  last_attempt_at   timestamptz,
  weakness_score    numeric(5,4) not null default 0,
  updated_at        timestamptz not null default now(),

  primary key (user_id, skill_key),
  constraint user_skill_progress_skill_valid check (
    skill_key in ('meaning', 'spelling', 'listening', 'speaking', 'reading')
  ),
  constraint user_skill_progress_counts_valid check (
    total_attempts >= 0
    and correct_attempts >= 0
    and wrong_attempts >= 0
    and correct_attempts + wrong_attempts <= total_attempts
  ),
  constraint user_skill_progress_weakness_range check (weakness_score between 0 and 1)
);

alter table public.question_attempts enable row level security;
alter table public.user_skill_progress enable row level security;

drop policy if exists question_attempts_own on public.question_attempts;
create policy question_attempts_own
on public.question_attempts for select to authenticated
using (user_id = auth.uid());

drop policy if exists user_skill_progress_own_select on public.user_skill_progress;
create policy user_skill_progress_own_select
on public.user_skill_progress for select to authenticated
using (user_id = auth.uid());

revoke all on public.question_attempts from anon, authenticated;
revoke all on public.user_skill_progress from anon, authenticated;
grant select on public.question_attempts, public.user_skill_progress to authenticated;

create index if not exists question_attempts_user_answered_idx
  on public.question_attempts (user_id, answered_at desc);
create index if not exists question_attempts_user_sense_answered_idx
  on public.question_attempts (user_id, sense_id, answered_at desc);
create index if not exists user_skill_progress_user_idx
  on public.user_skill_progress (user_id, skill_key);
create index if not exists user_sense_mastery_priority_boost_idx
  on public.user_sense_mastery (user_id, priority_boost desc, next_due_at);

-- Ensure the reduced 8 question type catalog exists for generated rows.
insert into public.question_types (
  type_code, category, name, name_zh, answer_form, skill_type, notes
)
values
  (101, 'new_word',  'meaning_choice',          'meaning choice',          'option',   'meaning',   'Choose the English word that matches the meaning'),
  (102, 'new_word',  'sentence_cloze_typing',   'sentence cloze typing',   'keyboard', 'spelling',  'Type the target word in a sentence blank'),
  (103, 'listening', 'listening_choice',        'listening choice',        'option',   'listening', 'Choose the word heard in the prompt'),
  (104, 'listening', 'listening_fill',          'listening fill',          'keyboard', 'listening', 'Type the word heard in the prompt'),
  (105, 'speaking',  'speaking_repeat',         'speaking repeat',         'option',   'speaking',  'Repeat the word and self-check'),
  (106, 'speaking',  'open_speaking',           'open speaking',           'option',   'speaking',  'Use the word aloud and self-check'),
  (107, 'reading',   'word_form',               'word form',               'keyboard', 'spelling',  'Type the target word/form'),
  (108, 'reading',   'reading_comprehension',   'reading comprehension',   'option',   'reading',   'Choose the word that completes the context')
on conflict (type_code) do update
set category = excluded.category,
    name = excluded.name,
    name_zh = excluded.name_zh,
    answer_form = excluded.answer_form,
    skill_type = excluded.skill_type,
    notes = excluded.notes;

-- ---------------------------------------------------------------------------
-- Helper methods

create or replace function public.practice_skill_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_question_type_key
    when 'meaning_choice' then 'meaning'
    when 'sentence_cloze_typing' then 'spelling'
    when 'listening_choice' then 'listening'
    when 'listening_fill' then 'listening'
    when 'speaking_repeat' then 'speaking'
    when 'open_speaking' then 'speaking'
    when 'word_form' then 'spelling'
    when 'reading_comprehension' then 'reading'
    else 'meaning'
  end;
$$;

create or replace function public.practice_skill_type_for_key(
  p_skill_key text
)
returns public.learning_skill_enum
language sql
immutable
set search_path = ''
as $$
  select case p_skill_key
    when 'meaning' then 'meaning'::public.learning_skill_enum
    when 'spelling' then 'spelling'::public.learning_skill_enum
    when 'listening' then 'listening'::public.learning_skill_enum
    when 'speaking' then 'speaking'::public.learning_skill_enum
    when 'reading' then 'reading'::public.learning_skill_enum
    else 'meaning'::public.learning_skill_enum
  end;
$$;

create or replace function public.practice_type_code_for_key(
  p_question_type_key text
)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_question_type_key
    when 'meaning_choice' then 101
    when 'sentence_cloze_typing' then 102
    when 'listening_choice' then 103
    when 'listening_fill' then 104
    when 'speaking_repeat' then 105
    when 'open_speaking' then 106
    when 'word_form' then 107
    when 'reading_comprehension' then 108
    else 101
  end;
$$;

create or replace function public.practice_answer_form_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_question_type_key
    when 'sentence_cloze_typing' then 'keyboard'
    when 'listening_fill' then 'keyboard'
    when 'word_form' then 'keyboard'
    else 'option'
  end;
$$;

create or replace function public.practice_question_skill_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_question_type_key like 'listening_%' then 'listening'
    when p_question_type_key like 'speaking_%' then 'speaking'
    when p_question_type_key in ('sentence_cloze_typing', 'word_form', 'listening_fill')
      then 'active_recall'
    else 'recognition'
  end;
$$;

create or replace function public.pick_practice_question_type(
  p_sense_id uuid,
  p_is_new boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_word_id uuid;
  v_types text[] := array['meaning_choice'];
begin
  if p_is_new then
    return 'meaning_choice';
  end if;

  select word_id into v_word_id
  from public.word_senses
  where id = p_sense_id;

  -- Meaning choice always works from word_senses + words.
  v_types := array['meaning_choice', 'speaking_repeat', 'open_speaking'];

  if exists (
    select 1 from public.examples
    where sense_id = p_sense_id
      and not human_review
      and char_length(btrim(sentence_en)) > 0
      and char_length(btrim(target_span)) > 0
  ) then
    v_types := v_types || array['sentence_cloze_typing', 'reading_comprehension'];
  end if;

  -- Android currently has no audio player in this flow. These generated
  -- listening prompts remain runnable by a family/tester reading the word aloud.
  if v_word_id is not null then
    v_types := v_types || array['listening_choice', 'listening_fill'];
  end if;

  if exists (
    select 1 from public.word_forms
    where word_id = v_word_id
      and not human_review
      and char_length(btrim(form_text)) > 0
  ) then
    v_types := v_types || array['word_form'];
  end if;

  return v_types[1 + floor(random() * array_length(v_types, 1))::integer];
end;
$$;

create or replace function public.pick_practice_distractor_senses(
  p_target_sense_id uuid,
  p_level_number integer,
  p_limit integer default 3
)
returns table(sense_id uuid, headword text)
language sql
stable
set search_path = ''
as $$
  with target as (
    select ws.id, ws.word_id, ws.part_of_speech
    from public.word_senses ws
    where ws.id = p_target_sense_id
  ),
  same_level as (
    select
      ws.id as sense_id,
      w.headword,
      1 as source_rank
    from public.level_sense_assignments lsa
    join public.word_senses ws on ws.id = lsa.sense_id
    join public.words w on w.id = ws.word_id
    cross join target t
    where lsa.level_number = p_level_number
      and lsa.placement_type = 'new'
      and ws.id <> t.id
      and ws.word_id <> t.word_id
      and ws.part_of_speech = t.part_of_speech
  ),
  nearby as (
    select
      ws.id as sense_id,
      w.headword,
      2 as source_rank
    from public.level_sense_assignments lsa
    join public.word_senses ws on ws.id = lsa.sense_id
    join public.words w on w.id = ws.word_id
    cross join target t
    where lsa.level_number between greatest(1, p_level_number - 2) and p_level_number + 2
      and lsa.placement_type = 'new'
      and ws.id <> t.id
      and ws.word_id <> t.word_id
  ),
  any_level as (
    select
      ws.id as sense_id,
      w.headword,
      3 as source_rank
    from public.word_senses ws
    join public.words w on w.id = ws.word_id
    cross join target t
    where ws.id <> t.id
      and ws.word_id <> t.word_id
  ),
  unioned as (
    select * from same_level
    union all
    select * from nearby
    union all
    select * from any_level
  ),
  deduped as (
    select distinct on (sense_id) sense_id, headword, source_rank
    from unioned
    order by sense_id, source_rank
  )
  select sense_id, headword
  from deduped
  order by source_rank, random()
  limit p_limit;
$$;

create or replace function public.generate_practice_question(
  p_sense_id uuid,
  p_level_number integer,
  p_question_type_key text
)
returns table(
  question_id uuid,
  option_ids uuid[],
  correct_option_id uuid,
  answer_form text,
  question_skill text,
  generated_payload jsonb,
  correct_answer_payload jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_word_id uuid;
  v_headword text;
  v_definition_en text;
  v_definition_zh text;
  v_type_code integer := public.practice_type_code_for_key(p_question_type_key);
  v_answer_form text := public.practice_answer_form_for_type(p_question_type_key);
  v_skill_key text := public.practice_skill_for_type(p_question_type_key);
  v_question_skill text := public.practice_question_skill_for_type(p_question_type_key);
  v_stem text;
  v_prompt_hint text;
  v_correct_answer text;
  v_translation_zh text;
  v_example public.examples%rowtype;
  v_form_text text;
  v_correct_option_id uuid;
  v_option_ids uuid[] := '{}';
  v_option_id uuid;
  v_option_sort integer := 1;
  v_distractor record;
  v_question_id uuid;
  v_generated_payload jsonb;
  v_correct_payload jsonb;
begin
  select ws.word_id, w.headword, ws.definition_en, ws.definition_zh
  into v_word_id, v_headword, v_definition_en, v_definition_zh
  from public.word_senses ws
  join public.words w on w.id = ws.word_id
  where ws.id = p_sense_id;

  if v_word_id is null then
    raise exception 'Sense % not found', p_sense_id;
  end if;

  v_translation_zh := coalesce(v_definition_zh, '');
  v_correct_answer := v_headword;

  if p_question_type_key in ('sentence_cloze_typing', 'reading_comprehension') then
    select * into v_example
    from public.examples e
    where e.sense_id = p_sense_id
      and not e.human_review
      and char_length(btrim(e.sentence_en)) > 0
    order by e.sort_order, e.created_at
    limit 1;
  end if;

  if p_question_type_key = 'word_form' then
    select form_text into v_form_text
    from public.word_forms
    where word_id = v_word_id
      and (sense_id = p_sense_id or sense_id is null)
      and not human_review
      and lower(form_text) <> lower(v_headword)
    order by case when sense_id = p_sense_id then 0 else 1 end, form_type, form_text
    limit 1;

    v_correct_answer := coalesce(v_form_text, v_headword);
  end if;

  v_prompt_hint := case p_question_type_key
    when 'meaning_choice' then 'Choose the correct word.'
    when 'sentence_cloze_typing' then 'Fill the blank by typing the word.'
    when 'listening_choice' then 'Listen to the tester and choose.'
    when 'listening_fill' then 'Listen to the tester and type.'
    when 'speaking_repeat' then 'Repeat aloud, then self-check.'
    when 'open_speaking' then 'Speak aloud, then self-check.'
    when 'word_form' then 'Type the correct word form.'
    when 'reading_comprehension' then 'Read the context and choose.'
    else 'Answer the question.'
  end;

  v_stem := case p_question_type_key
    when 'meaning_choice' then
      'Which word means: ' || coalesce(nullif(v_definition_zh, ''), v_definition_en) || '?'
    when 'sentence_cloze_typing' then
      case when v_example.id is not null then
        replace(v_example.sentence_en, v_example.target_span, '___')
      else
        'Type the word that means: ' || v_definition_en || '.'
      end
    when 'listening_choice' then
      'Listening demo: your tester says "' || v_headword || '". Which word did you hear?'
    when 'listening_fill' then
      'Listening demo: your tester says the target word. Type the word you heard.'
    when 'speaking_repeat' then
      'Say this word aloud: "' || v_headword || '". Then self-check your pronunciation.'
    when 'open_speaking' then
      'Say one short sentence aloud using "' || v_headword || '". Then self-check.'
    when 'word_form' then
      'Type the requested word form for "' || v_headword || '". Meaning: ' || v_definition_en || '.'
    when 'reading_comprehension' then
      case when v_example.id is not null then
        'Choose the word that completes this sentence: ' ||
        replace(v_example.sentence_en, v_example.target_span, '___')
      else
        'Choose the word that best fits this context: This word means "' || v_definition_en || '".'
      end
    else
      v_headword
  end;

  insert into public.questions (
    sense_id,
    question_type_id,
    type_code,
    category,
    answer_form,
    word_id,
    stem,
    correct_answer,
    difficulty,
    is_active,
    generation_version,
    human_review,
    prompt_hint,
    translation_zh,
    expected_time_ms,
    question_type_key,
    is_context_hint,
    context_for_multiple_meaning
  )
  values (
    p_sense_id,
    v_type_code,
    v_type_code,
    case
      when p_question_type_key like 'listening_%' then 'listening'::public.question_category
      when p_question_type_key like 'speaking_%' then 'speaking'::public.question_category
      when p_question_type_key in ('word_form', 'reading_comprehension') then 'reading'::public.question_category
      else 'new_word'::public.question_category
    end,
    v_answer_form::public.answer_form,
    v_word_id,
    v_stem,
    v_correct_answer,
    4.0,
    true,
    'generated_round_v1',
    false,
    v_prompt_hint,
    v_translation_zh,
    case v_answer_form when 'keyboard' then 18000 else 12000 end,
    p_question_type_key,
    false,
    false
  )
  returning id into v_question_id;

  if v_answer_form = 'option' then
    if p_question_type_key in ('speaking_repeat', 'open_speaking') then
      for v_distractor in
        select * from (values
          ('I said it clearly.', true),
          ('I need more practice.', false),
          ('I skipped speaking.', false),
          ('I am not sure.', false)
        ) as opt(option_text, is_correct)
      loop
        insert into public.question_options (
          question_id, option_text, target_sense_id, is_correct, sort_order, human_review
        )
        values (
          v_question_id,
          v_distractor.option_text,
          null,
          v_distractor.is_correct,
          v_option_sort,
          false
        )
        returning id into v_option_id;

        if v_distractor.is_correct then
          v_correct_option_id := v_option_id;
        end if;

        v_option_ids := v_option_ids || v_option_id;
        v_option_sort := v_option_sort + 1;
      end loop;
    else
      insert into public.question_options (
        question_id, option_text, target_sense_id, is_correct, sort_order, human_review
      )
      values (v_question_id, v_headword, p_sense_id, true, 1, false)
      returning id into v_correct_option_id;

      v_option_ids := v_option_ids || v_correct_option_id;
      v_option_sort := 2;

      for v_distractor in
        select * from public.pick_practice_distractor_senses(p_sense_id, p_level_number, 3)
      loop
        insert into public.question_options (
          question_id, option_text, target_sense_id, is_correct, sort_order, human_review
        )
        values (
          v_question_id,
          v_distractor.headword,
          v_distractor.sense_id,
          false,
          v_option_sort,
          false
        )
        returning id into v_option_id;

        v_option_ids := v_option_ids || v_option_id;
        v_option_sort := v_option_sort + 1;
      end loop;

      if array_length(v_option_ids, 1) < 4 then
        raise exception 'Not enough distractors for sense %', p_sense_id;
      end if;

      select array_agg(option_id order by random())
      into v_option_ids
      from unnest(v_option_ids) as option_id;
    end if;
  end if;

  v_generated_payload := jsonb_build_object(
    'question_type_key', p_question_type_key,
    'answer_form', v_answer_form,
    'skill_key', v_skill_key,
    'word_id', v_word_id,
    'sense_id', p_sense_id,
    'headword', v_headword,
    'stem', v_stem,
    'prompt_hint', v_prompt_hint,
    'translation_zh', v_translation_zh,
    'example_id', case when v_example.id is null then null else to_jsonb(v_example.id) end
  );

  v_correct_payload := jsonb_build_object(
    'correct_answer', v_correct_answer,
    'correct_option_id', v_correct_option_id,
    'option_ids', v_option_ids
  );

  return query select
    v_question_id,
    v_option_ids,
    v_correct_option_id,
    v_answer_form,
    v_question_skill,
    v_generated_payload,
    v_correct_payload;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public RPC: generated 20-slot round

create or replace function public.start_practice_round(
  p_level_number integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round_id uuid;
  v_session_id uuid;
  v_result jsonb;
  v_target_count integer := 20;
  v_position integer := 1;
  v_mistake_count integer := 0;
  v_new_count integer := 0;
  v_review_count integer := 0;
  v_fallback_count integer := 0;
  v_picked_senses uuid[] := '{}';
  v_candidate_sense_id uuid;
  v_candidate_source_bucket text;
  v_candidate_is_new boolean;
  v_generated record;
  v_question_type_key text;
  v_question_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.user_level_progress
    where user_id = v_user_id
      and level_number = p_level_number
      and is_unlocked
  ) then
    raise exception 'Level % is not unlocked', p_level_number;
  end if;

  select id into v_round_id
  from public.practice_rounds
  where user_id = v_user_id
    and level_number = p_level_number
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_round_id is null then
    insert into public.practice_sessions (user_id, level_number, session_type, status)
    values (v_user_id, p_level_number, 'daily', 'started')
    returning id into v_session_id;

    insert into public.practice_rounds (
      user_id, level_number, session_id, question_count
    )
    values (v_user_id, p_level_number, v_session_id, 1)
    returning id into v_round_id;

    while v_position <= v_target_count loop
      v_candidate_sense_id := null;
      v_candidate_source_bucket := null;
      v_candidate_is_new := false;

      if v_mistake_count < 10 then
        select
          usm.sense_id,
          'mistake'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        join public.mistake_senses ms
          on ms.user_id = usm.user_id
         and ms.sense_id = usm.sense_id
        where usm.user_id = v_user_id
          and ms.is_active
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (
            usm.next_due_at is null
            or usm.next_due_at <= now()
            or ms.next_due_at is null
            or ms.next_due_at <= now()
          )
        order by ms.last_wrong_at desc, ms.wrong_count desc, usm.next_due_at nulls first
        limit 1;
      end if;

      if v_candidate_sense_id is null and v_new_count < 7 then
        select
          lsa.sense_id,
          'new'::text as source_bucket,
          true as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and usm.user_id is null
          and not (lsa.sense_id = any(v_picked_senses))
        order by lsa.order_in_level
        limit 1;
      end if;

      if v_candidate_sense_id is null then
        select
          usm.sense_id,
          'review'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        left join public.level_sense_assignments lsa
          on lsa.sense_id = usm.sense_id
         and lsa.placement_type = 'new'
        where usm.user_id = v_user_id
          and usm.next_due_at is not null
          and usm.next_due_at <= now()
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (lsa.level_number is null or lsa.level_number <= p_level_number)
        order by usm.next_due_at, usm.priority_boost desc, usm.difficulty_level desc, random()
        limit 1;
      end if;

      if v_candidate_sense_id is null then
        select
          lsa.sense_id,
          'fallback'::text as source_bucket,
          (usm.user_id is null) as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and not (lsa.sense_id = any(v_picked_senses))
        order by
          case when usm.user_id is null then 1 else 0 end,
          coalesce(usm.priority_boost, 0) desc,
          coalesce(usm.difficulty_level, 0) desc,
          random()
        limit 1;
      end if;

      exit when v_candidate_sense_id is null;

      v_question_type_key := public.pick_practice_question_type(
        v_candidate_sense_id,
        v_candidate_is_new
      );

      begin
        select * into v_generated
        from public.generate_practice_question(
          v_candidate_sense_id,
          p_level_number,
          v_question_type_key
        );
      exception when others then
        -- If a richer generated type fails due to sparse assets, fall back to
        -- meaning choice for the same selected vocabulary.
        v_question_type_key := 'meaning_choice';
        select * into v_generated
        from public.generate_practice_question(
          v_candidate_sense_id,
          p_level_number,
          v_question_type_key
        );
      end;

      insert into public.practice_round_questions (
        round_id,
        position,
        question_id,
        sense_id,
        question_skill,
        answer_form,
        question_type_key,
        option_ids,
        correct_option_id,
        source_bucket,
        generated_payload,
        correct_answer_payload
      )
      values (
        v_round_id,
        v_position,
        v_generated.question_id,
        v_candidate_sense_id,
        v_generated.question_skill,
        v_generated.answer_form,
        v_question_type_key,
        coalesce(v_generated.option_ids, '{}'::uuid[]),
        v_generated.correct_option_id,
        v_candidate_source_bucket,
        v_generated.generated_payload,
        v_generated.correct_answer_payload
      );

      v_picked_senses := v_picked_senses || v_candidate_sense_id;
      v_position := v_position + 1;

      case v_candidate_source_bucket
        when 'mistake' then v_mistake_count := v_mistake_count + 1;
        when 'new' then v_new_count := v_new_count + 1;
        when 'review' then v_review_count := v_review_count + 1;
        else v_fallback_count := v_fallback_count + 1;
      end case;
    end loop;

    select count(*) into v_question_count
    from public.practice_round_questions
    where round_id = v_round_id;

    if v_question_count = 0 then
      delete from public.practice_rounds where id = v_round_id;
      delete from public.practice_sessions where id = v_session_id;
      raise exception 'No eligible practice vocabulary for Level %', p_level_number;
    end if;

    update public.practice_rounds
    set question_count = v_question_count,
        new_sense_count = v_new_count,
        review_sense_count = v_mistake_count + v_review_count + v_fallback_count
    where id = v_round_id;
  end if;

  select jsonb_build_object(
    'round_id', r.id,
    'level_number', r.level_number,
    'status', r.status,
    'question_count', r.question_count,
    'new_sense_count', r.new_sense_count,
    'review_sense_count', r.review_sense_count,
    'questions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'position', rq.position,
          'question_id', q.id,
          'sense_id', rq.sense_id,
          'stem', q.stem,
          'prompt_hint', q.prompt_hint,
          'translation_zh', q.translation_zh,
          'question_skill', rq.question_skill,
          'type_code', q.type_code,
          'answer_form', rq.answer_form,
          'question_type_key', rq.question_type_key,
          'expected_time_ms', q.expected_time_ms,
          'attempt_count', rq.attempt_count,
          'hint_used', rq.hint_used,
          'letter_count', case
            when rq.hint_used then char_length(q.correct_answer)
            else null
          end,
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
          'options',
            case when rq.answer_form = 'option' then (
              select jsonb_agg(
                jsonb_build_object(
                  'option_id', opt.id,
                  'option_text', opt.option_text
                )
                order by ord.ordinality
              )
              from unnest(rq.option_ids) with ordinality ord(option_id, ordinality)
              join public.question_options opt on opt.id = ord.option_id
            ) else '[]'::jsonb end,
          'answer_given', rq.answer_given,
          'is_answered', rq.answered_at is not null
        )
        order by rq.position
      )
      from public.practice_round_questions rq
      join public.questions q on q.id = rq.question_id
      where rq.round_id = r.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.practice_rounds r
  where r.id = v_round_id and r.user_id = v_user_id;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public answer flow: keep staged cloze behavior, but update the terminal
-- persistence function to log attempts and skill progress.

create or replace function public.finalize_practice_answer(
  p_round_id         uuid,
  p_position         integer,
  p_answer           text,
  p_response_time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id             uuid := auth.uid();
  v_round               public.practice_rounds%rowtype;
  v_item                public.practice_round_questions%rowtype;
  v_q_answer_form       text;
  v_q_correct_answer    text;
  v_q_type_key          text;
  v_q_word_id           uuid;
  v_skill_key           text;
  v_skill_type          public.learning_skill_enum;
  v_is_correct          boolean;
  v_outcome             public.answer_outcome_enum;
  v_score_points        numeric(4,2);
  v_normalized_answer   text;
  v_set_active_recall   boolean := false;
  v_now                 timestamptz := clock_timestamp();
  v_mastery             public.user_sense_mastery%rowtype;
  v_old_stage           smallint;
  v_new_stage           smallint;
  v_new_state           public.sense_learning_state_enum;
  v_due_advance         boolean := false;
  v_next_due            timestamptz;
  v_spaced_increment    integer := 0;
  v_recent              boolean[];
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_response_time_ms < 0 then
    raise exception 'response_time_ms must be non-negative';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id and user_id = v_user_id
  for update;

  if not found or v_round.status <> 'started' then
    raise exception 'Practice round is not active';
  end if;

  select * into v_item
  from public.practice_round_questions
  where round_id = p_round_id and position = p_position
  for update;

  if not found then
    raise exception 'Question position not found';
  end if;

  if v_item.answered_at is not null then
    return jsonb_build_object(
      'position', p_position,
      'answer_outcome', v_item.answer_outcome,
      'is_correct', v_item.is_correct,
      'correct_option_id', v_item.correct_option_id,
      'correct_answer', null,
      'already_saved', true
    );
  end if;

  select
    q.answer_form::text,
    q.correct_answer,
    coalesce(q.question_type_key, v_item.question_type_key),
    q.word_id
  into v_q_answer_form, v_q_correct_answer, v_q_type_key, v_q_word_id
  from public.questions q
  where q.id = v_item.question_id;

  v_q_answer_form := coalesce(v_item.answer_form, v_q_answer_form);
  v_q_type_key := coalesce(v_item.question_type_key, v_q_type_key, 'meaning_choice');
  v_skill_key := public.practice_skill_for_type(v_q_type_key);
  v_skill_type := public.practice_skill_type_for_key(v_skill_key);

  if v_q_answer_form = 'option' then
    if v_item.correct_option_id is null then
      raise exception 'Option question missing correct_option_id';
    end if;
    if not (p_answer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
      raise exception 'Answer must be an option UUID';
    end if;
    if not (p_answer::uuid = any(v_item.option_ids)) then
      raise exception 'Answer option does not belong to this question';
    end if;
    v_is_correct := p_answer::uuid = v_item.correct_option_id;
  elsif v_q_answer_form = 'keyboard' then
    v_normalized_answer := public.normalize_cloze_answer(p_answer);
    v_is_correct := v_normalized_answer = public.normalize_cloze_answer(v_q_correct_answer);
    v_set_active_recall := v_is_correct and v_item.attempt_count = 0;
  else
    raise exception 'Unsupported answer_form: %', v_q_answer_form;
  end if;

  v_outcome := case when v_is_correct
    then 'full_correct'::public.answer_outcome_enum
    else 'wrong'::public.answer_outcome_enum end;
  v_score_points := case when v_is_correct then 1.0 else 0.0 end;

  update public.practice_round_questions
  set answer_given = p_answer,
      normalized_answer = v_normalized_answer,
      is_correct = v_is_correct,
      answer_outcome = v_outcome,
      question_type_key = v_q_type_key,
      answer_form = v_q_answer_form,
      score_points = v_score_points,
      attempt_count = attempt_count + 1,
      response_time_ms = p_response_time_ms,
      answered_at = v_now
  where round_id = p_round_id and position = p_position;

  insert into public.user_sense_mastery (
    user_id, sense_id, learning_state, seen_count, correct_count, wrong_count,
    consecutive_correct_count, recent_results, review_stage,
    first_seen_at, first_correct_at, last_seen_at, last_correct_at,
    next_due_at, updated_at
  )
  values (
    v_user_id, v_item.sense_id, 'new', 0, 0, 0, 0, '{}', 0,
    v_now, null, null, null, null, v_now
  )
  on conflict (user_id, sense_id) do nothing;

  select * into v_mastery
  from public.user_sense_mastery
  where user_id = v_user_id and sense_id = v_item.sense_id
  for update;

  v_old_stage := v_mastery.review_stage;
  v_recent := public.append_recent_formal_result(v_mastery.recent_results, v_is_correct);

  if v_is_correct then
    if v_mastery.first_correct_at is null then
      v_new_stage := 1;
      v_new_state := 'learning';
      v_next_due := v_now + interval '1 day';
      v_spaced_increment := 1;
    elsif v_mastery.next_due_at is not null and v_now >= v_mastery.next_due_at then
      v_due_advance := true;
      v_new_stage := least(4, v_old_stage + 1);
      v_new_state := case when v_new_stage >= 4 then 'mastered' else 'reviewing' end;
      v_spaced_increment := 1;
      v_next_due := case v_new_stage
        when 1 then v_now + interval '1 day'
        when 2 then v_now + interval '7 days'
        when 3 then v_now + interval '30 days'
        when 4 then v_now + interval '90 days'
        else v_now + interval '1 day'
      end;
    else
      v_new_stage := greatest(v_old_stage, 1);
      v_new_state := case
        when v_mastery.learning_state = 'mastered' then 'reviewing'
        when v_mastery.learning_state = 'new' then 'learning'
        else v_mastery.learning_state
      end;
      v_next_due := coalesce(v_mastery.next_due_at, v_now + interval '1 day');
    end if;

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        correct_count = correct_count + 1,
        consecutive_correct_count = consecutive_correct_count + 1,
        recent_results = v_recent,
        spaced_success_count = spaced_success_count + v_spaced_increment,
        review_stage = v_new_stage,
        mastery_score = least(0.99, greatest(v_new_stage, 1)::numeric / 4),
        has_active_recall_success = has_active_recall_success or v_set_active_recall,
        priority_boost = greatest(0, priority_boost - 1),
        first_seen_at = coalesce(first_seen_at, v_now),
        first_correct_at = coalesce(first_correct_at, v_now),
        last_seen_at = v_now,
        last_correct_at = v_now,
        next_due_at = v_next_due,
        mastered_at = case when v_new_state = 'mastered' then v_now else null end,
        updated_at = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    if v_due_advance then
      update public.mistake_senses
      set is_active = false,
          resolved_at = v_now,
          last_reviewed_at = v_now,
          correct_review_count = correct_review_count + 1,
          updated_at = v_now
      where user_id = v_user_id and sense_id = v_item.sense_id and is_active;
    end if;
  else
    v_new_stage := case
      when v_old_stage <= 1 then 0
      when v_old_stage = 2 then 1
      when v_old_stage = 3 then 2
      else 3
    end;
    v_new_state := case when v_new_stage = 0 then 'learning' else 'reviewing' end;
    v_next_due := v_now + interval '10 minutes';

    update public.user_sense_mastery
    set learning_state = v_new_state,
        seen_count = seen_count + 1,
        wrong_count = wrong_count + 1,
        consecutive_correct_count = 0,
        recent_results = v_recent,
        review_stage = v_new_stage,
        mastery_score = least(0.99, v_new_stage::numeric / 4),
        difficulty_level = difficulty_level + 1,
        priority_boost = priority_boost + 2,
        first_seen_at = coalesce(first_seen_at, v_now),
        last_seen_at = v_now,
        last_wrong_at = v_now,
        next_due_at = v_next_due,
        mastered_at = null,
        updated_at = v_now
    where user_id = v_user_id and sense_id = v_item.sense_id;

    insert into public.mistake_senses (
      user_id, sense_id, wrong_count, first_wrong_at, last_wrong_at,
      is_active, resolved_at, next_due_at, created_at, updated_at
    )
    values (
      v_user_id, v_item.sense_id, 1, v_now, v_now, true, null,
      v_next_due, v_now, v_now
    )
    on conflict (user_id, sense_id) do update
    set wrong_count = public.mistake_senses.wrong_count + 1,
        last_wrong_at = v_now,
        next_due_at = v_next_due,
        is_active = true,
        resolved_at = null,
        updated_at = v_now;
  end if;

  insert into public.practice_answers (
    user_id, session_id, question_id, sense_id, skill_type,
    answer_given, is_correct, response_time_ms, answered_at
  )
  values (
    v_user_id, v_round.session_id, v_item.question_id, v_item.sense_id,
    v_skill_type, p_answer, v_is_correct, p_response_time_ms, v_now
  )
  on conflict (session_id, question_id) do nothing;

  insert into public.question_attempts (
    user_id, round_id, session_id, position, question_id, sense_id, word_id,
    question_type_key, skill_key, answer_form, presented_at, answered_at,
    response_time_ms, was_correct, answer_outcome, presented_payload,
    answer_payload
  )
  values (
    v_user_id, p_round_id, v_round.session_id, p_position, v_item.question_id,
    v_item.sense_id, v_q_word_id, v_q_type_key, v_skill_key, v_q_answer_form,
    v_round.started_at, v_now, p_response_time_ms, v_is_correct,
    v_outcome::text, v_item.generated_payload,
    v_item.correct_answer_payload || jsonb_build_object(
      'answer_given', p_answer,
      'normalized_answer', v_normalized_answer
    )
  )
  on conflict (round_id, position) do nothing;

  insert into public.user_skill_progress (
    user_id, skill_key, total_attempts, correct_attempts, wrong_attempts,
    last_attempt_at, weakness_score, updated_at
  )
  values (
    v_user_id, v_skill_key, 1,
    case when v_is_correct then 1 else 0 end,
    case when v_is_correct then 0 else 1 end,
    v_now,
    case when v_is_correct then 0 else 1 end,
    v_now
  )
  on conflict (user_id, skill_key) do update
  set total_attempts = public.user_skill_progress.total_attempts + 1,
      correct_attempts = public.user_skill_progress.correct_attempts
        + case when v_is_correct then 1 else 0 end,
      wrong_attempts = public.user_skill_progress.wrong_attempts
        + case when v_is_correct then 0 else 1 end,
      last_attempt_at = v_now,
      weakness_score = case
        when public.user_skill_progress.total_attempts + 1 = 0 then 0
        else (
          public.user_skill_progress.wrong_attempts
          + case when v_is_correct then 0 else 1 end
        )::numeric / (public.user_skill_progress.total_attempts + 1)
      end,
      updated_at = v_now;

  insert into public.user_sense_skill_progress (
    user_id, sense_id, skill_type, attempt_count, correct_count,
    last_attempt_at, mastery_score, updated_at
  )
  values (
    v_user_id, v_item.sense_id, v_skill_type, 1,
    case when v_is_correct then 1 else 0 end,
    v_now,
    case when v_is_correct then 1.0 else 0.0 end,
    v_now
  )
  on conflict (user_id, sense_id, skill_type) do update
  set attempt_count = public.user_sense_skill_progress.attempt_count + 1,
      correct_count = public.user_sense_skill_progress.correct_count
        + case when v_is_correct then 1 else 0 end,
      last_attempt_at = v_now,
      mastery_score = (
        public.user_sense_skill_progress.correct_count
        + case when v_is_correct then 1 else 0 end
      )::numeric / (public.user_sense_skill_progress.attempt_count + 1),
      updated_at = v_now;

  return jsonb_build_object(
    'position', p_position,
    'answer_outcome', v_outcome,
    'is_correct', v_is_correct,
    'correct_option_id', v_item.correct_option_id,
    'correct_answer', case when v_q_answer_form = 'keyboard' then v_q_correct_answer else null end,
    'already_saved', false,
    'learning_state', v_new_state,
    'review_stage', v_new_stage,
    'next_due_at', v_next_due
  );
end;
$$;

revoke all on function public.practice_skill_for_type(text) from public, anon, authenticated;
revoke all on function public.practice_skill_type_for_key(text) from public, anon, authenticated;
revoke all on function public.practice_type_code_for_key(text) from public, anon, authenticated;
revoke all on function public.practice_answer_form_for_type(text) from public, anon, authenticated;
revoke all on function public.practice_question_skill_for_type(text) from public, anon, authenticated;
revoke all on function public.pick_practice_question_type(uuid, boolean) from public, anon, authenticated;
revoke all on function public.pick_practice_distractor_senses(uuid, integer, integer) from public, anon, authenticated;
revoke all on function public.generate_practice_question(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.finalize_practice_answer(uuid, integer, text, integer)
  from public, anon, authenticated;

grant execute on function public.start_practice_round(integer) to authenticated;
grant execute on function public.save_practice_answer(uuid, integer, text, integer)
  to authenticated;
grant execute on function public.complete_practice_round(uuid) to authenticated;

commit;


-- ============================================================================
-- Migration: 202606290021_fix_level1_sense_target.sql
-- ============================================================================

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


-- ============================================================================
-- Migration: 202606290022_backfill_round_question_type_key.sql
-- ============================================================================

-- KuaKua Duck: repair stale practice_round_questions.question_type_key values.
--
-- Problem: migration 017 (run before migrations 019/020 introduced real
-- per-type keys like 'listening_choice') backfilled any null
-- question_type_key to the literal string 'option_recognition' and made the
-- column NOT NULL. Any round still in status='started' from that era is
-- stuck with that literal wrong value -- not null, so a "fill nulls" repair
-- does not touch it. start_practice_round resumes an existing started round
-- rather than regenerating it, so the Android client keeps rendering these
-- as plain "单词选义" MCQ with no listening/speaking/word_form panel or TTS
-- replay button, no matter what the generator or the Android resolver does
-- for *new* rounds.
--
-- Fix: overwrite practice_round_questions.question_type_key (and
-- answer_form) whenever it disagrees with the parent questions row, not just
-- when it's null. Safe to re-run.

begin;

update public.practice_round_questions rq
set question_type_key = q.question_type_key,
    answer_form        = q.answer_form::text
from public.questions q
where rq.question_id = q.id
  and q.question_type_key is not null
  and rq.question_type_key is distinct from q.question_type_key;

commit;


-- ============================================================================
-- Migration: 202607020023_add_listening_audio_text_to_round_payload.sql
-- ============================================================================

-- KuaKua Duck: expose the generated listening target to the client TTS layer.
--
-- Listening questions intentionally render the target word as audio, not as
-- visible text. The generated target is already stored on each round question;
-- this migration includes it in the start_practice_round JSON as audio_text so
-- the app does not fall back to speaking the instruction stem.

do $$
declare
  v_original text;
  v_updated text;
begin
  select pg_get_functiondef('public.start_practice_round(integer)'::regprocedure)
  into v_original;

  v_updated := replace(
    v_original,
$old$
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
$old$,
$new$
          'revealed_answer', case
            when rq.revealed_answer_at is not null then q.correct_answer
            else null
          end,
          'audio_text', case
            when rq.question_type_key like 'listening_%' then
              coalesce(
                rq.generated_payload ->> 'headword',
                rq.generated_payload ->> 'correct_answer',
                rq.correct_answer_payload ->> 'correct_answer'
              )
            else null
          end,
$new$
  );

  if v_updated = v_original then
    raise exception 'Could not patch public.start_practice_round(integer) with audio_text';
  end if;

  execute v_updated;
end;
$$;


-- ============================================================================
-- Migration: 202607050024_streak_props_and_protection.sql
-- ============================================================================

-- Persist 我的道具 (streak protection / challenge key) and let a missed day
-- auto-consume 连胜保护 instead of resetting the streak.

begin;

create table public.user_props (
  user_id uuid not null references public.profiles(id) on delete cascade,
  prop_type text not null check (prop_type in ('streak_protection', 'challenge_key')),
  count integer not null default 0 check (count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, prop_type)
);

alter table public.user_props enable row level security;

create policy user_props_select_own
on public.user_props
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.grant_prop(
  p_prop_type text,
  p_count integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_new_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if p_prop_type not in ('streak_protection', 'challenge_key') then
    raise exception 'Invalid prop_type: %', p_prop_type;
  end if;
  if p_count <= 0 then
    raise exception 'p_count must be positive';
  end if;

  insert into public.user_props (user_id, prop_type, count, updated_at)
  values (v_user_id, p_prop_type, p_count, now())
  on conflict (user_id, prop_type)
  do update set count = public.user_props.count + excluded.count,
                updated_at = now()
  returning count into v_new_count;

  return jsonb_build_object('prop_type', p_prop_type, 'count', v_new_count);
end;
$$;

revoke all on function public.grant_prop(text, integer) from public, anon;
grant execute on function public.grant_prop(text, integer) to authenticated;

-- Recreate complete_practice_round: same behavior, plus a one-day-gap
-- streak-protection consumption so 连胜保护 actually does something.
create or replace function public.complete_practice_round(
  p_round_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.practice_rounds%rowtype;
  v_profile public.profiles%rowtype;
  v_answered integer;
  v_correct integer;
  v_completed_level boolean;
  v_today date;
  v_new_streak integer;
  v_protection_consumed boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.practice_rounds
  where id = p_round_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Practice round not found';
  end if;

  if v_round.status = 'completed' then
    return jsonb_build_object(
      'round_id', v_round.id,
      'correct_count', v_round.correct_count,
      'question_count', v_round.question_count,
      'star_rating', case
        when v_round.correct_count = v_round.question_count then 3
        when v_round.correct_count::numeric / v_round.question_count >= 0.80 then 2
        when v_round.correct_count::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      'duck_power_earned', v_round.correct_count,
      'already_completed', true,
      'level_completed', (
        select is_completed
        from public.user_level_progress
        where user_id = v_user_id
          and level_number = v_round.level_number
      )
    );
  end if;

  select
    count(*) filter (where answered_at is not null),
    count(*) filter (where is_correct)
  into v_answered, v_correct
  from public.practice_round_questions
  where round_id = p_round_id;

  if v_answered <> v_round.question_count then
    raise exception 'All round questions must be answered before completion';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  select timezone(
    coalesce(settings_row.reminder_timezone, 'UTC'),
    now()
  )::date
  into v_today
  from public.user_settings settings_row
  where settings_row.user_id = v_user_id;

  if v_today is null then
    v_today := (now() at time zone 'UTC')::date;
  end if;

  if v_profile.last_practice_date = v_today then
    v_new_streak := v_profile.current_streak_days;
  elsif v_profile.last_practice_date = v_today - 1 then
    v_new_streak := v_profile.current_streak_days + 1;
  elsif v_profile.last_practice_date = v_today - 2 then
    update public.user_props
    set count = count - 1,
        updated_at = now()
    where user_id = v_user_id
      and prop_type = 'streak_protection'
      and count > 0
    returning true into v_protection_consumed;

    v_new_streak := case
      when v_protection_consumed then v_profile.current_streak_days + 1
      else 1
    end;
  else
    v_new_streak := 1;
  end if;

  update public.practice_rounds
  set status = 'completed',
      correct_count = v_correct,
      completed_at = now()
  where id = p_round_id;

  update public.practice_sessions
  set status = 'completed',
      completed_at = now(),
      correct_count = v_correct,
      total_count = v_round.question_count,
      star_rating = case
        when v_correct = v_round.question_count then 3
        when v_correct::numeric / v_round.question_count >= 0.80 then 2
        when v_correct::numeric / v_round.question_count >= 0.60 then 1
        else 0
      end,
      base_power = v_correct,
      duck_power_earned = v_correct
  where id = v_round.session_id;

  update public.profiles
  set duck_power = v_profile.duck_power + v_correct,
      current_streak_days = v_new_streak,
      longest_streak_days = greatest(v_profile.longest_streak_days, v_new_streak),
      last_practice_date = v_today
  where id = v_user_id;

  update public.user_level_progress
  set progress = greatest(
        progress,
        case
          when v_round.question_count > 0
            then v_correct::numeric / v_round.question_count
          else 0
        end
      ),
      best_star_rating = greatest(
        best_star_rating,
        case
          when v_correct = v_round.question_count then 3
          when v_correct::numeric / v_round.question_count >= 0.80 then 2
          when v_correct::numeric / v_round.question_count >= 0.60 then 1
          else 0
        end
      ),
      completed_session_count = completed_session_count + 1,
      updated_at = now()
  where user_id = v_user_id
    and level_number = v_round.level_number;

  v_completed_level := public.refresh_level_completion(
    v_user_id,
    v_round.level_number
  );

  return jsonb_build_object(
    'round_id', p_round_id,
    'correct_count', v_correct,
    'question_count', v_round.question_count,
    'star_rating', case
      when v_correct = v_round.question_count then 3
      when v_correct::numeric / v_round.question_count >= 0.80 then 2
      when v_correct::numeric / v_round.question_count >= 0.60 then 1
      else 0
    end,
    'duck_power_earned', v_correct,
    'already_completed', false,
    'level_completed', v_completed_level,
    'streak_protection_consumed', v_protection_consumed
  );
end;
$$;

revoke all on function public.complete_practice_round(uuid) from public, anon;
grant execute on function public.complete_practice_round(uuid) to authenticated;

commit;


-- ============================================================================
-- Migration: 202607060025_combo_scope_practice_type_selection.sql
-- ============================================================================

-- Phase 1 combo scope practice type policy.
--
-- Levels 1-5 remain the deep eight-type learning slice.
-- Levels 6-54 use a lighter generated set that only depends on core word,
-- definition/translation, and headword data.

create or replace function public.pick_practice_question_type(
  p_sense_id uuid,
  p_is_new boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_word_id uuid;
  v_level_number integer;
  v_types text[] := array['meaning_choice'];
begin
  select word_id into v_word_id
  from public.word_senses
  where id = p_sense_id;

  select min(level_number)
  into v_level_number
  from public.level_sense_assignments
  where sense_id = p_sense_id
    and placement_type = 'new';

  -- First exposure introduces the word by meaning before richer review.
  if p_is_new then
    return 'meaning_choice';
  end if;

  if coalesce(v_level_number, 999) between 1 and 5 then
    v_types := array['meaning_choice', 'speaking_repeat', 'open_speaking'];

    if exists (
      select 1 from public.examples
      where sense_id = p_sense_id
        and not human_review
        and char_length(btrim(sentence_en)) > 0
        and char_length(btrim(target_span)) > 0
    ) then
      v_types := v_types || array['sentence_cloze_typing', 'reading_comprehension'];
    end if;

    if v_word_id is not null then
      v_types := v_types || array['listening_choice', 'listening_fill'];
    end if;

    if exists (
      select 1 from public.word_forms
      where word_id = v_word_id
        and not human_review
        and char_length(btrim(form_text)) > 0
    ) then
      v_types := v_types || array['word_form'];
    end if;
  else
    -- Lightweight Band 4 path: no authored example, collocation, or word-form
    -- dependency. sentence_cloze_typing falls back to a definition prompt in
    -- generate_practice_question when no example exists.
    v_types := array['meaning_choice', 'sentence_cloze_typing', 'speaking_repeat'];

    if v_word_id is not null then
      v_types := v_types || array['listening_choice', 'listening_fill'];
    end if;
  end if;

  return v_types[1 + floor(random() * array_length(v_types, 1))::integer];
end;
$$;

revoke all on function public.pick_practice_question_type(uuid, boolean) from public, anon, authenticated;
grant execute on function public.pick_practice_question_type(uuid, boolean) to authenticated;



-- ============================================================================
-- Migration: 202607060026_band_upgrade_exam_core.sql
-- ============================================================================

-- Core Band upgrade exam backend for Phase 1.
--
-- Implements the Band 4.0 -> 4.5 prototype path with generic source/target
-- band arguments so later bands can reuse the same RPCs when content exists.

create table if not exists public.band_upgrade_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_band numeric(2,1) not null references public.bands(band_score),
  target_band numeric(2,1) not null references public.bands(band_score),
  status text not null default 'started',
  question_count smallint not null default 40,
  correct_count smallint,
  accuracy numeric(5,2),
  passed boolean,
  category_counts jsonb not null default '{}'::jsonb,
  attempt_version text not null default 'phase1_band_upgrade_v1',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint band_upgrade_attempt_status_valid
    check (status in ('started', 'completed', 'abandoned')),
  constraint band_upgrade_attempt_question_count_valid
    check (question_count = 40),
  constraint band_upgrade_attempt_correct_count_valid
    check (correct_count is null or correct_count between 0 and question_count),
  constraint band_upgrade_attempt_accuracy_valid
    check (accuracy is null or accuracy between 0 and 100),
  constraint band_upgrade_attempt_band_step_valid
    check (target_band = source_band + 0.5)
);

create unique index if not exists band_upgrade_one_started_per_target
  on public.band_upgrade_attempts (user_id, target_band)
  where status = 'started';

create table if not exists public.band_upgrade_attempt_questions (
  attempt_id uuid not null references public.band_upgrade_attempts(id) on delete cascade,
  position smallint not null,
  question_id uuid not null references public.questions(id),
  sense_id uuid not null references public.word_senses(id),
  question_type_key text not null,
  category text not null,
  answer_form text not null,
  option_ids uuid[] not null default '{}',
  correct_option_id uuid,
  generated_payload jsonb not null default '{}'::jsonb,
  correct_answer_payload jsonb not null default '{}'::jsonb,
  answer_given text,
  is_correct boolean,
  response_time_ms integer,
  answered_at timestamptz,
  created_at timestamptz not null default now(),

  primary key (attempt_id, position),
  constraint band_upgrade_position_valid check (position between 1 and 40),
  constraint band_upgrade_category_valid
    check (category in ('meaning', 'listening', 'spelling', 'speaking')),
  constraint band_upgrade_answer_time_valid
    check (response_time_ms is null or response_time_ms >= 0)
);

create index if not exists band_upgrade_attempt_questions_question_idx
  on public.band_upgrade_attempt_questions (question_id);

create index if not exists band_upgrade_attempt_questions_sense_idx
  on public.band_upgrade_attempt_questions (sense_id);

alter table public.band_upgrade_attempts enable row level security;
alter table public.band_upgrade_attempt_questions enable row level security;

drop policy if exists band_upgrade_attempts_own_select on public.band_upgrade_attempts;
create policy band_upgrade_attempts_own_select
on public.band_upgrade_attempts for select to authenticated
using (auth.uid() = user_id);

-- Attempt questions contain correctness payloads. Keep direct table access
-- closed; RPCs return learner-safe payloads only.

grant select on public.band_upgrade_attempts to authenticated;

create or replace function public.band_exam_category_for_type(
  p_question_type_key text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_question_type_key = 'meaning_choice' then 'meaning'
    when p_question_type_key in ('listening_choice', 'listening_fill') then 'listening'
    when p_question_type_key = 'sentence_cloze_typing' then 'spelling'
    when p_question_type_key = 'speaking_repeat' then 'speaking'
    else 'meaning'
  end;
$$;

create or replace function public.band_exam_public_payload(
  p_attempt_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'attempt_id', a.id,
    'source_band', a.source_band,
    'target_band', a.target_band,
    'status', a.status,
    'question_count', a.question_count,
    'correct_count', a.correct_count,
    'accuracy', a.accuracy,
    'passed', a.passed,
    'category_counts', a.category_counts,
    'questions', coalesce(jsonb_agg(
      jsonb_build_object(
        'position', aq.position,
        'question_id', aq.question_id,
        'question_type_key', aq.question_type_key,
        'category', aq.category,
        'answer_form', aq.answer_form,
        'stem', aq.generated_payload ->> 'stem',
        'prompt_hint', aq.generated_payload ->> 'prompt_hint',
        'translation_zh', aq.generated_payload ->> 'translation_zh',
        'headword', aq.generated_payload ->> 'headword',
        'option_ids', aq.option_ids,
        'options', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', qo.id,
              'text', qo.option_text,
              'sort_order', qo.sort_order
            )
            order by array_position(aq.option_ids, qo.id)
          )
          from public.question_options qo
          where qo.id = any(aq.option_ids)
        ), '[]'::jsonb),
        'answered', aq.answered_at is not null,
        'is_correct', aq.is_correct
      )
      order by aq.position
    ), '[]'::jsonb)
  )
  from public.band_upgrade_attempts a
  join public.band_upgrade_attempt_questions aq on aq.attempt_id = a.id
  where a.id = p_attempt_id
  group by a.id;
$$;

create or replace function public.start_band_upgrade_exam(
  p_target_band numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_source_band numeric(2,1) := (p_target_band - 0.5)::numeric(2,1);
  v_attempt_id uuid;
  v_question_types text[] := array[
    'meaning_choice',
    'listening_choice',
    'sentence_cloze_typing',
    'speaking_repeat'
  ];
  v_position integer := 1;
  v_type text;
  v_generated record;
  v_item record;
  v_category_counts jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (select 1 from public.bands where band_score = p_target_band) then
    raise exception 'Target band % does not exist', p_target_band;
  end if;

  if not exists (select 1 from public.bands where band_score = v_source_band) then
    raise exception 'Source band % does not exist', v_source_band;
  end if;

  select id into v_attempt_id
  from public.band_upgrade_attempts
  where user_id = v_user_id
    and target_band = p_target_band
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_attempt_id is not null then
    return public.band_exam_public_payload(v_attempt_id);
  end if;

  if (
    select count(*)
    from public.level_sense_assignments lsa
    join public.levels l on l.level_number = lsa.level_number
    join public.bands b on b.id = l.band_id
    where b.band_score = v_source_band
      and lsa.placement_type = 'new'
  ) < 40 then
    raise exception 'Not enough vocabulary in source band % for a 40-question exam', v_source_band;
  end if;

  insert into public.band_upgrade_attempts (
    user_id, source_band, target_band, question_count
  )
  values (v_user_id, v_source_band, p_target_band, 40)
  returning id into v_attempt_id;

  for v_item in
    select lsa.sense_id, lsa.level_number
    from public.level_sense_assignments lsa
    join public.levels l on l.level_number = lsa.level_number
    join public.bands b on b.id = l.band_id
    where b.band_score = v_source_band
      and lsa.placement_type = 'new'
    order by random()
    limit 40
  loop
    v_type := v_question_types[1 + ((v_position - 1) % array_length(v_question_types, 1))];

    begin
      select * into v_generated
      from public.generate_practice_question(
        v_item.sense_id,
        v_item.level_number,
        v_type
      );
    exception when others then
      v_type := 'meaning_choice';
      select * into v_generated
      from public.generate_practice_question(
        v_item.sense_id,
        v_item.level_number,
        v_type
      );
    end;

    insert into public.band_upgrade_attempt_questions (
      attempt_id,
      position,
      question_id,
      sense_id,
      question_type_key,
      category,
      answer_form,
      option_ids,
      correct_option_id,
      generated_payload,
      correct_answer_payload
    )
    values (
      v_attempt_id,
      v_position,
      v_generated.question_id,
      v_item.sense_id,
      v_type,
      public.band_exam_category_for_type(v_type),
      v_generated.answer_form,
      coalesce(v_generated.option_ids, '{}'::uuid[]),
      v_generated.correct_option_id,
      v_generated.generated_payload,
      v_generated.correct_answer_payload
    );

    v_position := v_position + 1;
  end loop;

  select jsonb_object_agg(category, category_count)
  into v_category_counts
  from (
    select category, count(*) as category_count
    from public.band_upgrade_attempt_questions
    where attempt_id = v_attempt_id
    group by category
  ) counts;

  update public.band_upgrade_attempts
  set category_counts = coalesce(v_category_counts, '{}'::jsonb),
      updated_at = now()
  where id = v_attempt_id;

  return public.band_exam_public_payload(v_attempt_id);
end;
$$;

create or replace function public.save_band_upgrade_answer(
  p_attempt_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.band_upgrade_attempts%rowtype;
  v_question public.band_upgrade_attempt_questions%rowtype;
  v_answer text := btrim(coalesce(p_answer, ''));
  v_correct_answer text;
  v_is_correct boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.band_upgrade_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Exam attempt not found';
  end if;

  if v_attempt.status <> 'started' then
    raise exception 'Exam attempt is already completed';
  end if;

  select * into v_question
  from public.band_upgrade_attempt_questions
  where attempt_id = p_attempt_id
    and position = p_position;

  if v_question.attempt_id is null then
    raise exception 'Question position % not found', p_position;
  end if;

  if v_question.answered_at is not null then
    return jsonb_build_object(
      'already_saved', true,
      'position', p_position,
      'is_correct', v_question.is_correct
    );
  end if;

  v_correct_answer := v_question.correct_answer_payload ->> 'correct_answer';

  if v_question.answer_form = 'option' then
    v_is_correct :=
      v_answer = v_question.correct_option_id::text
      or exists (
        select 1
        from public.question_options qo
        where qo.id = v_question.correct_option_id
          and lower(btrim(qo.option_text)) = lower(v_answer)
      );
  else
    v_is_correct := lower(v_answer) = lower(btrim(coalesce(v_correct_answer, '')));
  end if;

  update public.band_upgrade_attempt_questions
  set answer_given = v_answer,
      is_correct = v_is_correct,
      response_time_ms = p_response_time_ms,
      answered_at = now()
  where attempt_id = p_attempt_id
    and position = p_position;

  update public.band_upgrade_attempts
  set updated_at = now()
  where id = p_attempt_id;

  return jsonb_build_object(
    'already_saved', false,
    'position', p_position,
    'is_correct', v_is_correct
  );
end;
$$;

create or replace function public.complete_band_upgrade_exam(
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.band_upgrade_attempts%rowtype;
  v_answered_count integer;
  v_correct_count integer;
  v_accuracy numeric(5,2);
  v_passed boolean;
  v_first_target_level integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.band_upgrade_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Exam attempt not found';
  end if;

  if v_attempt.status = 'completed' then
    return public.band_exam_public_payload(p_attempt_id);
  end if;

  select
    count(*) filter (where answered_at is not null),
    count(*) filter (where is_correct)
  into v_answered_count, v_correct_count
  from public.band_upgrade_attempt_questions
  where attempt_id = p_attempt_id;

  if v_answered_count <> v_attempt.question_count then
    raise exception 'Cannot complete exam until all % questions are answered', v_attempt.question_count;
  end if;

  v_accuracy := round((v_correct_count::numeric / v_attempt.question_count::numeric) * 100, 2);
  v_passed := v_correct_count >= 37;

  update public.band_upgrade_attempts
  set status = 'completed',
      correct_count = v_correct_count,
      accuracy = v_accuracy,
      passed = v_passed,
      completed_at = now(),
      updated_at = now()
  where id = p_attempt_id;

  if v_passed then
    insert into public.user_level_progress (
      user_id,
      level_number,
      is_unlocked,
      is_completed,
      progress,
      unlocked_at,
      completed_at
    )
    select
      v_user_id,
      l.level_number,
      true,
      true,
      1,
      now(),
      now()
    from public.levels l
    join public.bands b on b.id = l.band_id
    where b.band_score <= v_attempt.source_band
    on conflict (user_id, level_number) do update
    set is_unlocked = true,
        is_completed = true,
        progress = greatest(public.user_level_progress.progress, 1),
        unlocked_at = coalesce(public.user_level_progress.unlocked_at, now()),
        completed_at = coalesce(public.user_level_progress.completed_at, now()),
        updated_at = now();

    select min(l.level_number)
    into v_first_target_level
    from public.levels l
    join public.bands b on b.id = l.band_id
    where b.band_score = v_attempt.target_band;

    if v_first_target_level is not null then
      insert into public.user_level_progress (
        user_id,
        level_number,
        is_unlocked,
        is_completed,
        progress,
        unlocked_at
      )
      values (
        v_user_id,
        v_first_target_level,
        true,
        false,
        0,
        now()
      )
      on conflict (user_id, level_number) do update
      set is_unlocked = true,
          unlocked_at = coalesce(public.user_level_progress.unlocked_at, now()),
          updated_at = now();
    end if;
  end if;

  return public.band_exam_public_payload(p_attempt_id);
end;
$$;

revoke all on function public.band_exam_category_for_type(text) from public, anon, authenticated;
revoke all on function public.band_exam_public_payload(uuid) from public, anon, authenticated;
revoke all on function public.start_band_upgrade_exam(numeric) from public, anon, authenticated;
revoke all on function public.save_band_upgrade_answer(uuid, integer, text, integer) from public, anon, authenticated;
revoke all on function public.complete_band_upgrade_exam(uuid) from public, anon, authenticated;

grant execute on function public.start_band_upgrade_exam(numeric) to authenticated;
grant execute on function public.save_band_upgrade_answer(uuid, integer, text, integer) to authenticated;
grant execute on function public.complete_band_upgrade_exam(uuid) to authenticated;


-- ============================================================================
-- Migration: 202607060028_due_review_new_word_gate.sql
-- ============================================================================

-- Phase 1 practice policy: when a learner has more than one full round of
-- due reviews, do not introduce new words in that round.

do $$
declare
  v_original text;
  v_updated text;
begin
  select pg_get_functiondef('public.start_practice_round(integer)'::regprocedure)
  into v_original;

  v_updated := replace(
    v_original,
$old$
  v_question_count integer;
begin
$old$,
$new$
  v_question_count integer;
  v_due_review_count integer := 0;
  v_new_sense_limit integer := 7;
begin
$new$
  );

  v_updated := replace(
    v_updated,
$old$
    while v_position <= v_target_count loop
$old$,
$new$
    select count(*)
    into v_due_review_count
    from public.user_sense_mastery usm
    left join public.level_sense_assignments lsa
      on lsa.sense_id = usm.sense_id
     and lsa.placement_type = 'new'
    where usm.user_id = v_user_id
      and usm.next_due_at is not null
      and usm.next_due_at <= now()
      and usm.learning_state <> 'mastered'
      and (lsa.level_number is null or lsa.level_number <= p_level_number);

    if v_due_review_count > v_target_count then
      v_new_sense_limit := 0;
    end if;

    while v_position <= v_target_count loop
$new$
  );

  v_updated := replace(
    v_updated,
    'if v_candidate_sense_id is null and v_new_count < 7 then',
    'if v_candidate_sense_id is null and v_new_count < v_new_sense_limit then'
  );

  if v_updated = v_original then
    raise exception 'Could not patch public.start_practice_round(integer) with due review new-word gate';
  end if;

  execute v_updated;
end;
$$;


-- ============================================================================
-- Migration: 202607070029_review_before_new_sense_priority.sql
-- ============================================================================

-- Phase 1 masterplan Feature E fix: overdue reviews must outrank new senses
-- when both are eligible for the same round position. Migration 020 tried the
-- 'new' sense bucket before the 'review' bucket, so a learner with a handful
-- of due reviews (fewer than the 20-question round size, so migration 028's
-- due_review_new_word_gate never engaged) would still see new senses fill
-- positions ahead of their overdue reviews. This swaps the bucket order to:
-- mistake (unchanged) -> review -> new -> fallback (unchanged).

do $$
declare
  v_original text;
  v_updated text;
begin
  select pg_get_functiondef('public.start_practice_round(integer)'::regprocedure)
  into v_original;

  v_updated := replace(
    v_original,
$old$
      if v_candidate_sense_id is null and v_new_count < v_new_sense_limit then
        select
          lsa.sense_id,
          'new'::text as source_bucket,
          true as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and usm.user_id is null
          and not (lsa.sense_id = any(v_picked_senses))
        order by lsa.order_in_level
        limit 1;
      end if;

      if v_candidate_sense_id is null then
        select
          usm.sense_id,
          'review'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        left join public.level_sense_assignments lsa
          on lsa.sense_id = usm.sense_id
         and lsa.placement_type = 'new'
        where usm.user_id = v_user_id
          and usm.next_due_at is not null
          and usm.next_due_at <= now()
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (lsa.level_number is null or lsa.level_number <= p_level_number)
        order by usm.next_due_at, usm.priority_boost desc, usm.difficulty_level desc, random()
        limit 1;
      end if;
$old$,
$new$
      if v_candidate_sense_id is null then
        select
          usm.sense_id,
          'review'::text as source_bucket,
          false as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.user_sense_mastery usm
        left join public.level_sense_assignments lsa
          on lsa.sense_id = usm.sense_id
         and lsa.placement_type = 'new'
        where usm.user_id = v_user_id
          and usm.next_due_at is not null
          and usm.next_due_at <= now()
          and usm.learning_state <> 'mastered'
          and not (usm.sense_id = any(v_picked_senses))
          and (lsa.level_number is null or lsa.level_number <= p_level_number)
        order by usm.next_due_at, usm.priority_boost desc, usm.difficulty_level desc, random()
        limit 1;
      end if;

      if v_candidate_sense_id is null and v_new_count < v_new_sense_limit then
        select
          lsa.sense_id,
          'new'::text as source_bucket,
          true as is_new
        into v_candidate_sense_id, v_candidate_source_bucket, v_candidate_is_new
        from public.level_sense_assignments lsa
        left join public.user_sense_mastery usm
          on usm.user_id = v_user_id
         and usm.sense_id = lsa.sense_id
        where lsa.level_number = p_level_number
          and lsa.placement_type = 'new'
          and usm.user_id is null
          and not (lsa.sense_id = any(v_picked_senses))
        order by lsa.order_in_level
        limit 1;
      end if;
$new$
  );

  if v_updated = v_original then
    raise exception 'Could not patch public.start_practice_round(integer) with review-before-new priority';
  end if;

  execute v_updated;
end;
$$;


-- ============================================================================
-- Migration: 202607070030_login_tracking.sql
-- ============================================================================

-- Phase 1 Feature B: login tracking. Every session start (app open / session
-- restore / sign-in) calls record_login(), which logs the event and updates
-- profiles.login_count. Distinct from the daily streak: a login alone does
-- not earn a streak day (only completing a practice round does, per
-- complete_practice_round in migration 202607050024).

begin;

alter table public.profiles
  add column if not exists login_count integer not null default 0,
  add column if not exists first_login_at timestamptz,
  add column if not exists last_login_at timestamptz;

create table public.user_login_log (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  logged_in_at timestamptz not null default now(),
  platform     text not null default 'android'
);

create index on public.user_login_log (user_id, logged_in_at desc);

alter table public.user_login_log enable row level security;

create policy user_login_log_select_own
on public.user_login_log
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.record_login()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_login_count integer;
  v_first_login_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  insert into public.user_login_log (user_id, logged_in_at, platform)
  values (v_user_id, now(), 'android');

  update public.profiles
  set login_count = coalesce(login_count, 0) + 1,
      last_login_at = now(),
      first_login_at = coalesce(first_login_at, now())
  where id = v_user_id
  returning login_count, first_login_at into v_login_count, v_first_login_at;

  if not found then
    raise exception 'Profile not found for authenticated user';
  end if;

  return jsonb_build_object(
    'login_count', v_login_count,
    'first_login_at', v_first_login_at
  );
end;
$$;

revoke all on function public.record_login() from public, anon;
grant execute on function public.record_login() to authenticated;

commit;


-- ============================================================================
-- Migration: 202607070031_awards_system.sql
-- ============================================================================

-- Phase 1 Feature J: login-milestone and level/band-completion badges.
-- check_and_grant_awards() is idempotent (checks actual current state, not
-- incremental events) and is called by the Android client after
-- record_login(), complete_practice_round(), and complete_band_upgrade_exam()
-- rather than embedded inside those RPCs, to avoid touching their
-- already-verified grading/streak logic.

begin;

create table public.award_definitions (
  id              text primary key,
  name_zh         text not null,
  description_zh  text,
  trigger_type    text not null check (trigger_type in ('login_count', 'level_complete', 'band_complete')),
  trigger_value   text not null,
  icon_name       text
);

create table public.user_awards (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  award_id     text not null references public.award_definitions(id),
  awarded_at   timestamptz not null default now(),
  seen_by_user boolean not null default false,
  unique (user_id, award_id)
);

create index on public.user_awards (user_id);

alter table public.award_definitions enable row level security;
alter table public.user_awards enable row level security;

create policy award_definitions_select_all
on public.award_definitions
for select
to authenticated
using (true);

create policy user_awards_select_own
on public.user_awards
for select
to authenticated
using (user_id = auth.uid());

insert into public.award_definitions (id, name_zh, description_zh, trigger_type, trigger_value, icon_name)
values
  ('bronze_duck',    '第一只鸭！',       '完成首次登录',        'login_count',   '1',   'duck_bronze'),
  ('login_streak_3', '初学者连续登录',   '累计登录 3 次',       'login_count',   '3',   'streak_freeze'),
  ('silver_duck',    '坚持一周',         '累计登录 7 次',       'login_count',   '7',   'duck_silver'),
  ('gold_duck',      '学习达人',         '累计登录 30 次',      'login_count',   '30',  'duck_gold'),
  ('platinum_duck',  '坚持不懈',         '累计登录 100 次',     'login_count',   '100', 'duck_platinum'),
  ('first_level',    '初露锋芒',         '完成 Level 1',        'level_complete', '1',   'level_1'),
  ('band4_starter',  'Band 4 通关新星',  '完成 Level 5',        'level_complete', '5',   'level_5');

create or replace function public.check_and_grant_awards(p_user_id uuid)
returns table (new_award_id text, new_award_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_login_count integer;
  v_def record;
begin
  if v_caller is null or v_caller <> p_user_id then
    raise exception 'Authentication required';
  end if;

  select p.login_count into v_login_count
  from public.profiles p
  where p.id = p_user_id;

  for v_def in
    select * from public.award_definitions where trigger_type = 'login_count'
  loop
    if v_login_count >= v_def.trigger_value::integer then
      insert into public.user_awards (user_id, award_id)
      values (p_user_id, v_def.id)
      on conflict (user_id, award_id) do nothing;
    end if;
  end loop;

  for v_def in
    select * from public.award_definitions where trigger_type = 'level_complete'
  loop
    if exists (
      select 1 from public.user_level_progress ulp
      where ulp.user_id = p_user_id
        and ulp.level_number = v_def.trigger_value::integer
        and ulp.is_completed
    ) then
      insert into public.user_awards (user_id, award_id)
      values (p_user_id, v_def.id)
      on conflict (user_id, award_id) do nothing;
    end if;
  end loop;

  for v_def in
    select * from public.award_definitions where trigger_type = 'band_complete'
  loop
    if exists (
      select 1 from public.band_upgrade_attempts bua
      where bua.user_id = p_user_id
        and bua.target_band = v_def.trigger_value::numeric
        and bua.passed
    ) then
      insert into public.user_awards (user_id, award_id)
      values (p_user_id, v_def.id)
      on conflict (user_id, award_id) do nothing;
    end if;
  end loop;

  return query
  select ua.award_id, ad.name_zh
  from public.user_awards ua
  join public.award_definitions ad on ad.id = ua.award_id
  where ua.user_id = p_user_id
    and not ua.seen_by_user;

  update public.user_awards
  set seen_by_user = true
  where user_id = p_user_id
    and not seen_by_user;
end;
$$;

revoke all on function public.check_and_grant_awards(uuid) from public, anon;
grant execute on function public.check_and_grant_awards(uuid) to authenticated;

commit;


-- ============================================================================
-- Migration: 202607070032_skill_category_column.sql
-- ============================================================================

-- Phase 1 Feature I: tag each question with the IELTS skill it tests, so the
-- Overall Assessment and Band Upgrade Exam result screens can report
-- per-skill scores. listening_fill counts as listening (the primary skill
-- tested), not spelling, matching the masterplan's Feature I mapping.

begin;

alter table public.questions
  add column if not exists skill_category text
  check (skill_category in ('listening', 'reading', 'speaking', 'spelling'));

update public.questions q
set skill_category = case q.question_type_key
  when 'listening_choice'      then 'listening'
  when 'listening_fill'        then 'listening'
  when 'speaking_repeat'       then 'speaking'
  when 'open_speaking'         then 'speaking'
  when 'meaning_choice'        then 'reading'
  when 'reading_comprehension' then 'reading'
  when 'sentence_cloze_typing' then 'spelling'
  when 'word_form'             then 'spelling'
  else q.skill_category
end
where q.skill_category is null
  and q.question_type_key is not null;

commit;


-- ============================================================================
-- Migration: 202607070033_coming_soon_flag.sql
-- ============================================================================

-- Phase 1 Feature K: Levels 6+ show a "coming soon" locked card once tapped,
-- distinct from the normal 未解锁 (locked-by-progress) treatment. Only
-- Band 4.0 (band_id=1, Levels 1-33) has production-ready content in Phase 1;
-- every other band is metadata-only stub rows (240 total level rows exist,
-- only 33 have real word/question data per verify_project_installation.sql).

begin;

alter table public.levels
  add column if not exists is_coming_soon boolean not null default false;

update public.levels
set is_coming_soon = true
where band_id <> 1;

commit;


-- ============================================================================
-- Migration: 202607070034_skill_scoring.sql
-- ============================================================================

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


-- ============================================================================
-- Migration: 202607070035_overall_assessment.sql
-- ============================================================================

-- Phase 1 Feature H: home-page Overall Assessment. 100 questions stratified
-- 25 per IELTS skill (listening/reading/speaking/spelling), drawn from ALL
-- available bands/levels (Phase 1 = Band 4.0 only). Purely diagnostic: never
-- touches user_sense_mastery or level/band progression. Mirrors the
-- band_upgrade_attempts pattern in migration 202607060026 but stratifies by
-- skill_category (migration 202607070032) instead of question type rotation,
-- since the diagnostic needs to report per-IELTS-skill, not per-type.

create table public.overall_assessment_attempts (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  status            text not null default 'started',
  question_count    smallint not null default 100,
  correct_count     smallint,
  listening_correct smallint,
  listening_total   smallint,
  reading_correct   smallint,
  reading_total     smallint,
  speaking_correct  smallint,
  speaking_total    smallint,
  spelling_correct  smallint,
  spelling_total    smallint,
  listening_band    numeric(3,1),
  reading_band      numeric(3,1),
  speaking_band     numeric(3,1),
  spelling_band     numeric(3,1),
  overall_band      numeric(3,1),
  started_at        timestamptz not null default now(),
  completed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint overall_assessment_status_valid
    check (status in ('started', 'completed', 'abandoned')),
  constraint overall_assessment_question_count_valid
    check (question_count = 100)
);

create unique index overall_assessment_one_started_per_user
  on public.overall_assessment_attempts (user_id)
  where status = 'started';

create table public.overall_assessment_questions (
  attempt_id        uuid not null references public.overall_assessment_attempts(id) on delete cascade,
  position          smallint not null,
  question_id       uuid not null references public.questions(id),
  sense_id          uuid not null references public.word_senses(id),
  question_type_key text not null,
  skill_category    text not null,
  answer_form       text not null,
  option_ids        uuid[] not null default '{}',
  correct_option_id uuid,
  generated_payload jsonb not null default '{}'::jsonb,
  correct_answer_payload jsonb not null default '{}'::jsonb,
  answer_given      text,
  is_correct        boolean,
  response_time_ms  integer,
  answered_at       timestamptz,
  created_at        timestamptz not null default now(),

  primary key (attempt_id, position),
  constraint overall_assessment_position_valid check (position between 1 and 100),
  constraint overall_assessment_skill_valid
    check (skill_category in ('listening', 'reading', 'speaking', 'spelling'))
);

create index overall_assessment_questions_question_idx
  on public.overall_assessment_questions (question_id);

create index overall_assessment_questions_sense_idx
  on public.overall_assessment_questions (sense_id);

alter table public.overall_assessment_attempts enable row level security;
alter table public.overall_assessment_questions enable row level security;

create policy overall_assessment_attempts_own_select
on public.overall_assessment_attempts for select to authenticated
using (auth.uid() = user_id);

-- Attempt questions contain correctness payloads; RPCs return learner-safe
-- payloads only, matching practice_round_questions / band_upgrade_attempt_questions.

grant select on public.overall_assessment_attempts to authenticated;

create or replace function public.overall_assessment_public_payload(
  p_attempt_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'attempt_id', a.id,
    'status', a.status,
    'question_count', a.question_count,
    'correct_count', a.correct_count,
    'listening_correct', a.listening_correct, 'listening_total', a.listening_total,
    'reading_correct', a.reading_correct, 'reading_total', a.reading_total,
    'speaking_correct', a.speaking_correct, 'speaking_total', a.speaking_total,
    'spelling_correct', a.spelling_correct, 'spelling_total', a.spelling_total,
    'listening_band', a.listening_band,
    'reading_band', a.reading_band,
    'speaking_band', a.speaking_band,
    'spelling_band', a.spelling_band,
    'overall_band', a.overall_band,
    'questions', coalesce(jsonb_agg(
      jsonb_build_object(
        'position', aq.position,
        'question_id', aq.question_id,
        'question_type_key', aq.question_type_key,
        'skill_category', aq.skill_category,
        'answer_form', aq.answer_form,
        'stem', aq.generated_payload ->> 'stem',
        'prompt_hint', aq.generated_payload ->> 'prompt_hint',
        'translation_zh', aq.generated_payload ->> 'translation_zh',
        'headword', aq.generated_payload ->> 'headword',
        'option_ids', aq.option_ids,
        'options', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', qo.id,
              'text', qo.option_text,
              'sort_order', qo.sort_order
            )
            order by array_position(aq.option_ids, qo.id)
          )
          from public.question_options qo
          where qo.id = any(aq.option_ids)
        ), '[]'::jsonb),
        'answered', aq.answered_at is not null,
        'is_correct', aq.is_correct
      )
      order by aq.position
    ), '[]'::jsonb)
  )
  from public.overall_assessment_attempts a
  join public.overall_assessment_questions aq on aq.attempt_id = a.id
  where a.id = p_attempt_id
  group by a.id;
$$;

create or replace function public.overall_assessment_types_for_skill(
  p_skill text
)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_skill
    when 'listening' then array['listening_choice', 'listening_fill']
    when 'reading'   then array['meaning_choice', 'reading_comprehension']
    when 'speaking'  then array['speaking_repeat', 'open_speaking']
    when 'spelling'  then array['sentence_cloze_typing', 'word_form']
  end;
$$;

create or replace function public.start_overall_assessment()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt_id uuid;
  v_skills text[] := array['listening', 'reading', 'speaking', 'spelling'];
  v_skill text;
  v_types text[];
  v_position integer := 1;
  v_generated record;
  v_item record;
  v_skill_taken integer;
  v_type_index integer;
  v_attempted_type text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select id into v_attempt_id
  from public.overall_assessment_attempts
  where user_id = v_user_id
    and status = 'started'
  order by started_at desc
  limit 1;

  if v_attempt_id is not null then
    return public.overall_assessment_public_payload(v_attempt_id);
  end if;

  insert into public.overall_assessment_attempts (user_id, question_count)
  values (v_user_id, 100)
  returning id into v_attempt_id;

  foreach v_skill in array v_skills loop
    v_types := public.overall_assessment_types_for_skill(v_skill);
    v_skill_taken := 0;
    v_type_index := 0;

    for v_item in
      select lsa.sense_id, lsa.level_number
      from public.level_sense_assignments lsa
      where lsa.placement_type = 'new'
      order by random()
      limit 300
    loop
      exit when v_skill_taken >= 25;

      v_type_index := v_type_index + 1;
      v_attempted_type := v_types[1 + (v_type_index % array_length(v_types, 1))];

      begin
        select * into v_generated
        from public.generate_practice_question(
          v_item.sense_id,
          v_item.level_number,
          v_attempted_type
        );
      exception when others then
        v_attempted_type := v_types[1 + ((v_type_index + 1) % array_length(v_types, 1))];
        begin
          select * into v_generated
          from public.generate_practice_question(
            v_item.sense_id,
            v_item.level_number,
            v_attempted_type
          );
        exception when others then
          continue;
        end;
      end;

      insert into public.overall_assessment_questions (
        attempt_id,
        position,
        question_id,
        sense_id,
        question_type_key,
        skill_category,
        answer_form,
        option_ids,
        correct_option_id,
        generated_payload,
        correct_answer_payload
      )
      values (
        v_attempt_id,
        v_position,
        v_generated.question_id,
        v_item.sense_id,
        v_attempted_type,
        v_skill,
        v_generated.answer_form,
        coalesce(v_generated.option_ids, '{}'::uuid[]),
        v_generated.correct_option_id,
        v_generated.generated_payload,
        v_generated.correct_answer_payload
      );

      v_position := v_position + 1;
      v_skill_taken := v_skill_taken + 1;
    end loop;
  end loop;

  update public.overall_assessment_attempts
  set question_count = v_position - 1,
      listening_total = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'listening'),
      reading_total   = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'reading'),
      speaking_total  = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'speaking'),
      spelling_total  = (select count(*) from public.overall_assessment_questions where attempt_id = v_attempt_id and skill_category = 'spelling'),
      updated_at = now()
  where id = v_attempt_id;

  if v_position <= 1 then
    delete from public.overall_assessment_attempts where id = v_attempt_id;
    raise exception 'No eligible vocabulary available for the overall assessment';
  end if;

  return public.overall_assessment_public_payload(v_attempt_id);
end;
$$;

revoke all on function public.start_overall_assessment() from public, anon;
grant execute on function public.start_overall_assessment() to authenticated;

create or replace function public.save_overall_assessment_answer(
  p_attempt_id uuid,
  p_position integer,
  p_answer text,
  p_response_time_ms integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.overall_assessment_attempts%rowtype;
  v_question public.overall_assessment_questions%rowtype;
  v_answer text := btrim(coalesce(p_answer, ''));
  v_correct_answer text;
  v_is_correct boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.overall_assessment_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Assessment attempt not found';
  end if;

  if v_attempt.status <> 'started' then
    raise exception 'Assessment attempt is already completed';
  end if;

  select * into v_question
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id
    and position = p_position;

  if v_question.attempt_id is null then
    raise exception 'Question position % not found', p_position;
  end if;

  if v_question.answered_at is not null then
    return jsonb_build_object(
      'already_saved', true,
      'position', p_position,
      'is_correct', v_question.is_correct
    );
  end if;

  v_correct_answer := v_question.correct_answer_payload ->> 'correct_answer';

  if v_question.answer_form = 'option' then
    v_is_correct :=
      v_answer = v_question.correct_option_id::text
      or exists (
        select 1
        from public.question_options qo
        where qo.id = v_question.correct_option_id
          and lower(btrim(qo.option_text)) = lower(v_answer)
      );
  else
    v_is_correct := lower(v_answer) = lower(btrim(coalesce(v_correct_answer, '')));
  end if;

  update public.overall_assessment_questions
  set answer_given = v_answer,
      is_correct = v_is_correct,
      response_time_ms = p_response_time_ms,
      answered_at = now()
  where attempt_id = p_attempt_id
    and position = p_position;

  update public.overall_assessment_attempts
  set updated_at = now()
  where id = p_attempt_id;

  return jsonb_build_object(
    'already_saved', false,
    'position', p_position,
    'is_correct', v_is_correct
  );
end;
$$;

revoke all on function public.save_overall_assessment_answer(uuid, integer, text, integer) from public, anon;
grant execute on function public.save_overall_assessment_answer(uuid, integer, text, integer) to authenticated;

create or replace function public.complete_overall_assessment(
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_attempt public.overall_assessment_attempts%rowtype;
  v_answered_count integer;
  v_correct_count integer;
  v_listening_correct integer; v_listening_total integer;
  v_reading_correct integer; v_reading_total integer;
  v_speaking_correct integer; v_speaking_total integer;
  v_spelling_correct integer; v_spelling_total integer;
  v_listening_weighted_correct numeric; v_listening_weighted_max numeric;
  v_reading_weighted_correct numeric; v_reading_weighted_max numeric;
  v_speaking_weighted_correct numeric; v_speaking_weighted_max numeric;
  v_spelling_weighted_correct numeric; v_spelling_weighted_max numeric;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_attempt
  from public.overall_assessment_attempts
  where id = p_attempt_id
    and user_id = v_user_id;

  if v_attempt.id is null then
    raise exception 'Assessment attempt not found';
  end if;

  if v_attempt.status = 'completed' then
    return public.overall_assessment_public_payload(p_attempt_id);
  end if;

  select count(*) into v_answered_count
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id
    and answered_at is not null;

  if v_answered_count <> v_attempt.question_count then
    raise exception 'All % questions must be answered before completion (answered %)',
      v_attempt.question_count, v_answered_count;
  end if;

  select count(*) filter (where is_correct) into v_correct_count
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id;

  select
    count(*) filter (where skill_category = 'listening' and is_correct), count(*) filter (where skill_category = 'listening'),
    count(*) filter (where skill_category = 'reading' and is_correct), count(*) filter (where skill_category = 'reading'),
    count(*) filter (where skill_category = 'speaking' and is_correct), count(*) filter (where skill_category = 'speaking'),
    count(*) filter (where skill_category = 'spelling' and is_correct), count(*) filter (where skill_category = 'spelling')
  into
    v_listening_correct, v_listening_total,
    v_reading_correct, v_reading_total,
    v_speaking_correct, v_speaking_total,
    v_spelling_correct, v_spelling_total
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id;

  select
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'listening' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'listening'), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'reading' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'reading'), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'speaking' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'speaking'), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'spelling' and is_correct), 0),
    coalesce(sum(public.sense_difficulty_weight(sense_id)) filter (where skill_category = 'spelling'), 0)
  into
    v_listening_weighted_correct, v_listening_weighted_max,
    v_reading_weighted_correct, v_reading_weighted_max,
    v_speaking_weighted_correct, v_speaking_weighted_max,
    v_spelling_weighted_correct, v_spelling_weighted_max
  from public.overall_assessment_questions
  where attempt_id = p_attempt_id;

  update public.overall_assessment_attempts
  set status = 'completed',
      correct_count = v_correct_count,
      listening_correct = v_listening_correct, listening_total = v_listening_total,
      reading_correct = v_reading_correct, reading_total = v_reading_total,
      speaking_correct = v_speaking_correct, speaking_total = v_speaking_total,
      spelling_correct = v_spelling_correct, spelling_total = v_spelling_total,
      listening_band = public.compute_skill_band(v_listening_weighted_correct, v_listening_weighted_max),
      reading_band = public.compute_skill_band(v_reading_weighted_correct, v_reading_weighted_max),
      speaking_band = public.compute_skill_band(v_speaking_weighted_correct, v_speaking_weighted_max),
      spelling_band = public.compute_skill_band(v_spelling_weighted_correct, v_spelling_weighted_max),
      completed_at = now(),
      updated_at = now()
  where id = p_attempt_id;

  update public.overall_assessment_attempts
  set overall_band = (
    select round(avg(b), 1) from unnest(array[
      listening_band, reading_band, speaking_band, spelling_band
    ]) as b
    where b is not null
  )
  where id = p_attempt_id;

  return public.overall_assessment_public_payload(p_attempt_id);
end;
$$;

revoke all on function public.complete_overall_assessment(uuid) from public, anon;
grant execute on function public.complete_overall_assessment(uuid) to authenticated;

