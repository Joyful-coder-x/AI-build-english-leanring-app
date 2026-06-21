# KuaKua Duck — Content & Data Build Brief

**Document owner:** Product Manager  
**Audience:** Data constructor, content engineer, or AI assistant executing content production  
**Last updated:** 2026-06-12  
**Status:** Active — pilot phase

> **Read this document top to bottom before producing any data.**
> Everything you need is here. No other document is required to begin work.
> Cross-references to `DATA_DESIGN.md`, `DATA_SOURCES.md`, and `ARCHITECTURE.md`
> are provided for deeper context only.

---

## 1. What This App Is

**KuaKua Duck (夸夸鸭AI)** is a gamified IELTS vocabulary-learning Android app.
Users progress through 240 levels of English vocabulary, earning "Duck Power" (鸭力值)
and streaks by completing daily practice sessions. Each session presents 10 questions
drawn from a pool of generated questions. Questions test vocabulary across 14 exercise
types (fill-in, multiple choice, listening, speaking, reading, writing).

**What the data powers:** Every question a user sees, every word they look up, every
audio clip they hear comes from the database you build. Without this content,
the app has nothing to teach.

---

## 2. Your Role and What Success Looks Like

You are the **content constructor**. Your job is to:

1. Source vocabulary words from approved references (see §6 and `DATA_SOURCES.md`)
2. Build a complete "word package" for each word (see §7)
3. Load word packages into the Supabase database in the exact formats specified in §8
4. From each word package, generate questions using the templates in §9 — do **not**
   hand-author questions and do **not** invent content
5. Upload audio files to Supabase Storage (see §10)

**Success = the app can run a complete 10-question practice session using only real
data, with no fabricated content, for at least one full level (≈80 words).**

**You are NOT responsible for:**
- User accounts, profiles, streaks, or any data written by the app at runtime
- Building or modifying any app code
- Decisions marked ⏸ in §11 — those require PM sign-off before you proceed

---

## 3. The Two Data Domains

| Domain | Who creates it | Your job |
|--------|---------------|----------|
| **Content data** — words, definitions, examples, questions, audio | You (the constructor) | Source, format, and load it |
| **User data** — profiles, progress, sessions, mistakes | The app, at runtime | Create empty tables only (SQL in §5.2); do NOT populate |

This brief covers content data only. User data tables are listed in §5.2 for
completeness — create them empty and move on.

---

## 4. What Already Exists in Supabase

These tables are live and the app is reading from them today. Do not drop or
recreate them. Add missing columns only (SQL provided in §5.1).

| Table | State | What the app reads from it |
|-------|-------|---------------------------|
| `public.questions` | ✅ Exists, has data | Fetches `type_code IN (1,2)` and `is_active = true`; 10 rows per session |
| `public.question_options` | ✅ Exists, has data | Fetches options for the 10 questions returned above |
| `public.words` | ✅ Exists, early seed data | Not yet read by app; schema needs columns added (§5.1) |

All other tables listed in §5 do not yet exist. Create them in the order given.

---

## 5. Table Construction Order and SQL

Build in this exact order. Later tables have foreign key dependencies on earlier ones.

### 5.1 Step 1 — Create enum types and reference tables (load data immediately after)

Run in Supabase Dashboard → **SQL Editor**.

