\set ON_ERROR_STOP on

-- A speaking self-check may use the client sentinel when an older active
-- round snapshot lacks the displayed positive option. It must be accepted for
-- speaking questions without weakening UUID validation for other option types.

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000043',
  'speaking-self-check@example.com',
  '{"username":"speaking_self_check","nickname":"Speaking Check"}'::jsonb
);

insert into public.user_level_progress (
  user_id,
  level_number,
  is_unlocked,
  unlocked_at
)
values (
  '10000000-0000-0000-0000-000000000043',
  1,
  true,
  now()
)
on conflict (user_id, level_number) do update
set is_unlocked = true,
    unlocked_at = coalesce(public.user_level_progress.unlocked_at, now());

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000043',
  true
);

do $$
declare
  v_round_id uuid;
  v_position integer;
  v_question_id uuid;
  v_result jsonb;
begin
  v_round_id := (public.start_practice_round(1) ->> 'round_id')::uuid;

  select rq.position, rq.question_id
  into v_position, v_question_id
  from public.practice_round_questions rq
  where rq.round_id = v_round_id
    and rq.answer_form = 'option'
    and rq.correct_option_id is not null
    and rq.correct_option_id = any(rq.option_ids)
  order by rq.position
  limit 1;

  if v_question_id is null then
    raise exception 'Generated round has no usable option question';
  end if;

  update public.questions
  set question_type_key = 'speaking_repeat'
  where id = v_question_id;

  update public.practice_round_questions
  set question_type_key = 'speaking_repeat'
  where round_id = v_round_id
    and position = v_position;

  v_result := public.save_practice_answer(
    v_round_id,
    v_position,
    '__self_check_known__',
    1000
  );

  if coalesce((v_result ->> 'is_correct')::boolean, false) is not true
     or v_result ->> 'answer_outcome' <> 'full_correct' then
    raise exception 'Speaking self-check sentinel was not accepted: %', v_result;
  end if;

  if not exists (
    select 1
    from public.practice_round_questions rq
    where rq.round_id = v_round_id
      and rq.position = v_position
      and rq.answer_given = '__self_check_known__'
      and rq.is_correct
      and rq.answered_at is not null
  ) then
    raise exception 'Speaking self-check result was not persisted';
  end if;
end;
$$;

rollback;
