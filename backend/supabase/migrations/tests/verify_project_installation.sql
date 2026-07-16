-- KuaKua Duck: read-only Supabase installation and complete Band 4.0 check.
--
-- Run the entire file in Supabase Dashboard -> SQL Editor.
-- It does not change persistent application data. Temporary objects disappear
-- when the SQL Editor session ends.
--
-- Result:
--   PASS = required object/data is present
--   WARN = present, but below the expected five-level package count
--   FAIL = required object is missing or an integrity check failed

drop table if exists pg_temp.kuakua_verification_report;

create temporary table kuakua_verification_report (
  sort_order integer not null,
  category text not null,
  check_name text not null,
  status text not null check (status in ('PASS', 'WARN', 'FAIL')),
  expected text,
  actual text,
  details text
);

do $$
declare
  item text;
  actual_count bigint;
  expected_count bigint;
  relation_name text;
begin
  -- Required public tables.
  foreach item in array array[
    'profiles',
    'user_settings',
    'user_consents',
    'onboarding_profiles',
    'bands',
    'topic_clusters',
    'levels',
    'content_sources',
    'words',
    'word_senses',
    'level_sense_assignments',
    'word_forms',
    'pronunciations',
    'examples',
    'collocations',
    'lexical_relations',
    'usage_evidence',
    'question_types',
    'questions',
    'question_options',
    'user_level_progress',
    'practice_sessions',
    'practice_answers',
    'user_sense_mastery',
    'user_sense_skill_progress',
    'mistake_senses',
    'practice_rounds',
    'practice_round_questions'
  ]
  loop
    insert into kuakua_verification_report
    values (
      10,
      'schema',
      'table public.' || item,
      case when to_regclass('public.' || item) is not null then 'PASS' else 'FAIL' end,
      'exists',
      case when to_regclass('public.' || item) is not null then 'exists' else 'missing' end,
      null
    );
  end loop;

  -- Persisted profile counters used by the Home status row.
  foreach item in array array[
    'current_streak_days',
    'longest_streak_days',
    'last_practice_date'
  ]
  loop
    insert into kuakua_verification_report
    select
      15,
      'schema',
      'column public.profiles.' || item,
      case when exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'profiles'
          and column_name = item
      ) then 'PASS' else 'FAIL' end,
      'exists',
      case when exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'profiles'
          and column_name = item
      ) then 'exists' else 'missing' end,
      null;
  end loop;

  foreach item in array array[
    'is_context_hint',
    'context_for_multiple_meaning'
  ]
  loop
    insert into kuakua_verification_report
    select
      15,
      'schema',
      'column public.questions.' || item,
      case when exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'questions'
          and column_name = item
      ) then 'PASS' else 'FAIL' end,
      'exists',
      case when exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'questions'
          and column_name = item
      ) then 'exists' else 'missing' end,
      null;
  end loop;

  -- Required enum types.
  foreach item in array array[
    'onboarding_status_enum',
    'consent_document_enum',
    'onboarding_flow_state_enum',
    'vocabulary_role_enum',
    'placement_type_enum',
    'content_review_status_enum',
    'learning_skill_enum',
    'session_type_enum',
    'session_status_enum',
    'question_category',
    'answer_form',
    'sense_learning_state_enum',
    'practice_round_status_enum'
  ]
  loop
    insert into kuakua_verification_report
    select
      20,
      'schema',
      'type public.' || item,
      case when exists (
        select 1
        from pg_type t
        join pg_namespace n on n.oid = t.typnamespace
        where n.nspname = 'public'
          and t.typname = item
      ) then 'PASS' else 'FAIL' end,
      'exists',
      case when exists (
        select 1
        from pg_type t
        join pg_namespace n on n.oid = t.typnamespace
        where n.nspname = 'public'
          and t.typname = item
      ) then 'exists' else 'missing' end,
      null;
  end loop;

  -- Required functions/RPCs. to_regprocedure checks the exact argument types.
  foreach item in array array[
    'public.set_updated_at()',
    'public.handle_new_auth_user()',
    'public.record_user_consent(public.consent_document_enum,text)',
    'public.get_user_bootstrap_state()',
    'public.build_user_bootstrap_state(uuid)',
    'public.save_onboarding_answer(text,text,text,integer)',
    'public.finalize_placement(numeric,boolean)',
    'public.save_meaning_choice_answer(integer,uuid,uuid,boolean,integer)',
    'public.complete_meaning_choice_session(integer,integer,integer,smallint,integer)',
    'public.start_practice_round(integer)',
    'public.save_practice_answer(uuid,integer,text,integer)',
    'public.complete_practice_round(uuid)',
    'public.get_level_learning_status(integer)',
    'public.get_level_word_statuses(integer)'
  ]
  loop
    insert into kuakua_verification_report
    values (
      30,
      'rpc',
      item,
      case when to_regprocedure(item) is not null then 'PASS' else 'FAIL' end,
      'exists with exact signature',
      case when to_regprocedure(item) is not null then 'exists' else 'missing' end,
      null
    );
  end loop;

  -- Latest onboarding behavior: the fifth answer completes onboarding and
  -- unlocks Level 1 instead of routing to the retired assessment flow.
  insert into kuakua_verification_report
  select
    35,
    'rpc',
    'onboarding completes into Level 1',
    case
      when to_regprocedure(
        'public.save_onboarding_answer(text,text,text,integer)'
      ) is null then 'FAIL'
      when pg_get_functiondef(
        to_regprocedure(
          'public.save_onboarding_answer(text,text,text,integer)'
        )
      ) ilike '%is_final_answer%'
       and pg_get_functiondef(
        to_regprocedure(
          'public.save_onboarding_answer(text,text,text,integer)'
        )
      ) ilike '%level_number%'
       and pg_get_functiondef(
        to_regprocedure(
          'public.save_onboarding_answer(text,text,text,integer)'
        )
      ) ilike '%home_ready%'
      then 'PASS'
      else 'FAIL'
    end,
    'fifth answer sets home_ready and unlocks Level 1',
    case
      when to_regprocedure(
        'public.save_onboarding_answer(text,text,text,integer)'
      ) is null then 'function missing'
      when pg_get_functiondef(
        to_regprocedure(
          'public.save_onboarding_answer(text,text,text,integer)'
        )
      ) ilike '%is_final_answer%'
       and pg_get_functiondef(
        to_regprocedure(
          'public.save_onboarding_answer(text,text,text,integer)'
        )
      ) ilike '%level_number%'
       and pg_get_functiondef(
        to_regprocedure(
          'public.save_onboarding_answer(text,text,text,integer)'
        )
      ) ilike '%home_ready%'
      then 'latest flow installed'
      else 'legacy assessment flow still installed'
    end,
    'Apply migration 202606240007_onboarding_starts_at_level_one.sql if this fails.';

  -- Auth signup trigger.
  insert into kuakua_verification_report
  select
    40,
    'authentication',
    'auth.users signup trigger',
    case when exists (
      select 1
      from pg_trigger trigger_row
      join pg_class table_row on table_row.oid = trigger_row.tgrelid
      join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
      where schema_row.nspname = 'auth'
        and table_row.relname = 'users'
        and trigger_row.tgname = 'on_auth_user_created'
        and not trigger_row.tgisinternal
    ) then 'PASS' else 'FAIL' end,
    'on_auth_user_created exists',
    case when exists (
      select 1
      from pg_trigger trigger_row
      join pg_class table_row on table_row.oid = trigger_row.tgrelid
      join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
      where schema_row.nspname = 'auth'
        and table_row.relname = 'users'
        and trigger_row.tgname = 'on_auth_user_created'
        and not trigger_row.tgisinternal
    ) then 'exists' else 'missing' end,
    'Creates profile, settings, consent, and onboarding rows after signup';

  -- RLS must be enabled on all user-private tables.
  foreach item in array array[
    'profiles',
    'user_settings',
    'user_consents',
    'onboarding_profiles',
    'user_level_progress',
    'practice_sessions',
    'practice_answers',
    'user_sense_mastery',
    'user_sense_skill_progress',
    'mistake_senses',
    'practice_rounds',
    'practice_round_questions'
  ]
  loop
    insert into kuakua_verification_report
    select
      50,
      'security',
      'RLS public.' || item,
      case when coalesce(c.relrowsecurity, false) then 'PASS' else 'FAIL' end,
      'enabled',
      case when coalesce(c.relrowsecurity, false) then 'enabled' else 'disabled/missing' end,
      null
    from (values (1)) seed(value)
    left join pg_class c
      on c.oid = to_regclass('public.' || item);

    select count(*)
    into actual_count
    from pg_policies
    where schemaname = 'public'
      and tablename = item;

    insert into kuakua_verification_report
    values (
      51,
      'security',
      'policy public.' || item,
      case
        when item = 'practice_round_questions' and actual_count = 0 then 'PASS'
        when item <> 'practice_round_questions' and actual_count > 0 then 'PASS'
        else 'FAIL'
      end,
      case
        when item = 'practice_round_questions'
          then '0 policies; security-definer RPC access only'
        else 'at least 1 policy'
      end,
      actual_count::text,
      case
        when item = 'practice_round_questions'
          then 'Correct answers are stored in the snapshot and must not be directly readable.'
        else null
      end
    );
  end loop;

  insert into kuakua_verification_report
  select
    52,
    'security',
    'authenticated has no direct practice-round snapshot access',
    case when not has_table_privilege(
      'authenticated',
      'public.practice_round_questions',
      'SELECT'
    ) then 'PASS' else 'FAIL' end,
    'no SELECT privilege',
    case when has_table_privilege(
      'authenticated',
      'public.practice_round_questions',
      'SELECT'
    ) then 'SELECT granted' else 'no SELECT privilege' end,
    'Snapshot access must go through start/save/complete RPCs.';

  -- Complete Band 4.0 import minimum row counts. Greater counts are allowed
  -- because later difficulty bands may also be loaded.
  for relation_name, expected_count in
    select *
    from (values
      ('content_sources', 6::bigint),
      ('topic_clusters', 62::bigint),
      ('levels', 240::bigint),
      ('words', 1465::bigint),
      ('word_senses', 1465::bigint),
      ('word_forms', 1747::bigint),
      ('pronunciations', 1453::bigint),
      ('level_sense_assignments', 1465::bigint),
      ('usage_evidence', 1429::bigint),
      ('examples', 2930::bigint),
      ('collocations', 34::bigint),
      ('questions', 4395::bigint),
      ('question_options', 11720::bigint)
    ) expected(relation_name, expected_count)
  loop
    if to_regclass('public.' || relation_name) is null then
      insert into kuakua_verification_report
      values (
        60,
        'Band 4.0 import',
        relation_name || ' row count',
        'FAIL',
        'at least ' || expected_count,
        'table missing',
        null
      );
    else
      execute format('select count(*) from public.%I', relation_name)
      into actual_count;

      insert into kuakua_verification_report
      values (
        60,
        'Band 4.0 import',
        relation_name || ' row count',
        case when actual_count >= expected_count then 'PASS' else 'WARN' end,
        'at least ' || expected_count,
        actual_count::text,
        case
          when actual_count < expected_count
          then 'The compact Levels 1-33 Band 4.0 package does not appear to be loaded.'
          else null
        end
      );
    end if;
  end loop;

  -- Every compact Band 4.0 level must match its configurable new_sense_target.
  if to_regclass('public.level_sense_assignments') is not null
     and to_regclass('public.levels') is not null then
    for item in select generate_series(1, 33)::text
    loop
      execute
        'select count(*) from public.level_sense_assignments
         where level_number = $1 and placement_type = ''new'''
      into actual_count
      using item::integer;

      select new_sense_target
      into expected_count
      from public.levels
      where level_number = item::integer;

      insert into kuakua_verification_report
      values (
        70,
        'Band 4.0 import',
        'level ' || item || ' new sense assignments',
        case
          when actual_count = expected_count and actual_count > 0 then 'PASS'
          else 'FAIL'
        end,
        expected_count::text,
        actual_count::text,
        case
          when item::integer <= 5 and expected_count <> 45
            then 'Levels 1-5 must retain 45 reviewed new senses.'
          when item::integer >= 6 and expected_count not between 40 and 50
            then 'Levels 6-33 should use compact study-sized targets around 45.'
          else null
        end
      );
    end loop;

    insert into kuakua_verification_report
    select
      71,
      'Band 4.0 import',
      'first Band 4.5 level after compact Band 4',
      case when band_id = 2 then 'PASS' else 'FAIL' end,
      'Level 34 has band_id=2',
      'Level 34 band_id=' || coalesce(band_id::text, 'missing'),
      'Band 4 uses Levels 1-33 so a passed Band 4 exam should unlock Level 34.'
    from public.levels
    where level_number = 34;
  end if;

  -- Basic import integrity checks.
  if to_regclass('public.word_senses') is not null
     and to_regclass('public.words') is not null then
    select count(*)
    into actual_count
    from public.word_senses sense_row
    left join public.words word_row on word_row.id = sense_row.word_id
    where word_row.id is null;

    insert into kuakua_verification_report
    values (
      80,
      'integrity',
      'word senses without words',
      case when actual_count = 0 then 'PASS' else 'FAIL' end,
      '0',
      actual_count::text,
      null
    );
  end if;

  if to_regclass('public.question_options') is not null
     and to_regclass('public.questions') is not null then
    select count(*)
    into actual_count
    from (
      select option_row.question_id
      from public.question_options option_row
      group by option_row.question_id
      having count(*) <> 4
         or count(*) filter (where option_row.is_correct) <> 1
    ) invalid_question;

    insert into kuakua_verification_report
    values (
      81,
      'integrity',
      'choice questions with invalid option sets',
      case when actual_count = 0 then 'PASS' else 'FAIL' end,
      '0',
      actual_count::text,
      'Every imported choice question must have four options and exactly one correct option.'
    );
  end if;

  if to_regclass('public.examples') is not null
     and to_regclass('public.word_senses') is not null then
    select count(*)
    into actual_count
    from (
      select sense_row.id
      from public.word_senses sense_row
      join public.level_sense_assignments assignment
        on assignment.sense_id = sense_row.id
       and assignment.level_number between 1 and 5
       and assignment.placement_type = 'new'
      left join public.examples example_row
        on example_row.sense_id = sense_row.id
      group by sense_row.id
      having count(example_row.id) < 2
    ) incomplete_sense;

    insert into kuakua_verification_report
    values (
      82,
      'integrity',
      'levels 1-5 senses with fewer than two examples',
      case when actual_count = 0 then 'PASS' else 'FAIL' end,
      '0',
      actual_count::text,
      null
    );
  end if;
end;
$$;

-- Detailed report.
select
  category,
  check_name,
  status,
  expected,
  actual,
  details
from kuakua_verification_report
order by
  case status when 'FAIL' then 1 when 'WARN' then 2 else 3 end,
  sort_order,
  category,
  check_name;

-- One-line summary. A valid complete installation should return READY.
select
  case
    when count(*) filter (where status = 'FAIL') > 0 then 'NOT READY'
    when count(*) filter (where status = 'WARN') > 0 then 'PARTIAL'
    else 'READY'
  end as overall_status,
  count(*) filter (where status = 'PASS') as passed,
  count(*) filter (where status = 'WARN') as warnings,
  count(*) filter (where status = 'FAIL') as failures
from kuakua_verification_report;
