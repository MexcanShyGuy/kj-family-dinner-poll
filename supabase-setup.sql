-- KJ's separate family dinner poll. Safe to run once in a NEW Supabase project.
-- Keep the organizer allowlist private; do not expose it in the public website repo.

create table if not exists public.kj_family_dinner_responses (
  voter_id uuid primary key,
  poll_id text not null default 'kj-family-dinner-2026',
  respondent_name text not null,
  phone_number text not null default '',
  meal_choices text[] not null,
  allergy_details text not null default '',
  substitution_request text not null default '',
  submitted_at timestamptz not null default now(),
  constraint kj_family_dinner_poll_id check (poll_id = 'kj-family-dinner-2026'),
  constraint kj_family_dinner_name_length check (char_length(btrim(respondent_name)) between 1 and 80),
  constraint kj_family_dinner_phone_length check (char_length(phone_number) <= 40),
  constraint kj_family_dinner_choice_count check (cardinality(meal_choices) between 1 and 3),
  constraint kj_family_dinner_allowed_choices check (
    meal_choices <@ array['Seared Atlantic salmon', 'Steak frites', 'Cacio e pepe']::text[]
  ),
  constraint kj_family_dinner_notes_length check (
    char_length(allergy_details) <= 500 and char_length(substitution_request) <= 500
  )
);

create index if not exists kj_family_dinner_responses_submitted_idx
  on public.kj_family_dinner_responses (submitted_at desc);

alter table public.kj_family_dinner_responses enable row level security;
revoke all privileges on table public.kj_family_dinner_responses from public, anon, authenticated;

-- Only emails explicitly added by the project owner can use the organizer view.
create table if not exists public.kj_family_dinner_organizers (
  email text primary key check (email = lower(email)),
  added_at timestamptz not null default now()
);
alter table public.kj_family_dinner_organizers enable row level security;
revoke all privileges on table public.kj_family_dinner_organizers from public, anon, authenticated;

create or replace function public.is_kj_family_dinner_organizer()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.kj_family_dinner_organizers o
    where o.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all privileges on function public.is_kj_family_dinner_organizer() from public, anon, authenticated;
grant execute on function public.is_kj_family_dinner_organizer() to authenticated;

-- Anonymous visitors can read aggregate counts only, never individual rows.
create or replace function public.get_kj_family_dinner_totals()
returns table (meal_choice text, vote_count bigint)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select choices.meal_choice, count(*)::bigint
  from public.kj_family_dinner_responses r
  cross join lateral unnest(r.meal_choices) as choices(meal_choice)
  where r.poll_id = 'kj-family-dinner-2026'
  group by choices.meal_choice;
$$;
revoke all privileges on function public.get_kj_family_dinner_totals() from public, anon, authenticated;
grant execute on function public.get_kj_family_dinner_totals() to anon, authenticated;

-- Anonymous voting writes only through this bounded RPC; it cannot SELECT rows.
create or replace function public.submit_kj_family_dinner_vote(
  p_voter_id uuid,
  p_respondent_name text,
  p_phone_number text,
  p_meal_choices text[],
  p_allergy_details text,
  p_substitution_request text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_voter_id is null then raise exception 'A voter id is required'; end if;
  if char_length(btrim(coalesce(p_respondent_name, ''))) not between 1 and 80 then
    raise exception 'A name is required (up to 80 characters)';
  end if;
  if char_length(coalesce(p_phone_number, '')) > 40 or
     char_length(coalesce(p_allergy_details, '')) > 500 or
     char_length(coalesce(p_substitution_request, '')) > 500 then
    raise exception 'A response field is too long';
  end if;
  if coalesce(cardinality(p_meal_choices), 0) not between 1 and 3 or
     not (coalesce(p_meal_choices, array[]::text[]) <@
       array['Seared Atlantic salmon', 'Steak frites', 'Cacio e pepe']::text[]) then
    raise exception 'Choose one or more valid meals';
  end if;

  insert into public.kj_family_dinner_responses (
    voter_id, poll_id, respondent_name, phone_number, meal_choices,
    allergy_details, substitution_request, submitted_at
  ) values (
    p_voter_id, 'kj-family-dinner-2026', btrim(p_respondent_name),
    coalesce(p_phone_number, ''), p_meal_choices,
    coalesce(p_allergy_details, ''), coalesce(p_substitution_request, ''), now()
  )
  on conflict (voter_id) do update set
    respondent_name = excluded.respondent_name,
    phone_number = excluded.phone_number,
    meal_choices = excluded.meal_choices,
    allergy_details = excluded.allergy_details,
    substitution_request = excluded.substitution_request,
    submitted_at = now();
end;
$$;
revoke all privileges on function public.submit_kj_family_dinner_vote(uuid, text, text, text[], text, text)
  from public, anon, authenticated;
grant execute on function public.submit_kj_family_dinner_vote(uuid, text, text, text[], text, text)
  to anon, authenticated;

-- Authenticated, allowlisted organizers only; the browser never gets table access.
create or replace function public.list_kj_family_dinner_responses()
returns table (
  respondent_name text,
  phone_number text,
  meal_choices text[],
  allergy_details text,
  substitution_request text,
  submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or not public.is_kj_family_dinner_organizer() then
    raise exception 'Organizer access required' using errcode = '42501';
  end if;
  return query
    select r.respondent_name, r.phone_number, r.meal_choices,
           r.allergy_details, r.substitution_request, r.submitted_at
    from public.kj_family_dinner_responses r
    where r.poll_id = 'kj-family-dinner-2026'
    order by r.submitted_at desc;
end;
$$;
revoke all privileges on function public.list_kj_family_dinner_responses() from public, anon, authenticated;
grant execute on function public.list_kj_family_dinner_responses() to authenticated;