```sql
-- ── Enum types (create first; tables below reference them) ──────────────────

CREATE TYPE question_category AS ENUM
  ('new_word','listening','speaking','reading','writing');
CREATE TYPE answer_form AS ENUM ('option','keyboard','voice');
CREATE TYPE prop_type_enum AS ENUM ('streak_protection','challenge_key');

-- ── levels — 240 rows, one per game level ────────────────────────────────────
-- Why: every word belongs to a level; the app uses level_number to sequence
-- content and unlock cards. This is a fixed reference — values come from
-- the game spec and never change at runtime.

CREATE TABLE IF NOT EXISTS levels (
  level_number   int          PRIMARY KEY,   -- 1..240
  ielts_band     numeric(2,1) NOT NULL,       -- 4.0..8.0
  band_name      text         NOT NULL,       -- e.g. "雅思5分词汇"
  title_name     text         NOT NULL,       -- English-level title shown in UI
  order_in_band  int          NOT NULL        -- position within the band
);

ALTER TABLE levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON levels
  FOR SELECT TO authenticated USING (true);

-- ── INSERT all 240 rows (copy this block exactly) ────────────────────────────
-- Pattern: (level_number, ielts_band, band_name, title_name, order_in_band)
-- Band 4.0  → Lv 1–54   (54 levels) title: 脆皮萌鸭
-- Band 4.5  → Lv 55–81  (27 levels) title: 词圈鸭仔
-- Band 5.0  → Lv 82–99  (18 levels) title: 鸭闯词关
-- Band 5.5  → Lv 100–126(27 levels) title: 鸭学启程
-- Band 6.0  → Lv 127–144(18 levels) title: 鸭题先锋
-- Band 6.5  → Lv 145–162(18 levels) title: 鸭行辞海
-- Band 7.0  → Lv 163–180(18 levels) title: 鸭掌全局
-- Band 7.5  → Lv 181–210(30 levels) title: 鸭系词霸
-- Band 8.0  → Lv 211–240(30 levels) title: 鸭学词宗

INSERT INTO levels (level_number, ielts_band, band_name, title_name, order_in_band)
SELECT
  n,
  CASE
    WHEN n <= 54  THEN 4.0
    WHEN n <= 81  THEN 4.5
    WHEN n <= 99  THEN 5.0
    WHEN n <= 126 THEN 5.5
    WHEN n <= 144 THEN 6.0
    WHEN n <= 162 THEN 6.5
    WHEN n <= 180 THEN 7.0
    WHEN n <= 210 THEN 7.5
    ELSE               8.0
  END,
  CASE
    WHEN n <= 54  THEN '雅思4分词汇'
    WHEN n <= 81  THEN '雅思4.5分词汇'
    WHEN n <= 99  THEN '雅思5分词汇'
    WHEN n <= 126 THEN '雅思5.5分词汇'
    WHEN n <= 144 THEN '雅思6分词汇'
    WHEN n <= 162 THEN '雅思6.5分词汇'
    WHEN n <= 180 THEN '雅思7分词汇'
    WHEN n <= 210 THEN '雅思7.5分词汇'
    ELSE               '雅思8分词汇'
  END,
  CASE
    WHEN n <= 54  THEN '脆皮萌鸭'
    WHEN n <= 81  THEN '词圈鸭仔'
    WHEN n <= 99  THEN '鸭闯词关'
    WHEN n <= 126 THEN '鸭学启程'
    WHEN n <= 144 THEN '鸭题先锋'
    WHEN n <= 162 THEN '鸭行辞海'
    WHEN n <= 180 THEN '鸭掌全局'
    WHEN n <= 210 THEN '鸭系词霸'
    ELSE               '鸭学词宗'
  END,
  n - CASE
    WHEN n <= 54  THEN 0
    WHEN n <= 81  THEN 54
    WHEN n <= 99  THEN 81
    WHEN n <= 126 THEN 99
    WHEN n <= 144 THEN 126
    WHEN n <= 162 THEN 144
    WHEN n <= 180 THEN 162
    WHEN n <= 210 THEN 180
    ELSE               210
  END
FROM generate_series(1, 240) AS n;

-- ── question_types — 14 rows, fixed by spec ──────────────────────────────────
-- Why: maps type_code integers (used throughout questions table) to their
-- human-readable name and answer form; the app uses type_code to decide
-- which UI component to render.

CREATE TABLE IF NOT EXISTS question_types (
  type_code    int               PRIMARY KEY,
  category     question_category NOT NULL,
  name_zh      text              NOT NULL,
  answer_form  answer_form       NOT NULL,
  notes        text
);

ALTER TABLE question_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON question_types
  FOR SELECT TO authenticated USING (true);

INSERT INTO question_types (type_code, category, name_zh, answer_form, notes) VALUES
  (1,  'new_word',  '单词·首字母填空', 'keyboard',  'example + target_span'),
  (2,  'new_word',  '单词·单词选择',   'option',    'example + 3 distractors'),
  (3,  'listening', '听力选择',        'option',    'example audio + 3 distractors'),
  (4,  'listening', '听力填空',        'keyboard',  'example audio + target_span'),
  (5,  'listening', '听力理解',        'option',    'audio + comprehension Q + options'),
  (6,  'speaking',  '选择并复述',      'voice',     'example + options'),
  (7,  'speaking',  '理解并口述',      'voice',     'passage/question'),
  (8,  'speaking',  '填空并复述',      'voice',     'example + target_span'),
  (9,  'reading',   '词义英文解释',    'option',    'definition_en + options'),
  (10, 'reading',   '词形变化',        'keyboard',  'word_forms + example'),
  (11, 'reading',   '词根词缀变化',    'option',    'root_affix + options'),
  (12, 'reading',   '关键词填空',      'keyboard',  'same as type 1'),
  (13, 'reading',   '阅读选择',        'option',    'example + options'),
  (14, 'writing',   '翻译补全',        'keyboard',  'translation_zh + sentence_en + target_span');

-- ── duck_titles — 8 rows ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS duck_titles (
  title_zh        text PRIMARY KEY,
  min_duck_power  int  NOT NULL
);

ALTER TABLE duck_titles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON duck_titles
  FOR SELECT TO authenticated USING (true);

INSERT INTO duck_titles (title_zh, min_duck_power) VALUES
  ('初学鸭',   0),
  ('努力鸭',   500),
  ('进步鸭',   2000),
  ('熟练鸭',   5000),
  ('超级鸭',   10000),
  ('卓越鸭',   20000),
  ('无敌鸭',   50000),
  ('大师鸭',   100000);
```

