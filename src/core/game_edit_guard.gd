extends RefCounted

var workspace := ""
var stdio: FileAccess
var stderr: FileAccess
var pid := -1
var owned := false
var error := ""

func acquire() -> bool:
    if owned and pid > 0 and OS.is_process_running(pid):
        return true
    release()
    error = ""
    var helper = "user://host/ownership.mjs"
    var source = FileAccess.get_file_as_bytes("res://tools/agent/ownership.mjs")
    if not FileAccess.file_exists(helper) or FileAccess.get_file_as_bytes(helper) != source:
        if not JsonStore.write_bytes_atomic(helper, source):
            error = "Could not prepare game ownership."
            return false
    var launched = OS.execute_with_pipe("node", [ProjectSettings.globalize_path(helper), ProjectSettings.globalize_path(workspace)], false)
    stdio = launched.get("stdio")
    stderr = launched.get("stderr")
    pid = int(launched.get("pid", -1))
    var text := ""
    # This bounds only the small local ownership helper, never an agent request.
    var deadline = Time.get_ticks_msec() + 5000
    while stdio != null and pid > 0 and Time.get_ticks_msec() < deadline:
        text += stdio.get_buffer(4096).get_string_from_utf8()
        if "\n" in text:
            var response = JSON.parse_string(text.get_slice("\n", 0))
            if response is Dictionary:
                owned = bool(response.get("ok", false))
                error = str(response.get("error", ""))
            break
        if not OS.is_process_running(pid): break
        OS.delay_msec(5)
    if not owned:
        if error == "": error = "Could not acquire game ownership. Ensure Node.js is installed and try again."
        release()
    return owned

func release() -> void:
    owned = false
    if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
    if stdio != null: stdio.close()
    if stderr != null: stderr.close()
    stdio = null
    stderr = null
    pid = -1

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # At engine shutdown script method dispatch may already be unavailable.
        if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
        if stdio != null: stdio.close()
        if stderr != null: stderr.close()
