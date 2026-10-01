extends SceneTree

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const AgentControllerScript = preload("res://src/agent/agent_controller.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")

const GAME_NAME = "HTTP Restart History"

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var phase = OS.get_environment("GAMESMITH_RESTART_PHASE")
    var base_url = OS.get_environment("GAMESMITH_FAKE_BASE")
    if phase not in ["seed", "verify"] or base_url == "":
        push_error("GAMESMITH_RESTART_PHASE=seed|verify and GAMESMITH_FAKE_BASE are required")
        quit(2); return
    var store = WorkspaceStoreScript.new(); store.ensure()
    var meta = MetadataStoreScript.new(); meta.ensure()
    meta.save_global_settings({"provider": "custom", "model": "gamesmith-history", "custom_base_url": base_url, "reasoning_effort": ""})
    if phase == "seed":
        if GAME_NAME in store.list_games(): store.delete_game(GAME_NAME)
        var created = store.create_game(GAME_NAME)
        if not created.get("ok", false):
            push_error("Could not create restart test workspace"); quit(1); return
        var ok = await _send(GAME_NAME, created.path, "Remember cyan")
        if not ok:
            push_error("Seed conversation failed"); quit(1); return
        print("PASS: persisted first HTTP conversation in process 1")
        quit(0); return

    if not GAME_NAME in store.list_games():
        push_error("Restart test workspace did not survive process restart"); quit(1); return
    var ok = await _send(GAME_NAME, store.game_path(GAME_NAME), "What color?")
    if not ok:
        push_error("Provider rejected process-2 history; durable conversation was not replayed"); quit(1); return
    var transcript = TranscriptStoreScript.new().read_all(GAME_NAME)
    if transcript.is_empty() or str(transcript[-1].content) != "Cyan.":
        push_error("Process-2 transcript did not contain the history-aware response"); quit(1); return
    print("PASS: process 2 replayed durable HTTP conversation to provider")
    store.delete_game(GAME_NAME)
    quit(0)

func _send(name: String, path: String, text: String) -> bool:
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(path, runner))
    agent.send_player_request(text)
    var ok = await agent.finished
    agent.queue_free(); runner.queue_free(); await process_frame
    return bool(ok)