### 5.2 Step 2 — Create content tables (you will populate these)

```sql
-- ── words ────────────────────────────────────────────────────────────────────
-- One row per vocabulary word. This is the master atom all questions are
-- derived from. The existing words table may need columns added — use
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS for safety.

CREATE TABLE IF NOT EXISTS words (
  id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  level_number        int          NOT NULL REFERENCES levels(level_number),
  headword            text         NOT NULL,          -- lowercase, e.g. "abandon"
  phonetic            text         NOT NULL,          -- British IPA, e.g. /əˈbændən/
  pronunciation_path  text         NOT NULL,          -- Storage: pronunciations/{id}.mp3
  mnemonic            text         NOT NULL,          -- Chinese memory aid
  root_affix          jsonb,                          -- {root, prefix, suffix, gloss} or null
  pos_primary         text         NOT NULL,          -- n. / v. / adj. / adv. etc.
  frequency_rank      int,                            -- optional; lower = more common
  created_at          timestamptz  NOT NULL DEFAULT now(),
  updated_at          timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (level_number, headword)
);

ALTER TABLE words ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON words FOR SELECT TO authenticated USING (true);

-- ── word_meanings ─────────────────────────────────────────────────────────────
-- 1–N meanings per word (most words have 1–3 senses).
-- definition_en is required — it drives TYPE 9 questions (词义英文解释).

CREATE TABLE IF NOT EXISTS word_meanings (
  id             uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  word_id        uuid  NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  pos            text  NOT NULL,           -- part of speech for this sense
  definition_zh  text  NOT NULL,           -- Chinese meaning
  definition_en  text  NOT NULL,           -- English definition (learner-friendly)
  sort_order     int   NOT NULL DEFAULT 0  -- primary sense = 0
);

ALTER TABLE word_meanings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON word_meanings FOR SELECT TO authenticated USING (true);

-- ── word_forms ────────────────────────────────────────────────────────────────
-- Irregular or noteworthy inflected forms only.
-- Do NOT add rows for regular inflections (walk→walked, cat→cats).
-- Drives TYPE 10 questions (词形变化).

CREATE TABLE IF NOT EXISTS word_forms (
  id          uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  word_id     uuid  NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  form_label  text  NOT NULL,    -- e.g. "past", "plural", "comparative", "-ing", "noun"
  form_text   text  NOT NULL     -- e.g. "abandoned", "analyses", "worse"
);

ALTER TABLE word_forms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON word_forms FOR SELECT TO authenticated USING (true);

-- ── examples ──────────────────────────────────────────────────────────────────
-- ≥2 example sentences per word. The backbone of most question types.
-- EVERY sentence must come from an approved source in DATA_SOURCES.md §3.
-- target_span is the exact substring of sentence_en that gets blanked in
-- fill-in questions — verify it exists as a literal substring before inserting.

CREATE TABLE IF NOT EXISTS examples (
  id              uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  word_id         uuid  NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  sentence_en     text  NOT NULL,           -- full English sentence from approved source
  translation_zh  text  NOT NULL,           -- Chinese translation, human-reviewed
  target_span     text  NOT NULL,           -- exact word/phrase to blank; must be in sentence_en
  audio_path      text,                     -- Storage: example-audio/{id}.mp3; null if no audio
  sort_order      int   NOT NULL DEFAULT 0  -- primary example = 0
);

ALTER TABLE examples ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated_read" ON examples FOR SELECT TO authenticated USING (true);
```

