# KuaKua Duck - IELTS Word Research Guide

**Purpose:** give an external researcher a complete, standalone checklist for
finding IELTS vocabulary words and source-backed evidence.

**Last updated:** 2026-06-17

**Standalone rule:** this document must work by itself. Do not assume the
researcher has access to the app repository, database schema, prototype files,
pipeline scripts, or any other internal document. All required source rules,
copyright rules, output fields, exclusion rules, and question-pattern rules are
included below.

---

## 1. Project Overview

KuaKua Duck is a gamified IELTS vocabulary-learning app for Chinese learners.
Users study words, answer daily practice questions, review wrong words, and
progress through IELTS-aligned levels from band 4.0 to 8.0.

The app eventually stores approved vocabulary content in database tables for:

- Words: headword, level, phonetic, part of speech, mnemonic, pronunciation path.
- Word meanings: Chinese and English definitions.
- Examples: sourced example sentences and Chinese translations.
- Questions: generated practice questions based on approved word data.
- Question options: multiple-choice options for question types that need them.

The researcher does not write app code and does not create final database rows.
The researcher finds source-backed candidate words, records which quality boxes
each word checks, and returns a table for PM/content approval.

---

## 2. Source And Copyright Rules

The researcher may use public sources for evidence, but should not copy large
amounts of copyrighted text into the output table. Record source names and URLs
where possible.

### Approved Source Types

- Official IELTS-facing public materials: British Council IELTS, IDP IELTS,
  IELTS.org public pages, and public Cambridge IELTS sample pages.
- Learner dictionaries: Cambridge Dictionary, Oxford Learner's Dictionaries,
  Longman, Collins, Merriam-Webster Learner.
- Chinese dictionary/reference sources: Youdao, MDBG, and human Chinese review.
- Chinese IELTS books, course materials, coaching sites, apps, decks, and learner
  communities as evidence of Chinese learner relevance.
- Corpus sources such as BNC/COCA when examples are needed and dictionary
  examples are not enough.
- Etymology/root sources such as Etymonline, Merriam-Webster, and Wiktionary.

### Copyright Status Labels

Use one of these values in `copyright_status`:

- `reusable` - public/low-risk material may be used directly or heavily
  paraphrased after PM approval.
- `reference_only` - useful as evidence, but do not copy text into production.
- `needs_license` - likely paid/copyrighted source; PM must confirm licensing.
- `unknown` - unclear status; PM must review.

Rules:

- Do not copy from paid Cambridge IELTS books, private course PDFs, paid decks,
  or copyrighted books unless PM confirms licensing.
- Prefer using sources to confirm word choice, sense, difficulty, and pattern
  rather than copying exact text.
- Dictionary/book example sentences should usually be treated as
  `reference_only` unless licensing is confirmed.
- If a source only verifies that a word is IELTS-relevant, record the source
  name/URL and do not copy long passages.
- AI may help organize notes, but AI must not invent definitions, examples,
  source names, IELTS frequency, band level, or pronunciation.

---

## 3. Research Goal

For each candidate word, find enough evidence to check as many boxes as
possible. The best words are not just "real English words"; they have IELTS
relevance, Chinese learner relevance, reliable definitions, usable examples,
and enough source material to create app questions.

Use this rule of thumb:

- **9-12 boxes checked:** strong candidate; likely ready for PM approval.
- **6-8 boxes checked:** possible candidate; usually needs PM review or more sources.
- **3-5 boxes checked:** weak candidate; keep only if strategically important.
- **0-2 boxes checked:** exclude.

Do not fill unchecked boxes with AI. Leave gaps visible.

---

## 4. Word Research Checklist

For every word, check these boxes.

### Must-Have Boxes

| Box | Requirement | If missing |
|-----|-------------|------------|
| 1 | Clear `headword` and primary `pos` | `EXCLUDE` or `MANUAL_PACKAGE_CANDIDATE` |
| 2 | Clear IELTS-relevant meaning/sense | `FLAG_FOR_PM` |
| 3 | Reliable English definition source | `FIND_DEFINITION` |
| 4 | Reliable Chinese meaning source | `FIND_DEFINITION` |
| 5 | British IPA / phonetic source | `FIND_IPA` |
| 6 | At least 1 IELTS or IELTS-adjacent word-bank source | `EXCLUDE` unless needed for Level 1 |

