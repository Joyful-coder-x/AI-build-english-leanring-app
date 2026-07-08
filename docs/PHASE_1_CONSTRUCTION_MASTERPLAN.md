# KuaKua Duck 夸夸鸭AI — Phase 1 Construction Masterplan

Document type: construction direction file  
Created: 2026-07-07  
Author: product planning session  
Repository root: `D:\project`  
Status: ACTIVE — this is the single controlling build-direction document for Phase 1.

Read this before touching any file. Every section that says "3 options" gives you the tradeoff; the PM recommendation at the bottom of each section is what to build.

---

## 0. How To Use This Document

This document answers three questions for every feature in Phase 1:
1. What exactly does it do and why?
2. What are the three realistic ways to build it?
3. What does the PM recommend, and why does that match what market leaders do?

After each feature spec is a database schema section, RPC contract, Android plan, and an ordered implementation sequence. Nothing in this document is hypothetical; every item maps to a real screen, table, RPC, or test in this repository.

**Conflict rule:** This document supersedes all older plan docs for Phase 1 scope decisions. Where the code or migrations already implement something, the code wins for behavior; this document is the source of truth for product intent.

---

## 1. Glossary

These terms have precise definitions throughout. Do not reinterpret them.

| Term | Definition |
|---|---|
| **vocab / sense** | One distinct meaning of a word. A word with two genuinely different meanings has two vocabs/senses. Polysemy where the difference is mild context does not create a new vocab. |
| **level** | One study unit. Contains `new_sense_target` new senses (~45 for Levels 1–5) plus review slots from prior levels. The learner-facing label: `雅思 4 分难度 Level 1`. |
| **practice set / round** | Exactly 20 questions, server-created, immutable. Contains a mix of new senses and review senses for the selected level. |
| **question type** | One of 8 skill-flavored interaction modes (see Feature D). A single sense can have questions of all 8 types. |
| **band** | A difficulty tier mapped to IELTS score range: Band 4.0 = IELTS 4.0–5.0, Band 4.5 = IELTS 5.5–6.5, Band 7.0 = IELTS 7.0–8.0, Band 8.5 = IELTS 8.5–9.0. Learner-facing label: `雅思 4 分难度`. |
| **band assessment** | A 40-question test drawn from all available levels in one band. Tests mastery of that band's vocabulary. Does NOT gate progression by itself — it produces a skill score. In the Band Upgrade Exam context, passing (≥37/40) unlocks the next band. |
| **overall assessment** | A 100-question test drawn from all available levels across all bands. Run from the home page. Produces a 4-skill score report (listening, reading, speaking, spelling). |
| **skill score** | A 0–10 numeric value for each of the four IELTS skills (listening, reading, speaking, spelling/writing), derived from accuracy on skill-typed questions. Mapped to an estimated IELTS band per the Scoring PDF. |
| **login** | A user session start: any time the app opens and the Supabase auth session is restored or a new sign-in completes. |
| **daily streak** | Consecutive calendar days with at least one completed practice round. |
| **review** | A question on a previously seen sense, delivered when its spaced interval is due. |
| **spaced interval** | The review schedule: immediate (10 min "now"), 1 day, 1 week (7 days), 1 month (30 days). |

---

## 2. Phase 1 Scope

### What is fully working in Phase 1

Status as of 2026-07-07 (implementation pass): backend migrations 030–035 and
the corresponding Android UI were built and verified via the local Docker SQL
test harness, `gradlew test` (all unit tests), and `gradlew assembleDebug`
(full build). Not yet verified: a real on-device manual run through the app,
or applying 030–035 to the hosted Supabase project — do both before calling
Phase 1 demo-ready.

| Area | Requirement | Status |
|---|---|---|
| Authentication | Username + password login, registration, session restore | Done |
| Onboarding | 5-question onboarding, routes directly to Level 1 | Done |
| Levels 1–5 | All 45 new senses per level, all 8 question types, practice rounds, logging, unlock chain | Done |
| Practice rounds | Server-created 20-question sets, all 8 types rendered in Android UI | Done (open_speaking + word_form added 2026-07-07) |
| Spaced review | now / 1 day / 1 week / 1 month intervals, strictly enforced | Done; review-before-new priority bug fixed 2026-07-07 (migration 029) |
| Level-up logic | Server-side: 90% of new senses with 10-min delayed review → unlock next level | Done |
| Mistake notebook | Wrong answers indexed, viewable, fed into next round | Done |
| Daily streak | Once-per-calendar-day check-in on round completion, persisted server-side | Done |
| Login tracking | Login count, first login, last login, per-user in Supabase | Done (migration 030) |
| Awards | Milestone awards for login streaks, level completions, band completions | Done (migration 031); Android calls `check_and_grant_awards` client-side after login/round completion rather than embedding it server-side — see Feature J |
| Band 4 assessment | 40 random questions from Band 4 available levels (currently 1–5) | Done |
| Overall assessment | 100 random questions from all available bands and levels | Done (migrations 034–035, `OverallAssessmentScreen`) |
| Skill scoring | Per-assessment skill scores (listening, reading, speaking, spelling) per the Scoring PDF | Done (`compute_skill_band`, piecewise mapping from Scoring PDF Table 2 — see Feature I) |
| Levels 6+ | "Coming Soon" locked cards — tapping shows an in-place dialog | Done (migration 033; `LevelRow` in `HomeScreen.kt`, not a separate placeholder screen route) |

### What is NOT in Phase 1

- Band 4.5 content
- Audio files (use Android TTS)
- Real email or phone login
- Social features
- In-app purchases
- Push notifications
- Admin console

---

## 3. Feature A: Login & Authentication

### What it does

A user opens the app, sees the login screen if no session exists. They enter a username and password. The app calls Supabase Auth, gets a JWT, and bootstraps their profile. On every subsequent open, the stored session is restored without showing the login screen.

Login is also the trigger for recording a login event (Feature B).

### Current state

Implemented: username/password auth, session restore, sign-out. The login screen (`LoginScreen.kt`) and ViewModel exist. Supabase placeholder email generation (username → `{username}@kuakuaduck.invalid`) is implemented.

### 3 Options

**Option 1 — Username/password only (current)**  
What: Keep exactly what is built. No email recovery. Password change is supported through the settings screen. Document the recovery gap clearly in the UI.  
Effort: Zero new work beyond polish.  
Risk: If a user forgets their password, no recovery path. Acceptable for a prototype.

**Option 2 — Phone OTP added alongside username/password**  
What: Add a phone number field at registration. Use Supabase Phone Auth to send a one-time code. User can also log in via phone OTP.  
Effort: Medium — Supabase Phone Auth requires Twilio or similar setup. Not free.  
Risk: Requires a paid SMS provider. Chinese phone numbers may require a China-approved SMS gateway.

**Option 3 — Real email + phone combined with WeChat/QQ social login**  
What: Standard registration with a real email address, email verification, password recovery. Social login via WeChat for Chinese users.  
Effort: High — WeChat OAuth requires MIIT business registration for the app. Not realistic for a prototype.  
Risk: Out of scope for Phase 1.

### PM Recommendation: Option 1

**Why:** Duolingo launched with email/password only. Khan Academy launched with Google/Facebook but both took years to add additional providers. SAT prep apps (Magoosh, PrepScholar) still rely heavily on email/password for their primary path. Username/password is the fastest, cheapest, and most controllable auth for a prototype. The only thing market leaders add early is a "forgot password" email link — which we cannot do with placeholder emails. Document this gap, don't hide it.

**What to add for Phase 1:** A clearly visible in-app note: `注意：此版本不支持密码找回，请牢记您的密码。` shown on the login screen and in Settings.

### Acceptance Criteria

- `AUTH-001` New user registers with a unique username and password.
- `AUTH-002` Existing user signs in after app restart without re-entering credentials.
- `AUTH-003` Wrong credentials produce a clear error message (no raw Supabase error text).
- `AUTH-004` Sign-out clears all in-memory state and shows the login screen.
- `AUTH-005` Login triggers a login event record (see Feature B).
- `AUTH-006` A duplicate username produces a clear error message: `该用户名已被注册`.

---

## 4. Feature B: Daily Streaks & Login Tracking

### What it does

Every time a user signs in or the app restores a session, a login event is recorded. Every time a user completes a practice round on a new calendar day, the day streak increments. Streak and login data drive awards (Feature J) and the streak calendar display.

### Current state — DONE 2026-07-07

Implemented: `current_streak_days`, `longest_streak_days`, `last_practice_date`, `duck_power` in profiles (migration 011, corrected names — the fields above used the intended-but-not-actual names). Migration 024 adds props and protection items.