### 5.3 Step 3 — Add missing columns to existing questions table

```sql
-- The questions and question_options tables already exist and have live data.
-- Only add the columns that are missing. Do not recreate or truncate the table.

ALTER TABLE questions
  ADD COLUMN IF NOT EXISTS category     question_category,
  ADD COLUMN IF NOT EXISTS answer_form  answer_form,
  ADD COLUMN IF NOT EXISTS word_id      uuid REFERENCES words(id),
  ADD COLUMN IF NOT EXISTS example_id   uuid REFERENCES examples(id),
  ADD COLUMN IF NOT EXISTS explanation  jsonb,          -- {board:[], narration:[]}
  ADD COLUMN IF NOT EXISTS audio_path   text,
  ADD COLUMN IF NOT EXISTS created_at   timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at   timestamptz NOT NULL DEFAULT now();

-- Columns that already exist (do NOT add again):
--   id, type_code, prompt_hint, stem, correct_answer,
--   translation_zh, expected_time_ms, is_active
```

### 5.4 Step 4 — Create user/app tables (create empty — do NOT populate)

```sql
-- These tables are written by the app at runtime. Your job is to create the
-- schema only. Leave them empty.

CREATE TABLE IF NOT EXISTS profiles (
  id                    uuid        PRIMARY KEY,   -- set to auth.uid() on signup
  nickname              text        NOT NULL,
  avatar_path           text,
  phone                 text,
  duck_power            int         NOT NULL DEFAULT 0,
  onboarding_completed  bool        NOT NULL DEFAULT false,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS level_progress (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  level_number  int         NOT NULL REFERENCES levels(level_number),
  progress      numeric(5,4) NOT NULL DEFAULT 0,
  is_unlocked   bool        NOT NULL DEFAULT false,
  is_completed  bool        NOT NULL DEFAULT false,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, level_number)
);

CREATE TABLE IF NOT EXISTS streaks (
  user_id            uuid  PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  current_days       int   NOT NULL DEFAULT 0,
  goal_days          int   NOT NULL DEFAULT 1,
  last_checkin_date  date
);

CREATE TABLE IF NOT EXISTS checkins (
  id            uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid  NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  checkin_date  date  NOT NULL,
  source        text  NOT NULL DEFAULT 'practice',
  UNIQUE (user_id, checkin_date)
);

CREATE TABLE IF NOT EXISTS user_props (
  id         uuid            PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid            NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  prop_type  prop_type_enum  NOT NULL,
  count      int             NOT NULL DEFAULT 0,
  UNIQUE (user_id, prop_type)
);

CREATE TABLE IF NOT EXISTS mistake_words (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  word_id       uuid        NOT NULL REFERENCES words(id),
  added_at      timestamptz NOT NULL DEFAULT now(),
  review_state  jsonb       NOT NULL DEFAULT '{"stage":0,"next_due_at":null}',
  UNIQUE (user_id, word_id)
);

CREATE TABLE IF NOT EXISTS practice_sessions (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  started_at        timestamptz NOT NULL DEFAULT now(),
  correct_count     int         NOT NULL,
  total_count       int         NOT NULL,
  star_rating       int         NOT NULL CHECK (star_rating BETWEEN 0 AND 3),
  duck_power_earned int         NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS practice_answers (
  id           uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   uuid  NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
  question_id  uuid  NOT NULL REFERENCES questions(id),
  is_correct   bool  NOT NULL,
  answer_given text  NOT NULL,
  time_ms      int   NOT NULL
);

CREATE TABLE IF NOT EXISTS assessment_results (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ielts_score  numeric(2,1) NOT NULL,
  radar        jsonb        NOT NULL,
  report       jsonb        NOT NULL,
  taken_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS onboarding_profiles (
  user_id      uuid        PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  answers      jsonb       NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS scratch_card_log (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reward_type text        NOT NULL,
  payload     jsonb       NOT NULL,
  granted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS feedback (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  category   text        NOT NULL,
  body        text        NOT NULL,
  status     text        NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS question_error_reports (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  question_id uuid        NOT NULL REFERENCES questions(id),
  reason      text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ── RLS on user tables (owner-only) ─────────────────────────────────────────

ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE level_progress       ENABLE ROW LEVEL SECURITY;
ALTER TABLE streaks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkins             ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_props           ENABLE ROW LEVEL SECURITY;
ALTER TABLE mistake_words        ENABLE ROW LEVEL SECURITY;
ALTER TABLE practice_sessions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE practice_answers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_results   ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE scratch_card_log     ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback             ENABLE ROW LEVEL SECURITY;
ALTER TABLE question_error_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own_rows" ON profiles
  FOR ALL TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY "own_rows" ON level_progress
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON streaks
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON checkins
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON user_props
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON mistake_words
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON practice_sessions
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON practice_answers
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON assessment_results
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON onboarding_profiles
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON scratch_card_log
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON feedback
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_rows" ON question_error_reports
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
```

