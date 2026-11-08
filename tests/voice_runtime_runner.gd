extends SceneTree

var failed := 0

class RepairVoice:
    extends "res://src/core/voice_input.gd"

    # Exercise the public Install path through real extraction, stopping before
    # package installation so corruption recovery needs no network or models.
    func _prepare_directory() -> bool:
        return false

func _init() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
    if value: print("PASS: ", message)
    else:
        failed += 1
        push_error("FAIL: " + message)

func run() -> void:
    if OS.get_name() != "Windows" or not OS.has_feature("x86_64"):
        print("SKIP: included voice runtime execution requires Windows x64; archive/license checks remain covered by node:voice")
        quit(0)
        return
    var voice = preload("res://src/core/voice_input.gd").new()
    root.add_child(voice)
    # Exercise production extraction with hostile global Python configuration.
    var old_path = OS.get_environment("PATH")
    var old_pythonpath = OS.get_environment("PYTHONPATH")
    # JsonStore uses Windows PowerShell for atomic writes. Keep Windows tools,
    # excluding every Python installation and the WindowsApps Python alias.
    OS.set_environment("PATH", OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0"))
    OS.set_environment("PYTHONPATH", "C:/not-a-python-installation")
    check(voice._prepare_runtime(), "included Python extracts and validates from source or PCK")
    if failed:
        quit(1)
        return
    check(voice._prepare_runtime(), "prepared runtime can be reused")
    var repair = RepairVoice.new()
    root.add_child(repair)
    var model_path = ProjectSettings.globalize_path(voice.ROOT.path_join("models/repair-sentinel"))
    DirAccess.make_dir_recursive_absolute(model_path.get_base_dir())
    var model = FileAccess.open(model_path, FileAccess.WRITE)
    model.store_string("keep downloaded model")
    model.close()
    for file in ["python313.dll", "pip.whl"]:
        var damaged_path = voice._runtime_directory().path_join(file)
        var original = FileAccess.get_file_as_bytes(damaged_path)
        if file.ends_with(".dll"):
            DirAccess.remove_absolute(damaged_path)
        else:
            var damaged = FileAccess.open(damaged_path, FileAccess.WRITE)
            damaged.store_string("corrupt wheel")
            damaged.close()
        repair.install_recognition()
        var restored = FileAccess.get_file_as_bytes(damaged_path) == original
        check(restored, "explicit Install restores damaged " + file + " despite a valid ready marker")
        # Keep the rest of this runner usable on the red regression revision.
        if not restored:
            var restore = FileAccess.open(damaged_path, FileAccess.WRITE)
            restore.store_buffer(original)
            restore.close()
        check(FileAccess.get_file_as_string(model_path) == "keep downloaded model", "runtime repair preserves cached models for " + file)
    DirAccess.remove_absolute(model_path)
    repair.queue_free()
    var marker = voice.ROOT.path_join("installed.json")
    var previous = JsonStore.read_dict(marker)
    JsonStore.write_dict(marker, {"packages":["legacy system-Python installation"]})
    check(not voice.installed(), "legacy system-Python marker requires reinstall with included runtime")
    # Simulate installed packages while varying only extraction readiness. Keep
    # real optional acceptance installations intact and restore their marker.
    var packages = voice.ROOT.path_join("environment/faster_whisper")
    var had_packages = DirAccess.dir_exists_absolute(packages)
    DirAccess.make_dir_recursive_absolute(packages)
    JsonStore.write_dict(marker, {"runtime":voice._bundle().python.version})
    var ready = voice._runtime_directory().path_join("ready.json")
    var bundle = JsonStore.read_dict(ready)
    check(voice.installed(), "matching readiness and recognition records report installed")
    DirAccess.remove_absolute(ready)
    check(not voice.installed(), "interrupted refresh without readiness cannot report installed")
    JsonStore.write_dict(ready, {"python":{"version":"obsolete"}})
    check(not voice.installed(), "mismatched runtime readiness cannot report installed")
    JsonStore.write_dict(ready, bundle)
    check(voice.installed(), "restoring matching readiness restores installed status")
    if not had_packages: DirAccess.remove_absolute(packages)
    if previous.is_empty(): DirAccess.remove_absolute(marker)
    else: JsonStore.write_dict(marker, previous)
    var output := []
    var code = OS.execute(voice._python(), ["-I", "-c", "import sys,ssl,sqlite3,json;print(json.dumps({'version':sys.version.split()[0],'isolated':sys.flags.isolated,'paths':sys.path}))"], output, true)
    var details = JSON.parse_string("".join(output))
    check(code == 0 and details is Dictionary and details.version == voice._bundle().python.version and details.isolated == 1, "included interpreter runs native standard library without system Python")
    output.clear()
    code = OS.execute(voice._python(), ["-I", "-c", "import runpy,sys;sys.path.insert(0,sys.argv.pop(1));runpy.run_module('pip',run_name='__main__')", voice._runtime_directory().path_join("pip.whl"), "--version"], output, true)
    check(code == 0 and "".join(output).contains("pip " + voice._bundle().pip.version), "bundled pip runs without a venv or global packages")
    if "--install-recognition" in OS.get_cmdline_user_args():
        voice.install_recognition()
        var deadline = Time.get_ticks_msec() + 610000
        while voice.state == "installing" and Time.get_ticks_msec() < deadline: await process_frame
        check(voice.installed(), "actual recognition packages install using included Python: " + voice.status)
    if voice.installed() or "--require-recognition" in OS.get_cmdline_user_args():
        check(voice.installed(), "included runtime has installed recognition packages")
        output.clear()
        code = OS.execute(voice._python(), ["-I", "-c", "import sys;sys.path.insert(0,sys.argv[1]);import faster_whisper,ctranslate2,av,onnxruntime;print('recognition imports OK')", ProjectSettings.globalize_path(voice.ROOT.path_join("environment"))], output, true)
        check(code == 0 and "".join(output).contains("recognition imports OK"), "real native recognition dependencies import under included Python")
    check(voice._ensure_worker(), "production voice worker starts with included Python")
    var audio = AudioStreamWAV.new()
    audio.format = AudioStreamWAV.FORMAT_16_BITS
    audio.mix_rate = 16000
    var silence := PackedByteArray()
    silence.resize(32000)
    audio.data = silence
    var path = voice.directory.path_join("silence.wav")
    audio.save_to_wav(path)
    JsonStore.write_dict(voice.directory.path_join("request-included.json"), {"id":"included", "audio":path, "model":"base", "language":"auto"})
    var result_path = voice.directory.path_join("result-included.json")
    var until = Time.get_ticks_msec() + 10000
    while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < until: await process_frame
    var result = JsonStore.read_dict(result_path)
    check(result.get("ok", false) and result.get("text", "bad") == "" and not FileAccess.file_exists(path), "included Python completes real silent-audio IPC and removes temporary WAV without model download")
    var pid = voice.worker_pid
    voice._stop_worker()
    until = Time.get_ticks_msec() + 3000
    while OS.is_process_running(pid) and Time.get_ticks_msec() < until: await process_frame
    check(not OS.is_process_running(pid), "included worker stops without leaving a process behind")
    OS.set_environment("PATH", old_path)
    OS.set_environment("PYTHONPATH", old_pythonpath)
    voice.queue_free()
    quit(1 if failed else 0)
