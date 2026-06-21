from __future__ import annotations

import argparse
from pathlib import Path

from pipeline_common import OUTPUT_DIR, ensure_output_dir


SCHEMA_SQL = """-- KuaKua Duck pilot content schema/reference setup.
-- Run this before importing generated CSV files.

create extension if not exists pgcrypto;

do $$
begin
  create type question_category as enum ('new_word','listening','speaking','reading','writing');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type answer_form as enum ('option','keyboard','voice');
exception when duplicate_object then null;
end $$;

create table if not exists levels (
  level_number int primary key,
  ielts_band numeric(2,1) not null,
  band_name text not null,
  title_name text not null,
  order_in_band int not null
);

insert into levels (level_number, ielts_band, band_name, title_name, order_in_band)
values (1, 4.0, 'IELTS 4.0 word bank', 'Beginner Duck', 1)
on conflict (level_number) do nothing;

create table if not exists question_types (
  type_code int primary key,
  category question_category not null,
  name_zh text not null,
  answer_form answer_form not null,
  notes text
);

insert into question_types (type_code, category, name_zh, answer_form, notes) values
  (1, 'new_word', '单词·首字母填空', 'keyboard', 'example + target_span'),
  (2, 'new_word', '单词·单词选择', 'option', 'example + 3 distractors')
on conflict (type_code) do nothing;

create table if not exists words (
  id uuid primary key default gen_random_uuid(),
  level_number int not null references levels(level_number),
  headword text not null,
  phonetic text not null,
  pronunciation_path text not null,
  mnemonic text not null,
  root_affix jsonb,
  pos_primary text not null,
  frequency_rank int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (level_number, headword)
);

create table if not exists word_meanings (
  id uuid primary key default gen_random_uuid(),
  word_id uuid not null references words(id) on delete cascade,
  pos text not null,
  definition_zh text not null,
  definition_en text not null,
  sort_order int not null default 0
);

create table if not exists word_forms (
  id uuid primary key default gen_random_uuid(),
  word_id uuid not null references words(id) on delete cascade,
  form_label text not null,
  form_text text not null
);

create table if not exists examples (
  id uuid primary key default gen_random_uuid(),
  word_id uuid not null references words(id) on delete cascade,
  sentence_en text not null,
  translation_zh text not null,
  target_span text not null,
  audio_path text,
  sort_order int not null default 0
);

create table if not exists questions (
  id uuid primary key default gen_random_uuid(),
  type_code int not null references question_types(type_code),
  prompt_hint text not null,
  stem text not null,
  correct_answer text not null,
  translation_zh text not null,
  expected_time_ms int not null,
  is_active bool not null default true
);

alter table questions
  add column if not exists category question_category,
  add column if not exists answer_form answer_form,
  add column if not exists word_id uuid references words(id),
  add column if not exists example_id uuid references examples(id),
  add column if not exists explanation jsonb,
  add column if not exists audio_path text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references questions(id) on delete cascade,
  option_text text not null,
  is_correct bool not null default false,
  sort_order int not null default 0
);

alter table levels enable row level security;
alter table question_types enable row level security;
alter table words enable row level security;
alter table word_meanings enable row level security;
alter table word_forms enable row level security;
alter table examples enable row level security;
alter table questions enable row level security;
alter table question_options enable row level security;

do $$
begin
  create policy authenticated_read_levels on levels for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_question_types on question_types for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_words on words for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_word_meanings on word_meanings for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_word_forms on word_forms for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_examples on examples for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_questions on questions for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
do $$
begin
  create policy authenticated_read_question_options on question_options for select to authenticated using (true);
exception when duplicate_object then null;
end $$;
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate pilot schema/reference SQL.")
    parser.add_argument("--output", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()

    output_dir = ensure_output_dir() if args.output == OUTPUT_DIR else args.output
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "schema_reference.sql"
    path.write_text(SCHEMA_SQL, encoding="utf-8")
    print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
