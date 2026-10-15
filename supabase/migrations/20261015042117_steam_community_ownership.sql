-- Existing UUID owners and records remain unchanged. Steam has no auth.users row.
alter table public.community_puzzles alter column owner_id drop not null;
alter table public.community_puzzles add column steam_owner_id text;
alter table public.community_puzzles add constraint community_owner_exactly_one
  check ((owner_id is null) <> (steam_owner_id is null));
alter table public.community_puzzles add constraint community_steam_id
  check (steam_owner_id is null or steam_owner_id ~ '^[1-9][0-9]{16,19}$');
create unique index community_steam_source on public.community_puzzles (steam_owner_id, source_id) where steam_owner_id is not null;
create index community_steam_owner on public.community_puzzles (steam_owner_id, published_at desc, id) where steam_owner_id is not null;
-- Owner UUID RLS stays intact. Steam private reads require the verified Edge API.
-- Direct anon/authenticated writes remain denied; service-role-only RPC.
drop function public.community_publish(uuid, jsonb, text);
create function public.community_publish(p_owner uuid, p_definition jsonb, p_compatibility text, p_steam_owner text default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  existing public.community_puzzles;
  puzzle_uuid uuid;
  next_revision integer := (p_definition->>'revision')::integer;
begin
  if (p_owner is null) = (p_steam_owner is null) or
    (p_steam_owner is not null and p_steam_owner !~ '^[1-9][0-9]{16,19}$') then
    raise exception 'invalid_owner';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_owner::text, p_steam_owner), 0));
  select * into existing from public.community_puzzles
    where owner_id is not distinct from p_owner and steam_owner_id is not distinct from p_steam_owner and source_id = p_definition->>'id' for update;
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
    if (select count(*) from public.community_puzzles where owner_id is not distinct from p_owner and steam_owner_id is not distinct from p_steam_owner) >= 50 then raise exception 'publication_limit'; end if;
    if exists (select 1 from public.community_puzzles where owner_id is not distinct from p_owner and steam_owner_id is not distinct from p_steam_owner and published_at > now() - interval '30 seconds') then raise exception 'publication_rate'; end if;
    insert into public.community_puzzles(owner_id, steam_owner_id, source_id, title, description, difficulty, revision, schema_version, compatibility)
      values(p_owner, p_steam_owner, p_definition->>'id', p_definition->>'name', coalesce(p_definition->>'description',''),
        coalesce(p_definition->>'difficulty','Workshop'), next_revision, (p_definition->>'version')::integer, p_compatibility)
      returning id into puzzle_uuid;
  end if;
  insert into public.community_revisions(puzzle_id, revision, definition, compatibility)
    values(puzzle_uuid, next_revision, p_definition, p_compatibility);
  return puzzle_uuid;
end;
$$;
revoke all on function public.community_publish(uuid, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.community_publish(uuid, jsonb, text, text) to service_role;