`login_count`, `first_login_at`, `last_login_at`, and the `user_login_log` table are now implemented in migration `202607070030_login_tracking.sql`, with `record_login()` called from `AppSessionViewModel` once per session (guarded by a `hasRecordedLoginThisSession` flag so retries don't double-count). Verified by `202607070030_login_tracking_test.sql`.

### 3 Options

**Option 1 — Counter-only in profiles (minimal)**  
What: Add `login_count integer default 0` to the `profiles` table. Increment it server-side every time a session is established (via RPC called from Android on app start). No detailed log.  
Effort: Tiny — one migration to add the column, one RPC to increment it.  
Risk: No audit trail. Can't show "you logged in on these specific days." Cannot power a heatmap calendar.

**Option 2 — Login log table + daily aggregation (recommended)**  
What: Add a `user_login_log` table: `(id, user_id, logged_in_at, platform)`. On each login event, the Android client calls `record_login()`. The RPC inserts into the log and also increments `login_count` and updates `last_login_at` on profiles. A separate idempotent `record_streak_check_in()` is called only on round completion.  
Effort: Small — one migration, one RPC.  
Risk: Login log can grow large. Add a cleanup policy (retain 365 days).

**Option 3 — Full activity tracking with detailed event types**  
What: One `user_events` table that tracks logins, round completions, level unlocks, awards, and all user actions with event types and metadata.  
Effort: Medium — requires event type definitions and more complex query logic.  
Risk: Over-engineered for Phase 1. Better for analytics, not needed now.

### PM Recommendation: Option 2

**Why:** Duolingo's streak system is one of its most-cited retention drivers. Their annual retrospective (Year in Review) is powered by per-day login data. Khan Academy shows a practice heatmap calendar. Both require a log table, not just a counter. Option 2 gives us the login_count for award logic AND the per-day log for a future heatmap. Option 1 loses the audit trail we'll want. Option 3 is pre-mature.

**Streak rules (strictly follow):**
- A streak day is earned by completing at least one practice round on a calendar day (server timezone: UTC+8).
- A login alone does NOT earn a streak day.
- Streak increments are idempotent — calling `record_streak_check_in()` multiple times on the same calendar day is safe.
- A missed day resets `consecutive_login_days` to 0 (unless a protection item is active — see Feature J).

**Review logic from login data:**
- Words last seen "now" (same session): re-queue after 10 minutes.
- Words last seen 1+ days ago (since last login): immediately due for review.
- The `next_due_at` field in `user_sense_mastery` handles this. On login, the round assembly RPC picks up all overdue senses automatically.

### Database additions needed

```sql
-- Add to profiles
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS login_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS first_login_at timestamptz;

-- New table
CREATE TABLE user_login_log (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  logged_in_at timestamptz NOT NULL DEFAULT now(),
  platform     text DEFAULT 'android'
);
CREATE INDEX ON user_login_log (user_id, logged_in_at DESC);
-- RLS: user can only see own rows
```

### RPC additions needed

```sql
-- Called by Android on every session start
CREATE OR REPLACE FUNCTION record_login()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO user_login_log (user_id, logged_in_at) VALUES (auth.uid(), now());
  UPDATE profiles
    SET login_count    = COALESCE(login_count, 0) + 1,
        last_login_at  = now(),
        first_login_at = COALESCE(first_login_at, now())
  WHERE id = auth.uid();
END;
$$;
```

### Acceptance Criteria

- `STREAK-001` Each app open / session restore calls `record_login()` exactly once.
- `STREAK-002` `profiles.login_count` increments by 1 each time `record_login()` is called.
- `STREAK-003` Completing a practice round on a new calendar day increments `consecutive_login_days`.
- `STREAK-004` Completing multiple rounds on the same day does not double-increment the streak.
- `STREAK-005` Missing a day resets `consecutive_login_days` to 0.
- `STREAK-006` `longest_login_streak` updates whenever `consecutive_login_days` exceeds the stored value.
- `STREAK-007` The streak calendar screen shows which days had activity (from `user_login_log`).

---

## 5. Feature C: Level-Up Logic (Levels 1–5)

### What it does

A learner practices Level 1. As they answer questions correctly, senses move through the review schedule. When 90% of the level's new senses have a confirmed "delayed correct" review (a second correct answer ≥10 minutes after the first), the level becomes `已通关` and the next level unlocks.

This is the core learning progression loop.

### Current state

Implemented in migration 009 and 014: `start_practice_round`, `save_practice_answer`, `complete_practice_round`. The server-side logic for level completion (`ceil(new_sense_target * 0.90)` threshold, 10-minute delay requirement) is implemented. Android reads level state from `user_level_progress`.

Not yet verified against the hosted Supabase. Level 1 is always unlocked; Levels 2–5 unlock only if prior level is `已通关`.

### 3 Options

**Option 1 — Single-session accuracy gate (simple, wrong)**  
What: If the user scores ≥80% on a 20-question round, the level unlocks immediately.  
Why this is wrong: It rewards lucky guessing in one session. Research shows single-session accuracy doesn't predict long-term retention. No competitor uses pure single-session gating for vocabulary mastery.

**Option 2 — Spaced recall gate (current design, correct)**  
What: The server counts how many of the level's new senses have been seen AND have a second correct answer ≥10 minutes after the first. When that count reaches `ceil(new_sense_target * 0.90)`, the level becomes `已通关` and the next level unlocks. Implemented via `complete_practice_round` RPC.  
Why this is right: This is the SRS (Spaced Repetition System) model used in Anki, Duolingo, and research-backed CALL (Computer-Assisted Language Learning) tools.

**Option 3 — Adaptive multi-session mastery gate**  
What: Use a more complex Bayesian Knowledge Tracing model (used by Khan Academy and DuoLingo internally). Track probability that the learner truly knows the sense, and unlock when the probability reaches 0.9.  
Why not for Phase 1: Too complex to implement correctly. Requires machine learning infrastructure. Khan Academy spent years building theirs.

### PM Recommendation: Option 2

**Why:** Duolingo's "crown" system requires multiple sessions before a skill is "golden." Khan Academy's mastery model requires multiple correct answers over time, not just one session. The current design (10-minute delay before a correct answer "counts" as a spaced review) is a simplified but academically grounded version of the same idea. Option 2 is what's already designed and partially implemented. Build it properly.

**The exact unlock math:**

```
For a Level with new_sense_target = 45:
  required_count = ceil(45 * 0.90) = 41

A sense counts toward the threshold when ALL are true:
  1. It has appeared in at least one formal question.
  2. It has at least one correct formal answer.
  3. It has a SECOND correct formal answer that happened >= 10 minutes after the FIRST correct answer.
  4. Its learning_state is 'reviewing' or 'mastered'.

When qualifying_sense_count >= 41, the level's is_completed = true.
The complete_practice_round RPC checks this and, if met:
  - Sets user_level_progress.is_completed = true for this level.
  - Sets user_level_progress.is_unlocked = true for the next level.
  - Returns the updated level state to Android.
```

**Level states shown in Android UI:**

| Internal | Chinese label | Meaning |
|---|---|---|
| `locked` | 未解锁 | Cannot practice |
| `available` | 待开始 | Unlocked, not started |
| `learning` | 学习中 | In progress, not all senses seen |
| `consolidating` | 巩固中 | All senses seen, threshold not met |
| `completed` | 已通关 | Threshold met, next level unlocked |

V1.0 does NOT show `已掌握`. Do not add it until V1.1 active recall question types exist.

### Acceptance Criteria

- `LEVEL-001` Level 1 is unlocked for all users after onboarding.
- `LEVEL-002` Levels 2–5 are locked until the previous level's `is_completed = true`.
- `LEVEL-003` A level's completion requires `ceil(new_sense_target * 0.90)` senses with a second correct answer ≥10 minutes after first.
- `LEVEL-004` Completing a round never double-increments progress (idempotent `complete_practice_round`).
- `LEVEL-005` A user who signs out and back in sees the same level unlock state.
- `LEVEL-006` A locked level's card is grayed out; tapping it shows a 🔒 message, not the practice screen.
- `LEVEL-007` Level 5 completion does NOT automatically unlock Level 6 (which is "coming soon").
- `LEVEL-008` The Level progress screen shows correct `seen_count`, `qualifying_count`, and threshold.

---

## 6. Feature D: Eight Question Types

### What it does

Every new sense in Levels 1–5 is practiced through 8 different interaction modes. Each mode tests a different IELTS sub-skill. A practice round can contain any mix of these types.

### Question type map

| Type key | Chinese name | Skill | What the learner does | Answer type |
|---|---|---|---|---|
| `meaning_choice` | 词义选择 | Reading/Vocab | See a Chinese definition, choose the correct English word | Multiple choice (4 options) |
| `sentence_cloze_typing` | 填词 | Writing/Spelling | Read a sentence with a blank, type the missing word | Keyboard text input |
| `listening_choice` | 听音选词 | Listening | Hear the word (TTS), choose the correct word from 4 options | Multiple choice (4 options) |
| `listening_fill` | 听写 | Listening + Spelling | Hear the word (TTS), type the word | Keyboard text input |
| `speaking_repeat` | 跟读 | Speaking | Read the word aloud (or listen), then self-assess: "I got it" / "I need more practice" | Binary self-check |
| `open_speaking` | 开口说 | Speaking production | Say the word in a sentence aloud, then self-assess | Binary self-check |
| `word_form` | 词形变化 | Grammar/Spelling | See a prompt (e.g. "verb form"), type the correct form | Keyboard text input |
| `reading_comprehension` | 阅读理解 | Reading | Read a sentence with the word used in context, choose the correct definition | Multiple choice (4 options) |

### Current state — CORRECTED per 2026-07-07 code audit

The question type infrastructure (question_types, questions, question_options tables) and round assembly logic exists. Migrations 019 and 020 added type-key support and generation logic.

Android is further along than previously documented: `LevelPracticeScreen.kt` already has a `when(questionTypeKey)` dispatch rendering distinct UI for `meaning_choice`, `sentence_cloze_typing` (icon/title/instruction only, no distinct content block yet), `listening_choice`, `listening_fill`, `speaking_repeat`, and `reading_comprehension`. TTS covers both listening types.

**Gap fixed 2026-07-07:** `open_speaking` and `word_form` now have dedicated content-area blocks and icon/title/instruction entries in `LevelPracticeScreen.kt`. Note `open_speaking`'s answer submission needed no new plumbing — it already used `answer_form='option'` with 4 generated options (same self-check-via-multiple-choice mechanism as `speaking_repeat`, both seeded in migration 019's `speaking_options` block), so the existing generic `OptionList` renders it correctly; only the prompt/content display was missing. All 8 types now render distinctly. Verified by `gradlew test` + `assembleDebug` (compiles); not yet verified by a manual on-device run through a real Level 1 round.

