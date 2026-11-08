@tool
extends RefCounted
## Gets this machine's Godot Git library when the addon came without it (the loader edition, or a
## teammate on another OS), from the GitHub release its manifest names, and checks every file
## against the manifest's SHA256 before any of it is written into the addon.
##
## The manifest (godot_git.manifest.json, committed with the project) is the only thing that says
## which version a project uses: everyone who pulls it gets the same one. Without a manifest (a
## build from source, like this repository's own) nothing here ever runs.
##
## Plain GDScript and no editor classes, so the tests can run it against a scratch folder. The
## plugin (plugin.gd) does the downloading and shows the progress.

const MANIFEST := "godot_git.manifest.json"
const GDEXTENSION := "godot_git.gdextension"

## The addon folder, absolute or res://.
var addon_dir := ""
var manifest := {}
## Why the last call failed, worded for the panel.
var error := ""


func _init(p_addon_dir: String) -> void:
	addon_dir = p_addon_dir


## This machine's key in the manifest ("windows.x86_64", "macos", ...), or "" when no build
## exists for it.
static func platform_key() -> String:
	var arch := Engine.get_architecture_name()
	match OS.get_name():
		"Windows":
			return "windows." + arch if arch in ["x86_64", "arm64"] else ""
		"Linux":
			return "linux." + arch if arch in ["x86_64", "arm64"] else ""
		"macOS":
			return "macos"  # One universal library for Intel and Apple Silicon.
	return ""


