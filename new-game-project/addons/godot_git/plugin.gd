@tool
extends EditorPlugin
## The switch for Godot Git under Project Settings > Plugins. The extension itself loads the Git
## dock and the Git Diff panel, and shows them while this plugin is on. Plain GDScript on purpose:
## a plugin made of the extension's own class crashed the editor when the addon's folder went away
## (switching to a branch without it).
##
## It's also the loader: when the addon came without this machine's library (the loader edition,
## or a teammate on another OS than the one who installed it), it downloads the version the
## manifest names, checks it (loader.gd), and loads it into the running editor, so the Git dock
## appears without a restart. Godot loads it by itself from the next start on. It also looks for a
## newer release once a day and, when asked (the Git dock's ⋮ menu), updates the addon to it.
## Without a manifest (built from source) it does nothing.

## Something the Git dock shows changed: latest, busy, notice.
signal changed

const Loader := preload("loader.gd")
const ADDON := "res://addons/godot_git"
const GDEXTENSION := ADDON + "/godot_git.gdextension"
const CHECK_SETTING := "godot_git/settings/check_for_updates"

var loader: Loader
var key := ""
var manifest_time := 0
var http: HTTPRequest
var update_version := ""
var update_keys := PackedStringArray()
var update_zips: Array[String] = []

## A newer release than the manifest's, "" when there's none (or it wasn't looked for).
var latest := ""
## What's running, for the Git dock's status strip ("Downloading Godot Git 2.2.0…"); "" when idle.
var busy := ""
## The last result of an update, for the status strip; "" when there's nothing to say.
var notice := ""
var notice_failed := false

var placeholder: EditorDock
var message: Label
var bar: ProgressBar
var retry: Button


func _enter_tree() -> void:
	Engine.set_meta("godot_git_loader", self)
	loader = Loader.new(ADDON)
	loader.remove_old_files()
	_check()
	# A pull that changes the manifest (a teammate updated Godot Git) is picked up while the editor
	# is open, not only at the next start.
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	get_tree().create_timer(10.0).timeout.connect(_check_for_update)


func _exit_tree() -> void:
	if Engine.get_meta("godot_git_loader", null) == self:
		Engine.remove_meta("godot_git_loader")
	if http:
		http.cancel_request()
		http.queue_free()
		http = null
	_hide()


func _on_filesystem_changed() -> void:
	if http == null and FileAccess.get_modified_time(loader.path(Loader.MANIFEST)) != manifest_time:
		_check()


# Gets and loads this computer's library when it isn't the manifest's version.
func _check() -> void:
	manifest_time = FileAccess.get_modified_time(loader.path(Loader.MANIFEST))
	if not loader.read_manifest():
		if not loader.error.is_empty():
			_show(loader.error)
		return
	key = Loader.platform_key()
	if key.is_empty():
		_show("Godot Git has no build for %s on %s." % [Engine.get_architecture_name(), OS.get_name()])
		return
	var in_use := GDExtensionManager.is_extension_loaded(GDEXTENSION)
	if not loader.needs_install(key):
		if not in_use:
			_load()
		return
	var text := "Getting Godot Git %s for this computer…" % loader.version()
	if in_use:
		_set_busy(text)
	else:
		_show(text, true)
	_download(loader.download_url(key), func(p_zip: String) -> void:
		var ok := loader.install(key, p_zip, in_use)
		DirAccess.remove_absolute(p_zip)
		if not ok:
			_failed(loader.error, in_use)
		elif in_use:
			# A teammate's update: the library in use can't be swapped, the next start uses the new one.
			_done("Godot Git %s is ready. Restart the editor to switch to it." % loader.version())
		else:
			_load()
	, in_use, "Godot Git %s" % loader.version())


func _load() -> void:
	EditorInterface.get_resource_filesystem().update_file(GDEXTENSION)
	match GDExtensionManager.load_extension(GDEXTENSION):
		GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
			_hide()
		GDExtensionManager.LOAD_STATUS_NEEDS_RESTART:
			_show("Restart the editor to finish installing Godot Git %s." % loader.version())
		_:
			_failed("Godot Git %s was downloaded but couldn't be loaded. The editor's Output says why." % loader.version(), false)


