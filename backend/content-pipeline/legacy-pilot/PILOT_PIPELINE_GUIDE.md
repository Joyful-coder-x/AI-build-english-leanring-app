# Content Pipeline Operations Guide

**Who this is for:** Anyone (human or Claude) running this pipeline to produce word packages for Supabase.
This guide was written after the Level 1 pilot run (20 words: boy, man, son, baby, girl, wife, bed, bath, door, room, egg, tea, food, milk, day, hour, buy, eat, ask, see).

---

## Quick Reference — Full Run Order

```powershell
# All commands run from: d:\project\content_pipeline\scripts

# One-time session setup
$env:ANTHROPIC_API_KEY = "sk-ant-..."

# Step 1:  Fill level_001_seed.csv manually (see §WORD SELECTION)
# Step 2:  Fetch English raw data
python fetch_candidates.py

# ⛔ STOP — review output/level_001_candidates.jsonl before continuing
# (see §QUALITY GATE 1)

python normalize_senses.py

# ⛔ STOP — review output/level_001_packages.todo.json before continuing
# (see §QUALITY GATE 2)

# Step 4:  English LLM rewrite
python rewrite_and_draft.py

# ⛔ STOP — spot-check packages/level_001_packages.json before continuing
# (see §QUALITY GATE 3)

# Step 5:  Chinese translation
python translate_chinese.py

# Step 6:  Validate schema
python validate_packages.py          # must print "passed: N word(s)"

# Step 7:  Export to CSV
python export_csv.py
python generate_questions.py
python generate_tts_manifest.py

# Then: import CSVs to Supabase in the order shown in §SUPABASE LOAD ORDER
```

---

## Word Selection Rules

### Batch size
- **Run 20–50 words per batch, not all 2880 at once.**
- Reason: if normalize_senses.py picks a wrong sense for a word, you catch it before wasting API calls on 2880 words. Validate each batch end-to-end before starting the next.
- Suggested schedule: 1 batch per level per session. Oxford A1 has ~500 words; run in groups of 20–50.

### Words to INCLUDE
- Concrete nouns with one clear primary meaning: `family, home, water, food, book, school`
- Basic verbs with one clear primary action: `eat, drink, open, close, walk, help, buy`
- Common adjectives with one clear primary sense: `big, small, hot, cold, new, old`

### Words to EXCLUDE from the automated pipeline
These word types cause `fetch_candidates.py` or `normalize_senses.py` to fail or pick wrong senses.
Run them through a manual package entry instead.

| Word type | POS code | Examples | Problem |
|-----------|----------|----------|---------|
| Function words | pron., prep., conj., det., exclam. | i, at, he, and, oh | FreeDictionaryAPI has no useful data |
| Highly polysemous verbs | v. | see, run, make, take, get, go | API picks metaphorical sense over primary |
| Highly polysemous nouns | n. | tea (slang), bed (geological), room (space/freedom) | API picks rare/slang sense |
| Abbreviations and acronyms | — | TV, ID, app | No phonetic; poor sense coverage |
| Words where POS varies widely | — | fast (adj/adv/v), well (adj/adv/n) | normalize picks wrong POS sense |

### How to pick words from the Oxford A1 CSV

1. Open `content_pipeline/output/american_oxford_3000_a1.csv`
2. Skip all rows where `topic = "Core Function Words"` (these are the function words listed above)
3. Pick words from concrete topics: People, Home, Food, Time, Basic Actions, Nature, Numbers
4. Copy selected rows into `content_pipeline/input/level_001_seed.csv` using this format:

```csv
headword,pos,cefr_level,source,notes
family,n.,A1,Oxford 3000,
eat,v.,A1,Oxford 3000,
```

---

## Quality Gate 1 — After fetch_candidates.py

**File to check:** `content_pipeline/output/level_001_candidates.jsonl`

Open the file and scan for `"status": "not_found"`. If any words were not found:
- Try an alternate spelling or the base form (e.g., `families` → `family`)
- Or replace the word in the seed CSV and re-run `fetch_candidates.py` (it skips already-fetched words)

**Do NOT proceed to normalize_senses.py if more than 20% of words are `not_found`.**
It means the word selection has too many function words or rare forms.

---

## Quality Gate 2 — After normalize_senses.py ⚠️ MOST IMPORTANT GATE