---

## 6. Source Policy — Non-Negotiable

> **Do not fabricate any linguistic data. Do not invent example sentences.
> Do not hand-author questions. Every field in every row must trace back to
> an approved source.**

All approved sources are listed in `DATA_SOURCES.md` (same folder as this file).
Read it before producing any data. Key rules:

| Data type | Approved source |
|-----------|----------------|
| Word list / level assignment | Cambridge IELTS list, Oxford 3000/5000 (see `DATA_SOURCES.md §1`) |
| `definition_en`, `phonetic` | Cambridge Dictionary or OALD only (see §2) |
| `definition_zh` | Youdao Dictionary, human-reviewed (see §2) |
| `sentence_en` | Cambridge Dictionary examples, OALD, COCA corpus (see §3) |
| `translation_zh` | DeepL draft + native Chinese speaker review (see §4) |
| `root_affix.gloss` | Etymonline only (see §5) |
| Word forms | Cambridge Dictionary grammar section (see §6) |
| Audio files | Google TTS (en-GB voice) or Amazon Polly (Brian) (see §8) |
| Distractors | Drawn from same-level words in the `words` table (no external source) |

**Questions are generated from the word package using templates (see §9).
Questions are never hand-authored and never invented by an AI without
a verified word package as input.**

---

## 7. The Word Package — Your Authoring Unit

Produce one word package per vocabulary word. All questions for that word are
generated from this package. If a field is missing, the corresponding question
types cannot be generated for that word — that is acceptable; better to have
accurate partial data than inaccurate complete data.

### 7.1 Word package JSON format

```json
{
  "headword": "abandon",
  "level_number": 12,
  "phonetic": "/əˈbændən/",
  "pos_primary": "v.",
  "mnemonic": "a(一个)+band(乐队)+on(在上面)→乐队被遗留在台上→遗弃",
  "root_affix": {
    "root": "ban",
    "prefix": "a-",
    "suffix": null,
    "gloss": "summon, proclaim"
  },
  "frequency_rank": 142,
  "meanings": [
    {
      "pos": "v.",
      "definition_zh": "遗弃；放弃",
      "definition_en": "to leave a place, thing, or person permanently, usually because of necessity",
      "sort_order": 0
    },
    {
      "pos": "n.",
      "definition_zh": "放任；纵情",
      "definition_en": "a feeling of freedom from worry or care",
      "sort_order": 1
    }
  ],
  "forms": [
    { "form_label": "past",                "form_text": "abandoned" },
    { "form_label": "present_participle",  "form_text": "abandoning" },
    { "form_label": "noun",                "form_text": "abandonment" }
  ],
  "examples": [
    {
      "sentence_en": "He was forced to abandon his car on the motorway.",
      "translation_zh": "他被迫将汽车丢弃在高速公路上。",
      "target_span": "abandon",
      "has_audio": true,
      "sort_order": 0,
      "source": "Cambridge Dictionary"
    },
    {
      "sentence_en": "She abandoned her plan to study abroad after her mother fell ill.",
      "translation_zh": "母亲生病后，她放弃了出国留学的计划。",
      "target_span": "abandoned",
      "has_audio": false,
      "sort_order": 1,
      "source": "Oxford Learner's Dictionaries"
    }
  ],
  "distractors": ["neglect", "reject", "dismiss"]
}
```

