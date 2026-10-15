-- Format 3 adds bounded, declarative guidance; formats 1 and 2 remain supported.
alter table public.community_puzzles
  drop constraint community_puzzles_schema_version_check;
alter table public.community_puzzles
  add constraint community_puzzles_schema_version_check
  check (schema_version in (1, 2, 3)) not valid;
alter table public.community_puzzles
  validate constraint community_puzzles_schema_version_check;
