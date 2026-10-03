#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";

const port = Number(process.env.GAMESMITH_PI_FAKE_PORT || "31339");
const logPath = process.env.GAMESMITH_PI_FAKE_LOG || "";
const expectedKey = process.env.GAMESMITH_PI_FAKE_KEY || "pi-test-key";
const states = new Map();

function state(model) {
  if (!states.has(model)) states.set(model, { calls: 0, lastResponseAt: 0, compacted: false });
  return states.get(model);
}
function appendLog(entry) {
  if (logPath) fs.appendFileSync(logPath, JSON.stringify(entry) + "\n");
}
function textOf(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((x) => x?.type === "text" ? String(x.text || "") : "").join("");
}
function hasText(messages, needle) {
  return messages.some((m) => textOf(m?.content).includes(needle));
}
function sse(res, model, delta, finishReason = null, usage = null) {
  const id = "pi-fake-" + Date.now();
  const created = Math.floor(Date.now() / 1000);
  const chunks = [];
  if (Object.keys(delta).length) {
    chunks.push({ id, object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta: { role: "assistant", ...delta }, finish_reason: null }] });
  }
  chunks.push({ id, object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta: {}, finish_reason: finishReason }] });
  if (usage) chunks.push({ id, object: "chat.completion.chunk", created, model, choices: [], usage });
  for (const chunk of chunks) res.write("data: " + JSON.stringify(chunk) + "\n\n");
  res.write("data: [DONE]\n\n");
  res.end();
  state(model).lastResponseAt = Date.now();
}
function tool(res, model, id, name, args, usage = null) {
  sse(res, model, {
    tool_calls: [{ index: 0, id, type: "function", function: { name, arguments: JSON.stringify(args) } }]
  }, "tool_calls", usage ?? { prompt_tokens: 500, completion_tokens: 40, total_tokens: 540 });
}
function answer(res, model, content, usage = null, reasoning = "") {
  const delta = { content };
  if (reasoning) delta.reasoning_content = reasoning;
  sse(res, model, delta, "stop", usage ?? { prompt_tokens: 700, completion_tokens: 30, total_tokens: 730 });
}
function summary(res, model) {
  state(model).compacted = true;
  answer(res, model, [
    "## Goal",
    "Continue building the Godot game.",
    "",
    "## Constraints & Preferences",
    "- Preserve the current working game.",
    "",
    "## Progress",
    "### Done",
    "- [x] Prior GameSmith work",
    "",
    "### In Progress",
    "- [ ] Continue the user's current game",
    "",
    "### Blocked",
    "- (none)",
    "",
    "## Key Decisions",
    "- **Workspace is source of truth**: inspect current files.",
    "",
    "## Next Steps",
    "1. Continue from the retained recent context.",
    "",
    "## Critical Context",
    "- main.gd"
  ].join("\n"), { prompt_tokens: 4000, completion_tokens: 300, total_tokens: 4300 });
}
function toolNames(body) {
  return (body.tools || []).map((t) => t?.function?.name).filter(Boolean);
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || !req.url?.endsWith("/v1/chat/completions")) {
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: { message: "not found" } }));
    return;
  }
  let raw = "";
  req.on("data", (c) => raw += c);
  req.on("end", () => {
    let body;
    try { body = JSON.parse(raw); } catch {
      res.writeHead(400, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: "bad json" } }));
      return;
    }

    const model = String(body.model || "");
    const st = state(model);
    st.calls += 1;
    const messages = Array.isArray(body.messages) ? body.messages : [];
    const tools = toolNames(body);
    const auth = String(req.headers.authorization || "");
    const now = Date.now();

    appendLog({
      time: now,
      path: req.url,
      model,
      call: st.calls,
      auth,
      reasoning_effort: body.reasoning_effort ?? null,
      stream: body.stream,
      tools,
      messages
    });

    if (auth !== "Bearer " + expectedKey) {
      res.writeHead(401, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: "bad fake test authorization" } }));
      return;
    }
    if (body.stream !== true) {
      res.writeHead(400, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: "Pi request was not streaming" } }));
      return;
    }

    if (model === "pi-gamesmith-retry" && st.calls <= 2) {
      res.writeHead(503, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: "transient fake provider failure" } }));
      return;
    }

    res.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      "connection": "close"
    });

    if (model === "pi-gamesmith-cancel" && st.calls === 1) {
      res.write(": waiting for cancellation\n\n");
      res.on("close", () => appendLog({ model, event: "cancelled-connection", time: Date.now() }));
      return;
    }
    if (model === "pi-gamesmith-cancel") {
      if (st.calls === 2) {
        tool(res, model, "diagnostics-read", "read_runtime_log", { severity: "error", raw: true, cursor: 0, limit: 2 });
        return;
      }
      answer(res, model, "Resumed after cancellation.");
      return;
    }

    // Pi native compaction requests do not expose the coding tool loadout.
    if (tools.length === 0) {
      summary(res, model);
      return;
    }

    if (model === "pi-gamesmith-e2e") {
      if (st.calls === 1) {
        tool(res, model, "write-main", "write", {
          path: "main.gd",
          content: "extends Node3D\n\nvar speed := 200.0\nvar frames := 0\n\nfunc _process(_delta):\n    frames += 1\n"
        }, { prompt_tokens: 1200, completion_tokens: 120, total_tokens: 1320 });
      } else if (st.calls === 2) {
        if (st.lastResponseAt && now - st.lastResponseAt < 35) answer(res, model, "RATE_DELAY_MISSING");
        else tool(res, model, "reload-1", "reload_game", {});
      } else if (st.calls === 3) {
        tool(res, model, "commit-1", "git_commit", { message: "milestone: build initial Pi game" });
      } else if (st.calls === 4) {
        answer(res, model, "Built the initial Pi-powered game.", { prompt_tokens: 1800, completion_tokens: 35, total_tokens: 1835 }, "I verified the game through GameSmith reload.");
      } else if (st.calls === 5) {
        tool(res, model, "read-main", "read", { path: "main.gd" });
      } else if (st.calls === 6) {
        tool(res, model, "edit-speed", "edit", {
          path: "main.gd",
          edits: [{ oldText: "var speed := 200.0", newText: "var speed := 400.0" }]
        });
      } else if (st.calls === 7) {
        tool(res, model, "reload-2", "reload_game", {});
      } else if (st.calls === 8) {
        tool(res, model, "commit-2", "git_commit", { message: "milestone: increase player speed" });
      } else if (st.calls === 9) {
        answer(res, model, "Player speed is now 400.");
      } else {
        if (!hasText(messages, "Build a tiny test game") || !hasText(messages, "make the player faster") || !hasText(messages, "Player speed is now 400.")) answer(res, model, "HISTORY_MISSING");
        else answer(res, model, "I remember both requests; the current speed is 400.");
      }
      return;
    }

    if (model === "pi-gamesmith-false-done") {
      if (st.calls === 1) {
        answer(res, model, "Done.");
      } else if (st.calls === 2) {
        if (!hasText(messages, "GameSmith verification rejected completion")) answer(res, model, "VERIFIER_CONTEXT_MISSING");
        else tool(res, model, "false-write", "write", { path: "main.gd", content: "extends Node\n\nvar built_by_pi := true\n" });
      } else if (st.calls === 3) {
        tool(res, model, "false-reload", "reload_game", {});
      } else {
        answer(res, model, "Created and reloaded the game after verification.");
      }
      return;
    }

    if (model === "pi-gamesmith-retry") {
      answer(res, model, "Recovered after transient provider failures.");
      return;
    }

    if (model === "pi-gamesmith-runaway") {
      tool(res, model, "loop-" + st.calls, "read", { path: "main.gd" });
      return;
    }

    if (model.startsWith("pi-gamesmith-compact")) {
      if (!st.compacted) {
        answer(res, model, "Stored lots of context.", { prompt_tokens: 7000, completion_tokens: 20, total_tokens: 7020 });
      } else {
        const sawSummary = messages.some((m) => {
          const value = textOf(m?.content);
          return value.includes("The conversation history before this point was compacted") || value.includes("## Goal");
        });
        answer(res, model, sawSummary ? "Continued from Pi's compacted session." : "COMPACTION_SUMMARY_MISSING", { prompt_tokens: 1600, completion_tokens: 20, total_tokens: 1620 });
      }
      return;
    }

    answer(res, model, "Unknown fake Pi model.");
  });
});

server.listen(port, "127.0.0.1", () => process.stdout.write("READY " + server.address().port + "\n"));
