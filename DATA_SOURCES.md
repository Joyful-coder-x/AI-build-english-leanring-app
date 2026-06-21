# KuaKua Duck — Approved Data Sources Registry

**Purpose.** Every piece of content loaded into the Supabase database must
originate from a source listed here. If a source is not on this list, do not
use it without PM approval. Do not fabricate any linguistic data (definitions,
phonetics, example sentences, translations, or etymology).

When a data row is produced, record which source it came from in your working
spreadsheet (not in the DB — source metadata stays in your production log, not
in the app's tables).

---

## 1. Word Lists (defines the 19,200 words and their level assignment)

These sources define WHICH words belong at which IELTS level. Pick one primary
list; use supplementary lists only to fill gaps or verify coverage.

| Source | URL | Trust level | Notes |
|--------|-----|-------------|-------|
| **Cambridge English Vocabulary for IELTS** | https://www.cambridge.org/elt/catalogue/subject/item2701990 | ✅ Primary | Official Cambridge; bands align with IELTS scores |
| **British Council IELTS vocabulary** | https://learnenglish.britishcouncil.org/grammar/english-grammar-reference/vocabulary | ✅ Primary | Free; officially endorsed |
| **Oxford IELTS Wordlist** | https://www.oxfordlearnersdictionaries.com/wordlists/oxford3000-5000 | ✅ Supplementary | Oxford 3000 / 5000 overlap well with IELTS bands |
| **IELTS Liz word lists** | https://ieltsliz.com/ielts-vocabulary/ | ⚠️ Cross-check only | Practitioner-curated; use to verify, not as primary |

> ✅ **Locked 2026-06-12:** Oxford 3000/5000 is the primary list.
> Oxford 3000 covers bands 4.0–6.0; Oxford 5000 covers bands 6.5–8.0.
> Use the British Council IELTS list to fill any gaps.

---

## 2. Definitions & Phonetics (IPA)

Every `definition_zh`, `definition_en`, and `phonetic` field must come from one
of these dictionaries. Do not invent or paraphrase definitions.

| Source | URL | Use for | Notes |
|--------|-----|---------|-------|
| **Cambridge Dictionary** | https://dictionary.cambridge.org | `definition_en`, `phonetic` (British IPA) | Most aligned with IELTS; preferred primary |
| **Oxford Learner's Dictionaries (OALD)** | https://www.oxfordlearnersdictionaries.com | `definition_en`, `phonetic`, `pos_primary` | OALD 10th ed.; excellent learner definitions |
| **Merriam-Webster** | https://www.merriam-webster.com | `definition_en` cross-check | American English; use to verify edge cases |
| **有道词典 (Youdao)** | https://www.youdao.com | `definition_zh` | Industry-standard CN-EN; machine + human reviewed |
| **MDBG Chinese-English Dictionary** | https://www.mdbg.net | `definition_zh` cross-check | Open-source CC-licensed; good for verification |

**Rules:**
- `phonetic` must be British IPA (Cambridge format), e.g. `/əˈbændən/`.
- `definition_en` must be a learner-appropriate definition (not a technical one).
- `definition_zh` must be verified against Youdao; do not use machine translation
  alone — spot-check 10% of rows manually.

---

## 3. Example Sentences

Every `sentence_en` must come from a real corpus or dictionary — never
fabricated. The sentence must naturally contain the target word.

| Source | URL | Use for | Notes |
|--------|-----|---------|-------|
| **Cambridge Dictionary examples** | https://dictionary.cambridge.org | Primary sentence source | Example sentences shown per entry; citation-free for educational use |
| **OALD example sentences** | https://www.oxfordlearnersdictionaries.com | Primary sentence source | Carefully levelled for learners |
| **COCA — Corpus of Contemporary American English** | https://www.english-corpora.org/coca/ | Supplementary, when dict examples insufficient | Real-world corpus; filter by register (academic/fiction) |
| **BNC — British National Corpus** | https://www.english-corpora.org/bnc/ | Supplementary | British English; good for IELTS alignment |

**Rules:**
- Each sentence must contain the `target_span` as a natural substring (not inserted
  awkwardly). Verify that blanking the `target_span` produces a solvable fill-in.
- Do not use sentences that reveal the answer in the surrounding context (e.g., a
  definition embedded in the sentence).
- Each word must have ≥2 example sentences from different contexts.

---

## 4. Chinese Translations of Example Sentences

| Source | URL | Use for | Notes |
|--------|-----|---------|-------|
| **DeepL** | https://www.deepl.com | `translation_zh` first draft | Highest quality MT for EN→ZH; still requires human review |
| **有道翻译** | https://fanyi.youdao.com | `translation_zh` cross-check | Good for colloquial Chinese naturalness check |

**Rule:** Machine translations are a starting point only. Every `translation_zh`
must be reviewed by a native Chinese speaker before bulk loading. Flag any
translation that sounds unnatural or loses the meaning of `target_span`.

---

## 5. Etymology, Roots & Affixes

Used for `words.root_affix` and TYPE 11 questions (词根词缀变化).

| Source | URL | Use for | Notes |
|--------|-----|---------|-------|
| **Etymonline** | https://www.etymonline.com | Root/affix origin and gloss | Most trusted English etymology reference online; free |
| **Merriam-Webster etymology** | https://www.merriam-webster.com | Cross-check for root gloss | Secondary verification |
| **Wiktionary etymology sections** | https://en.wiktionary.org | Supplementary only | CC-BY-SA licensed; quality varies — always cross-check with Etymonline |

**Rule:** Only populate `root_affix` when a clear, learner-relevant root/prefix/
suffix exists. Leave null for words where the decomposition would confuse rather
than help (e.g., words where the modern meaning has drifted far from the root).

---

## 6. Word Forms (inflections)

Used for `word_forms` table and TYPE 10 questions (词形变化).

| Source | URL | Use for | Notes |
|--------|-----|---------|-------|
| **Cambridge Dictionary grammar section** | https://dictionary.cambridge.org | All inflected forms | Shows irregular past, plural, comparative, -ing forms |
| **OALD grammar codes** | https://www.oxfordlearnersdictionaries.com | Inflection patterns | Especially useful for irregular verbs and countability |

**Rule:** Only create `word_forms` rows for forms that are irregular or
noteworthy. Regular forms (walk → walked, cat → cats) do NOT need a DB row.

---

## 7. Mnemonics (助记法)

Used for `words.mnemonic` — the Chinese memory aid shown in the word detail screen.

| Source | Use for | Notes |
|--------|---------|-------|
| **Etymonline** + your own synthesis | Root-based mnemonics | Derive from actual etymology; do not fabricate etymology |
| **沪江英语 (hujiang.com)** | Inspiration for Chinese memory hooks | Chinese learner community; verify that mnemonic is accurate before using |
| **百词斩 (baicizhan.com)** | Inspiration only | Cross-check quality; do not copy verbatim |

**Rule:** A mnemonic must be based on real word features (root, sound, spelling
pattern). Do not create false etymologies. Mark synthetic/creative mnemonics
differently from root-based ones in your production log.

---

## 8. Audio Files

| Source | Use for | Format | Notes |
|--------|---------|--------|-------|
| **Google Cloud Text-to-Speech** | Pronunciation audio (`pronunciations/`) | mp3, mono, 22kHz, ≤50 KB | Use `en-GB-Standard-B` (male) or `en-GB-Standard-A` (female) voice for IELTS (British English) |
| **Amazon Polly** | Alternative TTS | mp3 | `Brian` (en-GB) voice; similar quality |
| **Cambridge Dictionary audio** | Spot-check reference only | — | Cannot bulk-download; use only to QA TTS quality on sample words |

**Rules:**
- All pronunciation audio must be British English (IELTS standard).
- Normalize loudness to -16 LUFS before upload.
- File naming: `{word_uuid}.mp3` for pronunciation, `{example_uuid}.mp3` for
  example audio. Never name by headword (encoding/collision issues).
- Do not use audio scraped from dictionary websites — copyright risk.

---

## 9. Distractors (Wrong Options for MCQ Questions)

Distractors are the 3 wrong answer choices for TYPE 2, 3, 9, 11, 13 questions.

**Approved strategy — pick from same level, same POS:**
1. From the same `level_number` → same difficulty band.
2. Same `pos_primary` as the correct answer → grammatically plausible.
3. Different enough in meaning to be clearly wrong on reflection.
4. NOT phonetically or visually identical to the correct answer (not confusable
   spellings — those belong in a different question type).

**Source:** Your own `words` table — once words are loaded, distractors are
drawn programmatically. You do not need an external source for distractors.

---

## 10. What Is NOT an Approved Source

| Source | Reason not approved |
|--------|---------------------|
| ChatGPT / Claude / any LLM as primary source | LLMs hallucinate definitions, IPA, and etymology. Use only to FORMAT data that was sourced from approved references above, or to generate question stems from verified word packages. |
| Random IELTS blogs / prep websites | No editorial standard; definitions often paraphrased incorrectly |
| Wikipedia (as primary) | Encyclopedic, not dictionary-level; definitions not learner-appropriate |
| Google Translate alone | Acceptable only as a starting point for `translation_zh`; must be human-reviewed |
| Hand-crafted / invented sentences | Never acceptable; sentences must come from real corpus or approved dictionaries |

---

## Source Citation Log (keep this updated during production)

Maintain a separate spreadsheet (not in the DB) with one row per word package:

| Column | What to record |
|--------|---------------|
| `headword` | The word |
| `word_list_source` | Which approved word list it came from (§1) |
| `definition_source` | Cambridge / OALD / other (§2) |
| `example_source_1` | URL or source name for example sentence 1 |
| `example_source_2` | URL or source name for example sentence 2 |
| `translation_reviewer` | Name/initials of person who verified `translation_zh` |
| `etymology_source` | Etymonline / Merriam-Webster / null (§5) |
| `audio_generated_by` | Google TTS / Amazon Polly + voice name (§8) |
| `qa_passed` | ✅ / ❌ |

This log is your audit trail. It is not loaded into Supabase but must be
retained for content QA and copyright compliance reviews.