### 3 Options

**Option 1 — One Composable per question type (8 separate files)**  
What: Build `MeaningChoiceCard`, `SentenceClozeCard`, `ListeningChoiceCard`, etc. as 8 fully separate composables. Each gets its own `@Preview`.  
Effort: Medium-high. 8 separate implementations with lots of duplicated structure.  
Risk: Inconsistent styling, harder to maintain. But makes each type's logic cleanly isolated.

**Option 2 — Unified question host + type-specific answer panel (recommended)**  
What: One `PracticeQuestionScreen` composable handles: question prompt display, progress indicator, timer, feedback overlay. The answer area is a `when(questionType)` switch that slots in a type-specific panel: `MultipleChoicePanelPanel`, `TextInputPanel`, `SelfCheckPanel`.  
There are only 3 answer interaction modes needed:
- Multiple choice (4 buttons): used by `meaning_choice`, `listening_choice`, `reading_comprehension`
- Text input (keyboard): used by `sentence_cloze_typing`, `listening_fill`, `word_form`
- Self-check (2 buttons: "会了" / "再练练"): used by `speaking_repeat`, `open_speaking`  
Effort: Medium — 3 answer panels + 8 question prompt templates.  
Risk: Risk of over-abstracting. Keep the shared code minimal.

**Option 3 — Dynamic JSON-driven rendering (no if/else)**  
What: Store question rendering rules in a config JSON. Android renders questions based on config without code changes. Used by some enterprise learning platforms.  
Effort: High — requires a config schema, a renderer engine, and a fallback for unknown types.  
Risk: Overkill for 8 static types. Debugging is harder.

### PM Recommendation: Option 2

**Why:** Duolingo's app has ~15 exercise types. They all share a common "challenge" chrome (hearts, progress bar, continue button, skip button). Only the answer area changes per type. Quizlet has flashcard mode, multiple choice mode, and write mode — 3 answer panel types, many question types. Khan Academy uses a similar pattern: question stem + answer widget. Option 2 follows this proven model. Keep the `when(questionType)` block in one file — if it gets too complex, extract it, but don't abstract prematurely.

**Audio for listening types:** Use Android TTS (`TextToSpeech`) in Phase 1. Call `tts.speak(headword, QUEUE_FLUSH, null, null)` for `listening_choice` and `listening_fill`. Real audio files are a Phase 2 priority.

**Self-check scoring for speaking types:** Self-reported answers (`speaking_repeat`, `open_speaking`) are always marked as "correct" if the user taps 会了/读对了. This is NOT a fake mastery signal — self-check advances the review schedule the same as any correct answer. Users who consistently self-report correct but are not retaining the word will fall behind on other question types (cloze, fill) — the system self-corrects.

### Android Composable Structure

```
ui/practice/
  PracticeQuestionScreen.kt        ← host composable, shared chrome
  PracticeViewModel.kt             ← existing, extend with type routing
  answer/
    MultipleChoicePanel.kt         ← 4 buttons
    TextInputPanel.kt              ← keyboard input + submit
    SelfCheckPanel.kt              ← 会了 / 再练练
  prompt/
    MeaningChoicePrompt.kt         ← Chinese def → pick English word
    SentenceClozePrompt.kt         ← sentence with blank
    ListeningChoicePrompt.kt       ← audio player + word options
    ListeningFillPrompt.kt         ← audio player + text input
    SpeakingRepeatPrompt.kt        ← word + read aloud instruction
    OpenSpeakingPrompt.kt          ← word + sentence use prompt
    WordFormPrompt.kt              ← base word + form type cue
    ReadingComprehensionPrompt.kt  ← example sentence + definition choice
```

### Acceptance Criteria

- `QT-001` All 8 question types render without crash.
- `QT-002` Multiple choice types show exactly 4 options in randomized order.
- `QT-003` Text input types accept keyboard input, submit on keyboard "Done" or button tap.
- `QT-004` Self-check types show 2 buttons; "会了" is always marked correct, "再练练" always incorrect.
- `QT-005` Listening types play audio via Android TTS before showing the answer panel.
- `QT-006` After answering, all types show the correct answer, a feedback animation, and a "Next" button.
- `QT-007` Answer is sent to `save_practice_answer` RPC with the correct `answer` value (matched option ID for choice, typed text for input, "self_check_correct"/"self_check_incorrect" for self-check).
- `QT-008` Question type distribution in a Level 1–5 round is approximately equal across types (the round assembly RPC handles this).

---

## 7. Feature E: 20-Question Practice Set Assembly

### What it does

When a learner taps a level card, the app calls `start_practice_round(level_number)`. The server creates an immutable round of ≤20 questions. The composition follows priority rules that mix new senses, due reviews, and mistake follow-ups. The learner answers all 20 questions; the server grades and records each answer.

### Current state

Implemented: `start_practice_round`, `save_practice_answer`, `complete_practice_round`. Round assembly logic in migration 020 and 025. Question type selection in migration 025 (combo scope type selector). The 8-type Level 1–5 selection is in migration 019.

**Discrepancy found in 2026-07-07 code audit, FIXED same day:** the priority order below is the *intended* design, but the actual `start_practice_round` loop (migration `202606260020`) filled slots in this order: mistakes (up to 10) → new senses (up to 7) → due reviews → filler — new senses were pulled before overdue reviews, the opposite of Priority 2 vs Priority 3 below. Migration `202607060028_due_review_new_word_gate.sql` only patched the case where overdue reviews exceed 20 (zeroes the new-word slot then); it did not generally reorder.

**Fix applied:** `202607070029_review_before_new_sense_priority.sql` swaps the bucket order to mistake → review → new → fallback, matching the table below. Verified with a new test, `202607070029_review_before_new_sense_priority_test.sql` (added to `run_phase1_local_docker_verification.ps1`'s test list and to the README's test list), which seeds 5 already-due review senses in Level 1 and asserts every `review`-bucket row's position is before every `new`-bucket row's position in the generated round. Full local Docker verification (all 12 SQL tests + `verify_project_installation.sql`) passes as of this fix.

### 3 Options

