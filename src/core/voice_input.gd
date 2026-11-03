extends Node

signal changed
signal transcribed

const MODELS = ["tiny", "base", "small", "medium", "large-v3", "turbo"]
const ROOT = "user://host/voice"
const MAX_SECONDS = 60.0
const WORK_TIMEOUT_MS = 600000

var settings: Dictionary = {}
var game_name := ""
var draft := ""
var state := "idle"
var status := ""
var level := 0.0
var elapsed := 0.0
var request_id := ""
var request_game := ""
var worker_pid := -1
var directory := ""
var work_started := 0
var microphone: AudioStreamPlayer
var recorder: AudioEffectRecord
var meter: AudioEffectCapture
var bus_name := ""
var previous_device := ""
var poll_elapsed := 0.0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func configure(values: Dictionary) -> void:
    if settings != values:
        cancel()
        if state != "installing": _stop_worker()
    settings = values.duplicate(true)
    changed.emit()

func bind_game(value: String) -> void:
    if value == game_name: return
    cancel()
    draft = ""
    game_name = value
    if state != "installing": status = ""
    changed.emit()

func enabled() -> bool:
    return bool(settings.get("voice_enabled", false))

func installed() -> bool:
    return FileAccess.file_exists(_python()) and FileAccess.file_exists(ROOT.path_join("installed.json"))

func set_draft(text: String) -> void:
    draft = text.left(4000)
    changed.emit()

func clear_draft() -> void:
    draft = ""
    status = ""
    changed.emit()

func install_recognition(executable: String = "") -> void:
    if state != "idle": return
    _stop_worker()
    if not _prepare_directory(): return
    state = "installing"
    status = "Installing local recognition…"
    if executable.strip_edges() == "": executable = str(settings.get("voice_python", "python")).strip_edges()
    worker_pid = OS.create_process(executable, _arguments(true), false)
    work_started = Time.get_ticks_msec()
    if worker_pid <= 0:
        _error("Python could not start. Choose its executable in Voice settings.")
    changed.emit()

func toggle_recording() -> void:
    if state == "recording":
        _finish_recording()
        return
    if state != "idle" or game_name == "": return
    if not enabled():
        _error("Enable voice input in Settings → Voice first.")
        return
    if not installed():
        _error("Install local recognition in Settings → Voice first.")
        return
    if not _capture_start(): return
    elapsed = 0.0
    state = "recording"
    status = "Recording"
    changed.emit()

func cancel() -> void:
    if state == "installing": return
    if state == "recording": _capture_stop()
    if state == "transcribing": _stop_worker()
    # Installation is independent of the game/voice draft and may finish while
    # the player navigates. Its worker observes host exit through the stop file.
    state = "idle"
    request_id = ""
    request_game = ""
    level = 0.0
    status = ""
    changed.emit()

func _capture_start() -> bool:
    if DisplayServer.get_name() == "headless":
        _error("Microphone capture requires the windowed app.")
        return false
    var device = str(settings.get("voice_microphone", "Default"))
    if device not in AudioServer.get_input_device_list():
        _error("Selected microphone is unavailable. Choose another in Voice settings.")
        return false
    previous_device = AudioServer.input_device
    AudioServer.input_device = device
    bus_name = "GameSmithVoice%d" % get_instance_id()
    AudioServer.add_bus()
    var index = AudioServer.bus_count - 1
    AudioServer.set_bus_name(index, bus_name)
    AudioServer.set_bus_mute(index, true) # Never play the microphone to speakers.
    recorder = AudioEffectRecord.new()
    recorder.format = AudioStreamWAV.FORMAT_16_BITS
    meter = AudioEffectCapture.new()
    meter.buffer_length = 0.2
    AudioServer.add_bus_effect(index, recorder)
    AudioServer.add_bus_effect(index, meter)
    microphone = AudioStreamPlayer.new()
    microphone.stream = AudioStreamMicrophone.new()
    microphone.bus = bus_name
    add_child(microphone)
    recorder.set_recording_active(true)
    microphone.play()
    return true

func _capture_stop() -> AudioStreamWAV:
    var audio: AudioStreamWAV
    if recorder != null:
        recorder.set_recording_active(false)
        audio = recorder.get_recording()
    if is_instance_valid(microphone):
        microphone.stop()
        microphone.queue_free()
    microphone = null
    var index = AudioServer.get_bus_index(bus_name)
    if index > 0: AudioServer.remove_bus(index)
    bus_name = ""
    recorder = null
    meter = null
    if previous_device != "": AudioServer.input_device = previous_device
    previous_device = ""
    return audio

