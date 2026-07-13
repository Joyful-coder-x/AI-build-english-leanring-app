-- Reset generated vocabulary/content data before a full content reload.
--
-- This intentionally keeps account tables:
--   profiles, user_settings, user_consents, onboarding_profiles, auth.users.
--
-- It clears shared curriculum/content plus dependent learning and assessment
-- rows so the Band 4 package can be loaded from a clean content state.
--
-- Static lookup tables such as bands and question_types are intentionally kept.
-- They are seeded by migrations and are referenced by the content package.

begin;

do $$
declare
  requested_tables text[] := array[
    'overall_assessment_questions',
    'overall_assessment_attempts',
    'band_upgrade_attempt_questions',
    'band_upgrade_attempts',
    'practice_round_questions',
    'practice_rounds',
    'practice_answers',
    'practice_sessions',
    'question_attempts',
    'user_level_progress',
    'user_sense_mastery',
    'user_sense_skill_progress',
    'user_skill_progress',
    'mistake_senses',
    'user_awards',
    'question_options',
    'questions',
    'question_types',
    'usage_evidence',
    'lexical_relations',
    'collocations',
    'examples',
    'pronunciations',
    'word_forms',
    'level_sense_assignments',
    'word_senses',
    'words',
    'content_sources',
    'levels',
    'topic_clusters'
  ];
  existing_tables text;
begin
  select string_agg(format('public.%I', table_name), ', ')
  into existing_tables
  from unnest(requested_tables) as requested(table_name)
  where to_regclass('public.' || requested.table_name) is not null;

  if existing_tables is not null then
    execute 'truncate table ' || existing_tables || ' restart identity cascade';
  end if;
end
$$;

commit;
