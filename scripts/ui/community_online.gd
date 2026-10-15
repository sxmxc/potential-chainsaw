extends VBoxContainer

var service: CommunityService
var session: ConstructionSession
var browser: Window
var publications: Array[Dictionary] = []
var publishing: Dictionary = {}
var offset: int = 0
var next_offset: int = -1
var generation: int = 0
var busy: bool = false

func configure(value: CommunityService, puzzle_session: ConstructionSession, window: Window) -> void:
	service = value
	session = puzzle_session
	browser = window
	%Refresh.pressed.connect(func(): offset = 0; refresh())
	%Search.text_submitted.connect(func(_text): offset = 0; refresh())
	%Search.text_changed.connect(func(_text): %SearchDelay.start())
	%SearchDelay.timeout.connect(func():
		if visible and browser.visible: offset = 0; refresh())
	%Mine.toggled.connect(func(_value): offset = 0; refresh())
	%NextPage.pressed.connect(func(): offset = next_offset; refresh())
	%PreviousPage.pressed.connect(func(): offset = maxi(0, offset - 20); refresh())
	%OnlineLevels.item_selected.connect(select_puzzle)
	%Download.pressed.connect(download)
	%OnlineLevels.item_activated.connect(func(_index): if not busy: download())
	%ShareToggle.pressed.connect(func(): %Shared.visible = not %Shared.visible; browser.fit_contents.call_deferred())
	%Unpublish.pressed.connect(unpublish)
	%CopyShare.pressed.connect(func():
		if not %ShareCode.text.is_empty(): DisplayServer.clipboard_set(%ShareCode.text); %Feedback.text = "Share code copied.")
	%ShareCode.text_changed.connect(func(text): %CopyShare.disabled = text.is_empty())
	%OpenShare.pressed.connect(open_share)
	%Account.pressed.connect(func(): %SignIn.visible = not %SignIn.visible)
	%SignInButton.pressed.connect(sign_in)
	%Password.text_submitted.connect(func(_text): if not busy: sign_in())
	%SignOut.pressed.connect(sign_out)
	%PublishOnline.pressed.connect(publish)
	service.authentication_changed.connect(refresh_account)
	browser.dismissing.connect(func(): generation += 1; %SearchDelay.stop(); %Password.clear())
	browser.visibility_changed.connect(func():
		if not browser.visible:
			generation += 1
			%SearchDelay.stop()
			%Password.clear())
	visibility_changed.connect(func():
		generation += 1
		if not visible: %SearchDelay.stop()
		if visible: refresh_account())
	refresh_account()

func open(puzzle: Dictionary = {}) -> void:
	publishing = puzzle.duplicate(true)
	%PublishOnline.visible = not publishing.is_empty()
	%PublishOnline.text = "Publish “%s” online" % publishing.get("name", "Puzzle")
	%Mine.set_pressed_no_signal(false)
	offset = 0
	show()
	refresh()

func refresh_account() -> void:
	%Account.visible = not service.uses_automatic_auth()
	if service.uses_automatic_auth():
		%SignIn.hide()
		%Password.clear()
		return
	%Account.text = "Account" if service.is_signed_in() else "Sign in"
	%SignOut.visible = service.is_signed_in()
	%SignInButton.visible = not service.is_signed_in()
	%Email.visible = not service.is_signed_in()
	%Password.visible = not service.is_signed_in()
	%SessionNote.text = "Signed in for this session." if service.is_signed_in() else "Sign in with your email and password."

func begin() -> int:
	busy = true
	generation += 1
	%Feedback.text = "Loading…"
	for button in [%Refresh, %Download, %Unpublish, %OpenShare, %SignInButton, %SignOut, %PublishOnline, %PreviousPage, %NextPage]: button.disabled = true
	return generation

func finish(ticket: int, result: Dictionary, message: String = "") -> bool:
	if ticket != generation or not visible or not browser.visible: return false
	busy = false
	for button in [%Refresh, %OpenShare, %SignInButton, %SignOut, %PublishOnline]: button.disabled = false
	%PreviousPage.disabled = offset == 0
	%NextPage.disabled = next_offset < 0
	select_puzzle(-1)
	%Feedback.text = message if result.ok else result.error.message
	if not result.ok and result.error.code == "sign_in_required" and not service.uses_automatic_auth(): %SignIn.show()
	return true

