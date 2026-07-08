# KuaKua Duck Data Construction Specification

**Status:** Approved direction for the first production curriculum  
**Primary product:** Academic IELTS vocabulary training for Chinese learners  
**Curriculum size:** 240 levels, approximately 12,530 approved headwords/senses

This document defines the decisions that must guide source ingestion, candidate
selection, enrichment, question generation, review, and Supabase loading.

## 1. Product Track

Version 1 is **Academic IELTS first**.

- Bands 4.0-5.0 build general English foundations needed by all IELTS learners.
- Bands 5.5-8.0 increasingly emphasize Academic Reading, Task 1, Task 2,
  academic collocations, argument language, research, science, and data.
- Listening and Speaking vocabulary remain part of the shared path.

TODO: consider a separate General Training path after version 1. It may reuse
the shared foundation but needs dedicated letter-writing, workplace, migration,
housing, public-service, notice, and practical-reading content.

## 2. Word Definition And Senses

In curriculum plans and user-facing descriptions, use **word**, not "unit".
A word is:

```text
lemma + part of speech + selected sense
```

Example:

```text
address + noun + location details
address + verb + deal with a problem
address + verb + speak formally to an audience
```

Each example above counts as a different word. The same spelling with a
different definition counts as a different word, including when the definitions
are introduced in different levels.

Rules:

- Keep one dictionary/headword record for `address`.
- Store all approved senses on the dictionary page.
- Highlight the sense currently being taught or reviewed.
- A different sense may be introduced as new content at a later level.
- Track mastery separately for each sense.
- Flag highly polysemous or difficult words for mandatory manual review.
- Do not generate questions whose answer is ambiguous between stored senses.

## 3. Curriculum Vocabulary Roles

Classify every sense with exactly one curriculum role:

```text
foundation
general_ielts
topic_recognition
```

### Foundation

High-frequency general English needed before IELTS-specific work. These senses
support everyday communication and later topic learning.

### General IELTS

Reusable words and senses that naturally support multiple IELTS papers and
topics, including argument, cause/effect, comparison, evaluation, and academic
discussion.

### Topic Recognition

Specialized, technical, or strongly topic-bound vocabulary that occurs in
credible IELTS Reading or Listening contexts but has limited natural use in
Speaking or Writing. Requiring production would add unnecessary burden.

Rules:

- Every curriculum word must be relevant to IELTS readiness.
- `topic_recognition` requires credible Reading or Listening usage evidence.
- Roles describe curriculum purpose, not which questions may exist.
- Every role may have every supported question type generated.
- Default `Auto` practice chooses a mix using mastery, mistakes, response time,
  review due dates, and question availability rather than blocking question
  types by role.

TODO: add a setting that lets learners enable or disable question categories,
including spelling, listening, speaking, reading, and writing.

## 4. Level Composition

The curriculum hierarchy is:

```text
words -> levels -> IELTS bands
```

Several words make up a level, and several levels make up an IELTS band. Each
level represents approximately 80 learning/practice word placements, not 80
entirely new words.

Recommended composition:

| Band | New words | Forms/collocations | Reviewed/context words |
|------|-----------|--------------------|------------------------|
| 4.0 | Configured per level; Levels 1–5 use 45 and Levels 6–54 currently use 17–28 | Up to 5 | Fill the remaining slots to approximately 80 |
| 4.5-5.0 | Configured from the reviewed candidate pool | Up to 5 | Fill the remaining slots to approximately 80 |
| 5.5-6.5 | 50 | 10 | 20 |
| 7.0-8.0 | 55 | 15 | 10 |

The current target of approximately 12,530 approved words is sufficient for the
first curriculum. Do not inflate the list with low-value dictionary words just
to reach 19,200 unique headwords.

The Band 4.0 engineering package preserves 225 reviewed senses in Levels 1–5
and adds 1,240 non-duplicate source-backed senses in Levels 6–54, for 1,465
unique senses total. `levels.new_sense_target` must equal the actual number of
new assignments in each level.

## 5. Topic Teaching Model

Each topic should teach:

1. A small group of new, context-driving words.
2. Topic-specific nouns, concepts, and collocations.
3. Reusable cross-topic words that help explain and discuss those concepts.
4. Previously learned words reused in the new context.

Example:

