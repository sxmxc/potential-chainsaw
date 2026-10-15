-- Only Edge Function code can write. Public/owner reads additionally use RLS.
create table public.community_puzzles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  source_id text not null check (source_id ~ '^[A-Za-z0-9_-]{1,100}$'),
  title text not null check (length(title) between 1 and 80),
  description text not null check (length(description) <= 2000),
  difficulty text not null check (length(difficulty) <= 80),
  revision integer not null check (revision between 1 and 100000),
  schema_version integer not null check (schema_version in (1,2)),
  compatibility text not null check (compatibility ~ '^[a-f0-9]{64}$'),
  published boolean not null default true,
  created_at timestamptz not null default now(),
  published_at timestamptz not null default now(),
  unique (owner_id, source_id)
);
create table public.community_revisions (
  puzzle_id uuid not null references public.community_puzzles(id) on delete cascade,
  revision integer not null check (revision between 1 and 100000),
  definition jsonb not null check (jsonb_typeof(definition) = 'object' and octet_length(definition::text) <= 5000000),
  compatibility text not null,
  created_at timestamptz not null default now(),
  primary key (puzzle_id, revision)
);
create index community_browse on public.community_puzzles (compatibility, published_at desc, id) where published;
create index community_owner on public.community_puzzles (owner_id, published_at desc, id);
alter table public.community_puzzles enable row level security;
alter table public.community_revisions enable row level security;
revoke all on public.community_puzzles, public.community_revisions from public, anon, authenticated;
grant select on public.community_puzzles, public.community_revisions to anon, authenticated;
grant all on public.community_puzzles, public.community_revisions to service_role;
create policy community_public_read on public.community_puzzles for select to anon, authenticated using (published);
create policy community_owner_read on public.community_puzzles for select to authenticated using (owner_id = (select auth.uid()));
create policy community_revision_read on public.community_revisions for select to anon, authenticated
  using (exists (select 1 from public.community_puzzles p where p.id = puzzle_id and p.published));
create policy community_revision_owner_read on public.community_revisions for select to authenticated
  using (exists (select 1 from public.community_puzzles p where p.id = puzzle_id and p.owner_id = (select auth.uid())));

-- Atomic publication, immutable revisions and bounded per-account storage.
-- Invoker, service-role-only: owner identity is supplied by the verified Edge API.
create function public.community_publish(p_owner uuid, p_definition jsonb, p_compatibility text)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  existing public.community_puzzles;
  puzzle_uuid uuid;
  next_revision integer := (p_definition->>'revision')::integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text, 0));
  select * into existing from public.community_puzzles
    where owner_id = p_owner and source_id = p_definition->>'id' for update;
  if found then
    puzzle_uuid := existing.id;
    if exists (select 1 from public.community_revisions where puzzle_id = puzzle_uuid and revision = next_revision) then
      if not exists (select 1 from public.community_revisions where puzzle_id = puzzle_uuid and revision = next_revision
        and definition = p_definition and compatibility = p_compatibility) then
        raise exception 'revision_conflict';
      end if;
      if next_revision != existing.revision then raise exception 'revision_conflict'; end if;
      update public.community_puzzles set published = true where id = puzzle_uuid;
      return puzzle_uuid;
    end if;
    if next_revision <= existing.revision then raise exception 'revision_conflict'; end if;
    if (select count(*) from public.community_revisions where puzzle_id = puzzle_uuid) >= 100 then raise exception 'publication_limit'; end if;
    if existing.published_at > now() - interval '30 seconds' then raise exception 'publication_rate'; end if;
    update public.community_puzzles set title = p_definition->>'name', description = coalesce(p_definition->>'description',''),
      difficulty = coalesce(p_definition->>'difficulty','Workshop'), revision = next_revision,
      schema_version = (p_definition->>'version')::integer, compatibility = p_compatibility,
      published = true, published_at = now() where id = puzzle_uuid;
  else
    if (select count(*) from public.community_puzzles where owner_id = p_owner) >= 50 then raise exception 'publication_limit'; end if;
    if exists (select 1 from public.community_puzzles where owner_id = p_owner and published_at > now() - interval '30 seconds') then raise exception 'publication_rate'; end if;
    insert into public.community_puzzles(owner_id, source_id, title, description, difficulty, revision, schema_version, compatibility)
      values(p_owner, p_definition->>'id', p_definition->>'name', coalesce(p_definition->>'description',''),
        coalesce(p_definition->>'difficulty','Workshop'), next_revision, (p_definition->>'version')::integer, p_compatibility)
      returning id into puzzle_uuid;
  end if;
  insert into public.community_revisions(puzzle_id, revision, definition, compatibility)
    values(puzzle_uuid, next_revision, p_definition, p_compatibility);
  return puzzle_uuid;
end;
$$;
revoke all on function public.community_publish(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.community_publish(uuid, jsonb, text) to service_role;
