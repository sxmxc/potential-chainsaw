-- Run only against the isolated local stack: supabase test db.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);
insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000002');
insert into public.community_puzzles(id,owner_id,source_id,title,description,difficulty,revision,schema_version,compatibility,published)
  values
  ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','published','Published','','Workshop',1,2,repeat('a',64),true),
  ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','hidden','Hidden','','Workshop',1,2,repeat('a',64),false);
insert into public.community_revisions(puzzle_id,revision,definition,compatibility)
  select id,1,'{}'::jsonb,repeat('a',64) from public.community_puzzles;
set local role anon;
select is((select count(*)::integer from public.community_puzzles),1,'Public sees published puzzles only');
select is((select count(*)::integer from public.community_revisions),1,'Public sees published revisions only');
select throws_ok($$update public.community_puzzles set published=false$$,'42501',null,'Public cannot write');
select throws_ok($$select public.community_publish('00000000-0000-0000-0000-000000000001','{}',repeat('a',64))$$,'42501',null,'Public cannot bypass server validation');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is((select count(*)::integer from public.community_puzzles),2,'Owner sees their unpublished puzzle');
select is((select count(*)::integer from public.community_revisions),2,'Owner sees their unpublished revision');
select throws_ok($$update public.community_puzzles set published=true$$,'42501',null,'Owner writes still require the validating API');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is((select count(*)::integer from public.community_puzzles),1,'Other user cannot see unpublished puzzles');
select is((select count(*)::integer from public.community_revisions),1,'Other user cannot see unpublished revisions');
select throws_ok($$select public.community_publish('00000000-0000-0000-0000-000000000001','{}',repeat('a',64))$$,'42501',null,'Authenticated user cannot impersonate a creator');
reset role;
select * from finish();
rollback;