### Strong-Signal Boxes

| Box | Requirement | Why it matters |
|-----|-------------|----------------|
| 7 | Appears in 2+ IELTS-specific sources | Confirms IELTS relevance. |
| 8 | Appears in at least 1 Chinese IELTS source | Confirms Chinese learner relevance. |
| 9 | Has IELTS topic cluster | Helps group levels and practice. |
| 10 | Has paper type signal: Reading / Writing / Listening / Speaking | Helps assessment and question planning. |
| 11 | Has 2 usable example sentence sources | Needed for production-ready word package. |
| 12 | Has public question source or source-backed question pattern | Helps avoid invented questions. |

### Nice-To-Have Boxes

| Box | Requirement | Why it matters |
|-----|-------------|----------------|
| 13 | Has Chinese learner difficulty note | Useful for explanations and review. |
| 14 | Has safe mnemonic/root/spelling cue source | Useful for word detail page. |
| 15 | Has clear band or CEFR/Oxford cross-check | Helps level placement. |
| 16 | Has reusable or low-risk copyright status | Speeds production. |

---

## 5. Product Data Requirements

Each approved word should eventually support:

- IELTS band placement: 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, or 8.0.
- App level placement: one of 240 levels, about 80 words per level.
- Word detail page: word, POS, phonetic, British pronunciation, Chinese meaning,
  mnemonic if available, and example sentences.
- Practice questions: sentence fill-in, word choice, Chinese meaning choice,
  listening choice, and English definition choice when enough source data exists.
- Review/assessment use: topic, paper type, difficulty, and learner confusion
  notes where available.

The researcher returns a source-backed research table for PM approval. The
researcher does not create final JSON packages or database rows.

---

## 6. Required Output Format

Return results as a CSV/table with these columns:

```csv
headword,pos,boxes_checked,missing_boxes,recommendation,ielts_band_target,app_level_candidate,cefr_or_oxford_level,topic_cluster,paper_type_flag,source_count_ielts,source_count_chinese,wordbank_sources,definition_en_source,definition_zh_source,phonetic_source,example_source_1,example_source_2,question_source_or_pattern,mnemonic_source,copyright_status,learner_difficulty_note,research_notes,next_action
```

Use one row per headword.

### Field Rules

| Field | Required? | What to enter |
|-------|-----------|---------------|
| `headword` | Yes | Lowercase base word, e.g. `environment`, `analyse`. |
| `pos` | Yes | `n.`, `v.`, `adj.`, `adv.`, or clear primary POS. |
| `boxes_checked` | Yes | Number of checklist boxes checked, e.g. `11/16`. |
| `missing_boxes` | Yes | Short list of missing box numbers, e.g. `5,12,14`. |
| `recommendation` | Yes | `INCLUDE`, `EXCLUDE`, `FLAG_FOR_PM`, `SOURCE_GAP`, `MANUAL_PACKAGE_CANDIDATE`. |
| `ielts_band_target` | Yes | Best IELTS band estimate: `4.0` to `8.0`, or `unknown`. |
| `app_level_candidate` | If known | Example: `Level 1`, `Level 55`, or `unknown`. |
| `cefr_or_oxford_level` | If found | `A1`, `A2`, `B1`, `B2`, `C1`, `not_on_oxford`, or `unknown`. |
| `topic_cluster` | Yes | IELTS topic or Level 1 topic. See section 11. |
| `paper_type_flag` | Yes | `Reading`, `Writing`, `Listening`, `Speaking`, `General`, or combined values. |
| `source_count_ielts` | Yes | Number of IELTS-specific sources where the word appears. |
| `source_count_chinese` | Yes | Number of Chinese IELTS sources where the word appears. |
| `wordbank_sources` | Yes | Source names plus URL/page/book chapter if available. |
| `definition_en_source` | Yes | Cambridge/OALD/etc. source, or `missing`. |
| `definition_zh_source` | Yes | Youdao/MDBG/etc. source, or `missing`. |
| `phonetic_source` | Yes | British IPA source, or `IPA_MISSING`. |
| `example_source_1` | Yes | Source for first usable example, or `missing`. |
| `example_source_2` | Yes | Source for second usable example, or `missing`. |
| `question_source_or_pattern` | Yes | Public question source, source-backed pattern, or `PATTERN_ONLY`. |
| `mnemonic_source` | If found | Etymonline/root source, spelling cue, or `missing`. |
| `copyright_status` | Yes | `reusable`, `reference_only`, `needs_license`, or `unknown`. |
| `learner_difficulty_note` | If useful | Chinese learner issue: false friend, spelling, pronunciation, sense confusion. |
| `research_notes` | Yes | Short evidence summary. |
| `next_action` | Yes | See section 12. |

