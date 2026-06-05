# 夸夸鸭AI — Data Design Guide (for the data constructor)

**Purpose.** This is the build sheet for whoever **sources, produces, and loads
the data** for this app. It defines *what tables exist*, *what every column
means*, *what values are allowed*, and *how much data you must find/produce*.
Pair it with `ARCHITECTURE.md` (the app/engineering plan). Where they disagree,
this file wins **for data**; `ARCHITECTURE.md` wins for app code.

> **Backend decision (confirmed):** ALL data — both the learning **content**
> (words, questions, audio) and **user/app data** (profiles, progress) — lives in
> **Supabase** (Postgres + Storage + Auth) and is served to the app over Supabase.
> This supersedes the earlier "content may be bundled JSON" note in
> `ARCHITECTURE.md §1`.

---

## 0. How to read this guide

- **`§4 Content data`** = the stuff you must *go find or create*. This is 95% of
  the sourcing effort. Start here.
- **`§5 User data`** = created at runtime by the app/users. You do **not** source
  it; you only build the empty tables + rules so it has somewhere to live.
- **`§6 Reference tables`** = small fixed lookup tables (levels, titles, etc.).
  Load these once from the spec; values are given below.
- **`§9 Volume budget`** = the headline numbers: *how much* to produce.
- **`§10 Shopping list`** = the prioritized to-do, phase by phase.
- **`§11 Open questions`** = decisions to lock **before** mass production, or you
  will redo work.

---

## 1. Principles

1. **Two data domains, different lifecycles:**
   - **Content data** — words/questions/audio. Read-only to the app. Authored by
     you, the same for every user. Changes via content releases.
   - **User data** — one user's profile, progress, mistakes, scores. Written by
     the app at runtime. Per-user, private.
   They live in the same Supabase project but are governed by **different
   security rules** (§8): content = world-readable; user data = owner-only.

2. **Separate ATOMIC content from DERIVED questions.** Do **not** hand-author
   60k+ questions one by one. Author a clean **per-word content package** (§4.x)
   — the word, its meanings, forms, roots, example sentences, distractors, and
   audio. Most of the 14 question types are then **generated** from that package
   by template. This is the single most important cost lever in the whole project
   (see §9). Author atoms once; generate questions many times.

3. **Everything keyed to a `level`.** Every word (and therefore every question)
   belongs to exactly one of the 240 levels (§6.1). This drives sequencing,
   unlocking, and how much you must produce per band.

4. **Audio & images are files, not columns.** Store binary in **Supabase
   Storage** buckets (§7); store only the *path/URL* in Postgres.

---

## 2. Storage layout in Supabase

| Layer | Use |
|-------|-----|
| **Postgres — `public` schema** | All relational tables below. |
| **Postgres enums / check constraints** | Closed value sets (question category, answer form, review state, prop type…). |
| **Supabase Storage buckets** | `pronunciations/`, `example-audio/`, `avatars/`, `question-media/` (§7). |
| **Supabase Auth (`auth.users`)** | Identity only. App profile data lives in `public.profiles`, keyed to `auth.users.id`. |

---

## 3. Naming & type conventions (follow exactly)

- Tables & columns: **`snake_case`**, plural table names (`words`, `questions`).
- Primary keys: **`id uuid default gen_random_uuid()`** for user/large content
  tables. Small fixed reference tables may use a natural key (e.g.
  `levels.level_number int PK`, `question_types.type_code int PK`).
- Timestamps: **`timestamptz`**, columns `created_at` / `updated_at`, default `now()`.
- Money/score: integer counts (`int`); IELTS bands: **`numeric(2,1)`** (e.g. `5.5`).
- Free-form/variable structures: **`jsonb`**.
- Foreign keys: `<singular>_id` (e.g. `word_id`, `level_number`). Always add the
  FK constraint + an index on it.
- Text needing length limits → enforce with `check (char_length(col) <= N)`.
- Booleans start with `is_`/`has_`.

---

## 4. CONTENT DATA — what you must source/produce

### 4.1 `levels` *(reference — load once, values fixed by spec 2.2.1)*

The 240 levels grouped into IELTS bands. **This is fixed data — type it in.**

