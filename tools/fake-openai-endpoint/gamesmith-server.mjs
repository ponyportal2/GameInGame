import http from 'node:http';
import fs from 'node:fs';

const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || '3017');
const logPath = process.env.GAMESMITH_FAKE_LOG || '';
const counts = new Map();

function appendLog(entry) {
  if (!logPath) return;
  fs.appendFileSync(logPath, JSON.stringify(entry) + '\n');
}

function responseMessage(model, message, status = 200) {
  return {
    status,
    body: {
      id: `chatcmpl-gamesmith-${Date.now()}`,
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [{ index: 0, message, finish_reason: message.tool_calls ? 'tool_calls' : 'stop' }],
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
    },
  };
}

function toolCall(id, name, args) {
  return { id, type: 'function', function: { name, arguments: typeof args === 'string' ? args : JSON.stringify(args) } };
}

const initialGame = `extends Node3D
var fall_speed = 1.0
var block: MeshInstance3D
func _ready():
    var camera = Camera3D.new()
    camera.position = Vector3(0, 3, 8)
    camera.look_at_from_position(camera.position, Vector3.ZERO)
    add_child(camera)
    var light = DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -30, 0)
    add_child(light)
    block = MeshInstance3D.new()
    var mesh = BoxMesh.new()
    mesh.size = Vector3(1, 1, 1)
    block.mesh = mesh
    block.position = Vector3(0, 2, 0)
    add_child(block)
func _process(delta):
    block.position.y -= fall_speed * delta
    if block.position.y < -2.0:
        block.position.y = 2.0
`;

function scriptedReply(body) {
  const model = String(body.model || '');
  const n = counts.get(model) || 0;
  counts.set(model, n + 1);
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const tools = Array.isArray(body.tools) ? body.tools : [];
  const lastUser = [...messages].reverse().find((m) => m && m.role === 'user');
  const lastUserText = typeof lastUser?.content === 'string' ? lastUser.content : '';

  if (model === 'gamesmith-noop-create' || model === 'gamesmith-ui-create') {
    if (body.reasoning_effort !== 'high') return { status: 400, body: { error: { message: 'reasoning_effort high missing' } } };
    const names = new Set(tools.map((t) => t?.function?.name));
    if (!names.has('write_file') || !names.has('reload_game')) return { status: 400, body: { error: { message: 'GameSmith tool schema missing' } } };
    if (n === 0) return responseMessage(model, { role: 'assistant', content: 'Done.' });
    if (n === 1) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [
      toolCall('create-main', 'write_file', { path: 'main.gd', content: initialGame }),
      toolCall('create-commit', 'git_commit', { message: 'Create fake-endpoint 3D game' }),
      toolCall('create-reload', 'reload_game', {}),
    ] });
    return responseMessage(model, { role: 'assistant', content: 'Built and loaded the 3D falling-block game.' });
  }

  if (model === 'gamesmith-edit-speed') {
    if (n === 0) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [toolCall('edit-read', 'read_file', { path: 'main.gd' })] });
    if (n === 1) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [
      toolCall('edit-patch', 'patch_file', { path: 'main.gd', old_text: 'var fall_speed = 1.0', new_text: 'var fall_speed = 3.0' }),
      toolCall('edit-commit', 'git_commit', { message: 'Increase fall speed' }),
    ] });
    if (n === 2) return responseMessage(model, { role: 'assistant', content: 'Done.' });
    if (n === 3) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [toolCall('edit-reload', 'reload_game', {})] });
    return responseMessage(model, { role: 'assistant', content: 'Fall speed increased and the updated game is running.' });
  }

  if (model === 'gamesmith-reload-repair') {
    if (n === 0) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [
      toolCall('repair-break', 'write_file', { path: 'main.gd', content: 'extends Node3D\nfunc broken(:\n' }),
      toolCall('repair-reload-bad', 'reload_game', {}),
    ] });
    if (n === 1) return responseMessage(model, { role: 'assistant', content: 'Done.' });
    if (n === 2) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [
      toolCall('repair-fix', 'write_file', { path: 'main.gd', content: initialGame.replace('var fall_speed = 1.0', 'var fall_speed = 4.0') }),
      toolCall('repair-reload-good', 'reload_game', {}),
    ] });
    return responseMessage(model, { role: 'assistant', content: 'Recovered from the failed load and launched the repaired game.' });
  }

  if (model === 'gamesmith-malformed-tool') {
    if (n === 0) return responseMessage(model, { role: 'assistant', content: null, tool_calls: [toolCall('malformed', 'git_commit', '{ definitely not json')] });
    return responseMessage(model, { role: 'assistant', content: 'Malformed tool arguments were surfaced and nothing unsafe ran.' });
  }

  if (model === 'gamesmith-step-limit') {
    return responseMessage(model, { role: 'assistant', content: null, tool_calls: [toolCall(`status-${n}`, 'git_status', {})] });
  }

  if (model === 'gamesmith-invalid-json') {
    return { status: 200, raw: '{not valid json' };
  }

  if (model === 'gamesmith-http-500') {
    return { status: 500, body: { error: { message: 'simulated HTTP 500' } } };
  }

  if (model === 'gamesmith-history') {
    if (lastUserText === 'Remember cyan') return responseMessage(model, { role: 'assistant', content: 'Cyan remembered.' });
    if (lastUserText === 'What color?') {
      const sawUser = messages.some((m) => m?.role === 'user' && m?.content === 'Remember cyan');
      const sawAssistant = messages.some((m) => m?.role === 'assistant' && m?.content === 'Cyan remembered.');
      if (!sawUser || !sawAssistant) return { status: 409, body: { error: { message: 'durable prior conversation missing after restart' } } };
      return responseMessage(model, { role: 'assistant', content: 'Cyan.' });
    }
    return responseMessage(model, { role: 'assistant', content: 'History scenario ready.' });
  }

  return responseMessage(model, { role: 'assistant', content: `Unhandled test model ${model}` });
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }
  if (req.method !== 'POST' || req.url !== '/v1/chat/completions') {
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: 'not found' } }));
    return;
  }
  let raw = '';
  req.setEncoding('utf8');
  req.on('data', (chunk) => { raw += chunk; });
  req.on('end', () => {
    try {
      const body = JSON.parse(raw);
      appendLog({ at: Date.now(), headers: req.headers, body });
      const reply = scriptedReply(body);
      res.writeHead(reply.status, { 'content-type': 'application/json' });
      res.end(reply.raw ?? JSON.stringify(reply.body));
    } catch (err) {
      res.writeHead(400, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: String(err) } }));
    }
  });
});

server.listen(port, host, () => {
  console.log(`GameSmith fake /v1 server listening at http://${host}:${port}/v1`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
