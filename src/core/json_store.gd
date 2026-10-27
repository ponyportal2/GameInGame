class_name JsonStore
extends RefCounted

static func read_dict(path: String, fallback: Dictionary = {}) -> Dictionary:
    if not FileAccess.file_exists(path):
        return fallback.duplicate(true)
    var text = FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return fallback.duplicate(true)
    return parsed

static func write_dict(path: String, data: Dictionary) -> bool:
    return write_bytes_atomic(path, JSON.stringify(data, "  ").to_utf8_buffer())

static func write_bytes_atomic(path: String, contents: PackedByteArray) -> bool:
    var absolute = ProjectSettings.globalize_path(path)
    if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
        return false
    # Keep the previous file intact until the replacement has been fully written.
    var temporary = absolute + ".%d-%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
    var file = FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return false
    file.store_buffer(contents)
    file.flush()
    var error = file.get_error()
    file.close()
    if error == OK:
        error = _replace_file(temporary, absolute)
    if error != OK:
        DirAccess.remove_absolute(temporary)
    return error == OK

static func _replace_file(temporary: String, destination: String) -> Error:
    # Only Windows rejects a replacement while a reader holds the destination
    # open. Elsewhere the rename is atomic and a retry cannot help, so a failure
    # there is returned as-is instead of being hidden behind a fixed delay.
    if OS.get_name() != "Windows":
        return DirAccess.rename_absolute(temporary, destination)
    # Readers poll these control files while writers replace them, so a single
    # attempt can lose a final status that the caller cannot retry.
    var error: Error = ERR_CANT_CREATE
    for attempt in range(6):
        error = _replace_once(temporary, destination)
        if error == OK:
            return OK
        OS.delay_msec(25)
    return error

static func _replace_once(temporary: String, destination: String) -> Error:
    # Godot's Windows rename deletes an existing destination before moving the
    # source. File.Replace uses Windows' replacement operation and preserves the
    # destination on failure. Encode paths so names cannot become shell syntax.
    var source64 = Marshalls.raw_to_base64(temporary.to_utf8_buffer())
    var destination64 = Marshalls.raw_to_base64(destination.to_utf8_buffer())
    var command = "$ErrorActionPreference='Stop'; "
    command += "$taskSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')); " % source64
    command += "$taskDestination=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')); " % destination64
    command += "try { if ([IO.File]::Exists($taskDestination)) { [IO.File]::Replace($taskSource,$taskDestination,[NullString]::Value) } else { [IO.File]::Move($taskSource,$taskDestination) }; exit 0 } catch { exit 1 }"
    var output: Array = []
    return OK if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", command], output, true) == 0 else ERR_CANT_CREATE

static func append_json_line(path: String, data: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.READ_WRITE)
    if file == null:
        file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    # A process killed mid-append can leave a partial final record. Terminate
    # it so this record starts on its own line instead of corrupting both.
    if file.get_length() > 0:
        file.seek(file.get_length() - 1)
        if file.get_8() != 10:
            file.seek_end()
            file.store_8(10)
    file.seek_end()
    file.store_line(JSON.stringify(data))
    file.close()
    return true