### 7.2 Field constraints

| Field | Constraint |
|-------|-----------|
| `headword` | Lowercase. Must be unique within its `level_number`. |
| `phonetic` | British IPA format. Must start and end with `/`. |
| `pronunciation_path` | Leave blank during authoring — filled in after audio upload (see §10). |
| `mnemonic` | Must be based on real word features (root, sound, or spelling). Do not fabricate etymology. |
| `root_affix` | Null is acceptable. Only populate when a real root/affix exists AND is relevant to the meaning. Source: Etymonline. |
| `definition_en` | Must be learner-appropriate (not encyclopedic). Source: Cambridge or OALD. |
| `definition_zh` | Human-reviewed. Source: Youdao, DeepL draft. |
| `sentence_en` | Must contain `target_span` as a literal substring. Verify before submitting. |
| `target_span` | Must be the headword or one of its inflected forms, as it appears in `sentence_en`. |
| `forms` | Only irregular or non-obvious forms. Regular -ed / -s forms do not need a row. |
| `distractors` | Exactly 3. Same part of speech as the correct answer. Plausible but clearly wrong. |
| `source` (in examples) | Required in your production log — not stored in DB, but auditable. |

---

## 8. How to Load Data Into Supabase (端口)

### Method A — SQL Editor (reference tables, ≤500 rows)

**Where:** Supabase Dashboard → SQL Editor → New query → Paste → Run

**Use for:** `levels`, `question_types`, `duck_titles` — SQL is provided in §5.1.

**Do not use for:** bulk content (words, examples, questions) — too slow.

---

### Method B — CSV Import (bulk content: words, word_meanings, word_forms, examples)

**Where:** Supabase Dashboard → Table Editor → [table name] → Import data → Upload CSV

**CSV column requirements:**
- Headers must match column names exactly (snake_case)
- `id` column: **leave blank** — Supabase auto-generates UUIDs
- FK columns (e.g., `word_id`): must be the UUID of a row that already exists in the parent table
- `jsonb` columns (e.g., `root_affix`): valid JSON string, e.g. `{"root":"ban","prefix":"a-","suffix":null,"gloss":"summon"}`
- Null values: leave the CSV cell empty

**CSV headers for each table:**

`words`:
```
level_number,headword,phonetic,pronunciation_path,mnemonic,root_affix,pos_primary,frequency_rank
```

`word_meanings`:
```
word_id,pos,definition_zh,definition_en,sort_order
```

`word_forms`:
```
word_id,form_label,form_text
```

`examples`:
```
word_id,sentence_en,translation_zh,target_span,audio_path,sort_order
```

**Important:** Load `words` before `word_meanings`, `word_forms`, and `examples`
(FK dependency). Load `examples` before `questions`.

---

### Method C — Service-Role API Script (bulk questions, ~190k rows)

**Where:** A Node.js or Python script you run once from your local machine.
Never put the service-role key in the Android app.

**Endpoint:**
```
POST https://<your-project-ref>.supabase.co/rest/v1/questions
```

**Headers:**
```
apikey: <service_role_key>
Authorization: Bearer <service_role_key>
Content-Type: application/json
Prefer: return=minimal
```

**Body:** Array of question objects (batch 500 rows per request):
```json
[
  {
    "type_code": 2,
    "category": "new_word",
    "answer_form": "option",
    "word_id": "uuid-of-abandon",
    "example_id": "uuid-of-example-1",
    "stem": "He was forced to _____ his car on the motorway.",
    "prompt_hint": "选择正确的单词填入空白处",
    "correct_answer": "abandon",
    "translation_zh": "他被迫将汽车丢弃在高速公路上。",
    "expected_time_ms": 20000,
    "is_active": true
  }
]
```

Then load `question_options` for MCQ questions (type_code = 2, 3, 5, 6, 9, 11, 13):
```json
[
  { "question_id": "uuid-of-question", "option_text": "abandon",  "is_correct": true,  "sort_order": 0 },
  { "question_id": "uuid-of-question", "option_text": "neglect",  "is_correct": false, "sort_order": 1 },
  { "question_id": "uuid-of-question", "option_text": "reject",   "is_correct": false, "sort_order": 2 },
  { "question_id": "uuid-of-question", "option_text": "dismiss",  "is_correct": false, "sort_order": 3 }
]
```