---

## 7. Where To Look First

Search in this order.

### 7.1 Word Bank / Word Selection Sources

Use these to decide whether a word belongs in the app and where it fits.

| Priority | Source | Use it for |
|----------|--------|------------|
| 1 | Cambridge IELTS / Cambridge Vocabulary for IELTS | IELTS vocabulary, topics, academic contexts, difficulty signal. |
| 2 | British Council IELTS / LearnEnglish | Official topic vocabulary and public learning examples. |
| 3 | IDP IELTS public materials | Official IELTS-facing topic/question context. |
| 4 | Chinese IELTS vocabulary books | Chinese learner priority, high-frequency words, must-know words, band/order. |
| 5 | Chinese IELTS coaching sites/apps | Topic lists, real-test vocabulary, paper-type grouping. |
| 6 | Chinese learner communities | Discovery only: repeated must-memorize / easy-confusion / high-score-word claims. Verify elsewhere. |
| 7 | Oxford 3000/5000 | CEFR/difficulty cross-check only. |

Chinese IELTS sources to check:

| Source | Look for |
|--------|----------|
| IELTS vocabulary books from major Chinese publishers/coaches | Word list, band/order, high-frequency words. |
| IELTS reading/listening/writing grouped vocabulary books | Paper-type grouping. |
| New Oriental IELTS core vocabulary materials | Core vocabulary and topic grouping. |
| IELTS Writing Task 2 vocabulary books | Writing vocabulary and collocations. |
| Recent IELTS must-know vocabulary books | Must-know tags and recent market consensus. |
| Glen Gu / 顾家北 style writing vocabulary sources | Writing vocabulary and high-score word usage. |
| IELTS Simon topic vocabulary | Topic vocabulary widely used by Chinese IELTS learners. |
| Chinese IELTS coaching websites | Real-test vocabulary and topic vocabulary. |
| Chinese vocabulary apps/decks such as Baicizhan or Momo IELTS decks | Popularity and difficulty signal only. |
| Xiaohongshu / Zhihu learner posts | Learner pain points; never final evidence by itself. |

### 7.2 English Definition And Phonetic Sources

Use these to find `definition_en`, `phonetic`, and POS:

1. Cambridge Dictionary.
2. Oxford Learner's Dictionaries.
3. Longman / Collins / Merriam-Webster Learner as cross-check.

Rules:

- Prefer British IPA.
- Use learner-friendly definitions.
- Record the source. Do not invent definitions with AI.

### 7.3 Chinese Meaning Sources

Use these to find `definition_zh`:

1. Youdao Dictionary.
2. MDBG Chinese-English Dictionary.
3. Human Chinese review if dictionary meanings are too broad or unnatural.

Rules:

- Keep Chinese meanings short and app-friendly.
- If multiple Chinese meanings exist, choose the IELTS-relevant sense.
- Record uncertainty in `research_notes`.

### 7.4 Example Sentence Sources

Use these to find `example_source_1` and `example_source_2`:

1. Cambridge Dictionary examples.
2. Oxford Learner's Dictionaries examples.
3. British Council / IDP public learning examples.
4. BNC / COCA corpus examples when dictionary examples are not enough.

Rules:

- Need 2 usable examples for production-ready words.
- Each example must contain the headword or valid inflected form as a literal
  target span.
- Prefer IELTS-like contexts: education, environment, health, technology,
  society, work, travel, media, research, charts, opinions.
- Do not use examples that are too long, too literary, too slang-heavy, or reveal
  the answer.

### 7.5 Question Source Or Pattern Sources