**File to check:** `content_pipeline/output/level_001_packages.todo.json`

This is the most important manual review step. Open the file and check **every word** for:

### 2A — Wrong sense picked

The scoring algorithm can pick a rare, metaphorical, or slang sense instead of the primary meaning.
**Red flags to look for:**

| Signal | Example from pilot | What to do |
|--------|--------------------|-----------|
| `definition_raw` describes something unrelated to the word's common meaning | `tea` → "A drug smoked or ingested for euphoric effect, cannabis" | Replace `definition_raw` and `example_raw` manually |
| `definition_raw` is about a technical/scientific usage | `bath` → "A substance in which something is immersed" | Replace with the everyday sense |
| `example_raw` is bizarre or impossible in a learner context | `tea` → "After smoking a bowl of that fine marijuana..." | Replace the example |
| `definition_raw` uses "(with possessive pronoun)" or other grammar notes | `room` → "(with possessive pronoun) bedroom" | Replace with plain definition |
| `definition_raw` is about the animal sense of a word | `wife` → "The female of a pair of mated animals" | Replace with the human sense |

**How to fix:** Edit `level_001_packages.todo.json` directly. Replace the wrong `definition_raw` and `example_raw` with the correct primary-sense content. Use Cambridge Dictionary or OALD as reference.

Example fix:
```json
"definition_raw": "A hot drink made by pouring boiling water over dried leaves.",
"example_raw": "She drinks a cup of tea every morning."
```

### 2B — Inappropriate or wrong distractors