## JSON's data, or null when it isn't JSON: JSON.parse_string would also print an error to the
## editor's Output, for something the panel already explains.
static func parse_json(p_text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(p_text) == OK else null


static func sha256(p_bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(p_bytes)
	return ctx.finish().hex_encode()


func path(p_relative: String) -> String:
	return addon_dir.path_join(p_relative)


## Reads the manifest. False without one (nothing to do) or when it can't be read (error says why).
func read_manifest() -> bool:
	manifest = {}
	if not FileAccess.file_exists(path(MANIFEST)):
		return false
	var parsed: Variant = parse_json(FileAccess.get_file_as_string(path(MANIFEST)))
	if not parsed is Dictionary or not parsed.has("version") or not parsed.has("platforms"):
		error = "%s can't be read. Restore it from git, or download Godot Git again." % MANIFEST
		return false
	manifest = parsed
	return true


func version() -> String:
	return str(manifest.get("version", ""))


## This platform's entry: { "zip": file name, "files": { path in the addon: sha256 } }.
func platform_entry(p_key: String) -> Dictionary:
	return manifest.get("platforms", {}).get(p_key, {})


func download_url(p_key: String) -> String:
	return str(manifest.get("release", "")).trim_suffix("/") + "/" + str(platform_entry(p_key).get("zip", ""))


## The version installed for p_key: "" when its library isn't there, "dev" for a library that came
## without a version stamp (built from source).
func installed_version(p_key: String) -> String:
	var files: Dictionary = platform_entry(p_key).get("files", {})
	for file in files:
		if str(file).begins_with("bin/") and not FileAccess.file_exists(path(file)):
			return ""
	if files.is_empty() or not FileAccess.file_exists(path(GDEXTENSION)):
		return ""
	var stamp := path(_stamp(p_key))
	return FileAccess.get_file_as_string(stamp).strip_edges() if FileAccess.file_exists(stamp) else "dev"


## Whether p_key's library has to be fetched: when it isn't the manifest's version, older or newer.
## The manifest decides, in both directions: a reverted update (or an older branch) goes back down
## the same way an update goes up (maintainer, 2026-10-25). Asking what's newest is only for
## offering an update, and changing the manifest is the only thing that does.
func needs_install(p_key: String) -> bool:
	var installed := installed_version(p_key)
	return installed != version() and installed != "dev"


## Unpacks the platform zip at p_zip into the addon, after checking every file the manifest lists
## for p_key. Nothing is written unless all of them are in the zip and match. With p_in_use (the
## library is loaded), the files in the way are renamed to "<name>.old" first: a loaded library
## can't be overwritten on Windows, but it can be renamed, and the new one takes over at the next
## editor start. Returns false with error set.
func install(p_key: String, p_zip: String, p_in_use: bool) -> bool:
	var files: Dictionary = platform_entry(p_key).get("files", {})
	if files.is_empty():
		error = "The manifest has no Godot Git build for %s." % p_key
		return false
	var reader := ZIPReader.new()
	if reader.open(p_zip) != OK:
		error = "The download isn't a zip file. Try again."
		return false
	var contents := {}
	var in_zip := reader.get_files()
	for file in files:
		var name := "addons/godot_git/" + str(file)
		if not name in in_zip:
			reader.close()
			error = "The download is missing %s. Try again, or download Godot Git again." % file
			return false
		var bytes := reader.read_file(name)
		if sha256(bytes) != str(files[file]):
			reader.close()
			error = "%s in the download doesn't match the manifest, so it wasn't used. Try again; if it keeps happening, the release or your connection has been tampered with." % file
			return false
		contents[file] = bytes
	reader.close()
	for file in contents:
		var target := path(file)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if p_in_use and FileAccess.file_exists(target) and str(file).begins_with("bin/"):
			DirAccess.remove_absolute(target + ".old")
			if DirAccess.rename_absolute(target, target + ".old") != OK:
				error = "Couldn't move the old %s aside to make room for the new one." % str(file).get_file()
				return false
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			error = "Couldn't write %s (%s)." % [file, error_string(FileAccess.get_open_error())]
			return false
		f.store_buffer(contents[file])
		f.close()
	var stamp := FileAccess.open(path(_stamp(p_key)), FileAccess.WRITE)
	if stamp:
		stamp.store_string(version() + "\n")
	return true


## Where version p_version's zips are (the manifest's "releases" pattern: the GitHub releases, or a
## stand-in in the tests).
func release_url(p_version: String) -> String:
	var tag := "v" + p_version.trim_prefix("v")
	return str(manifest.get("releases", "https://github.com/mssbabou/Godot-Git/releases/download/{tag}/")).replace("{tag}", tag)


## The platform zip of another version (an update), named as tools/package.py names it.
func update_url(p_version: String, p_key: String) -> String:
	var tag := "v" + p_version.trim_prefix("v")
	return release_url(p_version) + "godot_git-%s-%s.zip" % [tag, p_key.replace(".", "-")]


## The platforms whose library is in this addon (the loader edition: just this computer's; the
## Offline edition: all of them). An update replaces each, so the committed files stay one version.
func installed_platforms() -> PackedStringArray:
	var keys := PackedStringArray()
	for key in manifest.get("platforms", {}):
		if installed_version(key) != "":
			keys.push_back(key)
	return keys


## Takes the manifest from a downloaded release zip (an update), so install() checks its files.
func use_manifest_from(p_zip: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(p_zip) != OK:
		error = "The download isn't a zip file. Try again."
		return false
	var parsed: Variant = parse_json(reader.read_file("addons/godot_git/" + MANIFEST).get_string_from_utf8())
	reader.close()
	if not parsed is Dictionary or not parsed.has("version") or not parsed.has("platforms"):
		error = "The download has no readable manifest. Try again."
		return false
	manifest = parsed
	return true


## Writes the addon's own files (scripts, plugin.cfg, licenses) from an update's zip, checked
## against its manifest, and then the manifest itself. These are the files a team commits, so the
## update reaches everyone with their next pull.
func install_addon_files(p_zip: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(p_zip) != OK:
		error = "The download isn't a zip file. Try again."
		return false
	var files: Dictionary = manifest.get("addon", {})
	var contents := {}
	for file in files:
		var bytes := reader.read_file("addons/godot_git/" + str(file))
		if sha256(bytes) != str(files[file]):
			reader.close()
			error = "%s in the download doesn't match its manifest, so the update wasn't used." % file
			return false
		contents[file] = bytes
	var manifest_bytes := reader.read_file("addons/godot_git/" + MANIFEST)
	reader.close()
	contents[MANIFEST] = manifest_bytes
	for file in contents:
		DirAccess.make_dir_recursive_absolute(path(file).get_base_dir())
		var f := FileAccess.open(path(file), FileAccess.WRITE)
		if f == null:
			error = "Couldn't write %s (%s)." % [file, error_string(FileAccess.get_open_error())]
			return false
		f.store_buffer(contents[file])
	return true


## Whether version p_a is newer than p_b ("2.10.0" > "2.9.1"; "2.1.0" > "2.1.0-rc1").
static func is_newer(p_a: String, p_b: String) -> bool:
	var a := p_a.trim_prefix("v").split("-", true, 1)
	var b := p_b.trim_prefix("v").split("-", true, 1)
	var an := a[0].split(".")
	var bn := b[0].split(".")
	for i in maxi(an.size(), bn.size()):
		var x := an[i].to_int() if i < an.size() else 0
		var y := bn[i].to_int() if i < bn.size() else 0
		if x != y:
			return x > y
	# Same numbers: a release beats its pre-releases.
	return a.size() == 1 and b.size() == 2


## Removes what an update left behind (the libraries it renamed aside). A file that's still loaded
## stays until a later start.
func remove_old_files() -> void:
	_remove_old_in(path("bin"))


func _remove_old_in(p_dir: String) -> void:
	var dir := DirAccess.open(p_dir)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".old"):
			dir.remove(file)
	for sub in dir.get_directories():
		_remove_old_in(p_dir.path_join(sub))


func _stamp(p_key: String) -> String:
	return "bin/%s.version" % p_key