Use these to support question design:

1. British Council / IDP public sample questions.
2. Cambridge public sample pages.
3. Official IELTS public practice pages.
4. IELTS educator pages that explain question type patterns.
5. The built-in app question patterns listed in section 8.

Rules:

- Prefer question patterns over copying full question text.
- Do not copy from paid Cambridge IELTS books, private course PDFs, paid decks,
  or copyrighted books unless PM confirms licensing.
- If no reusable question text exists, use `PATTERN_ONLY` and generate questions
  later from sourced definitions/examples.

### 7.6 Mnemonic Sources

Use these only when available:

1. Etymonline for real root/affix evidence.
2. Merriam-Webster / Wiktionary etymology as cross-check.
3. Chinese mnemonic sites only as inspiration, not copied text.

Rules:

- Missing mnemonic is acceptable.
- Do not create fake etymology.
- If copied text would be needed, mark `needs_license`.

---

## 8. Built-In Question Patterns

Use these patterns to decide whether a word has enough evidence to become app
practice later. Do not write final questions during research unless explicitly
asked; record whether the source data supports these patterns.

### Pattern A: Sentence Fill-In

Purpose: test spelling and meaning in context.

Needed evidence:

- Correct headword and primary POS.
- IELTS-relevant meaning.
- One usable example sentence or source-backed sentence context.

Research note format:

```text
PATTERN_ONLY: sentence fill-in supported by [source/example].
```

### Pattern B: Word Choice / Multiple Choice

Purpose: choose the correct English word from 4 options.

Needed evidence:

- Target word meaning.
- Three plausible but clearly wrong distractors with similar topic/POS.
- Source-backed sentence context.

Research note format:

```text
PATTERN_ONLY: MCQ word choice; distractors need PM/content review.
```

### Pattern C: Chinese Meaning Choice

Purpose: choose the correct Chinese meaning.

Needed evidence:

- Reliable Chinese meaning source.
- One clear primary IELTS-relevant sense.
- Avoid words with several equally common meanings unless PM reviews manually.

### Pattern D: English Definition Choice

Purpose: match the word to an English learner-friendly definition.

Needed evidence:

- Reliable learner dictionary definition.
- Definition can be paraphrased safely.
- Distractors are definitions for other words, not copied from paid sources.

### Pattern E: Listening / Pronunciation Choice

Purpose: connect word recognition with pronunciation.

Needed evidence:

- British IPA or trusted pronunciation source.
- Audio availability can be checked later; researcher only records phonetic
  source unless explicitly asked to find audio licensing.

### Pattern F: Assessment / Topic Classification

Purpose: use words in placement or topic assessment.

Needed evidence:

- Band/CEFR/Oxford level signal.
- IELTS topic cluster.
- Paper type signal where available.

---

## 9. What Counts As A Good Candidate

Mark `INCLUDE` when most of these are true:

- Checks most must-have boxes and strong-signal boxes.
- Appears in an IELTS-specific source.
- Appears in at least one Chinese IELTS source, or has strong official IELTS
  evidence.
- Has a clear primary POS.
- Has a clear IELTS-relevant sense.
- Has reliable English definition, Chinese meaning, and British IPA source.
- Has 2 usable example sources.
- Fits a topic cluster and likely IELTS band.
- Does not violate pipeline exclusion rules.

Mark `FLAG_FOR_PM` when the word is likely useful but has uncertainty:

- Band is unclear.
- Source is copyrighted or paid.
- Meaning differs across sources.
- IELTS relevance is strong but Chinese-source signal is weak.
- It is useful but may require manual handling.

Mark `EXCLUDE` when:

- Checks fewer than 3 boxes.
- It has no IELTS signal.
- It is a function word.
- It is an acronym/abbreviation.
- It has no clear primary POS.
- It is too polysemous for automated handling.
- Source evidence is too weak.

---

## 10. What If You Cannot Find It?

Use these fallback labels. Do not fill gaps with AI.