# --- Updates -----------------------------------------------------------------

# Asks for the newest release, at most once a day per project (Settings can turn it off).
func _check_for_update() -> void:
	if loader.manifest.is_empty() or not is_inside_tree():
		return
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(CHECK_SETTING) and not settings.get_setting(CHECK_SETTING):
		return
	var now := int(Time.get_unix_time_from_system())
	if now - int(settings.get_project_metadata("godot_git", "update_checked", 0)) < 24 * 3600:
		_set_latest(str(settings.get_project_metadata("godot_git", "update_latest", "")))
		return
	var request := HTTPRequest.new()
	request.timeout = 30.0
	add_child(request)
	request.request_completed.connect(func(p_result: int, p_code: int, _headers: PackedStringArray, p_body: PackedByteArray) -> void:
		request.queue_free()
		if p_result != HTTPRequest.RESULT_SUCCESS or p_code != 200:
			return  # Quietly: the next start asks again.
		var data: Variant = Loader.parse_json(p_body.get_string_from_utf8())
		if data is Dictionary:
			settings.set_project_metadata("godot_git", "update_checked", now)
			settings.set_project_metadata("godot_git", "update_latest", str(data.get("tag_name", "")))
			_set_latest(str(data.get("tag_name", ""))))
	request.request(str(loader.manifest.get("latest", "")), ["Accept: application/vnd.github+json", "User-Agent: godot-git"])


func _set_latest(p_tag: String) -> void:
	var newer := p_tag.trim_prefix("v") if not p_tag.is_empty() and Loader.is_newer(p_tag, loader.version()) else ""
	if newer != latest:
		latest = newer
		changed.emit()


## Updates the addon to the newest release: every library it has (only this computer's in the
## loader edition), its scripts and its manifest. The new library is used from the next editor
## start. The changed files show up as changes, and committing them updates the whole team.
func update() -> void:
	if latest.is_empty() or http:
		return
	update_version = latest
	update_keys = loader.installed_platforms()
	if not key in update_keys:
		update_keys.push_back(key)
	update_zips.clear()
	_set_busy("Downloading Godot Git %s…" % update_version)
	_download(loader.update_url(update_version, update_keys[0]), _on_update_downloaded, true, "Godot Git %s" % update_version)


func _on_update_downloaded(p_zip: String) -> void:
	update_zips.push_back(p_zip)
	if update_zips.size() < update_keys.size():
		_download(loader.update_url(update_version, update_keys[update_zips.size()]), _on_update_downloaded, true, "Godot Git %s" % update_version)
		return
	var ok := _install_update()
	for zip in update_zips:
		DirAccess.remove_absolute(zip)
	if not ok:
		loader.read_manifest()  # Back to the committed one: nothing of the update was used.
		_failed(loader.error, true)
		return
	manifest_time = FileAccess.get_modified_time(loader.path(Loader.MANIFEST))
	EditorInterface.get_resource_filesystem().scan_sources()
	latest = ""
	_done("Updated Godot Git to %s. Restart the editor to use it, and commit the addon's changed files so your team gets it too." % update_version)


func _install_update() -> bool:
	var in_use := GDExtensionManager.is_extension_loaded(GDEXTENSION)
	if not loader.use_manifest_from(update_zips[0]):
		return false
	for i in update_keys.size():
		if not loader.install(update_keys[i], update_zips[i], in_use and update_keys[i] == key):
			return false
	return loader.install_addon_files(update_zips[0])


# --- Downloads -----------------------------------------------------------------