**Service-role key location:** Supabase Dashboard → Project Settings → API →
`service_role` (secret). Keep it out of version control.

---

## 9. Question Generation Templates

**These are the only approved methods for creating questions. Do not hand-author
questions. Do not invent stems or answers. Generate from the word package only.**

The app currently renders **type_code 1 (keyboard)** and **type_code 2 (MCQ)** only.
Generate these two types first. Other types can be generated later when the app UI
supports them — they can be loaded with `is_active = false` until then.

---

### TYPE 1 — 单词·首字母填空 (keyboard)

```
Input required: example.sentence_en, example.target_span

stem:           Replace target_span in sentence_en with "___[first letter]___"
                e.g. "He was forced to ___a___ his car on the motorway."
prompt_hint:    "请根据首字母提示，填写出完整单词"
correct_answer: target_span  (e.g. "abandon")
translation_zh: example.translation_zh
expected_time_ms: 30000
is_active:      true
answer_form:    keyboard
category:       new_word
```

---

### TYPE 2 — 单词·单词选择 (MCQ, 4 options)

```
Input required: example.sentence_en, example.target_span, word.distractors[3]

stem:           Replace target_span in sentence_en with "_____"
                e.g. "He was forced to _____ his car on the motorway."
prompt_hint:    "选择正确的单词填入空白处"
correct_answer: target_span
translation_zh: example.translation_zh
expected_time_ms: 20000
is_active:      true
answer_form:    option
category:       new_word

question_options (4 rows, shuffle order):
  { option_text: target_span,      is_correct: true  }
  { option_text: distractors[0],   is_correct: false }
  { option_text: distractors[1],   is_correct: false }
  { option_text: distractors[2],   is_correct: false }
```

---

### TYPE 9 — 词义英文解释 (MCQ, 4 options) — generate when app supports it

```
Input required: word.headword, word_meanings[0].definition_en,
                3 other headwords from the same level_number (wrong options)

stem:           'Which word best matches this definition?\n"[definition_en]"'
prompt_hint:    "根据英文释义，选出对应的单词"
correct_answer: headword
translation_zh: word_meanings[0].definition_zh
expected_time_ms: 25000
is_active:      false  ← set false until app UI supports type 9
answer_form:    option
category:       reading
```

---

### TYPE 14 — 翻译补全 (keyboard) — generate when app supports it

```
Input required: example.sentence_en, example.translation_zh, example.target_span

stem:           Show translation_zh with the part corresponding to target_span
                replaced by "_____". Instruction: "补全英文句子中缺失的单词"
                e.g. "他被迫将汽车_____在高速公路上。\nHe was forced to _____ his car on the motorway."
prompt_hint:    "根据中文翻译，补全英文句子中缺失的单词"
correct_answer: target_span
translation_zh: example.translation_zh
expected_time_ms: 35000
is_active:      false  ← set false until app UI supports type 14
answer_form:    keyboard
category:       writing
```

---

### expected_time_ms defaults by type

| type_code | Default ms | Rationale |
|-----------|-----------|-----------|
| 1 | 30,000 | Keyboard; user must recall and type |
| 2 | 20,000 | MCQ; recognition task |
| 3, 4, 5 | 40,000 | Audio; includes playback time |
| 6, 7, 8 | 50,000 | Voice; includes speaking time |
| 9, 11, 13 | 25,000 | MCQ with reading required |
| 10 | 30,000 | Keyboard form recall |
| 12 | 30,000 | Same as type 1 |
| 14 | 35,000 | Keyboard with translation processing |

---

## 10. Audio Files

### Format specification

| Parameter | Value |
|-----------|-------|
| Format | MP3 |
| Channels | Mono |
| Sample rate | 22,050 Hz |
| Bitrate | 64 kbps |
| Loudness | Normalized to –16 LUFS |
| Max file size | 50 KB per file |
| Accent | British English (IELTS standard) |
| TTS voice (Google) | `en-GB-Standard-B` (male) or `en-GB-Standard-A` (female) |
| TTS voice (Amazon) | `Brian` (en-GB) |

