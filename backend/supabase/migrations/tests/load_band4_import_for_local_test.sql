\set ON_ERROR_STOP on

-- Local/test helper. Run after applying migrations and copying the Band 4
-- package to /imports inside the Postgres container.

\copy public.content_sources(id,source_key,name,source_url,license_name,copyright_status,attribution_text,notes,human_review) from '/imports/01_content_sources.csv' with (format csv, header true, encoding 'UTF8')

\i /imports/02_topic_clusters_upsert.sql
\i /imports/03_band_levels_upsert.sql

\copy public.words(id,headword,display_spelling,frequency_rank,human_review) from '/imports/04_words.csv' with (format csv, header true, encoding 'UTF8')
\copy public.word_senses(id,word_id,part_of_speech,sense_number,definition_en,definition_zh,vocabulary_role,difficulty_band,cefr_level,register,is_primary,source_id,human_review,review_status) from '/imports/05_word_senses.csv' with (format csv, header true, encoding 'UTF8')
\copy public.word_forms(id,word_id,sense_id,form_type,form_text,source_id,human_review) from '/imports/06_word_forms.csv' with (format csv, header true, encoding 'UTF8')
\copy public.pronunciations(id,word_id,sense_id,ipa_us,audio_path,source_id,human_review) from '/imports/07_pronunciations.csv' with (format csv, header true, encoding 'UTF8')
\copy public.level_sense_assignments(level_number,sense_id,placement_type,order_in_level,vocabulary_role,is_required,human_review) from '/imports/08_level_sense_assignments.csv' with (format csv, header true, encoding 'UTF8')
\copy public.usage_evidence(id,sense_id,source_id,quoted_text,matched_span,source_locator,usage_analysis,paper_types,copyright_status,human_review) from '/imports/09_usage_evidence.csv' with (format csv, header true, encoding 'UTF8')
\copy public.examples(id,sense_id,sentence_en,translation_zh,target_span,origin,difficulty_band,source_id,review_status,human_review,audio_path,sort_order) from '/imports/10_examples.csv' with (format csv, header true, encoding 'UTF8')
\copy public.collocations(id,sense_id,collocation,translation_zh,difficulty_band,source_id,human_review,review_status) from '/imports/11_collocations.csv' with (format csv, header true, encoding 'UTF8')
\copy public.questions(id,sense_id,question_type_id,type_code,category,answer_form,word_id,example_id,stem,correct_answer,difficulty,is_active,generation_version,human_review,prompt_hint,translation_zh,expected_time_ms,question_type_key,is_context_hint,context_for_multiple_meaning) from '/imports/12_questions.csv' with (format csv, header true, encoding 'UTF8')
\copy public.question_options(id,question_id,option_text,target_sense_id,is_correct,sort_order,human_review) from '/imports/13_question_options.csv' with (format csv, header true, encoding 'UTF8')