**Option 1 — Static pre-stored 20-question sets (don't do this)**  
What: Generate and store 20 fixed questions per level in the database. Every learner always sees the same questions.  
Why not: No adaptive review. No personalization. The same 20 questions every time means a learner who already knows words 1–20 is wasting time. This is what old SAT vocabulary books do, and why apps displaced them.

**Option 2 — Dynamic server-side round assembly (current design)**  
What: `start_practice_round` assembles questions on the fly based on the learner's current state: mistakes from last round go first, overdue reviews next, then new senses, then upcoming reviews.  
Effort: Already implemented. The assembly priority order is in migration 020.  
Risk: Requires a working `user_sense_mastery` table with real data for the assembly to be meaningful.

**Option 3 — Client-side question selection from a cached question bank**  
What: Download all questions for a level to the device on first visit. Client picks 20 questions locally.  
Why not for Phase 1: Can't personalize based on server-side mastery state without a sync. Risk of client-side state diverging from server. Hard to keep idempotent.

### PM Recommendation: Option 2

**Why:** Duolingo uses server-side session assembly. Quizlet Learn mode is adaptive per session. Khan Academy's practice is completely server-driven. The research consensus is that spaced repetition only works when the scheduling is done by an algorithm, not randomly or statically. Option 2 is what we've built. Wire it correctly.

**Assembly priority (strictly follow this order):**

```
Priority 1 — Senses wrong in the PREVIOUS round (for this level), now overdue
Priority 2 — Any overdue review sense (next_due_at <= now()), all levels
Priority 3 — Unseen new senses from the selected level (first time appearing)
Priority 4 — New senses approaching next_due_at (within the next 2 hours)
Priority 5 — Low-progress new senses from this level (filler to reach 20)

Constraints:
  - MAX 20 questions total
  - If overdue_review_count > 20, the round contains ONLY reviews (0 new senses)
  - If any overdue reviews exist, new senses ≤ 60% of the round
  - No duplicate sense_id in one round
  - For Levels 1–5: select question types to cover all 8 types across the round
  - For Levels 6+: use lightweight type set only (meaning_choice, listening_choice,
    listening_fill, sentence_cloze_typing, speaking_repeat)
```

### Acceptance Criteria

- `ROUND-001` `start_practice_round` returns a round with ≤20 questions, no duplicate `sense_id`.
- `ROUND-002` If the user has >20 overdue reviews, the round contains 0 new senses.
- `ROUND-003` Overdue reviews always appear before new senses when both are present.
- `ROUND-004` A round for Level 1–5 contains a mix of question types (not all `meaning_choice`).
- `ROUND-005` Calling `start_practice_round` twice for the same level returns the same active round if it's not completed.
- `ROUND-006` After `complete_practice_round`, calling `start_practice_round` again creates a new round.
- `ROUND-007` The answer to each question is graded server-side; the client never computes correctness.
- `ROUND-008` An incomplete round (app killed mid-session) can be resumed from question 1; the snapshot does not change.

---

## 8. Feature F: Spaced Review (Now / 1 Day / 1 Week / 1 Month)

### What it does

Every time a sense is answered correctly, it gets scheduled for a future review. The schedule follows exactly:

```
First correct answer      → due in 10 minutes  ("now" — immediate consolidation)
Second correct (when due) → due in 1 day
Third correct (when due)  → due in 1 week (7 days)
Fourth correct (when due) → due in 1 month (30 days)
Fifth correct (when due)  → mastery maintenance (75 days, V1.1 only)
```

A wrong answer resets the due time to 10 minutes and regresses the stage (see below). A correct answer before the due time does NOT advance the stage.

### Current state

Fully implemented in `user_sense_mastery` and `save_practice_answer`. The stage-advance and stage-regression logic is in migration 009 and 020.

### 3 Options

**Option 1 — Fixed 4-interval SRS (now/1day/1week/1month) — CURRENT DESIGN**  
What: The four intervals above. Already implemented. This is what the user specifies.

**Option 2 — Variable interval SRS (SM-2 algorithm, Anki-style)**  
What: Use the SuperMemo 2 algorithm, where intervals grow based on an "easiness factor" per sense. Easy senses get longer intervals; hard senses get shorter ones.  
Why not for Phase 1: More complex to implement and explain. Requires tracking an easiness factor per sense per user. The current fixed-interval design is already effective and matches what users can understand.

**Option 3 — Passive review (no intervals, just show weak words often)**  
What: Weight question selection heavily toward wrong answers and senses with low correct rates. No fixed schedule.  
Why not: Research shows spaced intervals dramatically outperform frequency-based review for long-term retention. This is why Anki won and flashcard apps that don't use SRS lose users faster.

### PM Recommendation: Option 1

**Why:** Duolingo's word review uses a form of SRS. Anki's default deck uses SM-2 with variable intervals. For IELTS vocabulary (C1/C2 level words), the research is clear: spaced review with exact intervals outperforms cramming by 150-200% in 6-month retention tests. The fixed 10min/1day/1week/1month intervals are a simplified but proven schedule. Do not change this.

**Stage regression on wrong answer (do NOT change this either):**

| Current stage | After wrong answer |
|---|---|
| learning (stage 0) | remains learning |
| ten_minute (stage 1) | back to learning (stage 0) |
| one_day (stage 2) | back to ten_minute (stage 1) |
| seven_day (stage 3) | back to one_day (stage 2) |
| thirty_day (stage 4) | back to seven_day (stage 3) |

A wrong answer at stage 4 (30-day) does NOT go all the way back to stage 0. Limited regression prevents discouraging learners and matches how memory actually works (partial retention).

### Acceptance Criteria

- `SRS-001` First correct answer sets `next_due_at = now() + interval '10 minutes'`.
- `SRS-002` A correct answer received before `next_due_at` does NOT advance `review_stage`.
- `SRS-003` A correct answer received at or after `next_due_at` advances `review_stage` and sets the next interval.
- `SRS-004` A wrong answer at stage 4 regresses to stage 3, NOT to stage 0.
- `SRS-005` `recent_results` contains only the latest 6 formal answer results.
- `SRS-006` The mistake notebook shows the sense as active when `is_active = true` in `mistake_senses`.
- `SRS-007` A resolved mistake (`is_active = false`) reactivates after another wrong answer.

---

## 9. Feature G: Band Assessment (40 Questions)

### What it does

A dedicated 40-question test drawn randomly from all available levels in one band. For Band 4, this draws from Levels 1–5 (Phase 1) or Levels 1–33 (once all levels are active). The purpose is twofold:

1. **Upgrade exam:** Passing ≥37/40 unlocks the next band. This is the only mechanism to progress to Band 4.5+.
2. **Skill snapshot:** The per-skill breakdown (listening/reading/speaking/spelling) feeds the skill scoring system (Feature I).

The exam is always available, regardless of whether the learner has finished all levels in the band.

### Current state

Migration 026 implements `start_band_upgrade_exam`, `save_band_upgrade_answer`, `complete_band_upgrade_exam`. The Android `BandUpgradeExamScreen` is wired. SQL tests exist locally. Migrations 025–029 need to be applied to the hosted Supabase.

### 3 Options

**Option 1 — Fixed pre-generated 40-question paper (don't do this)**  
What: Store one fixed 40-question set per band. All users take the same test.  
Why not: Testable answers can be leaked. Learners who retake the test memorize the answers, not the vocabulary.

**Option 2 — Server-side random selection (current design)**  
What: `start_band_upgrade_exam` selects 40 unique random questions from the band's question pool. The selection is stratified to target ~10 per skill category. The snapshot is immutable once started.  
Effort: Already implemented.  
Risk: Thin question pool in early Phase 1 (only Levels 1–5). The 10-per-category target may not be achievable for all types. The system falls back to filling from available types and records the actual mix.

**Option 3 — Computerized Adaptive Testing (CAT)**  
What: Start with a medium-difficulty question; adjust question difficulty based on answer history. GMAT and GRE use this.  
Why not for Phase 1: Requires IRT item parameters (difficulty, discrimination, guessing) per question. These aren't calibrated. Massive complexity for marginal improvement in a prototype.

### PM Recommendation: Option 2

**Why:** SAT prep apps (PrepScholar, Magoosh) use fixed question banks but randomize the selection each time. Khan Academy's SAT practice draws randomly from a validated pool. Randomization prevents cheating and makes retakes meaningful. The 40-question format mirrors IELTS's own listening and reading sections (both are 40 questions), which creates a familiar test feel for the target learner.

**Stratification target (attempt, but don't fail if pool is thin):**

| Category | Questions | Drawn from |
|---|---|---|
| Reading/Vocabulary | 10 | `meaning_choice`, `reading_comprehension` |
| Listening | 10 | `listening_choice`, `listening_fill` |
| Spelling/Writing | 10 | `sentence_cloze_typing`, `word_form` |
| Speaking (self-check) | 10 | `speaking_repeat`, `open_speaking` |

If a category has fewer than 10 eligible questions, the shortage is filled from others. The result screen always shows the actual category breakdown — never claims 10/10/10/10 if that's not what was drawn.

**Pass/fail rule:**
- ≥37 correct out of 40 → PASS → unlock Band 4.5 (when available), record `passed=true`
- ≤36 correct out of 40 → FAIL → no progression change, unlimited retries

**Result screen must show:**
```
Band 4 升级考试结果

成绩：37 / 40 (92.5%)
结果：通过 ✓

词汇理解  9/10
听力      10/10
拼写写作  9/10
口语表达  9/10

已解锁雅思 4.5 分难度 🎉

注意：本考试用于确定应用内学习进度，不代表官方雅思成绩。
```

### Database additions for Phase 1 review

The Band upgrade exam tables (`band_upgrade_attempts`, `band_upgrade_attempt_questions`) already exist in migration 026. Verify they are applied to the hosted Supabase.

### Acceptance Criteria

- `EXAM-001` `start_band_upgrade_exam(4.0)` creates an attempt with exactly 40 unique questions from Band 4.
- `EXAM-002` Question order within the attempt is randomized; option order for choice questions is randomized.
- `EXAM-003` Closing and reopening the app resumes the same attempt snapshot (questions don't change).
- `EXAM-004` `save_band_upgrade_answer` grades server-side; client never computes correctness.
- `EXAM-005` `complete_band_upgrade_exam` with 36 correct → `passed=false`, no unlock change.
- `EXAM-006` `complete_band_upgrade_exam` with 37 correct → `passed=true`, Band 4.5 first level unlocked.
- `EXAM-007` Retrying completion after a pass does not double-unlock.
- `EXAM-008` Two different users taking the same band exam get different question selections.
- `EXAM-009` Unauthenticated users cannot start an exam.
- `EXAM-010` Result screen shows actual per-category breakdown, not a fixed 10/10/10/10.

---

## 10. Feature H: Overall Assessment (100 Questions, Home Page)

### What it does

A 100-question assessment launched from the home screen. This tests the learner's overall vocabulary knowledge across all available bands and levels. It produces a 4-skill score report. It is purely informational — it does not gate any progression, does not unlock any level, and does not affect the learner's study progress or review schedule.

Think of it as the app's equivalent of a "diagnostic test" at the start of Khan Academy SAT prep, or the initial IELTS Reading test in Magoosh.

### Current state — DONE 2026-07-07

Implemented: migrations `202607070034_skill_scoring.sql` and `202607070035_overall_assessment.sql` (`overall_assessment_attempts`, `overall_assessment_questions`, `start_overall_assessment`, `save_overall_assessment_answer`, `complete_overall_assessment`). Android: `OverallAssessmentScreen.kt` + `OverallAssessmentViewModel.kt`, entered via a "📊 开始评测" button on the home screen, routed through `HomeNav.OverallAssessment`. Verified by `202607070035_overall_assessment_test.sql` (stratification, grading, `user_sense_mastery` untouched, band computation) plus `gradlew test`/`assembleDebug`.

The legacy `AssessmentScreen.kt` this section originally referenced was removed in the 2026-07-07 `_temp/` cleanup; the new implementation was built fresh from this document's spec, not from that legacy code.

### 3 Options

**Option 1 — Self-report assessment (28 questions, self-check only)**  
What: Show the learner a word at a given difficulty level. Ask "do you think you know this word?" Binary: 会/不会. 28 items (7 per skill). Map responses to a skill score.  
Pros: Fast to answer (~5 min). Easy to implement. No grading needed.  
Cons: Self-report is biased (learners overestimate their knowledge, especially beginners). The score is less meaningful. Not comparable to an actual IELTS test format.

**Option 2 — Objective 100-question test (recommended for Phase 1 final prototype)**  
What: Draw 100 real questions from the app's question bank, stratified as:
- 25 reading questions (meaning_choice + reading_comprehension)
- 25 listening questions (listening_choice + listening_fill)
- 25 spelling questions (sentence_cloze_typing + word_form)
- 25 speaking questions (speaking_repeat + open_speaking)

Draw questions randomly from ALL available bands and levels. For Phase 1, all available = Band 4 Levels 1–5. Score each skill section. Map to an IELTS band estimate per the Scoring PDF.

Pros: Real grading. Consistent with the band assessment format. Result is meaningful.  
Cons: 100 questions takes ~20–30 minutes. May feel long for a mobile experience.

**Option 3 — Hybrid: 40-question adaptive test (best UX)**  
What: Run a 40-question test (same infrastructure as band assessment). Stratify 10 per skill. Use difficulty stratification (e.g. 5 Band 4 questions + 3 Band 5 questions + 2 Band 7 questions per skill — but since we only have Band 4 in Phase 1, all 10 are Band 4). Score and report per skill.  
Pros: Same infrastructure as band assessment. 40 questions is the IELTS listening/reading section length. Faster to complete.  
Cons: Requires questions from multiple band levels to be truly diagnostic. Phase 1 with only Band 4 makes this less differentiated.

### PM Recommendation: Option 2 for Phase 1

**Why:** Khan Academy's SAT diagnostic is 44 questions and takes 55 minutes — and students complete it because they know the score is meaningful. Magoosh IELTS starts with a full-length practice test. The 100-question format allows proper stratification across the 4 IELTS skills (25 each) and produces a score that learners can understand as "similar to a 25-question IELTS section." For Phase 1 where we only have Band 4 (Levels 1–5), the overall assessment and band assessment will draw from the same pool — that's OK. As more content is added, the overall assessment automatically becomes more diagnostic.

**However:** Show an honest estimated time warning before starting: `本评测共100题，约需20-25分钟，请确保有充足时间。`

**Data model for overall assessment:**

```sql
CREATE TABLE overall_assessment_attempts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES profiles(id),
  status            text NOT NULL DEFAULT 'started',  -- started, completed, abandoned
  total_questions   int DEFAULT 100,
  answered_count    int DEFAULT 0,
  correct_count     int DEFAULT 0,
  -- Per-skill scores (set on completion)
  listening_correct int,  listening_total int,
  reading_correct   int,  reading_total   int,
  speaking_correct  int,  speaking_total  int,
  spelling_correct  int,  spelling_total  int,
  -- Derived (set on completion via scoring function)
  listening_band    numeric(3,1),
  reading_band      numeric(3,1),
  speaking_band     numeric(3,1),
  spelling_band     numeric(3,1),
  overall_band      numeric(3,1),
  started_at        timestamptz DEFAULT now(),
  completed_at      timestamptz
);

CREATE TABLE overall_assessment_questions (
  attempt_id        uuid REFERENCES overall_assessment_attempts(id),
  position          smallint NOT NULL,
  question_id       uuid NOT NULL REFERENCES questions(id),
  skill_category    text NOT NULL,  -- listening, reading, speaking, spelling
  answer_given      text,
  is_correct        boolean,
  response_time_ms  int,
  answered_at       timestamptz,
  PRIMARY KEY (attempt_id, position)
);
```

**RPCs needed:**

```
start_overall_assessment()
  → creates/resumes one active attempt per user
  → selects 100 questions: 25 per skill from available pool
  → returns question snapshot (no correctness)

save_overall_assessment_answer(attempt_id, position, answer)
  → grades server-side, saves answer
  → does NOT update user_sense_mastery (diagnostic only)

complete_overall_assessment(attempt_id)
  → verifies all 100 questions answered
  → tallies per-skill correct counts
  → applies scoring formula from Scoring PDF
  → sets band estimates
  → returns full result
```

### Result screen

```
总体评测结果

听力   8/25   (32%)  ≈ 雅思 4.5 分水平
阅读   15/25  (60%)  ≈ 雅思 5 分水平
口语   20/25  (80%)  ≈ 雅思 6 分水平
拼写   12/25  (48%)  ≈ 雅思 4.5 分水平

综合估算：雅思 4.5 分词汇水平

注意：这是基于词汇练习的参考估算，不等同于官方雅思成绩。
建议：重点练习听力和拼写，继续完成Band 4关卡。
```

### Acceptance Criteria

- `ASSESS-001` The home screen has a visible "开始评测" button.
- `ASSESS-002` Tapping it shows a warning screen with question count, estimated time, and a confirm button.
- `ASSESS-003` `start_overall_assessment()` selects 100 unique questions from available bands (25 per skill category, no duplicate question).
- `ASSESS-004` The assessment can be resumed if the app is closed mid-test.
- `ASSESS-005` Questions are graded server-side.
- `ASSESS-006` The assessment does NOT update `user_sense_mastery` — it has no effect on learning progress.
- `ASSESS-007` On completion, the result screen shows per-skill correct/total and estimated IELTS band.
- `ASSESS-008` The result screen shows a disclaimer that this is not an official IELTS score.
- `ASSESS-009` A learner can retake the assessment (creates a new attempt; the old one is preserved in history).

---

## 11. Feature I: Skill Scoring System

### What it does

Based on a learner's answers in the Overall Assessment (100Q) or the Band Assessment (40Q), compute four skill scores:
- **听力 Listening score:** accuracy on `listening_choice` + `listening_fill` questions
- **阅读 Reading score:** accuracy on `meaning_choice` + `reading_comprehension` questions
- **口语 Speaking score:** accuracy on `speaking_repeat` + `open_speaking` questions (self-reported)
- **拼写 Spelling score:** accuracy on `sentence_cloze_typing` + `word_form` + `listening_fill` questions

`listening_fill` contributes to both Listening and Spelling. In the overall tally, count it in Listening (the primary skill being tested). The spelling score uses `sentence_cloze_typing` + `word_form` only.

Then map each skill's accuracy rate to an estimated IELTS band, per the Scoring System PDF.

### Current state — DONE 2026-07-07

Implemented in migration `202607070034_skill_scoring.sql`: `sense_difficulty_weight(sense_id)` (returns the `bands.band_score` of the sense's originating level, default 4.0) and `compute_skill_band(weighted_correct, weighted_max)`. Read the actual PDF (`pdftotext`-extracted, since no PDF renderer was available in this environment): it offers two calibration methods — a logistic S-curve requiring simulation-derived constants (`k`, `m`) we don't have (no real user data exists pre-launch), and a piecewise raw-to-band table (its Table 2). We implemented the piecewise table, generalized as fractions of the maximum achievable weighted score (its cut points 0/10/25/40/55/70/85/100/115/130/135 out of max 135 become fractions 0/.074/.185/.296/.407/.519/.630/.741/.852/.963/1.0) — this is directly reusable without inventing calibration constants, unlike the logistic option. `complete_overall_assessment` computes weighted correct/max sums per skill (via `sense_difficulty_weight`) and calls `compute_skill_band`. Verified by `202607070034_skill_scoring_test.sql` and the overall-assessment integration test.

Note: in Phase 1, all content is Band 4.0, so the difficulty weighting is inert (every item has the same weight) — it activates automatically once Band 4.5+ content exists, without further changes.

### 3 Options

**Option 1 — Simple linear accuracy mapping**  
What: Map accuracy → IELTS band using a fixed linear scale:
- 0–49% → Band 4 (学习中)
- 50–64% → Band 4.5
- 65–74% → Band 5
- 75–84% → Band 5.5
- 85–92% → Band 6
- 93–97% → Band 6.5
- 98–100% → Band 7+
These thresholds are illustrative — replace with exact values from the Scoring PDF.

Effort: Very small. One function/SQL procedure.

**Option 2 — Weighted per-level accuracy (recommended, per the Scoring PDF)**  
What: Questions are tagged with the band level they come from (Band 4, 4.5, etc.). Within each skill, compute accuracy separately per band level. Then weight by difficulty:
```
axis_score(skill) = weighted_sum(correct_i * weight_i) / weighted_sum(total_i * weight_i)
where weight_i = band_difficulty_for_level_i
```
The highest band level where accuracy ≥ threshold determines the estimated IELTS band.

Effort: Small — requires the scoring formula from the PDF. The data shape already supports per-level tallies.

**Option 3 — Item Response Theory (IRT)**  
What: Estimate learner ability (θ) using a 3-parameter logistic model. Each question has calibrated difficulty, discrimination, and guessing parameters.  
Why not: The item parameters are not calibrated. This requires thousands of learner responses to estimate properly. Way beyond Phase 1.

### PM Recommendation: Option 2

**Why:** SAT scoring uses a "raw score → scaled score" conversion table (essentially a non-linear mapping). IELTS's own scoring converts raw scores to a band using a fixed rubric. Magoosh's score predictor uses regression over practice score distribution. Option 2 matches the Scoring PDF's intent (weighted by level difficulty) and is what we have been planning. Read the PDF and implement the exact formula it specifies.

**Required reading: D:\project\support\Scoring System Design for IELTS-Style Bands.pdf**  
Implement the scoring exactly as specified there. If any detail is unclear, the fallback formula from `SELF_ASSESSMENT_20Q_PLAN.md` is:
```
axis_score(skill) = 10 * Σ(correct_i) / Σ(total_i)   [0–10 scale]
```
Map the 0–10 score to IELTS band using the thresholds in the PDF.

### Question-to-skill mapping in database

The `questions` table must have a `skill_category` column. Values: `listening`, `reading`, `speaking`, `spelling`. The round assembly RPC should populate this when returning questions so Android can group them for the result screen.

If `skill_category` is not yet in the schema, add it:

```sql
-- To questions table
ALTER TABLE questions ADD COLUMN IF NOT EXISTS skill_category text
  CHECK (skill_category IN ('listening', 'reading', 'speaking', 'spelling'));

-- Backfill based on question type
UPDATE questions SET skill_category = CASE question_type_key
  WHEN 'listening_choice'          THEN 'listening'
  WHEN 'listening_fill'            THEN 'listening'
  WHEN 'speaking_repeat'           THEN 'speaking'
  WHEN 'open_speaking'             THEN 'speaking'
  WHEN 'meaning_choice'            THEN 'reading'
  WHEN 'reading_comprehension'     THEN 'reading'
  WHEN 'sentence_cloze_typing'     THEN 'spelling'
  WHEN 'word_form'                 THEN 'spelling'
  ELSE NULL
END
WHERE skill_category IS NULL;
```

### Acceptance Criteria

- `SCORE-001` After completing an assessment (40Q or 100Q), the result screen shows a score for each of the 4 skills.
- `SCORE-002` The skill score formula follows the exact specification in `Scoring System Design for IELTS-Style Bands.pdf`.
- `SCORE-003` The IELTS band estimate is labeled as an estimate, not an official score.
- `SCORE-004` If a skill category has 0 eligible questions in the assessment (thin pool), that skill shows "N/A — insufficient data."
- `SCORE-005` The score is computed server-side in `complete_overall_assessment` / `complete_band_upgrade_exam`, not on the client.
- `SCORE-006` The `overall_band` is the average (or minimum, per the PDF) of the 4 skill scores.

---

## 12. Feature J: Awards & Reward System

### What it does

The app rewards learners with:
1. **Duck power (经验值):** earned on every round completion. Accumulates toward titles.
2. **Streak props (道具):** Streak Freeze (冻结符), Streak Repair (修复符) — protect the streak.
3. **Login milestone awards (登录成就徽章):** badges for reaching login count milestones.
4. **Level completion awards:** badges for completing levels or bands.
5. **Scratch cards (刮刮卡):** earned on round completion, provide a random bonus (extra duck power, a streak freeze, etc.).

### Current state — DONE 2026-07-07

Duck power, streak fields, titles, scratch card UI, and migration 024 (props and protection) exist. Login-milestone and level-completion badges are now implemented in migration `202607070031_awards_system.sql` (`award_definitions`, `user_awards`, `check_and_grant_awards(user_id)`). Band-completion badges are wired into the same function (checked via `band_upgrade_attempts.passed`) but no `band_complete` award rows are seeded yet — add them when Band 4.5 content ships.

**Deliberate deviation from this section's original design:** `check_and_grant_awards()` is called by the Android client (`AppSessionViewModel` after `record_login()`) rather than embedded inside `complete_practice_round`/`complete_band_upgrade_exam`. This avoids modifying those already-tested, complex functions. The function is idempotent (checks actual current state, not incremental events), so a client that forgets to call it just delays a badge grant to the next login — it never loses one. Wire a call after `complete_practice_round`/`complete_band_upgrade_exam` too if you want badges to appear immediately after those actions rather than at next login.

Verified by `202607070031_awards_system_test.sql` (grants exactly once, respects thresholds) and Android `ProfileScreen.kt`'s new "我的成就" card + `MainActivity.kt`'s celebration dialog.

### 3 Options

**Option 1 — Static badge-only system**  
What: Predefined badges. Show a badge when a milestone is reached. No economy or spending. Simple to build.

**Option 2 — XP + spendable currency (Duolingo model)**  
What: Duck power = XP (experience points) that accumulates and determines title. Separate "gems" or coins that can be spent on streak freezes, hints, or cosmetics. Implements a full micro-economy.  
Complexity: Requires a ledger table, spend/earn transactions, price definitions. Risk of balance issues.

**Option 3 — Achievement layer + spendable props + login milestones (recommended)**  
What: Three parallel systems:
- Duck power: earns titles, purely display-only accumulation. Already implemented.
- Props: streak freezes and repairs. Earned via scratch cards and login milestones. Spent by the system (auto) or user. Already partially implemented.
- Badges/achievements: earned for login count milestones, level completions. Display-only. New.

### PM Recommendation: Option 3

**Why:** Duolingo has both XP (accumulating, earns leagues ranking) AND gems (spendable). Khan Academy uses badges for milestones (Earth, Moon, Sun, Black Hole levels). SAT prep apps (Magoosh) use streak and daily goal systems. The combination of accumulating XP (duck power) + one-time achievement badges + limited spendable props is the most balanced system for a vocabulary app.

**Login milestone awards (badge triggers based on `login_count`):**

| Trigger | Award | Badge name |
|---|---|---|
| First login | `bronze_duck` badge | 第一只鸭！|
| 3rd login | 1× Streak Freeze | 初学者连续登录 |
| 7th login | `silver_duck` badge + 1× Streak Repair | 坚持一周 |
| 30th login | `gold_duck` badge + 2× Streak Freeze | 学习达人 |
| 100th login | `platinum_duck` badge + 3× Streak Freeze | 坚持不懈 |

**Level completion awards:**

| Trigger | Award |
|---|---|
| Complete Level 1 | 50 duck power bonus + `first_level` badge |
| Complete Level 5 | 200 duck power bonus + `band4_starter` badge |

### Database additions needed

```sql
CREATE TABLE award_definitions (
  id          text PRIMARY KEY,  -- e.g. 'bronze_duck', 'first_level'
  name_zh     text NOT NULL,
  description_zh text,
  trigger_type text NOT NULL,  -- 'login_count', 'level_complete', 'band_complete'
  trigger_value text,          -- e.g. '1', '5', '4.0'
  icon_name   text
);

CREATE TABLE user_awards (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  award_id    text NOT NULL REFERENCES award_definitions(id),
  awarded_at  timestamptz NOT NULL DEFAULT now(),
  seen_by_user boolean DEFAULT false,
  UNIQUE (user_id, award_id)  -- each badge earned at most once
);
CREATE INDEX ON user_awards (user_id);
```

**Award-check RPC (called from `record_login` and `complete_practice_round`):**

```sql
CREATE OR REPLACE FUNCTION check_and_grant_awards(p_user_id uuid)
RETURNS TABLE (new_award_id text, new_award_name text) ...
-- Checks login_count milestones and newly completed levels/bands.
-- Inserts into user_awards for any not-yet-earned awards.
-- Returns the newly granted awards so Android can show a celebration animation.
```

### Acceptance Criteria

- `AWARD-001` First login grants the `bronze_duck` badge.
- `AWARD-002` Each login milestone badge is granted exactly once (idempotent check).
- `AWARD-003` When a new award is granted, Android shows a celebration screen/animation.
- `AWARD-004` The profile screen shows all earned badges.
- `AWARD-005` Scratch card reward is earned on completing a practice round (once per day maximum).
- `AWARD-006` Duck power cannot be manipulated by the client; only RPCs grant it.
- `AWARD-007` A Streak Freeze prop, when active, prevents streak loss on a missed day.

---

## 13. Feature K: Levels 6+ "Coming Soon"

### What it does

Levels 6 through all higher levels are visible in the UI as locked cards with a "即将上线" ("Coming soon") label. Tapping them shows a placeholder screen — it does not crash or route to a blank screen.

### Current state — DONE 2026-07-07

Levels 6–33 have `band_4_0_v1` data imported and are genuinely playable (lightweight question-type set, per migration 025) — they are Band 4.0 content, not "coming soon." Only levels outside Band 4.0 (`band_id <> 1`, i.e. Level 34+ / Band 4.5 and beyond) are coming-soon, since those are metadata-only stub rows with no real word/question data (confirmed via `verify_project_installation.sql`: 240 total level rows, only 33 have content).

Implemented in migration `202607070033_coming_soon_flag.sql` (`levels.is_coming_soon`, set `true` where `band_id <> 1`). Android: `HomeScreen.kt`'s `LevelRow` shows a dimmed card with a "即将上线" label; tapping shows an `AlertDialog` ("这个关卡即将上线，敬请期待！") instead of navigating — this reuses the existing locked-level dimming pattern rather than a separate placeholder screen/route, which is a smaller change with the same user-facing effect (CS-002/CS-003 are satisfied by the dialog, not a dedicated screen).

### 3 Options

**Option 1 — Hidden completely**  
What: Only show Levels 1–5 in the home screen. No hint that more exist.  
Cons: Makes the app look tiny. No anticipation. Users don't know there's a learning path ahead.

**Option 2 — Show locked cards with "Coming Soon" label (recommended)**  
What: Show all levels in the learning path list. Levels 6+ appear grayed out with a `🔒 即将上线` label. Tapping shows a non-dismissable "这个关卡即将上线，敬请期待！" screen. Progress bar for the level shows empty.  
Pros: Creates a sense of journey. The learner sees how much is ahead. Standard UX for early-access apps.

**Option 3 — Show a separate "Roadmap" section**  
What: The home screen has an "即将推出" section below the active levels, listing future content with their topic names but locked and unplayable.  
Pros: Even more transparent about the content roadmap.  
Cons: Requires maintaining a separate list. More UI work.

### PM Recommendation: Option 2

**Why:** Duolingo shows the entire language tree, with future skills locked in gray until prerequisites are met. Khan Academy shows all units in a course — locked units are visually present. This creates a sense of a complete product and motivates learners to keep going. Option 2 is simple to implement and has the highest UX benefit-to-effort ratio.

**Implementation rule:** Levels 6+ are read from Supabase just like Levels 1–5. The only difference is their `is_coming_soon = true` flag (or they have `is_unlocked = false` and no completion of Level 5 by the user means Level 6 never gets unlocked). Use the `is_coming_soon` metadata to render the label differently.

Add a `is_coming_soon` boolean to the `levels` table or derive it from: if `level_number > 5` AND user has not received Band 4.5 content → show as coming soon.

For Phase 1: Set `is_coming_soon = true` for all levels where the band content is not yet production-ready (Levels 6+ for Band 4.5, all Band 5+).

### Acceptance Criteria

- `CS-001` Levels 6–33 appear in the learning path list with a locked visual treatment.
- `CS-002` Tapping a "coming soon" level shows a placeholder screen with encouraging text.
- `CS-003` Tapping a "coming soon" level does NOT start a practice round.
- `CS-004` The Band 4.5 section header is visible but labeled as "即将上线."
- `CS-005` All "coming soon" behavior is determined by server-returned metadata, not hardcoded in the client.

---

## 14. Database Schema — Complete Requirement Summary

### Already implemented (verify on hosted Supabase)

```
profiles                      — user account, duck_power, streak fields
user_settings
onboarding_profiles
bands, topic_clusters, levels
content_sources, words, word_senses
level_sense_assignments
word_forms, pronunciations
examples, collocations, lexical_relations, usage_evidence
question_types, questions, question_options
user_level_progress
practice_sessions, practice_answers
practice_rounds, round_questions
user_sense_mastery
mistake_senses
band_upgrade_attempts
band_upgrade_attempt_questions
```

### Must add or verify in Phase 1 — ALL DONE 2026-07-07, pending hosted-Supabase apply

| Table | Status | Priority |
|---|---|---|
| `user_login_log` | Done — migration 030 | High |
| `award_definitions` | Done — migration 031 | High |
| `user_awards` | Done — migration 031 | High |
| `overall_assessment_attempts` | Done — migration 035 | High |
| `overall_assessment_questions` | Done — migration 035 | High |
| `questions.skill_category` | Done — migration 032 | High |
| `profiles.login_count` | Done — migration 030 | High |
| `profiles.first_login_at` | Done — migration 030 | Medium |
| `levels.is_coming_soon` | Done — migration 033 | Medium |

### Migration sequence for Phase 1 additions — actual filenames (differ slightly from the original plan)

```
202607070029_review_before_new_sense_priority.sql — Feature E bug fix (see above), not originally planned
202607070030_login_tracking.sql          — user_login_log, profiles.login_count/first_login_at/last_login_at, record_login()
202607070031_awards_system.sql           — award_definitions, user_awards, check_and_grant_awards()
202607070032_skill_category_column.sql   — questions.skill_category, backfill UPDATE
202607070033_coming_soon_flag.sql        — levels.is_coming_soon, set true where band_id <> 1
202607070034_skill_scoring.sql           — sense_difficulty_weight(), compute_skill_band() (must precede 035, which calls it)
202607070035_overall_assessment.sql      — overall_assessment_attempts/questions, start/save/complete RPCs
```

Apply all of 025–035 to the hosted Supabase in filename order — none of migrations 029–035 have been applied to a hosted project yet, only verified via the local Docker harness (`backend/supabase/manual/run_phase1_local_docker_verification.ps1`).

---

## 15. RPC Contract Summary

### Existing RPCs (verify are applied on hosted Supabase)

| RPC | Migration | Status |
|---|---|---|
| `bootstrap_user()` | 001–007 | Verify |
| `save_onboarding_answer()` | 007 | Verify |
| `complete_onboarding()` | 007 | Verify |
| `start_practice_round(level_number)` | 009, 020, 025 | Verify |
| `save_practice_answer(round_id, position, answer, ms)` | 009, 011, 012 | Verify — this is the live path |
| `complete_practice_round(round_id)` | 009, 011, 014 | Verify |
| `get_level_word_statuses(level_number)` | 014 | Verify |
| `start_band_upgrade_exam(target_band)` | 026 | Verify |
| `save_band_upgrade_answer(attempt_id, position, answer)` | 026 | Verify |
| `complete_band_upgrade_exam(attempt_id)` | 026 | Verify |

**Dead code found in 2026-07-07 audit:** `finalize_practice_answer` (added in migration 020) appears to have no `GRANT EXECUTE` to `authenticated` and is not called by the production evidence test (`202607060029_phase1_practice_logging_evidence_test.sql` calls `save_practice_answer` directly). Confirm this is truly unused before Phase 1 sign-off, and either wire it in or delete it — don't leave two parallel answer-saving functions in the schema.

### New RPCs for Phase 1 — DONE 2026-07-07

| RPC | Migration | Purpose |
|---|---|---|
| `record_login()` | 030 | Increment login_count, insert into user_login_log |
| `check_and_grant_awards(user_id)` | 031 | Check login milestones, grant new badges — called from Android, not embedded server-side (see Feature J) |
| `sense_difficulty_weight(sense_id)` | 034 | Per-item difficulty weight (bands.band_score) for the Scoring PDF's weighted raw score |
| `compute_skill_band(weighted_correct, weighted_max)` | 034 | Piecewise raw-to-band mapping (Scoring PDF Table 2) |
| `start_overall_assessment()` | 035 | Create/resume the learner's one active 100-question assessment attempt |
| `save_overall_assessment_answer(attempt_id, position, answer, ms)` | 035 | Grade and save one assessment answer |
| `complete_overall_assessment(attempt_id)` | 035 | Tally scores, compute per-skill bands, return result |

---

## 16. Android Implementation Sequence

Do these in order. Do not start step N until step N-1 passes its acceptance criteria.

### Step 1: Backend stabilization — DONE locally 2026-07-07, hosted apply still pending

1. Apply migrations 025–035 to the hosted Supabase in filename order. **Not yet done** — only applied and verified against the disposable local Docker Postgres via `run_phase1_local_docker_verification.ps1`.
2. Run `verify_project_installation.sql`. Required READY, 0 warnings, 0 failures — passed locally (137 checks).
3. Run all SQL test files in `backend/supabase/tests/` — all pass locally, including the 4 new ones added 2026-07-07 (`202607070030`, `202607070031`, `202607070034`, `202607070035`).
4. Run `.\gradlew.bat test` — passed.
5. Run `.\gradlew.bat assembleDebug` — passed.
6. Record the hosted migration state in `docs/plans/README.md` — still to do once applied to a real hosted project.

### Step 2: 8 question types in Android UI — DONE 2026-07-07

All 8 types now render with distinct content-area UI in `LevelPracticeScreen.kt`; `open_speaking` and `word_form` were the gap, both fixed. Not yet verified by an actual on-device manual run through a Level 1 round (only `gradlew test`/`assembleDebug`).

### Step 3: Login tracking — DONE 2026-07-07

Migration 030 applied locally. `AppSessionViewModel` calls `recordLoginAndCheckAwards()` (which calls both `record_login()` and `check_and_grant_awards()`) once per session, guarded against double-counting on `retry()`.

### Step 4: Awards system — DONE 2026-07-07

Migration 031 applied locally with 7 seeded `award_definitions` rows (bronze/silver/gold/platinum_duck at login counts 1/7/30/100, login_streak_3 at count 3, first_level/band4_starter at level completions). `check_and_grant_awards()` is called from Android (`AppSessionViewModel`) rather than embedded in `complete_practice_round`, per the deliberate-deviation note in Feature J. `MainActivity.kt` shows a celebration `AlertDialog` for new awards; `ProfileScreen.kt` has a "我的成就" card listing all earned badges.

### Step 5: Level-up unlock chain verification (Levels 1–5)

Not re-verified in this pass — `202607060027_band4_unlock_chain_test.sql` already passed as part of the Step 1 local Docker run, but a manual on-device play-through against a hosted Supabase project is still outstanding.

### Step 6: "Coming Soon" treatment — DONE 2026-07-07, with a scope correction

Migration 033 sets `is_coming_soon = true` where `band_id <> 1` (not "Level 6+" — Levels 6–33 are real Band 4.0 content and are NOT coming-soon; only Level 34+/Band 4.5+ is). Android: `HomeScreen.kt`'s existing `LevelRow` renders the coming-soon state inline (dimmed, "即将上线" label) rather than a separate `ComingSoonLevelCard`/`ComingSoonScreen`; tapping shows an `AlertDialog`, not a routed screen. This reuses existing UI instead of building new components, with the same user-facing effect.

### Step 7: Band Assessment wiring

Already done prior to this pass (confirmed by the 2026-07-07 audit) — `BandUpgradeExamScreen`/`BandUpgradeExamViewModel` are fully wired to the real RPCs. `band4_complete`/similar award rows are not yet seeded in `award_definitions` (only `band_complete` trigger-type support exists in `check_and_grant_awards`); add rows when needed.

### Step 8: Overall Assessment — DONE 2026-07-07

Migrations 032 (`skill_category_column.sql`) and 035 (`overall_assessment.sql`) applied locally. `OverallAssessmentScreen.kt` and `OverallAssessmentViewModel.kt` built, with a `Confirm` state (question count + time warning) before starting. Wired to `start_overall_assessment`/`save_overall_assessment_answer`/`complete_overall_assessment`. Result screen shows the 4-skill breakdown, band estimates, and the "not an official IELTS score" disclaimer. "📊 开始评测" button added to `HomeScreen.kt`.

### Step 9: Scoring system implementation — DONE 2026-07-07

Read the actual Scoring PDF via `pdftotext` extraction (no PDF renderer was available in this environment). Implemented `sense_difficulty_weight(sense_id)` and `compute_skill_band(weighted_correct, weighted_max)` in migration 034 (signature differs from this step's original sketch — see Feature I for why: it takes pre-aggregated weighted sums, not raw arrays, computed by the caller). Called from `complete_overall_assessment` only; `complete_band_upgrade_exam` was left untouched since its result screen only needs raw category counts, not band estimates (see Feature G's result mockup). Unit-tested against concrete accuracy fractions in `202607070034_skill_scoring_test.sql`.

### Step 10: Final integration pass

1. Full fresh-user run-through: register → onboarding → Level 1–5 → band exam → overall assessment.
2. Sign-out and sign-in → verify all state restored.
3. App kill mid-round → verify round resumes.
4. Wrong answers → verify in mistake notebook and in next round's priority list.
5. Run all unit tests and SQL tests.
6. Record evidence (build hash, migration state, test results).

---

## 17. Acceptance Criteria Master Checklist

### Authentication

- [ ] `AUTH-001` through `AUTH-006` (Feature A)

### Login Tracking & Streaks

- [ ] `STREAK-001` through `STREAK-007` (Feature B)

### Level-Up Logic

- [ ] `LEVEL-001` through `LEVEL-008` (Feature C)

### Question Types

- [ ] `QT-001` through `QT-008` (Feature D)

### Practice Rounds

- [ ] `ROUND-001` through `ROUND-008` (Feature E)

### Spaced Review

- [ ] `SRS-001` through `SRS-007` (Feature F)

### Band Assessment

- [ ] `EXAM-001` through `EXAM-010` (Feature G)

### Overall Assessment

- [ ] `ASSESS-001` through `ASSESS-009` (Feature H)

### Skill Scoring

- [ ] `SCORE-001` through `SCORE-006` (Feature I)

### Awards

- [ ] `AWARD-001` through `AWARD-007` (Feature J)

### Coming Soon

- [ ] `CS-001` through `CS-005` (Feature K)

---

## 18. What "Done" Means for Phase 1

Phase 1 is done when a fresh user can run through this entire script without manual database intervention:

```
1. Install APK
2. Register new account (username + password)
3. Complete 5-question onboarding
4. Land on home screen with Level 1 unlocked, Levels 2-5 locked, Level 6+ "coming soon"
5. Start Level 1 practice round
   → Round contains a mix of all 8 question types
   → Answers are graded server-side
   → Wrong answers appear in mistake notebook
   → Duck power increments on completion
   → Day streak check-in records
6. Complete enough rounds of Level 1 to unlock Level 2
   → Level 2 card changes from 🔒 to 待开始
7. Progress through Level 2, 3, 4, 5 in the same manner
8. Take the Band 4 assessment
   → 40 questions from Band 4 content
   → Result shows per-skill score
   → Passing ≥37/40 shows "通过" (Band 4.5 not available yet, but unlock logic fires)
9. Run the Overall Assessment from the home page
   → 100 questions
   → Result shows 4-skill breakdown + IELTS band estimate + disclaimer
10. Sign out
11. Sign back in → same level progress, same streak, same awards, same mistakes
12. Kill app mid-round, reopen → same round resumes at the correct question
```

**No feature is done because its screen exists. A feature is done when its server state, client behavior, error handling, and persistence all work correctly across the above script.**

---

## 19. Market Comparison Reference

| Design decision | Our app | Duolingo | Khan Academy SAT | Magoosh IELTS |
|---|---|---|---|---|
| Auth | Username/PW | Email/Google/Apple | Google/Email | Email/Google |
| Streak | Daily, server-enforced | Daily, with freeze | Weekly goals | No streak |
| Progress gate | 10-min delayed recall | Multiple crowns | Mastery > 70% score | Accuracy threshold |
| Review schedule | 10min/1day/7day/30day | Hidden (SRS-like) | Adaptive practice | Flashcard review |
| Assessment | 100Q diagnostic | Placement test | Full 44Q SAT test | Full IELTS mock |
| Question types | 8 types | ~15 types | Reading + Writing | All 4 IELTS skills |
| Rewards | Duck power + badges + props | XP + gems + leagues | Points + badges | Progress bar only |
| Coming soon | Locked with label | Locked with lock icon | Hidden until prereq | N/A |
| Score reporting | Per-skill bands | XP only | SAT scale score | IELTS band estimate |

The competitive insight: **Duolingo wins on engagement (streaks, social, daily habits). Khan Academy wins on score validity (diagnostic quality). Magoosh wins on IELTS relevance.** This app must combine all three for a Chinese learner: the habit hooks of Duolingo, the IELTS-specific score reporting of Magoosh, and the spaced mastery logic of Khan Academy's exercise system.

---

*End of Phase 1 Construction Masterplan*  
*Next action: Begin with Section 16, Step 1 (backend stabilization). Do not skip steps.*
