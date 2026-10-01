class_name AppLogger
extends RefCounted

const GLOBAL_LOG_PATH = "user://logs/gamesmith-app.log"
const GAME_META_ROOT = "user://host/games"
const MAX_LOG_BYTES = 2 * 1024 * 1024
const KEEP_LOG_BYTES = 1024 * 1024

static func global_log_path() -> String:
    return GLOBAL_LOG_PATH

static func game_log_path(game_name: String) -> String:
    return GAME_META_ROOT.path_join(game_name).path_join("gamesmith.log")

static func global_event(kind: String, message: String, level: String = "INFO") -> bool:
    return _append(GLOBAL_LOG_PATH, kind, message, level)

static func game_event(game_name: String, kind: String, message: String, level: String = "INFO") -> bool:
    if game_name.strip_edges() == "":
        return global_event(kind, message, level)
    return _append(game_log_path(game_name), kind, message, level)

static func redact(message: String) -> String:
    var out = message
    out = _regex_sub(out, '(?i)(authorization\\s*[:=]\\s*bearer\\s+)[^\\s",;]+', '$1[REDACTED]')
    out = _regex_sub(out, '(?i)(api[_-]?key\\s*[:=]\\s*)[^\\s",;]+', '$1[REDACTED]')
    out = _regex_sub(out, '(?i)("authorization"\\s*:\\s*")[^"]+(")', '$1[REDACTED]$2')
    out = _regex_sub(out, '(?i)("(?:api_key|apiKey)"\\s*:\\s*")[^"]+(")', '$1[REDACTED]$2')
    out = _regex_sub(out, '(?i)\\bsk-[A-Za-z0-9_-]{8,}\\b', '[REDACTED-KEY]')
    return out

static func _append(path: String, kind: String, message: String, level: String) -> bool:
    var abs_dir = ProjectSettings.globalize_path(path.get_base_dir())
    var err = DirAccess.make_dir_recursive_absolute(abs_dir)
    if err != OK and err != ERR_ALREADY_EXISTS:
        return false
    var mode = FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
    var file = FileAccess.open(path, mode)
    if file == null:
        return false
    if mode == FileAccess.READ_WRITE:
        file.seek_end()
    var clean_kind = kind.strip_edges().replace("\n", " ").left(96)
    var clean_level = level.strip_edges().to_upper().replace("\n", " ").left(16)
    var clean_message = redact(message).replace("\r", " ").replace("\n", " ").left(6000)
    var stamp = Time.get_datetime_string_from_system(true)
    file.store_line("[%s][%s][%s] %s" % [stamp, clean_level, clean_kind, clean_message])
    file.close()
    _trim_if_needed(path)
    return true

static func _trim_if_needed(path: String) -> void:
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return
    var length = file.get_length()
    file.close()
    if length <= MAX_LOG_BYTES:
        return
    var text = FileAccess.get_file_as_string(path).right(KEEP_LOG_BYTES)
    var first_newline = text.find("\n")
    if first_newline >= 0 and first_newline + 1 < text.length():
        text = text.substr(first_newline + 1)
    var out = FileAccess.open(path, FileAccess.WRITE)
    if out != null:
        out.store_string("[log trimmed to most recent entries]\n" + text)
        out.close()

static func _regex_sub(subject: String, pattern: String, replacement: String) -> String:
    var regex = RegEx.new()
    if regex.compile(pattern) != OK:
        return subject
    return regex.sub(subject, replacement, true)
