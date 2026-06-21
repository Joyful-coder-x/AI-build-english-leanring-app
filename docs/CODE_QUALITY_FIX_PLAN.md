# Engineering Principles & Future Change Plan

> Phase 0–2 complete (49/49 tests passing, BUILD SUCCESSFUL as of last commit).
> This document captures forward-looking constraints — things to remember before
> the next phase grows the codebase significantly.

## Guidance for Phase 3+

Apply these principles as the app grows beyond the current prototype.

### Dependency Injection

- Keep manual DI only while the app is small.
- Move from `AppRepositories` to an app-level container or Hilt/Koin when more real repositories are added.
- Make repository mode explicit: fake/demo, local test, or real backend.
- Avoid mixing fake and real implementations without a named feature flag or build variant.

### Navigation

- Keep simple manual navigation only for the current small flow.
- Move to `navigation-compose` before adding several nested flows, deep links, auth screens, or multiple independent tab back stacks.
- Make route arguments explicit instead of storing screen arguments only in local Compose state.

### Repository And Backend Boundaries

- Keep repository interfaces.
- Make every real repository query only the data it needs.
- Push filtering, sorting, limits, and user/card scoping into Supabase queries, views, or RPCs.
- Avoid temporary fake fallbacks inside real repository implementations unless they are clearly marked and centrally controlled.

### Testing

- Keep current unit tests.
- Improve tests when business rules expand:
  - Test extracted scoring functions directly.
  - Test ViewModels with fake repositories that exercise real paths.
  - Avoid duplicating production logic inside tests.
- Add integration tests only after backend behavior stabilizes.

### Source And Git Hygiene

- Decide which `.idea` files should be shared and ignore/remove personal IDE state.
- Keep `local.properties` and credentials out of git.
- Keep source files UTF-8, especially files with Chinese UI text.
- Move temporary debug screens and one-off connectivity tests to debug-only code or delete them after use.

### Architecture Restraint

- Do not add use cases/interactors just because they are common in larger apps.
- Add a new layer only when logic is duplicated, shared across screens, or hard to test inside a ViewModel.
- Keep feature changes small and avoid refactoring unrelated modules while adding product behavior.