### Naming convention

| File type | Name pattern | Supabase Storage path |
|-----------|-------------|----------------------|
| Word pronunciation | `{word_uuid}.mp3` | `pronunciations/{word_uuid}.mp3` |
| Example sentence | `{example_uuid}.mp3` | `example-audio/{example_uuid}.mp3` |

Never name by headword. UUIDs avoid encoding issues and collisions.

### Upload process

1. Generate audio using approved TTS service
2. Normalize loudness (use ffmpeg: `ffmpeg -i input.mp3 -af loudnorm=I=-16 output.mp3`)
3. Upload to Supabase Dashboard → Storage → `pronunciations` or `example-audio` bucket
4. After upload, update the corresponding `pronunciation_path` or `audio_path` column
   with the Storage path (not the full URL — just the path from the bucket root)

---

## 11. Production Phases

Do not attempt to produce all 19,200 words before validating the pipeline.

| Phase | Scope | Goal |
|-------|-------|------|
| **Pilot** | Level 1 only (~80 words, IELTS 4.0) | Validate end-to-end: word packages load → questions generate → app renders them → grading works |
| **MVP** | Bands 4.0–5.5 (Lv 1–126, ~10,000 words) | Cover the majority-beginner user base for launch |
| **Full** | Bands 6.0–8.0 (Lv 127–240, ~9,200 words) | Post-launch, as user base grows to higher IELTS bands |

**Pilot acceptance criteria:**
- 80 word rows loaded with all required fields populated
- Each word has ≥2 example rows
- Type 1 and Type 2 questions generated for each word (at least 1 per type per word)
- The Android app (with `USE_REAL_QUESTIONS = true`) can complete a full 10-question
  session without errors
- `is_active = true` on all pilot questions

---

## 12. Decisions — Locked 2026-06-12

✅ **All decisions resolved. Production may begin.**

| # | Decision | ✅ Resolved |
|---|----------|------------|
| 1 | **Primary word list source** | **Oxford 3000/5000** — use Oxford 3000 for bands 4.0–6.0, Oxford 5000 for bands 6.5–8.0. Supplement gaps with the British Council IELTS list. |
| 2 | **TTS provider for audio** | **Google Cloud TTS** — use `en-GB-Neural2-B` (male) or `en-GB-Neural2-C` (female) voice; 24kHz MP3; all audio generated server-side before loading to Storage. |
| 3 | **Chinese translation review workflow** | **PM spot-check 10%** — AI produces all `translation_zh` values; PM reviews a random 10% sample per level batch before that batch is marked approved. Flag rate > 5% triggers full re-review. |
| 4 | **Mnemonic coverage** | **AI-assisted + human review** — AI generates a candidate mnemonic for every word; PM or contractor reviews and approves/edits before load. `mnemonic` must not be null at load time. |
| 5 | **Explanation content (夸夸精讲)** | **AI-generated at runtime** — `explanation` column in `questions` is left null in the database. The app calls Claude at answer-review time to generate the 夸夸精讲 board. Not stored; no pre-authoring required. |

---

## 13. Glossary

| Term | Meaning |
|------|---------|
| Word package | The complete set of data for one word (headword + meanings + examples + forms + audio + distractors). The atomic authoring unit. |
| target_span | The exact word or phrase in an example sentence that gets replaced by a blank in fill-in questions. Must be a literal substring of sentence_en. |
| is_active | A boolean flag on each question. Set false to hide a question without deleting it (e.g., during QA). The app only fetches is_active = true. |
| Level | One of 240 game levels, each containing ~80 words. Levels map to IELTS bands (4.0–8.0). |
| 端口 (data entry point) | The mechanism by which a data type enters Supabase: SQL Editor / CSV import / service-role API. Each is described in §8. |
| service_role key | The Supabase admin key that bypasses RLS. Used only for bulk loading scripts. Never in the app. |
| Distractor | A wrong-answer option for MCQ questions. Must be the same part of speech, same difficulty band, and plausible but incorrect. |

---

*For approved source URLs and citation requirements, see `DATA_SOURCES.md`.*  
*For app architecture and repository interfaces, see `ARCHITECTURE.md`.*  
*For full table schemas and volume projections, see `DATA_DESIGN.md`.*
