export const hostTools = {
    blender: {description:'Blender CLI/bpy asset workflow. Read guide first. Python scripts require player approval unless the separate automatic Blender approval setting is enabled. Status is compact by default; details=true returns retained logs and paginated objects (offset, limit); stop cancels; inspect returns a PNG image for visual review.',properties:{action:{type:'string',enum:['guide','start','status','stop','inspect']},script:{type:'string'},blend:{type:'string'},render:{type:'string'},run_id:{type:'string'},path:{type:'string'},details:{type:'boolean'},offset:{type:'integer'},limit:{type:'integer'}}},
    reload_game: {description:'After successful headless testing of the current edits, request loading the game before handoff. Waits for player approval unless auto-approval is enabled.',properties:{}},
    read_runtime_log: {description:'Read live game errors and runtime logs.',properties:{since_sequence:{type:'integer'},limit:{type:'integer'}}},
    start_test_game: {description:'Start a separate Godot game test.',properties:{mode:{type:'string',enum:['headless','rendered']}}},
    read_test_log: {description:'Read separate game test status and logs.',properties:{run_id:{type:'string'},limit:{type:'integer'},since_sequence:{type:'integer'}}},
    stop_test_game: {description:'Stop a separate test gracefully.',properties:{run_id:{type:'string'}}},
    test_game_action: {description:'Inspect or interact with a test game; poll action IDs for results. Inspect returns exact game-relative paths (preserve @); depth 0-4 bounds recursion to 100 nodes. Screenshot requires an allowed rendered test.',properties:{run_id:{type:'string'},action:{type:'string',enum:['inspect','call','input','screenshot','poll']},action_id:{type:'string'},path:{type:'string'},depth:{type:'integer',minimum:0,maximum:4},properties:{type:'array',items:{type:'string'}},method:{type:'string'},arguments:{type:'array',items:{}},pressed:{type:'boolean'},input_action:{type:'string'}}},
    git_status: {description:'Show workspace Git status.',properties:{}},
    git_diff: {description:'Show workspace changes.',properties:{path:{type:'string'}}},
    git_log: {description:'Show workspace Git milestones.',properties:{limit:{type:'integer'}}},
    git_commit: {description:'Commit a coherent game milestone.',properties:{message:{type:'string'}}},
    delete_path: {description:'Delete a workspace path.',properties:{path:{type:'string'}}},
    move_path: {description:'Move a workspace path.',properties:{from:{type:'string'},to:{type:'string'}}},
  };

// Set by the host for each game runtime; inherited by native MCP children.
if (process.env.GAMESMITH_BLENDER_ENABLED === '0') delete hostTools.blender;

export function toolContent(result) {
    const {image_base64,mime_type,...metadata}=result;
    const content=[{type:'text',text:JSON.stringify(metadata)}];
    if(image_base64)content.push({type:'image',data:image_base64,mimeType:mime_type});
    return content;
}
