export const hostTools = {
    reload_game: {description:'After successful headless testing of the current edits, request loading the game before handoff. Waits for player approval unless auto-approval is enabled.',properties:{}},
    read_runtime_log: {description:'Read live game errors and runtime logs.',properties:{since_sequence:{type:'integer'},limit:{type:'integer'}}},
    start_test_game: {description:'Start a separate Godot game test.',properties:{mode:{type:'string',enum:['headless','rendered']}}},
    read_test_log: {description:'Read separate game test status and logs.',properties:{run_id:{type:'string'},limit:{type:'integer'},since_sequence:{type:'integer'}}},
    stop_test_game: {description:'Stop a separate test gracefully.',properties:{run_id:{type:'string'}}},
    test_game_action: {description:'Inspect or interact with a test game; poll action IDs for results.',properties:{run_id:{type:'string'},action:{type:'string',enum:['inspect','call','input','screenshot','poll']},action_id:{type:'string'},path:{type:'string'},properties:{type:'array',items:{type:'string'}},method:{type:'string'},arguments:{type:'array',items:{}},pressed:{type:'boolean'},input_action:{type:'string'}}},
    git_status: {description:'Show workspace Git status.',properties:{}},
    git_diff: {description:'Show workspace changes.',properties:{path:{type:'string'}}},
    git_log: {description:'Show workspace Git milestones.',properties:{limit:{type:'integer'}}},
    git_commit: {description:'Commit a coherent game milestone.',properties:{message:{type:'string'}}},
    delete_path: {description:'Delete a workspace path.',properties:{path:{type:'string'}}},
    move_path: {description:'Move a workspace path.',properties:{from:{type:'string'},to:{type:'string'}}},
  };