| Problem | Label / action |
|---------|----------------|
| No IELTS word-bank evidence | Check Chinese IELTS sources, then Oxford. If still absent, `EXCLUDE`. |
| No Chinese IELTS evidence | Keep only with strong official IELTS evidence. Mark `LOW_CHINESE_SIGNAL`. |
| No band assignment | Mark `BAND_UNKNOWN` and `FLAG_FOR_PM`. |
| No reliable English definition | Mark `SOURCE_GAP`; do not invent. |
| No Chinese meaning | Try Youdao/MDBG/human review. If unclear, `FLAG_FOR_PM`. |
| No British IPA | Mark `IPA_MISSING`; word can still be researched but not production-ready. |
| Only one usable example | Mark `PARTIAL_SOURCE` and `FIND_MORE_EXAMPLES`. |
| No reusable question text | Mark `PATTERN_ONLY`; use app templates later. |
| Paid/copyrighted source only | Mark `reference_only` or `needs_license`; do not copy text. |
| Sources disagree on sense | Pick IELTS-relevant sense if clear; otherwise `FLAG_FOR_PM`. |
| Word is important but pipeline-risky | Mark `MANUAL_PACKAGE_CANDIDATE`. |

---

## 11. Topic Clusters

Use IELTS topic clusters when possible:

- Education
- Environment / Climate
- Technology
- Social Issues
- Urbanisation / Housing
- Media & Advertising
- Health
- Transport
- Work / Career
- Travel / Culture
- Government / Policy
- Economy / Business
- Science / Research
- Academic General

For Level 1 / beginner words, use simpler clusters:

- People
- Home
- Food
- Time
- Basic Actions
- Nature
- Numbers
- Basic Descriptions
- School / Study
- Daily Life

---

## 12. Next Action Values

Use exactly one of these in `next_action`:

- `APPROVE_FOR_PIPELINE` - enough evidence; ready for PM approval and seed CSV.
- `PM_REVIEW_BAND` - word is good but band/level is unclear.
- `PM_REVIEW_LICENSE` - source is useful but copyright/licensing is unclear.
- `FIND_MORE_EXAMPLES` - word is good but fewer than 2 usable examples found.
- `FIND_DEFINITION` - word lacks reliable English/Chinese definition source.
- `FIND_IPA` - word lacks British IPA source.
- `PATTERN_ONLY` - no reusable question text; use app templates later.
- `MANUAL_PACKAGE_CANDIDATE` - important word but risky for automated pipeline.
- `EXCLUDE` - do not continue.

---

## 13. Pipeline Exclusion Rules

Do not send these into the automated pipeline:

- Function words: pronouns, prepositions, conjunctions, determiners,
  exclamations.
- Highly polysemous words: `see`, `run`, `make`, `take`, `get`, `go`, `set`,
  `point`, `case`.
- Acronyms and abbreviations: `TV`, `ID`, `app`.
- Words with unclear primary POS: `fast`, `well`, `like`.
- Words that require a phrase to teach correctly.
- Words whose common meaning is unsuitable for the product tone.

If important, mark `MANUAL_PACKAGE_CANDIDATE`. Otherwise mark `EXCLUDE`.

---

## 14. Batch Workflow

Work in batches of 20-50 words.

1. Pick one IELTS topic and target band.
2. Find candidate words from IELTS-specific sources.
3. Cross-check Chinese IELTS sources.
4. Cross-check Oxford/CEFR for difficulty only.
5. Fill the required output table.
6. Apply exclusion and fallback labels.
7. Send table to PM for approval.
8. Only approved rows go into the pipeline seed CSV.

Do not create final packages during research.

---

## 15. Existing Pilot Words

These 20 words are already in the app's pilot data. Do not research or
reproduce them unless the task is specifically to audit existing content:

```text
boy, man, son, baby, girl, wife,
bed, bath, door, room,
egg, tea, food, milk,
day, hour,
buy, eat, ask, see
```

Some pilot words are risky because of polysemy: `see`, `room`, `bed`, `tea`.
Avoid similar words in future automated batches unless manually reviewed.

---

## 16. Current Level 1 Need

- Pilot complete: 20 Level 1 words.
- Need about 60 more words to complete Level 1.
- Look first in these beginner-safe clusters:
  - Nature
  - Numbers
  - Basic Descriptions
  - School / Study
  - Daily Life
- Level 1 words should be concrete, beginner-safe, easy to define, and easy to
  test with simple examples.
