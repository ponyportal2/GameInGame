const runtimeHandle={type:'object',properties:{path:{type:'string',maxLength:1024},instance_id:{type:'string'},game_generation:{type:'string'}},required:['path','instance_id','game_generation'],additionalProperties:false};
export const hostTools = {
    inspect_runtime: {description:'Inspect the player\'s live active_game subtree, not a separate test. Paths are relative to its root (.). Returns identity handles, available property names/types and only requested values. Filter by engine class, exact script path or group. Bounded traversal; truncated means some nodes were omitted. No expression evaluation.',properties:{root:{type:'string',maxLength:1024},depth:{type:'integer',minimum:0,maximum:8},limit:{type:'integer',minimum:1,maximum:100},class:{type:'string'},script:{type:'string'},group:{type:'string'},properties:{type:'array',items:{type:'string'},maxItems:16}}},
    set_properties: {description:'Temporarily patch 1..100 explicit live node handles from inspect_runtime; stale identities fail. Also edit persistent source. Supports bool, exact JSON integers, finite numbers, strings (1024 chars), and tagged {type:"Vector2",x,y}, {type:"Vector3",x,y,z}, {type:"Color",r,g,b,a}. No objects, arrays, expressions or node replacement. Validates each target before writing; setters can cause partial changes. Results include per-target applied names, immediate readback and errors; values may change on later frames. Successful parameter patches need no reload.',properties:{targets:{type:'array',items:runtimeHandle,minItems:1,maxItems:100},values:{type:'object',minProperties:1,maxProperties:16,additionalProperties:{}}},required:['targets','values']},
    generate_image: {description:'Generate a game image through the native image harness selected in Settings > Images. No vendor fallback. Only one image job can run at a time. Start returns job_id; poll status until completed or failed; stop cancels. Keep the workspace unchanged until completion. Only a decoded, validated PNG is published. Relative target_path defaults to assets/generated/image.png. Reference images must be workspace-relative (up to four). Transparent output is verified. capabilities reports installed/authenticated candidates, not guaranteed account quota.',properties:{action:{type:'string',enum:['start','status','stop','capabilities']},prompt:{type:'string'},target_path:{type:'string'},reference_paths:{type:'array',items:{type:'string'},maxItems:4},purpose:{type:'string'},transparent:{type:'boolean'},job_id:{type:'string'}}},
    blender: {description:'Blender CLI/bpy asset workflow. Read guide first. Python scripts require player approval unless the separate automatic Blender approval setting is enabled. Status is compact by default; details=true returns retained logs and paginated objects (offset, limit); stop cancels; inspect returns a PNG image for visual review.',properties:{action:{type:'string',enum:['guide','start','status','stop','inspect']},script:{type:'string'},blend:{type:'string'},render:{type:'string'},run_id:{type:'string'},path:{type:'string'},details:{type:'boolean'},offset:{type:'integer'},limit:{type:'integer'}}},
    reload_game: {description:'Load or fully reload the game after successful headless testing. Use when a live property patch is insufficient; successful parameter patches need no reload. Waits for player approval unless auto-approval is enabled.',properties:{}},
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
