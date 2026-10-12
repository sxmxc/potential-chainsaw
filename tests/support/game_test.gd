extends GutTest

# Only persistence tests need this fixture. GUT owns node/input-sender cleanup.
var previous_test_directory: String
var had_test_directory: bool
var test_directory: String

func before_each() -> void:
	had_test_directory = OS.has_environment("MARBLE_ENGINEER_TEST_DATA")
	previous_test_directory = OS.get_environment("MARBLE_ENGINEER_TEST_DATA")
	test_directory = OS.get_user_data_dir().path_join("gut-tests").path_join(Crypto.new().generate_random_bytes(12).hex_encode())
	assert_eq(DirAccess.make_dir_recursive_absolute(test_directory), OK, "Create isolated persistence fixture")
	OS.set_environment("MARBLE_ENGINEER_TEST_DATA", test_directory)

func after_each() -> void:
	if had_test_directory:
		OS.set_environment("MARBLE_ENGINEER_TEST_DATA", previous_test_directory)
	else:
		OS.unset_environment("MARBLE_ENGINEER_TEST_DATA")
	remove_test_directory(test_directory)

func remove_test_directory(path: String) -> void:
	var resolved := ProjectSettings.globalize_path(path).simplify_path()
	if test_directory.is_empty() or (resolved != test_directory and not resolved.begins_with(test_directory + "/")):
		fail_test("Refusing cleanup outside the fixture directory")
		return
	var directory := DirAccess.open(resolved)
	if directory == null:
		fail_test("Could not open fixture directory for cleanup")
		return
	# Never follow a link out of the fixture tree.
	for filename in directory.get_files():
		assert_eq(DirAccess.remove_absolute(resolved.path_join(filename)), OK, "Remove fixture file")
	for child in directory.get_directories():
		var child_path := resolved.path_join(child)
		if directory.is_link(child):
			assert_eq(DirAccess.remove_absolute(child_path), OK, "Remove fixture link")
		else:
			remove_test_directory(child_path)
	assert_eq(DirAccess.remove_absolute(resolved), OK, "Remove fixture directory")
