import {rgSearch} from './rg-search.mjs';
const runtimeHandle={type:'object',properties:{path:{type:'string',maxLength:1024},instance_id:{type:'string'},game_generation:{type:'string'}},required:['path','instance_id','game_generation'],additionalProperties:false};
export const hostTools = {
    add_runtime_child: {description:'Add a NEW scripted child to an existing live node without reloading or replacing its script. Waits for player consent (Allow Child Code / Shift+F5) unless the independent Automatically approve live child additions setting is enabled; reload auto-approval does not authorize this operation. Mandatory isolated headless preflight boots the current workspace, finds explicit candidate_path, checks parent class/script, inserts AFTER parent ready, observes at least 4 process/3 physics ticks and clean shutdown. Requires fresh parent handle from inspect_runtime. Script declares the Node type; no required _init arguments. properties use the scalar/tagged value types of set_properties and are assigned before add_child. Duplicate names, missing/mismatched candidate parents, changed code, stale live handles or preflight errors reject before the live attempt. Preflight success is not rollback or identical-state proof; live initialization can fail after side effects. Returns live_attempted, actual added handle and bounded preflight evidence. Temporary until wired into persistent source. Create the component first; test/inject before wiring it into startup, then separately test persistent startup. Does not stack scripts on an existing object.',properties:{parent:runtimeHandle,candidate_path:{type:'string',maxLength:1024},name:{type:'string',maxLength:64},script_path:{type:'string',maxLength:1024},properties:{type:'object',maxProperties:16,additionalProperties:{}}},required:['parent','candidate_path','name','script_path']},
    remove_runtime_child: {description:'Remove only a node introduced by add_runtime_child, using its returned or freshly inspected handle. Deferred tree mutation; rejects stale handles and original game nodes. Does not undo previous side effects, signals/registrations stored elsewhere, source changes or resource edits. No reload.',properties:{target:runtimeHandle},required:['target']},
    rg_search: {description:'Search with system rg, no shell. target=source returns workspace file/line matches; target=runtime searches one compact inspection page and returns complete observed node records/handles. Runtime default depth is 3; zero matches with depth_limit is incomplete: increase depth or narrow root. Use root (not path), class/group/properties to focus runtime search, including large hordes; follow runtime_next_offset for another inspection page, offset/limit for matches in this page. Reset both offsets to 0 when changing the query; empty regex pages may still have runtime_next_offset. Missing rg is an explicit error. No arbitrary flags, files outside the workspace, or stored-output paths.',properties:{target:{type:'string',enum:['source','runtime']},pattern:{type:'string',maxLength:1024},path:{type:'string'},glob:{type:'string'},case_sensitive:{type:'boolean'},offset:{type:'integer',minimum:0,maximum:10000},limit:{type:'integer',minimum:1,maximum:100},root:{type:'string'},depth:{type:'integer',minimum:0,maximum:8},class:{type:'string'},script:{type:'string'},group:{type:'string'},properties:{type:'array',items:{type:'string'},maxItems:16},runtime_offset:{type:'integer',minimum:0,maximum:1000}},required:['target','pattern']},
    inspect_runtime: {description:'Inspect the player\'s live active_game subtree, not a separate test. Use root (not path) to select a node; unknown arguments are rejected. Paths are relative to its root (.). Returns compact identity handles, class and requested values. discover_properties=true adds metadata/property descriptors (default depth 0, limit 1; maximum 3 nodes per discovery page). Filter by engine class, exact script path or group. Use offset/limit for matching-node pages while has_more; next_offset continues result_limit only. depth_limit needs greater depth; traversal_limit needs narrower root. Live-tree pages can shift: deduplicate identities and restart if game_generation changes. Never infer handles. No expression evaluation.',properties:{root:{type:'string',maxLength:1024},depth:{type:'integer',minimum:0,maximum:8},limit:{type:'integer',minimum:1,maximum:100},offset:{type:'integer',minimum:0,maximum:1000},discover_properties:{type:'boolean'},class:{type:'string'},script:{type:'string'},group:{type:'string'},properties:{type:'array',items:{type:'string'},maxItems:16}}},
    set_properties: {description:'Temporarily patch 1..100 explicit live node handles from inspect_runtime; stale identities fail. Inspect fresh values/handles at the start of a later adjustment. Shared values apply identically to every target; use separate calls for different desired values. Copy handles verbatim; never infer IDs. Edit persistent source for durable changes; explicit live-only experiments need no source edits. Supports bool, exact JSON integers, finite numbers, strings (1024 chars), and tagged {type:"Vector2",x,y}, {type:"Vector3",x,y,z}, {type:"Color",r,g,b,a}. No objects, arrays, expressions or node replacement. Validates each target before writing; setters can cause partial changes. Results include per-target applied names, immediate readback and errors; values may change on later frames. Oversized possible outcomes are rejected before writes (writes_started:false); split targets or properties. Accepted batches return every per-target outcome. Unexpected oversized setter readback/path is an explicit post-write error with applied names; inspect again. Successful parameter patches need no reload.',properties:{targets:{type:'array',items:runtimeHandle,minItems:1,maxItems:100},values:{type:'object',minProperties:1,maxProperties:16,additionalProperties:{}}},required:['targets','values']},
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

export const OUTPUT_BYTES = 50 * 1024;
export const OUTPUT_LINES = 2000;
function logicalLines(value) {
    // Count JSON structure and decoded content lines, even though transport JSON escapes them.
    let extra=0;
    const visit=v=>{if(typeof v==='string')extra+=(v.match(/\n/g)||[]).length;
      else if(v && typeof v==='object')for(const item of Object.values(v))visit(item);};
    visit(value);
    return JSON.stringify(value,null,2).split('\n').length+extra;
}
export function boundedToolResult(result) {
    const {image_base64,mime_type,...metadata}=result;
    const text=JSON.stringify(metadata),bytes=Buffer.byteLength(text),lines=logicalLines(metadata);
    if(bytes<=OUTPUT_BYTES && lines<=OUTPUT_LINES)return result;
    const summary={};
    for(const key of ['ok','matched','changed','failed','temporary','game_generation','delivery_id'])
      if(['boolean','number'].includes(typeof metadata[key]) || typeof metadata[key]==='string' && metadata[key].length<=128)summary[key]=metadata[key];
    let preview='',size=0,count=1;
    for(const ch of JSON.stringify(metadata,null,2).replaceAll('\\n','\n')) {
      const n=Buffer.byteLength(ch);
      if(size+n>4096 || ch==='\n' && count>=100)break;
      preview+=ch;size+=n;if(ch==='\n')count++;
    }
    return {...summary,output_truncated:true,original_bytes:bytes,original_lines:lines,
      truncated_by:[...(bytes>OUTPUT_BYTES?['byte_limit']:[]),...(lines>OUTPUT_LINES?['line_limit']:[])],
      preview,recovery:'Preview is incomplete text, not complete records or handles. Narrow filters/path/properties and use pagination, or rg_search on source/runtime. Do not blindly repeat a mutation: it may already have applied.',
      ...(image_base64?{image_base64,mime_type}:{})};
}
export async function executeHostTool(name,args,{workspace,callHost,signal}={}) {
    const result=name==='rg_search' ? await rgSearch(args,{workspace,callHost,signal}) : await callHost(name,args,signal);
    return boundedToolResult(result);
}
export function toolContent(result) {
    const {image_base64,mime_type,...metadata}=boundedToolResult(result);
    const content=[{type:'text',text:JSON.stringify(metadata)}];
    if(image_base64)content.push({type:'image',data:image_base64,mimeType:mime_type});
    return content;
}
