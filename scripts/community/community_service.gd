class_name CommunityService
extends Node
## Game-facing asynchronous contract. Every operation returns {ok, data, error}.
## Adapter sessions are memory-only. This node belongs to the application scene.
signal authentication_changed

var backend: Node
var store: PuzzleStore
var compatibility: String = ""

static func success(data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "data": data, "error": {}}

static func failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": {"code": code, "message": message}}

func configure(puzzle_store: PuzzleStore, adapter: Node) -> void:
	store = puzzle_store
	backend = adapter
	add_child(backend)
	backend.authentication_changed.connect(authentication_changed.emit)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/community_catalog.json"))
	compatibility = manifest.get("compatibility", "")

func is_signed_in() -> bool:
	return backend != null and backend.is_signed_in()

func browse_puzzles(filters: Dictionary = {}) -> Dictionary:
	return await backend.browse_puzzles(filters, compatibility)

func get_puzzle(puzzle_id: String, revision: int) -> Dictionary:
	return await backend.get_puzzle(puzzle_id, revision, compatibility)

func download_puzzle(puzzle_id: String, revision: int) -> Dictionary:
	var result := await get_puzzle(puzzle_id, revision)
	if not result.ok: return result
	var puzzle: Variant = result.data.get("puzzle")
	if not puzzle is Dictionary: return failure("invalid_response", "The service returned an invalid puzzle.")
	var installed := store.install_community(puzzle)
	if installed.is_empty(): return failure("installation_failed", store.last_error)
	return success({"puzzle": installed})

func publish_puzzle(puzzle: Dictionary) -> Dictionary:
	var errors := store.publication_errors(puzzle)
	if not errors.is_empty(): return failure("invalid_puzzle", "\n".join(errors))
	var content := store.playable_content(puzzle)
	content.status = "published"
	content.required_assets = store.required_assets(content)
	return await backend.publish_puzzle(content, compatibility)

func unpublish_puzzle(puzzle_id: String) -> Dictionary:
	return await backend.unpublish_puzzle(puzzle_id)

func get_my_puzzles(filters: Dictionary = {}) -> Dictionary:
	return await backend.get_my_puzzles(filters)

func sign_in(email: String) -> Dictionary:
	var result: Dictionary = await backend.sign_in(email.strip_edges())
	return success() if result.ok else failure(result.error.code, result.error.message)

func verify_sign_in(email: String, code: String) -> Dictionary:
	var result: Dictionary = await backend.verify_sign_in(email.strip_edges(), code.strip_edges())
	return success() if result.ok else failure(result.error.code, result.error.message)

func sign_out() -> Dictionary:
	var result: Dictionary = await backend.sign_out()
	return success() if result.ok else failure(result.error.code, result.error.message)
