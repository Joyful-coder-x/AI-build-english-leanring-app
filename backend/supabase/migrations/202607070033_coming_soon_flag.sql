-- Phase 1 Feature K: Levels 6+ show a "coming soon" locked card once tapped,
-- distinct from the normal 未解锁 (locked-by-progress) treatment. Only
-- Band 4.0 (band_id=1, Levels 1-33) has production-ready content in Phase 1;
-- every other band is metadata-only stub rows (240 total level rows exist,
-- only 33 have real word/question data per verify_project_installation.sql).

begin;

alter table public.levels
  add column if not exists is_coming_soon boolean not null default false;

update public.levels
set is_coming_soon = true
where band_id <> 1;

commit;
