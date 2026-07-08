-- Adds a unique public username used during email/password registration.
-- Run this after 202606210001_create_user_foundation.sql.

begin;

alter table public.profiles
  add column username text;

update public.profiles
set username = lower(public_user_code)
where username is null;

alter table public.profiles
  alter column username set not null;

alter table public.profiles
  add constraint profiles_username_format
  check (username ~ '^[a-z][a-z0-9_]{2,23}$');

create unique index profiles_username_lower_unique
  on public.profiles (lower(username));

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_code text;
  requested_username text;
  requested_nickname text;
  requested_timezone text;
begin
  generated_code :=
    'KQ' || nextval('public.public_user_code_seq'::regclass)::text;

  requested_username :=
    lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  if requested_username !~ '^[a-z][a-z0-9_]{2,23}$' then
    raise exception 'Invalid username';
  end if;

  requested_nickname :=
    btrim(coalesce(new.raw_user_meta_data ->> 'nickname', requested_username));
  if char_length(requested_nickname) not between 1 and 36
     or requested_nickname ~ '[@<>/]' then
    requested_nickname := requested_username;
  end if;

  requested_timezone :=
    btrim(coalesce(new.raw_user_meta_data ->> 'timezone', ''));
  if char_length(requested_timezone) not between 1 and 100 then
    requested_timezone := 'UTC';
  end if;

  insert into public.profiles (
    id,
    public_user_code,
    username,
    nickname
  )
  values (
    new.id,
    generated_code,
    requested_username,
    requested_nickname
  );

  insert into public.user_settings (
    user_id,
    reminder_timezone
  )
  values (
    new.id,
    requested_timezone
  );

  insert into public.user_consents (
    user_id,
    document_type,
    document_version
  )
  values
    (
      new.id,
      'terms',
      coalesce(new.raw_user_meta_data ->> 'terms_version', '2026-06-01')
    ),
    (
      new.id,
      'privacy',
      coalesce(new.raw_user_meta_data ->> 'privacy_version', '2026-06-01')
    );

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public;

comment on column public.profiles.username is
  'Unique case-insensitive public username. Authentication still uses email/password.';

commit;
