extends SceneTree

# Workspace naming and deletion must stay safe on Windows: the same code runs
# for the library, rename and delete flows, and a bad name either hides a game
# or makes directory creation fail after the metadata was already written.

const PathUtilsRef = preload("res://src/core/path_utils.gd")
const Store = preload("res://src/core/workspace_store.gd")
const JsonStoreRef = preload("res://src/core/json_store.gd")
const FIXTURE_LOG = "user://workspace_store_fixture/events.jsonl"

var passed := 0
var failed := 0

class FailingDelete extends "res://src/core/workspace_store.gd":
    func _remove_tree(_path: String) -> bool:
        return false

func _init() -> void:
    call_deferred("run")

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("PASS: " + label)
    else:
        failed += 1
        print("FAIL: " + label)
        push_error(label)

func run() -> void:
    test_sanitize_matrix()
    test_reserved_and_hidden_names()
    test_create_collisions()
    test_delete_keeps_metadata_on_failure()
    test_jsonl_partial_tail()
    print("RESULT: %d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)

func test_sanitize_matrix() -> void:
    check(PathUtilsRef.sanitize_game_name("  My   Game  ") == "My Game", "collapses whitespace and trims edges")
    check(PathUtilsRef.sanitize_game_name("A/B\\C:D*E?F\"G<H>I|J") == "A B C D E F G H I J", "replaces every Windows-forbidden character")
    check(PathUtilsRef.sanitize_game_name("Line\nBreak\tTab") == "Line Break Tab", "replaces newlines and tabs with single spaces")
    check(PathUtilsRef.sanitize_game_name("Bell" + char(7) + "Del" + char(127)) == "Bell Del", "drops control characters including DEL")
    check(PathUtilsRef.sanitize_game_name("") == "Untitled Game", "empty input gets a stable fallback")
    check(PathUtilsRef.sanitize_game_name("   ") == "Untitled Game", "blank input gets a stable fallback")
    check(PathUtilsRef.sanitize_game_name("Trailing...") == "Trailing", "strips trailing dots Windows would drop")
    check(PathUtilsRef.sanitize_game_name("Trailing. . ") == "Trailing", "strips mixed trailing dots and spaces")
    check(PathUtilsRef.sanitize_game_name(".hidden") == "hidden", "removes a leading dot that would hide the workspace")
    check(PathUtilsRef.sanitize_game_name("..") == "Untitled Game", "dot-only input gets a stable fallback")
    check(PathUtilsRef.sanitize_game_name("v1.2 notes") == "v1.2 notes", "keeps interior dots")
    var long_name: String = "x".repeat(80)
    check(PathUtilsRef.sanitize_game_name(long_name).length() == 64, "caps the name at 64 characters")
    check(PathUtilsRef.sanitize_game_name("a".repeat(63) + "." + "bbb") == "a".repeat(63), "truncation never leaves a trailing dot")
    check(PathUtilsRef.sanitize_game_name("a".repeat(63) + " " + "bbb") == "a".repeat(63), "truncation never leaves a trailing space")

func test_reserved_and_hidden_names() -> void:
    check(PathUtilsRef.sanitize_game_name("CON") == "Game CON", "prefixes a reserved device name")
    check(PathUtilsRef.sanitize_game_name("con.txt") == "Game con.txt", "detects reserved device names with an extension")
    check(PathUtilsRef.sanitize_game_name("LPT9") == "Game LPT9", "detects reserved printer ports")
    check(PathUtilsRef.sanitize_game_name("Console") == "Console", "keeps names that only start with a device name")
    check(PathUtilsRef.sanitize_game_name("auxiliary") == "auxiliary", "keeps ordinary names containing a device name")
    var store = Store.new()
    var hidden: Dictionary = store.create_game(".Hidden fixture")
    check(hidden.get("ok", false) and hidden.get("name", "") == "Hidden fixture", "creating a dot-prefixed name stores a visible name")
    check(store.list_games().has("Hidden fixture"), "the sanitized workspace appears in the library listing")
    var reserved: Dictionary = store.create_game("CON")
    check(reserved.get("ok", false) and reserved.get("name", "") == "Game CON", "creating a reserved device name succeeds")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(store.game_path("Game CON"))), "the reserved-name workspace exists on disk")
    store.delete_game("Hidden fixture")
    store.delete_game("Game CON")

func test_create_collisions() -> void:
    var store = Store.new()
    var first: Dictionary = store.create_game("Duplicate fixture")
    var second: Dictionary = store.create_game("Duplicate fixture")
    check(first.get("name", "") == "Duplicate fixture", "the first workspace keeps the requested name")
    check(second.get("name", "") == "Duplicate fixture 2", "a second workspace gets a distinct suffix")
    check(store.list_games().has("Duplicate fixture") and store.list_games().has("Duplicate fixture 2"), "both workspaces are listed")
    check(store.delete_game("Duplicate fixture 2"), "deleting the suffixed workspace succeeds")
    check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(store.game_path("Duplicate fixture 2"))), "deleted workspace directory is gone")
    check(store.delete_game("Duplicate fixture"), "deleting the original workspace succeeds")

func test_delete_keeps_metadata_on_failure() -> void:
    var store = Store.new()
    var created: Dictionary = store.create_game("Locked delete fixture")
    var name: String = created.get("name", "")
    check(name != "", "locked-delete fixture is created")
    var failing = FailingDelete.new()
    check(not failing.delete_game(name), "a failed workspace removal reports failure")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(store.game_path(name))), "the locked workspace is kept")
    check(store.metadata.read_game(name).get("harness", "") == "pi", "failed deletion keeps the game metadata and library entry")
    check(store.list_games().has(name), "the retryable game remains listed")
    check(store.delete_game(name), "deletion succeeds once the workspace can be removed")
    check(store.metadata.read_game(name).get("harness", "") == "", "successful deletion removes the metadata")

func test_jsonl_partial_tail() -> void:
    var absolute: String = ProjectSettings.globalize_path(FIXTURE_LOG)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file = FileAccess.open(FIXTURE_LOG, FileAccess.WRITE)
    file.store_string("{\"partial\":")
    file.close()
    check(JsonStoreRef.append_json_line(FIXTURE_LOG, {"type": "second"}), "appending after a partial tail succeeds")
    var lines: PackedStringArray = FileAccess.get_file_as_string(FIXTURE_LOG).split("\n", false)
    check(lines.size() == 2, "the partial tail and the new record stay on separate lines")
    var appended = JSON.parse_string(lines[1])
    check(typeof(appended) == TYPE_DICTIONARY and appended.get("type", "") == "second", "the appended record is intact JSON")
    check(JsonStoreRef.append_json_line(FIXTURE_LOG, {"type": "third"}), "appending to a terminated file succeeds")
    lines = FileAccess.get_file_as_string(FIXTURE_LOG).split("\n", false)
    check(lines.size() == 3 and JSON.parse_string(lines[2]).get("type", "") == "third", "later records remain parseable")
    DirAccess.remove_absolute(absolute)