func _finish_recording() -> void:
    var audio = _capture_stop()
    state = "idle"
    level = 0.0
    if audio == null or audio.get_length() < 0.25:
        _error("No audio captured. Check microphone access and try again.")
        return
    if not _ensure_worker(): return
    request_id = Crypto.new().generate_random_bytes(12).hex_encode()
    request_game = game_name
    var path = directory.path_join(request_id + ".wav")
    if audio.save_to_wav(path) != OK:
        _error("Could not save the temporary voice recording.")
        return
    var model = str(settings.get("voice_model", "base"))
    if model not in MODELS: model = "base"
    if not JsonStore.write_dict(directory.path_join("request-" + request_id + ".json"), {
        "id":request_id, "audio":path, "model":model, "language":str(settings.get("voice_language", "auto"))
    }):
        DirAccess.remove_absolute(path)
        _error("Could not request voice transcription.")
        return
    state = "transcribing"
    status = "Transcribing (%s)… First use downloads the model." % model
    work_started = Time.get_ticks_msec()
    changed.emit()

func _process(delta: float) -> void:
    if state == "recording":
        elapsed += delta
        if meter != null:
            var samples = meter.get_buffer(meter.get_frames_available())
            level = 0.0
            for sample in samples:
                level = maxf(level, maxf(absf(sample.x), absf(sample.y)))
        changed.emit()
        if elapsed >= MAX_SECONDS:
            _finish_recording()
            return
    if state not in ["transcribing", "installing"]: return
    poll_elapsed += delta
    if poll_elapsed < 0.1: return
    poll_elapsed = 0.0
    var path = directory.path_join("installed.json" if state == "installing" else "result-" + request_id + ".json")
    if FileAccess.file_exists(path):
        var result = JsonStore.read_dict(path)
        DirAccess.remove_absolute(path)
        if state == "installing":
            state = "idle"
            status = "Local recognition installed. Enable voice and save settings." if result.get("ok", false) else str(result.get("error", "Installation failed."))
            worker_pid = -1
            changed.emit()
        else:
            _consume_result(result)
    elif worker_pid <= 0 or not OS.is_process_running(worker_pid):
        _error("Voice worker stopped. Check Python / reinstall recognition in Voice settings.")
        _stop_worker()
    elif Time.get_ticks_msec() - work_started > WORK_TIMEOUT_MS:
        _stop_worker()
        _error("Voice recognition timed out. Try a smaller model or check the model download connection.")

func _consume_result(result: Dictionary) -> void:
    if state != "transcribing" or str(result.get("id", "")) != request_id or request_game != game_name: return
    state = "idle"
    request_id = ""
    request_game = ""
    if not bool(result.get("ok", false)):
        _error(str(result.get("error", "Transcription failed.")))
        return
    var text = str(result.get("text", "")).strip_edges().left(4000)
    if text == "":
        status = "No speech recognized. Check your microphone level and try again."
        changed.emit()
        return
    # Dictation appends rather than destroying an unsent voice draft.
    draft = (draft + " " + text).strip_edges().left(4000)
    status = "Ready to send"
    changed.emit()
    transcribed.emit()

func _python() -> String:
    return ProjectSettings.globalize_path(ROOT.path_join("environment/Scripts/python.exe" if OS.get_name() == "Windows" else "environment/bin/python"))

func _prepare_directory() -> bool:
    directory = ProjectSettings.globalize_path(ROOT.path_join("sessions/" + Crypto.new().generate_random_bytes(12).hex_encode()))
    if DirAccess.make_dir_recursive_absolute(directory) != OK:
        _error("Could not create voice user-data directory.")
        return false
    var script = FileAccess.open(directory.path_join("worker.py"), FileAccess.WRITE)
    if script == null:
        _error("Could not prepare the voice worker.")
        return false
    script.store_string(FileAccess.get_file_as_string("res://tools/voice/worker.py"))
    script.close()
    return true

func _arguments(installing: bool = false) -> PackedStringArray:
    var args = PackedStringArray([directory.path_join("worker.py"), "--root", ProjectSettings.globalize_path(ROOT), "--directory", directory, "--parent", str(OS.get_process_id())])
    if installing: args.append("--install")
    return args

func _ensure_worker() -> bool:
    if worker_pid > 0 and OS.is_process_running(worker_pid): return true
    _stop_worker()
    if not _prepare_directory(): return false
    worker_pid = OS.create_process(_python(), _arguments(), false)
    if worker_pid <= 0:
        _error("Could not start local recognition. Reinstall it in Voice settings.")
        return false
    return true

func _stop_worker() -> void:
    if directory != "":
        var stop = FileAccess.open(directory.path_join("stop"), FileAccess.WRITE)
        if stop != null: stop.close()
    if worker_pid > 0 and OS.is_process_running(worker_pid) and state != "installing": OS.kill(worker_pid)
    worker_pid = -1
    if directory != "" and state != "installing":
        var dir = DirAccess.open(directory)
        if dir != null:
            for file in dir.get_files(): DirAccess.remove_absolute(directory.path_join(file))
            DirAccess.remove_absolute(directory)
    directory = ""

func _error(message: String) -> void:
    state = "idle"
    request_id = ""
    request_game = ""
    status = message
    changed.emit()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "recording":
        cancel()
        status = "Recording cancelled because GameSmith lost focus."
        changed.emit()

func _exit_tree() -> void:
    _capture_stop()
    _stop_worker()