```text
Topic: Environment / climate change

New topic words:
emission, drought, deforestation

Reusable cross-topic words:
impact, factor, result, significant, contribute

Older support words:
change, cause, increase, problem
```

This allows the learner to understand new concepts through familiar language
while repeatedly applying useful middle/core vocabulary.

## 6. Cross-Topic Vocabulary

Each topic must reserve part of its practice mix for cross-topic words
that do not belong clearly to one subject.

Examples:

```text
impact, factor, issue, significant, contribute, affect, result, approach
```

Rules:

- Assign these words primarily by difficulty and function.
- Store one primary functional group such as `cause_effect`, `evaluation`,
  `argument`, `data`, or `general_academic`.
- Attach secondary topic links where useful.
- Introduce each sense once.
- Reuse it in the same or later levels across many topic contexts.
- Do not count cross-topic reuse as another newly learned headword.
- A later distinct sense counts as a new word. A collocation remains a
  collocation placement rather than a new word.

## 7. Topic Assignment

Each sense may have:

- One primary topic.
- Zero to three secondary topics.
- One or more IELTS paper-type flags.
- Functional tags.

Topic assignment is many-to-many. Dictionary identity and curriculum placement
must not be merged into one field.

## 8. English Standard

Use **American English only** for version 1:

- American spelling is canonical: `analyze`, `color`, `center`, `traveling`.
- American pronunciation/audio is canonical.
- Definitions and examples should follow modern American usage.
- British variants may be stored as aliases for recognition and search, but are
  not displayed as the primary form.
- Product-authored answers and generated questions must use American forms.
- Keyboard questions accept the American form as the correct production answer;
  British aliases are not taught as target answers in version 1.

## 9. Words, Forms, And Collocations

Keep these as separate structures:

```text
word/headword
word sense
inflected form
spelling alias
collocation
```

Examples:

```text
word: contribute
forms: contributes, contributed, contributing
collocations: contribute to, make a contribution, contribute significantly
```

Do not create duplicate headwords for inflections. Do not store every phrase as
if it were a standalone word.

## 10. Source Roles

| Source | Approved role |
|--------|---------------|
| Chinese IELTS sources | Learner relevance, topic priority, exam-use evidence |
| ECDICT | Backbone, POS, Chinese draft, forms, frequency, IELTS tag |
| Oxford 5000 data | CEFR and meaning/example cross-check |
| News/books/corpora | Usage evidence and candidate example context |
| Learner dictionaries | Sense and definition QA |
| AI | Classification assistance, rewriting, original examples, mnemonics |

Every value derived from an external source must keep provenance and license
status.

## 11. Band Assignment

`curriculum_band` is an internal teaching placement, not an official IELTS
word-by-word score.

Initial scoring weights:

```text
Chinese IELTS evidence         25
Official IELTS/topic evidence  20
ECDICT IELTS tag               15
Frequency and usefulness       15
Topic relevance                10
CEFR/Oxford agreement          10
Data completeness               5
```

Band assignment also requires qualitative checks for abstraction, productive
use, collocation difficulty, polysemy, and expected Reading/Listening
recognition.

## 12. Examples And Quotations

Use a **two-layer example system**. Real-world source evidence and app practice
content are separate records with different rules.

### 12.1 Layer 1: Usage Evidence

Collect short real-world examples from news, books, research papers, public
reports, dictionaries, and corpora to confirm:

- The exact sense being used.
- Natural collocations.
- Grammar and register.
- IELTS topic relevance.
- Which curriculum role the sense serves.
- Whether a later meaning should be introduced at a different level.

Store at least:

```text
headword
sense_id
quoted_text
matched_span
source_title
source_author
source_publisher
source_url_or_locator
publication_date
topic
usage_analysis
license
copyright_status
```

Usage evidence is research data. It is not automatically an app exercise.

For copyrighted news, books, and dictionaries:

- Keep excerpts short and limited to what is needed to demonstrate usage.
- Store full attribution and a link/page locator.
- Do not copy articles, chapters, or large passages.
- Do not bypass paywalls, subscriptions, DRM, or access controls.
- Mark as `private_study_only` when used in this personal app.
- If the app is ever shared or published, exclude these records from the public
  build unless permission or a suitable license has been confirmed.

### 12.2 Layer 2: Practice Examples

Create a separate original sentence for app exercises. It may be:

- Written by a human.
- Generated by AI from one or more approved usage-evidence records.
- Reused directly from a source whose license explicitly permits it.

