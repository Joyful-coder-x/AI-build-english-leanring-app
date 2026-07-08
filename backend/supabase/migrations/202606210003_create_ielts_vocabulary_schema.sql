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
