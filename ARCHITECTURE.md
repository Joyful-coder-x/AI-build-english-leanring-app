# 夸夸鸭AI (KuaKua Duck) — Architecture & Build Plan

A gamified IELTS vocabulary-learning Android app. This document is the single
source of truth for *how* we build it. Specs (the "what") live in the design
docs at `第一期原型图+文档` (Phase-1 prototypes + Word docs).

---

## 1. Tech stack & key decisions

| Decision | Choice | Why |
|----------|--------|-----|
| UI toolkit | **Jetpack Compose** | Modern, Google-recommended default for new apps. |
| Architecture | **MVVM + Repository** | Clean separation; lets us swap data sources. |
| Language | Kotlin | — |
| Async | Kotlin coroutines / `Flow` | Standard for Compose. |
| Backend (app data) | **Supabase** (added in Phase 4) | Auth + Postgres + storage. |
| Content data (words/questions) | Bundled JSON / read-only source (TBD Phase 3) | Different lifecycle from user data. |
| AI features | **Faked entirely until late** | The spec assumes an AI backend; we stub it. |

### The core idea that makes this plan work: the Repository pattern
The UI never talks to a data source directly. It talks to a **`Repository`
interface**. We write two implementations:

- `Fake*Repository` — hardcoded in-memory data (build everything on this now)
- `Supabase*Repository` — real backend (Phase 4)

Swapping fake → real is a one-line change in the DI/provider. The UI and
ViewModels never change. **This is why we can build the whole app before
touching a backend.**

---

## 2. Module / package structure

```
com.example.firsttest/
├── data/
│   ├── model/          # Domain data classes (pure Kotlin, no Android deps)
│   └── repository/     # Repository interfaces + Fake implementations
│                       #   (Supabase implementations added in Phase 4)
├── ui/
│   ├── theme/          # Compose theme: Color, Type, Theme
│   ├── navigation/     # Bottom-nav + nav graph (4 tabs)
│   ├── profile/        # 个人中心  (Phase 1)
│   ├── home/           # 每日练习/首页  (Phase 1)
│   ├── streak/         # 夸夸连胜  (Phase 2)
│   ├── mistakes/       # 错词本  (Phase 2)
│   ├── practice/       # 答题流程  (Phase 2)
│   ├── onboarding/     # 新手引导  (Phase 2)
│   └── assessment/     # 评测体系  (Phase 2)
└── di/                 # Manual dependency provider (which repo impl to use)
```

Each feature screen folder holds its `*Screen.kt` (Composable) + `*ViewModel.kt`.

---

## 3. Build phases (current = Phase 0 → 1)

- **Phase 0 — Foundations** ✅ in progress
  - [x] Read all specs + prototypes
  - [x] Git init + baseline commit
  - [x] Architecture doc + core domain models + repository interfaces + fakes
  - [ ] Convert Gradle build to Kotlin + Compose  ← **next step**
  - [ ] Compose theme + bottom-nav scaffold

- **Phase 1 — Vertical slice on fake data**
  - [ ] Profile screen (个人中心) wired to `FakeUserRepository` via ViewModel
  - [ ] Home/daily-practice learning path (core of 2.2) on fake data
  - [ ] Unit tests on ViewModel + `DuckTitle` logic

- **Phase 2 — Expand features (still fake data):** streak, mistake notebook,
  answering flow, onboarding, assessment, duck-mascot text.

- **Phase 3 — Finalize data schemas:** design Supabase tables (app data) and
  the word/question content format (14 question types). Biggest content effort.

- **Phase 4 — Swap fake → Supabase:** implement `Supabase*Repository`s, real
  auth/login (2.1.1). UI/ViewModels unchanged.

- **Phase 5 — Polish:** loading/error/empty states, animations, release prep.

---

## 4. Domain model (entities)

Defined now (Phase 1) in `data/model/`:

- **User** — profile + progress. *App data → Supabase later.*
  - `DuckTitle` (鸭力称号, derived from `duckPower`) — 2.4.2
  - `UserLevel` (英语等级, Lv1–240 over IELTS bands 4.0–8.0) — 2.2.1
  - `AbilityRadar` (5 axes 0–10, current vs previous) — 2.1.3
  - `StreakInfo` (连胜) — 2.4.1
  - `Prop` (道具: 连胜保护 / 挑战赛钥匙) — 2.4
- **PracticeCard** — one card in the home learning path — 2.2.2

To be defined per phase (documented here so schema thinking isn't lost):

- **Word** (`text`, `phonetic`, `pronunciationUrl`, `meanings[]`, `mnemonic`,
  `examples[]`) + **WordMeaning** + **Example** (`sentenceEn`, `translationZh`,
  `audioUrl`) — 2.3 单词详情. *Content data.*
- **MistakeWord** (`word`, `addedAt`, Ebbinghaus `reviewState`) — 2.3 错词本.
- **Question** (`typeCode` 1–14, `category` 听说读写/新词, `answerForm`
  option/keyboard/voice, `stem`, `options[]`, `correctAnswer`, `translation`,
  `explanation`, `audioUrl`, `expectedTimeMs`) — 2.2.3. *Content data.*
- **PracticeSession** (the AI-pushed daily cycle + scoring) — 2.2.3.
- **Challenge** (极速挑战赛 / 连胜荣耀赛) — 2.2 辅助功能.
- **OnboardingProfile** (5 questions) — 2.7.
- **AssessmentResult** (IELTS score + radar + report) — 2.9.

### Scoring rules captured from spec (2.2.3) — for ViewModel + unit tests
- Star rating by accuracy: 0★ <40%, 1★ 40–65%, 2★ 65–90%, 3★ ≥90%.
- Base 鸭力值: +1 per correct; +5 if all correct.
- Combo: >5 → +1/correct; >10 → +2/correct. Speed bonus: 3★ within expected time → +5.
- Level/EXP only ever shown going **up** on the UI, never down.

---

## 5. Testing approach

- **Unit-test the logic**, not the UI: ViewModels, `DuckTitle.forDuckPower`,
  scoring/star rules. Use JUnit (already in project).
- **Defer** instrumented/Espresso UI tests (slow, flaky) until features settle.
- Manual testing on the emulator is the main end-to-end check for now.

---

## 6. Sample/fake data

`Fake*Repository`s mirror the values shown in the prototypes (e.g. user
`leoninebess`, 450 鸭力值 → 初学鸭, LV 20 / 脆皮新生, IELTS 5.5, 5-day streak,
连胜保护 ×2, 挑战赛钥匙 ×3) so screens look like the design while disconnected
from any backend.