The practice sentence must:

- Express the approved target sense unambiguously.
- Use American English.
- Match the target curriculum band.
- Use previously learned support vocabulary where possible.
- Contain the exact target form needed by the question.
- Be short enough for mobile practice.
- Support a reliable Chinese translation.
- Avoid unnecessary names, politics, violence, or sensitive claims.
- Pass automated validation and risk-based review.

Do not lightly paraphrase one copyrighted sentence and call it original. Generate
the app sentence from the verified meaning, collocations, and usage pattern.

Example:

```text
Usage evidence:
The source uses "impact" to mean an environmental effect of technology.

Original practice example:
Scientists are studying the environmental impact of artificial intelligence.
```

### 12.3 Direct-Reuse Priority

Use sources in this order:

1. `CC0` or public-domain sentences: reuse directly after quality review.
2. `CC BY` or compatible open-license sentences: reuse with required attribution.
3. Government/institutional material with explicit reuse permission: follow its
   stated terms.
4. News, books, and copyrighted dictionaries: private usage evidence only;
   create a separate original practice sentence.
5. AI-generated examples without source grounding: fallback only and require
   stronger review.

Tatoeba and similar corpora may be used only when the individual sentence and
audio licenses are recorded. Do not assume all audio has the same license as
the sentence text.

### 12.4 Required Record Types

Store usage evidence and practice examples separately:

```text
usage_evidence
- source quotation and provenance
- matched sense and usage analysis
- license and private/public permission

practice_examples
- original/reusable sentence
- Chinese translation
- target span
- difficulty and topic
- source-evidence links
- origin and review status
```

One practice example may reference multiple usage-evidence records. One
usage-evidence record may support multiple original practice examples.

Required origin values:

```text
sourced_reusable
sourced_private_study
ai_generated_from_sources
human_written
```

Required copyright values:

```text
public_domain
cc0
cc_by
licensed
private_study_only
unknown
```

Required review values:

```text
pending
auto_passed
human_approved
rejected
```

### 12.5 Attribution

For every directly reused sentence, preserve:

- Title.
- Author/contributor when available.
- Source URL or publication locator.
- License name and version.
- Required attribution text.
- Whether the sentence was modified.

Private source quotations should also preserve attribution so their source and
meaning can be audited later.

### 12.6 Build Behavior

The private build may display `private_study_only` usage evidence to the owner.

Any future shared/public build must:

- Exclude `private_study_only` and `unknown` source text.
- Include required attribution for reusable material.
- Continue using original approved practice examples.
- Fail export if a public example lacks confirmed rights metadata.

## 13. Mnemonics

Mnemonics are optional and should be included only when useful.

Allowed types:

- Verified root or affix.
- Clear spelling pattern.
- Safe Chinese sound association.
- Short semantic memory hook.

Do not force a mnemonic for every word and do not invent false etymology.

## 14. Human Review

Use risk-based review.

Mandatory manual review:

- Multiple common senses or parts of speech.
- Weak agreement between English and Chinese sources.
- High-band abstract productive words.
- Low-confidence topic or band placement.
- Sensitive, offensive, political, medical, or legally risky content.
- Uncertain copyright/audio rights.
- Confusable distractors.
- AI content that fails or nearly fails automatic checks.

Automatically process low-risk records, but manually sample every batch.

## 15. Curriculum Stability

No major curriculum rebalancing is currently planned after release.

However:

- Content errors must remain correctable.
- Source/license problems must remain removable.
- Store `curriculum_version = 1` as a safety field.
- Published learner progress must not be silently reset by content corrections.
- New curriculum versions or migration logic are TODO only if future changes
  become necessary.

## 16. First Vertical Slice

Do not construct the full curriculum first.

Start with:

```text
Topic: Daily Life
Subtopic: people and family
Levels: 1-3
Raw candidate target: 280
Approved candidate target: 80
Complete production packages: 20
```

The slice must validate:

- ECDICT import and parsing.
- Oxford/source joins.
- Sense separation.
- Curriculum-role classification.
- Topic and functional tags.
- American spelling/pronunciation policy.
- Chinese meaning quality.
- Source-evidence collection.
- AI example generation and provenance.
- Collocations and forms.
- Distractor generation.
- Questions and Supabase export.

Only scale after the 20-word slice passes end-to-end review.