# Downloads p_url into the project's .godot folder and calls p_done with the file, which p_done
# removes when it's done with it. While the placeholder shows (p_quiet false) its bar follows the
# download. p_what names it in a failure ("Godot Git 2.1.0").
func _download(p_url: String, p_done: Callable, p_quiet: bool, p_what: String) -> void:
	var dir := ProjectSettings.globalize_path("res://.godot/godot_git")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := dir.path_join(p_url.get_file())
	http = HTTPRequest.new()
	http.download_file = file
	http.use_threads = true
	http.timeout = 120.0
	add_child(http)
	http.request_completed.connect(func(p_result: int, p_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		http.queue_free()
		http = null
		if p_result != HTTPRequest.RESULT_SUCCESS or p_code != 200:
			DirAccess.remove_absolute(file)
			_failed("Couldn't download %s: %s." % [p_what, _why(p_result, p_code)], p_quiet, p_url)
			return
		p_done.call(file))
	var err := http.request(p_url)
	if err != OK:
		http.queue_free()
		http = null
		_failed("Couldn't start downloading %s (%s)." % [p_what, error_string(err)], p_quiet, p_url)
		return
	set_process(not p_quiet)


# A failed download in words, with what to do about it.
static func _why(p_result: int, p_code: int) -> String:
	match p_result:
		HTTPRequest.RESULT_SUCCESS:
			return "the server answered %d. Try again later" % p_code if p_code != 404 else "it isn't on the server (yet?). Try again later"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "the server's address couldn't be found. Check the internet connection, then try again"
		HTTPRequest.RESULT_TIMEOUT:
			return "it took too long. Check the internet connection, then try again"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "the secure connection failed (a proxy or firewall in between?)"
	return "no connection. Check the internet connection, then try again"


func _process(_delta: float) -> void:
	if http == null or bar == null:
		set_process(false)
		return
	var total := http.get_body_size()
	if total > 0:
		bar.indeterminate = false
		bar.value = 100.0 * http.get_downloaded_bytes() / total
		message.text = "Getting Godot Git %s for this computer… %s of %s" % [loader.version(), String.humanize_size(http.get_downloaded_bytes()), String.humanize_size(total)]


# --- What the user sees ----------------------------------------------------------

func _set_busy(p_text: String) -> void:
	busy = p_text
	changed.emit()


func _done(p_text: String) -> void:
	busy = ""
	notice = p_text
	notice_failed = false
	_tell()


# p_quiet: the Git dock is up (an update), so it goes to its status strip, not the placeholder.
# p_detail (the address it tried) goes in the placeholder's tooltip.
func _failed(p_why: String, p_quiet: bool, p_detail := "") -> void:
	busy = ""
	if p_quiet:
		notice = p_why
		notice_failed = true
		_tell()
		return
	_show(p_why)
	message.tooltip_text = p_detail
	message.mouse_filter = Control.MOUSE_FILTER_PASS  # So the tooltip shows.
	retry.show()


func _tell() -> void:
	if changed.get_connections().is_empty():
		# No Git dock listening (the library isn't loaded): a toast, so it isn't missed.
		EditorInterface.get_editor_toaster().push_toast(notice, EditorToaster.SEVERITY_WARNING if notice_failed else EditorToaster.SEVERITY_INFO)
	changed.emit()


# The Git tab until the real one is loaded: what's happening, its progress, or why it failed.
func _show(p_text: String, p_busy := false) -> void:
	if placeholder == null:
		var scale := EditorInterface.get_editor_scale()
		placeholder = EditorDock.new()
		placeholder.title = "Git"
		placeholder.icon_name = "VcsBranches"
		placeholder.layout_key = "GodotGitLoader"
		placeholder.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
		var margin := MarginContainer.new()
		for side in ["left", "right", "top"]:
			margin.add_theme_constant_override("margin_" + side, int(12 * scale))
		placeholder.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", int(10 * scale))
		margin.add_child(box)
		message = Label.new()
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.custom_minimum_size.x = 160 * scale  # A wrapping label needs a width (gotchas 28, 45).
		box.add_child(message)
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 4 * scale
		box.add_child(bar)
		retry = Button.new()
		retry.text = "Retry"
		retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		retry.pressed.connect(_check)
		box.add_child(retry)
		add_dock(placeholder)
	message.text = p_text
	bar.visible = p_busy
	# Moving until the size is known: connecting can take seconds, and an empty bar looks stuck.
	bar.indeterminate = p_busy
	bar.value = 0
	retry.hide()


func _hide() -> void:
	if placeholder:
		remove_dock(placeholder)
		placeholder.queue_free()
		placeholder = null