| Column | Type | Notes |
|--------|------|-------|
| `level_number` | int **PK** | 1..240 |
| `ielts_band` | numeric(2,1) | 4.0 … 8.0 |
| `band_name` | text | e.g. "雅思5分词汇" |
| `title_name` | text | 等级称号 (see table below) |
| `order_in_band` | int | position within its band |

**Band → level mapping (load exactly):**

| 雅思分数 | 等级区间 | 数量 | 等级称号 |
|---------|---------|-----|---------|
| 4.0 | Lv1–Lv54 | 54 | 脆皮萌鸭 |
| 4.5 | Lv55–Lv81 | 27 | 词圈鸭仔 |
| 5.0 | Lv82–Lv99 | 18 | 鸭闯词关 |
| 5.5 | Lv100–Lv126 | 27 | 鸭学启程 |
| 6.0 | Lv127–Lv144 | 18 | 鸭题先锋 |
| 6.5 | Lv145–Lv162 | 18 | 鸭行辞海 |
| 7.0 | Lv163–Lv180 | 18 | 鸭掌全局 |
| 7.5 | Lv181–Lv210 | 30 | 鸭系词霸 |
| 8.0 | Lv211–Lv240 | 30 | 鸭学词宗 |

> **240 levels total. Spec target ≈ 80 words/level, ≈ 5 days to clear a level.**
> ⚠️ NOTE: this title list (脆皮萌鸭…) is the **English-level title** and is
> *different* from the **鸭力称号** (初学鸭…, §6.2). Don't conflate them.

### 4.2 `words` *(the core atom — SOURCE THIS)*

One row per vocabulary word.

| Column | Type | Required | Notes / constraint |
|--------|------|----------|--------------------|
| `id` | uuid PK | ✓ | |
| `level_number` | int FK→levels | ✓ | which level it belongs to |
| `headword` | text | ✓ | the word, lowercase, unique per level |
| `phonetic` | text | ✓ | IPA, e.g. `/əˈbændən/` |
| `pronunciation_path` | text | ✓ | Storage path to the word's audio (§7) |
| `mnemonic` | text | ✓ | 记忆法/助记 (spec 2.3) |
| `root_affix` | jsonb | ⚠ for type 11 | `{root, prefix, suffix, gloss}` |
| `pos_primary` | text | ✓ | part of speech: n./v./adj.… |
| `frequency_rank` | int | optional | for ordering within a level |
| `created_at/updated_at` | timestamptz | ✓ | |

### 4.3 `word_meanings` *(SOURCE THIS — 1..N per word)*

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `word_id` | uuid FK→words | |
| `pos` | text | part of speech for this sense |
| `definition_zh` | text | Chinese meaning |
| `definition_en` | text | **English definition — required for type 9 (词义英文解释)** |
| `sort_order` | int | display order |

### 4.4 `word_forms` *(SOURCE THIS where applicable — for type 10 词形变化)*

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `word_id` | uuid FK→words | |
| `form_label` | text | e.g. past, plural, comparative, -ing |
| `form_text` | text | the inflected form |

### 4.5 `examples` *(SOURCE THIS — 1..N per word; the backbone of most questions)*

| Column | Type | Required | Notes |
|--------|------|----------|-------|
| `id` | uuid PK | ✓ | |
| `word_id` | uuid FK→words | ✓ | |
| `sentence_en` | text | ✓ | full English sentence containing the headword |
| `translation_zh` | text | ✓ | Chinese translation (spec 2.3 / type 14) |
| `target_span` | text | ✓ | the exact word/phrase in `sentence_en` that gets blanked |
| `audio_path` | text | ⚠ for listening | Storage path; **required if used in types 3/4/5** |
| `sort_order` | int | | |

### 4.6 `questions` + `question_options` *(mostly GENERATED, see §4.8)*