Datamuse sometimes returns distractors that are:
- **Near-synonyms** (bad: the MCQ answer is too obvious)
- **Vulgar or inappropriate** for a learning app
- **Compound forms or abbreviations of the headword itself**
- **Words from other languages** (happens with religious/classical terms)
- **Way too close in meaning** (learner can't distinguish)

**Known bad distractor patterns from the pilot:**

| Word | Bad distractors | Reason bad | Fixed to |
|------|----------------|------------|---------|
| `egg` | testicle, gonad, testis | Inappropriate/vulgar | bread, milk, cheese |
| `bed` | seam, screw, bottom | Wrong senses of "bed" | chair, table, sofa |
| `room` | elbow room, way, board | Idiom/abstract senses | garden, kitchen, office |
| `son` | logos, word | Greek translation of "son" in religious texts | daughter, brother, father |
| `man` | mankind, humanity, humankind | Synonymous compounds | woman, boy, person |
| `ask` | inquire, enquire, require | Near-synonyms, bad MCQ options | tell, answer, show |
| `hour` | hr | Abbreviation of the headword itself | minute, day, week |
| `day` | daytime, daylight, mean solar day | Parts of / compounds of the headword | night, week, hour |
| `buy` | purchase | Near-synonym | sell, find, lose |

**Distractor rules (must satisfy ALL):**
1. Same POS as headword
2. Same CEFR level (A1 for Level 1 words)
3. Clearly different in meaning — a learner should know it's wrong
4. Not a synonym (don't use thesaurus.com for distractors)
5. Not a compound/derivative of the headword (no "homework" as distractor for "home")
6. Not vulgar, offensive, or inappropriate
7. Not an abbreviation
8. Not a word in another language

**Good distractor pattern:** Think of 3 other words a learner might confuse or associate with this word, but that are clearly different in meaning when used in a sentence. For nouns, use other nouns in the same semantic category. For verbs, use other verbs from a different category.

---

## Quality Gate 3 — After rewrite_and_draft.py

**File to check:** `content_pipeline/packages/level_001_packages.json`

Spot-check 5 random words. For each one verify:

| Check | Rule |
|-------|------|
| `definition_en` length | ≤ 12 words |
| `definition_en` content | Does NOT contain the headword itself |
| `definition_en` vocabulary | Only A1/A2 words — no complex words |
| `examples[0].sentence_en` | Contains the EXACT headword string |
| `examples[1].sentence_en` | Contains the EXACT headword string, different context |
| `mnemonic` | Non-empty, makes sense in English |
| `definition_zh` | Still says `[待翻译]` (correct — filled by next step) |
| `phonetic` | Starts and ends with `/` |
| `distractors` | Exactly 3, all different from headword |

If `sentence_en` does NOT contain the headword, the validate step will fail on `target_span`. Fix it manually before running translate_chinese.py.

---

## Known Issues with Each Script

### fetch_candidates.py

| Issue | Description | Fix |
|-------|-------------|-----|
| Wrong phonetic IPA | API sometimes returns non-standard IPA characters (e.g., `/bɔːə/` for "boy" instead of `/bɔɪ/`) | Fix in todo.json before running normalize |
| Rate limiting | If you run too fast you get 429 errors | The default 4s delay handles this; don't lower it below 3s |
| `not_found` for common words | Happens with function words and very short words | Remove those words from seed CSV |

### normalize_senses.py

| Issue | Description | Fix |
|-------|-------------|-----|
| Wrong sense selection | Picks metaphorical/slang/rare sense instead of primary | **Always review todo.json before proceeding** (see Quality Gate 2) |
| Bad distractors from Datamuse | Synonyms, vulgar words, compound forms | **Always review distractors before proceeding** (see Quality Gate 2B) |
| Distractor is another headword | If "son" is in your batch and also appears as a distractor for "boy" | It won't break validation but is bad UX; fix manually |
| `phonetic` missing slashes | normalize passes through whatever API returned | Check and fix in todo.json |

### rewrite_and_draft.py

| Issue | Description | Fix |
|-------|-------------|-----|
| Not resume-safe | If it crashes midway, you lose all progress for that run | Re-run from scratch; it's fast (20 words ≈ 2 min) |
| Sentence doesn't contain headword | Claude sometimes uses a different form | The script retries twice; if still fails, the word is skipped with a warning — fix manually in packages.json |
| Wrong definition despite good `definition_raw` | Claude uses its own knowledge when `definition_raw` is clearly wrong — this is usually a feature, not a bug | Review output and override if wrong |
| API key not set | Fails immediately with `ANTHROPIC_API_KEY not set` | Set `$env:ANTHROPIC_API_KEY = "sk-ant-..."` in your terminal session |

### normalize_senses.py — Distractor Datamuse issue

| Issue | Description | Fix |
|-------|-------------|-----|
| Oxford A1 pool not filtering well | Datamuse boosts Oxford A1 words, but still returns wrong POS or compounds | Manual review of all distractors is mandatory |

### translate_chinese.py

| Issue | Description | Fix |
|-------|-------------|-----|
| `definition_zh` too long | Claude sometimes returns 12+ characters | The script validates and retries; if still long, fix manually |
| Overly formal Chinese | Claude may translate informally as overly literary | Review Chinese output — target is spoken, everyday Chinese |
| Resume-safe | Saves after each word; safe to interrupt and re-run | No action needed |

### validate_packages.py

| Error message | Cause | Fix |
|---------------|-------|-----|
| `phonetic must start and end with /` | normalize or rewrite produced phonetic without slashes | Edit packages.json: add `/` around the IPA |
| `distractors must contain exactly 3 values` | A word has fewer than 3 distractors | Edit todo.json and re-run rewrite, or edit packages.json directly |
| `distractor cannot equal headword` | Datamuse returned the headword as its own distractor | Edit packages.json to replace that distractor |
| `definition_zh is required` | translate_chinese.py skipped a word or left placeholder | Re-run translate_chinese.py or fill manually |
| `target_span is not a literal substring of sentence_en` | Sentence doesn't contain the exact headword string | Edit packages.json: fix either sentence_en or target_span |
| `mnemonic must be non-null and non-blank` | rewrite step skipped this word | Edit packages.json: add a mnemonic manually |

---

## Scaling Plan — 2880 Words

The full Oxford 3000 has approximately 3000 words. After removing function words (~120), you have ~2880 content words across CEFR levels A1–B2.

### Recommended batch schedule

| Batch | Words | CEFR | Estimated time |
|-------|-------|------|----------------|
| Pilot | 20 | A1 | 1 session |
| Batch 2 | 50 | A1 (remaining) | 1 session |
| Batch 3 | 50 | A1 (complete) | 1 session |
| Batch 4–8 | 50 each | A2 | 5 sessions |
| Batch 9–20 | 50 each | B1 | 12 sessions |
| Batch 21–40 | 50 each | B2 | 20 sessions |

**Total:** ~40 sessions to complete all 3000 words. Each session takes ~2 hours including review.

### Per-batch checklist

```
☐ Fill 20–50 rows into level_001_seed.csv (skip function words)
☐ python fetch_candidates.py
☐ Review candidates.jsonl — check for not_found words, replace if needed
☐ python normalize_senses.py
☐ ⚠️ Review EVERY word in todo.json:
    ☐ definition_raw makes sense for the primary meaning
    ☐ example_raw is appropriate for a learner app
    ☐ All 3 distractors are: same POS, different meaning, not synonyms, not vulgar
    ☐ phonetic has slashes and looks correct
☐ python rewrite_and_draft.py
☐ Spot-check 5 words in packages.json (definition_en ≤12 words, sentences contain headword)
☐ python translate_chinese.py
☐ Review all definition_zh: 4–10 characters, learner-friendly, correct meaning
☐ Review all translation_zh: natural Chinese, not overly formal
☐ python validate_packages.py  ← must pass before proceeding
☐ python export_csv.py
☐ python generate_questions.py
☐ python generate_tts_manifest.py
☐ Import CSVs to Supabase (see §SUPABASE LOAD ORDER)
☐ Test 3 words in the app
```

### Supabase incremental updates

After the first load, subsequent batches are additive. You do NOT delete and re-import all data each time. The UUIDs are stable (deterministic from headword + level_number), so re-importing a word that already exists will cause a duplicate key error.

**Safe update process for new batches:**
1. Run the full pipeline on new words only (the seed CSV only has new words)
2. In Supabase Table Editor, use **Insert** → **Import data from CSV** — this appends rows, it does NOT replace existing ones
3. Import in the same order: words → word_meanings → word_forms → examples → questions → question_options

---

## Important: Pipeline vs DATA_SOURCES.md

`DATA_SOURCES.md` lists strict rules about approved data sources. The pipeline in this directory produces **AI-draft content**, not final production-approved content. Before bulk-loading to production Supabase, the following checks from DATA_SOURCES.md must be completed by a human:

| Field | Pipeline produces | Required before production load |
|-------|------------------|--------------------------------|
| `definition_en` | AI-rewritten draft | Verify against Cambridge Dictionary definition |
| `sentence_en` | AI-generated original | Acceptable if it's clearly original and natural |
| `phonetic` | FreeDictionaryAPI (staging) | Verify against Cambridge Dictionary IPA |
| `definition_zh` | Claude translation | Spot-check 10% against Youdao |
| `translation_zh` | Claude translation | Reviewed by native Chinese speaker |
| `mnemonic` | AI-generated | Human approval before load |

The pipeline exists to dramatically speed up the drafting process. It does NOT eliminate the QA step. For a 20-word pilot, full human review is fast. For 2880 words, review at least 10% of each field type.

---

## Environment Setup for Each Session

The `ANTHROPIC_API_KEY` is not persisted between terminal sessions. Set it every time:

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

Find your key at: **console.anthropic.com → API Keys**

All scripts must be run from the `scripts/` directory:

```powershell
cd d:\project\content_pipeline\scripts
```

---

## File Reference

| File | Purpose | Safe to edit? |
|------|---------|---------------|
| `input/level_001_seed.csv` | Input word list | ✅ Yes — fill this with your selected words |
| `output/level_001_candidates.jsonl` | Raw API fetch results | ✅ Yes — delete to re-fetch from scratch |
| `output/level_001_packages.todo.json` | Normalized staging data | ✅ Yes — review and fix here before LLM step |
| `packages/level_001_packages.json` | Final package (LLM output) | ✅ Yes — fix edge cases here before validate |
| `output/words.csv` etc. | Supabase-ready exports | ⚠️ No — re-generate via export_csv.py instead |
| `config/pipeline_config.json` | Level config, UUIDs, TTS config | ⚠️ Do not change uuid_namespace — breaks stable IDs |
| `scripts/validate_packages.py` | Validation rules | ❌ Do not modify — it enforces the schema contract |

---

## What to Tell Claude at the Start of a New Session

When continuing pipeline work in a new conversation, give Claude this context:

```
We are running the KuaKua Duck content pipeline to produce word packages for Supabase.
The pipeline is in d:\project\content_pipeline\.
Read PIPELINE_GUIDE.md before doing anything.
The current batch is [LEVEL] words: [list words].
We are at Step [N] — [step name].
The last thing completed was [what you did].
Issues to watch out for: normalize_senses.py often picks wrong senses — always review
todo.json before running rewrite_and_draft.py.
```
