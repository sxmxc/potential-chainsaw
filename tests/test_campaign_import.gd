extends "res://tests/support/game_test.gd"

func write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func write_bundle(files: Dictionary) -> String:
	var path = test_directory.path_join("bundle.zip")
	var zip = ZIPPacker.new()
	assert_eq(zip.open(path), OK)
	for filename in files:
		zip.start_file(filename)
		zip.write_file((files[filename] if files[filename] is String else JSON.stringify(files[filename])).to_utf8_buffer())
		zip.close_file()
	zip.close()
	return path

func import_bundle(bundle: String, destination: String) -> int:
	# Exercise the actual Python importer; assertions and fixtures belong to GUT.
	var code = "import sys; sys.path.insert(0, sys.argv[1]); from import_campaign import import_bundle; import_bundle(sys.argv[2], sys.argv[3])"
	var output: Array = []
	return OS.execute("python", ["-B", "-c", code, ProjectSettings.globalize_path("res://tools"), bundle, destination], output, true)

func test_existing_ids_paths_and_chapters_survive_round_trip() -> void:
	var destination = test_directory.path_join("resources/campaign")
	var originals: Dictionary = {}
	for filename in DirAccess.get_files_at("res://resources/campaign"):
		if not filename.ends_with(".json"): continue
		var data = read_json("res://resources/campaign/" + filename)
		originals[filename] = data
		write_json(destination.path_join(filename), data)
	var manifest = read_json("res://resources/campaign_chapters.json")
	var manifest_path = test_directory.path_join("resources/campaign_chapters.json")
	write_json(manifest_path, manifest)
	var store := PuzzleStore.new(PieceCatalog.new())
	var bundle := test_directory.path_join("export.zip")
	assert_eq(store.export_campaign(bundle), originals.size())
	assert_eq(import_bundle(bundle, destination), 0)
	assert_eq(DirAccess.get_files_at(destination).size(), originals.size())
	for filename in originals: assert_eq(read_json(destination.path_join(filename)), originals[filename])
	assert_eq(read_json(manifest_path), manifest)

func test_future_chapters_preserve_existing_membership() -> void:
	var original = read_json("res://resources/campaign_chapters.json")
	var manifest_path = test_directory.path_join("resources/campaign_chapters.json")
	write_json(manifest_path, original)
	var incoming = {"version": 1, "chapters": [
		{"id":"introduction","name":"Introduction","optional":true,"introduction":true,"levels":["campaign-01"]},
		{"id":"chapter-2","name":"Chapter 2","order":2,"prerequisites":[],"levels":[]}
	]}
	var bundle = write_bundle({"campaign_chapters.json": incoming})
	assert_eq(import_bundle(bundle, test_directory.path_join("resources/campaign")), 0)
	var chapters: Dictionary = {}
	for chapter in read_json(manifest_path).chapters: chapters[chapter.id] = chapter
	assert_eq(chapters.introduction.levels, original.chapters[0].levels)
	assert_has(chapters, "chapter-1")
	assert_has(chapters, "chapter-2")

func test_invalid_bundle_leaves_destination_untouched() -> void:
	var filename = DirAccess.get_files_at("res://resources/campaign")[0]
	var good = read_json("res://resources/campaign/" + filename)
	var bundle = write_bundle({"campaign/good.json":good,"campaign/bad.json":{"id":"../escape"}})
	var destination = test_directory.path_join("resources/campaign")
	assert_ne(import_bundle(bundle, destination), 0)
	assert_false(DirAccess.dir_exists_absolute(destination))

func test_version_two_bundle_carries_fixed_native_environment() -> void:
	var data := read_json("res://resources/campaign/" + DirAccess.get_files_at("res://resources/campaign")[0])
	data.version = 2
	data.environment_instances = [{"uid": "env-1", "asset": "column", "position": [5, 0, 0], "rotation": 0}]
	var store := PuzzleStore.new(PieceCatalog.new())
	var snapshot_path := store.published_directory.path_join("frozen-test.tscn")
	data.environment_snapshot = snapshot_path
	var native := "[gd_scene format=3]\n\n[node name=\"Environment\" type=\"Node3D\"]\n"
	var snapshot := FileAccess.open(snapshot_path, FileAccess.WRITE)
	snapshot.store_string(native)
	snapshot.close()
	assert_true(store.write(store.published_directory.path_join(data.id + ".json"), data))
	var saved := read_json(store.published_directory.path_join(data.id + ".json"))
	var bundle := test_directory.path_join("export.zip")
	assert_eq(store.export_campaign(bundle), store.list_puzzles().size())
	assert_eq(read_json(store.published_directory.path_join(data.id + ".json")), saved, "Export leaves published source data intact")
	var destination := test_directory.path_join("resources/campaign")
	assert_eq(import_bundle(bundle, destination), 0)
	saved.environment_snapshot = "res://resources/campaign/environments/frozen-test.tscn"
	assert_eq(read_json(destination.path_join(data.id + ".json")), saved)
	assert_eq(FileAccess.get_file_as_string(destination.path_join("environments/frozen-test.tscn")), native)

func test_export_reports_missing_snapshot_without_overwriting_destination() -> void:
	var store := PuzzleStore.new(PieceCatalog.new())
	var data := store.list_puzzles()[0]
	data.environment_snapshot = store.published_directory.path_join("missing.tscn")
	assert_true(store.write(store.published_directory.path_join(data.id + ".json"), data))
	var bundle := write_bundle({"keep.txt": "Existing export"})
	var original := FileAccess.get_file_as_bytes(bundle)
	assert_eq(store.export_campaign(bundle), -1)
	assert_eq(store.last_error, "Published environment is missing")
	assert_eq(FileAccess.get_file_as_bytes(bundle), original)

func test_export_skips_untested_content_and_reports_open_failure() -> void:
	var store := PuzzleStore.new(PieceCatalog.new())
	var levels := store.list_puzzles()
	var untested := levels[0].duplicate(true)
	untested.validation.physics_success = false
	assert_true(store.write(store.published_directory.path_join(untested.id + ".json"), untested))
	var bundle := test_directory.path_join("export.zip")
	assert_eq(store.export_campaign(bundle), levels.size() - 1)
	var reader := ZIPReader.new()
	assert_eq(reader.open(bundle), OK)
	assert_false(reader.file_exists("campaign/" + untested.id + ".json"))
	assert_true(reader.file_exists("campaign_chapters.json"))
	reader.close()
	assert_eq(store.export_campaign(test_directory.path_join("missing/export.zip")), -1)
	assert_eq(store.last_error, "Could not open export file")