`questions`:

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `type_code` | int FK→question_types | 1..14 (§4.7) |
| `category` | enum | one of: `new_word`,`listening`,`speaking`,`reading`,`writing` (新词/听/说/读/写) |
| `answer_form` | enum | `option` \| `keyboard` \| `voice` |
| `word_id` | uuid FK→words | the word being tested |
| `example_id` | uuid FK→examples | source sentence (nullable for non-sentence types) |
| `stem` | text | the prompt/题干 shown to the user |
| `prompt_hint` | text | the 提示文字 (e.g. "请正确拼写出听到的内容") |
| `correct_answer` | text | canonical answer (for option = the correct option text) |
| `translation_zh` | text | shown in the judge/讲解 panel |
| `explanation` | jsonb | 夸夸精讲 content: `{board:[], narration:[]}` (spec 题目回顾) |
| `audio_path` | text | for listening types |
| `expected_time_ms` | int | **drives the 3★ speed bonus (§ scoring) — required** |
| `is_active` | bool | soft enable/disable |

`question_options` *(only for `answer_form = option`)*:

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `question_id` | uuid FK→questions | |
| `option_text` | text | one choice |
| `is_correct` | bool | exactly **one** true per question |
| `sort_order` | int | |

> **Distractors:** each option question needs **3 wrong options**. Source/produce
> plausible distractors per word (store as candidate distractors on the word, or
> generate). This is real authored content — budget for it.

### 4.7 `question_types` *(reference — load these 14 rows exactly, from spec 2.2.3)*

| type_code | category | name | answer_form | extra data it needs |
|-----------|----------|------|-------------|---------------------|
| 1 | new_word | 单词·首字母填空 | keyboard | example + target_span |
| 2 | new_word | 单词·单词选择 | option | example + 3 distractors |
| 3 | listening | 听力选择 | option | example audio + 3 distractors |
| 4 | listening | 听力填空 | keyboard | example audio + target_span |
| 5 | listening | 听力理解 | option | audio + comprehension Q + options |
| 6 | speaking | 选择并复述 | option+voice | example + options |
| 7 | speaking | 理解并口述 | voice | passage/question |
| 8 | speaking | 填空并复述 | voice | example + target_span |
| 9 | speaking/reading | 词义英文解释 | option | **definition_en** + options |
| 10 | reading | 词形变化 | keyboard | **word_forms** + example |
| 11 | reading | 词根词缀变化 | option | **root_affix** + options |
| 12 | reading | 关键词填空 | keyboard | same as type 1 |
| 13 | reading | 阅读选择 | option | example + options |
| 14 | writing | 翻译补全 | keyboard | translation_zh + sentence_en + target_span |