func refresh() -> void:
	%SearchDelay.stop()
	var ticket := begin()
	var filters := {"search": %Search.text, "offset": offset}
	var result := await service.get_my_puzzles(filters) if %Mine.button_pressed else await service.browse_puzzles(filters)
	if not finish(ticket, result): return
	publications.clear()
	%OnlineLevels.clear()
	next_offset = -1
	%NextPage.disabled = true
	select_puzzle(-1)
	if not result.ok: return
	var items: Variant = result.data.get("puzzles")
	if not items is Array:
		%Feedback.text = "The service returned an invalid puzzle list."
		return
	for item in items:
		if not item is Dictionary or not item.get("id") is String or not item.get("title") is String or not item.get("description") is String or not (item.get("revision") is float or item.get("revision") is int):
			%Feedback.text = "The service returned an invalid puzzle list."
			publications.clear()
			%OnlineLevels.clear()
			select_puzzle(-1)
			return
		publications.append(item)
		%OnlineLevels.add_item(item.title)
	var next: Variant = result.data.get("next_offset")
	if next is int or next is float: next_offset = int(next)
	%NextPage.disabled = next_offset < 0
	%PreviousPage.disabled = offset == 0
	%Feedback.text = "No puzzles found." if publications.is_empty() else ""
	if not publications.is_empty(): %OnlineLevels.select(0); select_puzzle(0)

func selected_puzzle() -> Dictionary:
	var selected: PackedInt32Array = %OnlineLevels.get_selected_items()
	return publications[selected[0]] if not selected.is_empty() and selected[0] < publications.size() else {}

func select_puzzle(_index: int) -> void:
	var item := selected_puzzle()
	%OnlineTitle.text = item.get("title", "Discover a new machine")
	var installed := installed_puzzle(item)
	var creator: String = str(item.get("creator", installed.get("creator", ""))).strip_edges()
	%Creator.text = "By " + creator if not creator.is_empty() else ""
	%Creator.visible = not creator.is_empty()
	%Installed.text = ("Installed · " if not installed.is_empty() else "") + str(item.get("difficulty", "")) + (" · Unpublished" if not item.get("published", true) else "")
	%Download.text = "Play puzzle" if not installed.is_empty() else "Download and play"
	%PageNumber.text = "Page %d" % (offset / 20 + 1)
	%OnlineDetails.text = "Choose a creation to see its goal." if item.is_empty() else item.description
	%Download.disabled = busy or item.is_empty() or (installed.is_empty() and not item.get("published", true))
	if not item.is_empty(): %ShareCode.text = str(item.id) + "@" + str(int(item.revision))
	%CopyShare.disabled = %ShareCode.text.is_empty()
	%Unpublish.visible = %Mine.button_pressed
	%Unpublish.disabled = busy or item.is_empty() or not item.get("published", true)

func download() -> void:
	var item := selected_puzzle()
	if busy or item.is_empty(): return
	var installed := installed_puzzle(item)
	if not installed.is_empty(): browser.dismiss(func(): session.player(installed))
	else: download_revision(item.id, int(item.revision))

func download_revision(id: String, revision: int) -> void:
	var ticket := begin()
	var result := await service.download_puzzle(id, revision)
	if not finish(ticket, result, "Puzzle installed."): return
	if result.ok: browser.dismiss(func(): session.player(result.data.puzzle))

func open_share() -> void:
	var parts: PackedStringArray = %ShareCode.text.strip_edges().split("@")
	if parts.size() != 2 or not parts[1].is_valid_int(): %Feedback.text = "Enter a share code in the form puzzle-id@revision."; return
	download_revision(parts[0], int(parts[1]))

func sign_in() -> void:
	var ticket := begin()
	var password: String = %Password.text
	%Password.clear()
	var result := await service.sign_in(%Email.text, password)
	if finish(ticket, result, "Signed in.") and result.ok:
		%SignIn.hide()
		if %Mine.button_pressed: refresh()

func sign_out() -> void:
	var ticket := begin()
	var result := await service.sign_out()
	if finish(ticket, result, "Signed out."):
		%Mine.set_pressed_no_signal(false)
		refresh()

func publish() -> void:
	var ticket := begin()
	var result := await service.publish_puzzle(publishing)
	if finish(ticket, result, "Published online.") and result.ok:
		%Shared.show()
		%ShareCode.text = result.data.get("share_code", "")
		%CopyShare.disabled = %ShareCode.text.is_empty()
		%Feedback.text = "Published online. Copy the share code to share this revision."

func unpublish() -> void:
	var item := selected_puzzle()
	if item.is_empty(): return
	var ticket := begin()
	var result := await service.unpublish_puzzle(item.id)
	if finish(ticket, result, "Unpublished. Installed copies remain playable.") and result.ok: refresh()

func installed_puzzle(item: Dictionary) -> Dictionary:
	if item.is_empty(): return {}
	for puzzle in session.store.list_community():
		if puzzle.id == item.id and int(puzzle.revision) == int(item.revision): return puzzle
	return {}