> **Listening/speaking are skippable** (spec): when a user skips, the app serves a
> **replacement question** of another type. So every listening/speaking question
> needs a non-audio fallback to exist for the same word. Account for this in
> coverage (don't make a word *only* answerable via audio types).

### 4.8 The "per-word content package" — your authoring unit ✅

For **each word**, produce this bundle. Questions are generated from it.

```
WORD PACKAGE (one word)
├── headword, phonetic, pos, mnemonic            (words)
├── pronunciation audio file                     (Storage → pronunciation_path)
├── 1..N meanings: zh + EN definition            (word_meanings)
├── word forms (if irregular/inflectable)        (word_forms)        → type 10
├── root/affix breakdown (if decomposable)       (words.root_affix)  → type 11
├── ≥2 example sentences:                         (examples)
│     • sentence_en + translation_zh + target_span
│     • audio file for each                       (Storage)          → types 3/4/5
└── ≥3 distractors per testable sense                                → option types
```

**Minimum bar per word** (for the app to be able to build a varied session):
1 pronunciation audio, ≥1 zh meaning + 1 EN definition, ≥2 examples (≥1 with
audio), ≥3 distractors, root/affix + forms where the word allows.

---

## 5. USER / APP DATA — build empty, app fills at runtime (do NOT source)

These mirror the domain models already in code (`data/model/`).

| Table | Holds | Key columns |
|-------|-------|-------------|
| `profiles` | one row per user; 1:1 with `auth.users` | `id uuid PK = auth.uid()`, `nickname`, `avatar_path`, `phone`, `duck_power int`, `created_at`. (鸭力称号 is **derived** from `duck_power`, not stored — see §6.2.) |
| `level_progress` | user's position/level | `user_id`, `level_number`, `progress numeric`, `is_unlocked`, `is_completed`. Rule: **front-end value only goes up** (spec 2.2.1) — never write a lower visible level. |
| `mistake_words` (错词本) | words the user got wrong | `user_id`, `word_id`, `added_at`, `review_state jsonb` (Ebbinghaus: stage, next_due_at) |
| `practice_sessions` | one daily-practice run | `user_id`, `started_at`, `correct_count`, `total_count`, `star_rating int (0..3)`, `duck_power_earned` |
| `practice_answers` | per-question result in a session | `session_id`, `question_id`, `is_correct`, `answer_given`, `time_ms` |
| `assessment_results` (评测 2.9) | IELTS score + radar + report | `user_id`, `ielts_score numeric`, `radar jsonb` (5 axes current/previous), `report jsonb`, `taken_at` |
| `onboarding_profiles` (2.7) | the 5 onboarding answers | `user_id`, `answers jsonb` (5 Q/A), `completed_at` |
| `user_props` (道具) | inventory | `user_id`, `prop_type enum`, `count int` |
| `streaks` (连胜) | current streak + goal | `user_id`, `current_days`, `goal_days`, `last_checkin_date` |
| `checkins` | per-day check-in log | `user_id`, `checkin_date`, `source` |
| `scratch_card_log` (刮刮卡) | rewards granted | `user_id`, `reward_type`, `payload jsonb`, `granted_at` |
| `feedback` (意见反馈) | user feedback | `user_id`, `category`, `body`, `status`, `created_at` |
| `question_error_reports` (题目报错) | flagged bad questions | `user_id`, `question_id`, `reason`, `created_at` |

---

## 6. Reference / config tables (small, fixed — load from spec)

### 6.1 `levels` — see §4.1 (240 rows).

### 6.2 `duck_titles` (鸭力称号 — spec 2.4.2; matches code `DuckTitle`)

| title | min_duck_power |
|-------|---------------|
| 初学鸭 | 0 |
| 努力鸭 | 500 |
| 进步鸭 | 2 000 |
| 熟练鸭 | 5 000 |
| 超级鸭 | 10 000 |
| 卓越鸭 | 20 000 |
| 无敌鸭 | 50 000 |
| 大师鸭 | 100 000 |

### 6.3 `prop_types`
`streak_protection` (连胜保护) · `challenge_key` (挑战赛钥匙).

### 6.4 `scratch_rewards` (刮刮卡 — spec 辅助功能, optional table or app-config)
Reward pool & probabilities: 经验值翻倍 40% · 经验值 30% · 连胜保护 10% ·
挑战赛钥匙 10% · 头像 10% (with the special first-5 fixed sequence and the
"guarantee a protection prop if user has none" rule). EXP reward = random
multiple of 5 in 20–40. Doubling = {10/20/30 min} × {1.5/2/3×}.

### 6.5 Scoring rules (encode in app, but data must support them)
- **Stars by accuracy:** 0★ <40% · 1★ 40–65% · 2★ 65–90% · 3★ ≥90%.
- **鸭力值:** +1 per correct; +5 if all correct.
- **Combo:** >5 correct → +1/correct; >10 → +2/correct.
- **Speed bonus:** 3★ within `expected_time_ms` → +5. *(⇒ every question MUST have
  a sensible `expected_time_ms`.)*

---

## 7. Supabase Storage (files)

| Bucket | Contents | Path convention | Public? |
|--------|----------|-----------------|---------|
| `pronunciations` | per-word audio | `pronunciations/{word_id}.mp3` | read-only public |
| `example-audio` | per-example sentence audio | `example-audio/{example_id}.mp3` | read-only public |
| `question-media` | any extra question audio/images | `question-media/{question_id}.*` | read-only public |
| `avatars` | user + unlockable avatars | `avatars/{user_id}/...` & `avatars/system/...` | user-owned / system public |

- Audio format: **mp3 or m4a**, mono, normalized loudness, target ≤ ~50 KB/word.
- Store only the **path** in Postgres; build the public URL in the app.
- Naming by UUID (not by headword) avoids collisions & encoding issues.

---

## 8. Security (RLS) — non-negotiable

- **Enable Row Level Security on every table.**
- **Content tables** (`words`, `examples`, `questions`, `levels`, refs…):
  policy = `select` allowed to all authenticated users; **no** client insert/update
  (loaded by you via service role / admin only).
- **User tables** (`profiles`, `*_progress`, `mistake_words`, sessions, etc.):
  policy = a user may `select/insert/update` **only rows where
  `user_id = auth.uid()`**. No cross-user reads.
- `profiles.id` must equal `auth.users.id` (1:1).

---

## 9. VOLUME BUDGET — how much data to produce

Assumptions: **240 levels × ~80 words = ~19,200 words** (plan range **18k–20k**).

| Asset | Per word | Total (×~19,200) | Notes |
|-------|----------|------------------|-------|
| Word rows | 1 | **~19,200** | core atoms |
| Meanings (zh + EN def) | ~1.5 | ~29,000 | EN def required for type 9 |
| Example sentences | ≥2 | **~40,000** | +zh translation + target_span each |
| Pronunciation audio | 1 | **~19,200 files** | TTS or recorded |
| Example audio | ≥1 | **~20,000+ files** | for listening types |
| Distractor sets | ~1 per option-word | ~19,200 sets (×3 each) | for option questions |
| **Questions (generated)** | ~8–12 across types | **~150,000–230,000** | ⚠ see below |

> ⚠️ **The question count is enormous IF authored by hand — and trivial if
> generated.** Because types 1,2,3,4,12,13 all derive from
> *example + target_span (+audio)(+distractors)*, and 9/10/11/14 derive from
> *definition/forms/root/translation*, the realistic plan is: **author the ~19,200
> word packages well, then auto-generate the question bank.** Hand-authoring
> 150k+ questions is not viable. **Budget effort on atoms, not questions.**

**Phased sourcing (don't build all 19k before testing):**
- **Pilot:** 1 level (~80 words), all assets, all 14 types generated → validate the
  whole pipeline end to end.
- **MVP content:** bands 4.0–5.5 (Lv1–126 ≈ ~10,000 words) — the beginner majority.
- **Full:** remaining bands 6.0–8.0.

---

## 10. Data constructor's shopping list (do in this order)

1. **Lock the open questions in §11.** (Cheap now, expensive later.)
2. **Load reference tables:** `levels` (240), `duck_titles` (8), `question_types`
   (14), `prop_types`. Values are all in this doc.
3. **Define the word-package template & generation rules** (which types generate
   from which fields; distractor strategy; audio source TTS vs recorded).
4. **Produce the PILOT level** (~80 full word packages) and generate its questions.
5. **Validate** with the app on fake→real swap: do all 14 types render & grade?
6. **Mass-produce** word packages band by band (§9 phases); regenerate questions.
7. **Upload audio** to Storage with the UUID path convention (§7).
8. **QA pass:** every option question has exactly 1 correct + 3 distractors; every
   listening word has a non-audio fallback; every question has `expected_time_ms`.

---

## 11. Open questions to resolve BEFORE mass production

1. **Word list source.** Which IELTS word list defines the 19.2k words and their
   level/band assignment? (Licensed list? Self-curated? This gates everything.)
2. **Audio: TTS or human-recorded?** Cost, quality, and licensing differ hugely at
   ~40k files. Decide per asset type (word vs sentence).
3. **Question generation: rule-based templates vs AI-assisted?** And who reviews
   generated questions for quality? (Ties into the "AI faked until late" plan.)
4. **Distractor strategy.** Hand-picked vs generated from same level/POS? Quality
   of distractors largely determines question difficulty validity.
5. **夸夸精讲 / explanation content.** Authored per question, or AI-generated on
   demand at runtime (spec hints "获取讲解内容" = fetched live)? If live, it is
   **not** content you pre-produce — confirm.
6. **Mnemonic & root/affix coverage.** Required for all words or best-effort? Type
   11 (词根词缀) only works for decomposable words — define the fallback.
7. **Licensing/copyright** of any sourced sentences, definitions, or audio.
8. **Content versioning / update flow.** How do content corrections reach users —
   straight table edits, or versioned releases?

---

*End of guide. Questions on any table → reconcile against `ARCHITECTURE.md §4`
(domain model) and the source spec in `第一期原型图+文档`.*
