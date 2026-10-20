import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { workspacePath } from "./workspace-paths.mjs";
import { resolveModelCapabilities, compactionReserveTokens } from "./model-capabilities.mjs";
import { DiagnosticDelivery } from "./diagnostic-delivery.mjs";
import { EmptyResponseRetry } from "./empty-response-retry.mjs";
import { hostTools, executeHostTool, boundedToolResult } from "./host-tools.mjs";

const execFileAsync = promisify(execFile);
const bridgeDir = process.env.GAMESMITH_HOST_BRIDGE_DIR || "";
const legacyTranscriptPath = process.env.GAMESMITH_LEGACY_TRANSCRIPT || "";
const delayMs = Math.max(0, Number(process.env.GAMESMITH_LLM_DELAY_MS || "0"));

function textResult(text: string, details: unknown = undefined) {
  const bounded = boundedToolResult({ok:true,text});
  return { content: [{ type: "text" as const, text: bounded.output_truncated ? JSON.stringify(bounded) : text }], details };
}

async function runGit(cwd: string, args: string[]) {
  try {
    const { stdout, stderr } = await execFileAsync("git", args, { cwd, maxBuffer: 1024 * 1024 });
    return { ok: true, output: (stdout + stderr).trim() };
  } catch (error: any) {
    return { ok: false, output: String(error?.stderr || error?.stdout || error?.message || error) };
  }
}

async function rawCallHost(toolCallId: string, command: string, args: unknown, signal?: AbortSignal) {
  if (!bridgeDir) throw new Error("GameSmith host bridge is not configured.");
  await mkdir(bridgeDir, { recursive: true });
  const id = `${Date.now()}-${toolCallId.replace(/[^a-zA-Z0-9_-]/g, "_")}`;
  const requestPath = join(bridgeDir, `request-${id}.json`);
  const responsePath = join(bridgeDir, `response-${id}.json`);
  await writeFile(requestPath + ".tmp", JSON.stringify({ id, command, args }), "utf8");
  await rename(requestPath + ".tmp", requestPath);

  while (true) {
    if (signal?.aborted) throw new Error(`GameSmith host tool ${command} was aborted.`);
    let result;
    try {
      const raw = await readFile(responsePath, "utf8");
      await rm(responsePath, { force: true });
      result = JSON.parse(raw);
    } catch {
      // Host has not answered yet.
    }
    if (result !== undefined) {
      return result;
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 25));
  }
}

async function callHost(toolCallId: string, command: string, args: unknown, signal?: AbortSignal) {
  if (!Object.hasOwn(hostTools, command)) return rawCallHost(toolCallId, command, args, signal);
  return executeHostTool(command, args, {workspace: process.cwd(), signal,
    callHost: (name, input) => rawCallHost(toolCallId, name, input, signal)});
}

export default async function (pi: ExtensionAPI) {
  const emptyResponseRetry = new EmptyResponseRetry();
  pi.on("before_agent_start", () => { emptyResponseRetry.reset(); });
  pi.on("message_end", event => { emptyResponseRetry.recordSuccess(event.message); });
  pi.on("agent_before_settle", async (event) => {
    const retry = emptyResponseRetry.prepare(event);
    if (!retry) return;
    await callHost("provider-retry", "provider_retry", {
      attempt: retry.attempt, maxRetries: retry.maxRetries,
      error: "Provider returned an empty response",
    });
    await new Promise(resolve => setTimeout(resolve, retry.delayMs));
    return retry.result;
  });
  const delivery = new DiagnosticDelivery();
  const confirmDelivery = (ctx: any) => delivery.confirm(ctx.sessionManager,
    (id: string) => callHost("diagnostic-receipt", "diagnostic_delivery", { delivery_id: id }));
  if (process.env.GAMESMITH_MODEL_PROVIDER !== "openai_subscription") {
    let lookup = () => undefined;
    try {
      const catalog = await import("@earendil-works/pi-ai/providers/all");
      lookup = (provider, id) => catalog.getBuiltinModel(provider, id);
    } catch {
      // An unavailable catalog leaves explicit conservative budgets.
    }
    const config = JSON.parse(await readFile(join(process.env.PI_CODING_AGENT_DIR!, "models.json"), "utf8"));
    const provider = config.providers.gamesmith;
    const model = provider.models[0];
    Object.assign(model, await resolveModelCapabilities(process.env.GAMESMITH_MODEL_PROVIDER || "", model.id, lookup, { baseUrl: provider.baseUrl, cachePath: process.env.GAMESMITH_MODEL_CACHE_PATH }));
    model.input ??= ["text"];
    model.cost ??= { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
    pi.registerProvider("gamesmith", provider);
  }
  pi.on("tool_call", async (event, ctx) => {
    const pathKeys: Record<string, string[]> = {
      read: ["path"],
      edit: ["path"],
      write: ["path"],
      grep: ["path"],
      find: ["path"],
      ls: ["path"],
      delete_path: ["path"],
      move_path: ["from", "to"],
    };
    for (const key of pathKeys[event.toolName] || []) {
      const value = (event.input as any)?.[key];
      if (typeof value !== "string") continue;
      try {
        await workspacePath(ctx.cwd, value, { destructive: ["edit", "write", "delete_path", "move_path"].includes(event.toolName) });
      } catch (error) {
        return { block: true, reason: String(error) };
      }
    }
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    const diagnostics = await callHost("diagnostic-notice", "diagnostic_notice", {});
    if (diagnostics?.notice) {
      delivery.retain(diagnostics, ctx.sessionManager, { customType: "gamesmith-diagnostics" }, String(diagnostics.notice));
      return { message: { customType: "gamesmith-diagnostics", content: String(diagnostics.notice), display: false } };
    }
  });

  // Native automatic compaction preserves the agent run and retries interrupted
  // work itself. Manual RPC compaction aborts it, so never use that mid-turn.
  let autoCompactionFailed = false;
  pi.on("before_agent_start", () => { autoCompactionFailed = false; });
  pi.on("session_compact_failed", (event) => { if (!event.aborted && !/nothing to compact|session too small/i.test(event.errorMessage ?? "")) autoCompactionFailed = true; });
  pi.on("session_before_compact", async (event, ctx) => {
    if (event.reason !== "manual") {
      const status = await callHost("compaction-policy", "compaction_status", {}, event.signal);
      if (autoCompactionFailed || status.blocked) return { cancel: true };
    }
    // The initial settings must fit unknown models. Once selected, size this
    // preparation's summary budget from the actual model, for manual and native
    // automatic compaction alike. Pi still caps output at model.maxTokens.
    event.preparation.settings = { ...event.preparation.settings, reserveTokens: compactionReserveTokens(ctx.model) };
  });

  let lastProviderResponseAt = 0;

  pi.on("before_provider_request", async (_event, ctx) => {
    await confirmDelivery(ctx);
    if (delayMs <= 0 || lastProviderResponseAt <= 0) return;
    const remaining = delayMs - (Date.now() - lastProviderResponseAt);
    if (remaining > 0) {
      await new Promise((resolvePromise) => setTimeout(resolvePromise, remaining));
    }
  });

  pi.on("after_provider_response", () => {
    lastProviderResponseAt = Date.now();
  });

  pi.on("agent_before_settle", async (_event, ctx) => {
    await confirmDelivery(ctx);
  });

  pi.on("session_start", async (_event, ctx) => {
    if (!legacyTranscriptPath) return;
    const existing = ctx.sessionManager.getEntries();
    const hasMeaningfulHistory = existing.some((entry) => {
      const type = String(entry.type || "");
      if (type === "model_change" || type === "thinking_level_change" || type === "session_info") return false;
      if (type === "message") {
        const message = (entry as { message?: { role?: string } }).message;
        if (message?.role === "system") return false;
      }
      return true;
    });
    if (hasMeaningfulHistory) return;
    try {
      const raw = await readFile(legacyTranscriptPath, "utf8");
      const lines = raw.split(/\r?\n/).filter(Boolean);
      const dialogue: string[] = [];
      for (const line of lines) {
        const entry = JSON.parse(line);
        if (entry?.role === "user" || entry?.role === "assistant") {
          dialogue.push(`${String(entry.role).toUpperCase()}: ${String(entry.content || "")}`);
        }
      }
      if (dialogue.length > 0) {
        pi.sendMessage({
          customType: "gamesmith-legacy-dialogue",
          content: "Legacy GameSmith dialogue imported from before the Pi runtime migration:\n\n" + dialogue.join("\n\n"),
          display: false,
        }, { triggerTurn: false });
      }
    } catch {
      // No readable legacy transcript: nothing to migrate.
    }
  });

  pi.registerTool({
    name: "delete_path",
    label: "delete_path",
    description: "Delete a file or directory inside the current game workspace.",
    promptSnippet: "delete_path: Delete a workspace path",
    parameters: Type.Object({ path: Type.String({ description: "Relative workspace path" }) }),
    annotations: { destructiveHint: true, openWorldHint: false },
    executionMode: "sequential",
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const path = await workspacePath(ctx.cwd, params.path, { destructive: true });
      await rm(path, { recursive: true, force: false });
      return textResult(`Deleted ${params.path}`);
    },
  });

  pi.registerTool({
    name: "move_path",
    label: "move_path",
    description: "Move or rename a file/directory inside the current game workspace.",
    promptSnippet: "move_path: Move or rename a workspace path",
    parameters: Type.Object({
      from: Type.String({ description: "Existing relative path" }),
      to: Type.String({ description: "Destination relative path" }),
    }),
    annotations: { destructiveHint: true, openWorldHint: false },
    executionMode: "sequential",
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const from = await workspacePath(ctx.cwd, params.from, { destructive: true });
      const to = await workspacePath(ctx.cwd, params.to, { destructive: true });
      await mkdir(dirname(to), { recursive: true });
      await rename(from, to);
      return textResult(`Moved ${params.from} -> ${params.to}`);
    },
  });

  for (const definition of [
    {
      name: "git_status",
      label: "git_status",
      description: "Show Git branch and working tree status for the current game.",
      args: ["status", "--short", "--branch"],
    },
    {
      name: "git_diff",
      label: "git_diff",
      description: "Show the current unstaged Git diff for the current game.",
      args: ["diff", "--", "."],
    },
  ]) {
    pi.registerTool({
      ...definition,
      promptSnippet: `${definition.name}: ${definition.description}`,
      parameters: Type.Object({}),
      annotations: { readOnlyHint: true, openWorldHint: false },
      async execute(_id, _params, _signal, _onUpdate, ctx) {
        const result = await runGit(ctx.cwd, definition.args);
        if (!result.ok) throw new Error(result.output || "Git command failed.");
        return textResult(result.output || "(no output)");
      },
    });
  }

  pi.registerTool({
    name: "git_log",
    label: "git_log",
    description: "Show recent Git commits for the current game.",
    promptSnippet: "git_log: Show recent game commits",
    parameters: Type.Object({ limit: Type.Optional(Type.Number({ minimum: 1, maximum: 50 })) }),
    annotations: { readOnlyHint: true, openWorldHint: false },
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const limit = Math.max(1, Math.min(50, Math.floor(params.limit || 10)));
      const result = await runGit(ctx.cwd, ["log", `-${limit}`, "--oneline", "--decorate"]);
      if (!result.ok) throw new Error(result.output || "Git log failed.");
      return textResult(result.output || "(no commits)");
    },
  });

  pi.registerTool({
    name: "git_commit",
    label: "git_commit",
    description: "Stage all current game changes and create one Git commit.",
    promptSnippet: "git_commit: Save a coherent game milestone",
    parameters: Type.Object({ message: Type.String({ description: "Commit message" }) }),
    annotations: { destructiveHint: false, openWorldHint: false },
    executionMode: "sequential",
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const status = await runGit(ctx.cwd, ["status", "--porcelain"]);
      if (!status.ok) throw new Error(status.output || "Git status failed.");
      if (!status.output.trim()) return textResult("No changes to commit.");
      const add = await runGit(ctx.cwd, ["add", "-A"]);
      if (!add.ok) throw new Error(add.output || "Git add failed.");
      const commit = await runGit(ctx.cwd, ["-c", "user.name=GameSmith", "-c", "user.email=gamesmith@local.invalid", "commit", "-m", params.message]);
      if (!commit.ok) throw new Error(commit.output || "Git commit failed.");
      return textResult(commit.output || "Committed.");
    },
  });

  for (const tool of [
    ...["inspect_runtime", "set_properties", "rg_search", "add_runtime_child", "remove_runtime_child"].map(name => ({ name, description: hostTools[name].description, parameters: Type.Unsafe({type: "object", properties: hostTools[name].properties, required: hostTools[name].required || [], additionalProperties: false}) })),
    { name: "generate_image", description: "Generate an image using the native harness selected in Settings > Images. Only one image job can run at a time. Start returns job_id; poll status until completed/failed; stop cancels. No vendor fallback. Keep workspace unchanged until completion. target_path must be relative PNG (default assets/generated/image.png); references are workspace-relative. Only a validated image is published.", parameters: Type.Object({ action: Type.Optional(Type.Union([Type.Literal("start"), Type.Literal("status"), Type.Literal("stop"), Type.Literal("capabilities")])), prompt: Type.Optional(Type.String()), target_path: Type.Optional(Type.String()), reference_paths: Type.Optional(Type.Array(Type.String(), {maxItems: 4})), purpose: Type.Optional(Type.String()), transparent: Type.Optional(Type.Boolean()), job_id: Type.Optional(Type.String()) }) },
    { name: "blender", description: "Blender CLI/bpy workflow. Read action=guide first. Start script/blend with optional PNG render, poll compact status (details=true for logs and paginated objects via offset/limit), stop, or inspect a PNG image. Python approval follows the separate Blender setting.", parameters: Type.Object({ action: Type.Union([Type.Literal("guide"), Type.Literal("start"), Type.Literal("status"), Type.Literal("stop"), Type.Literal("inspect")]), script: Type.Optional(Type.String()), blend: Type.Optional(Type.String()), render: Type.Optional(Type.String()), run_id: Type.Optional(Type.String()), path: Type.Optional(Type.String()), details: Type.Optional(Type.Boolean()), offset: Type.Optional(Type.Integer()), limit: Type.Optional(Type.Integer()) }) },
    { name: "start_test_game", description: "Start a separate Godot test process for the current workspace. Headless is always available; rendered requires user Settings permission. Returns immediately with run_id; read_test_log reports startup progress. Does not interrupt the player or promote the working snapshot. One test at a time.", parameters: Type.Object({ mode: Type.Optional(Type.Union([Type.Literal("headless"), Type.Literal("rendered")])) }) },
    { name: "read_test_log", description: "Read separate test-process status, shared runtime diagnostics and raw engine/stdout/stderr tails. Includes mode, exit code, graceful/forced stop and reason. Use cursor/raw/severity for diagnostics pagination. Omit run_id to list recent runs and current rendered permission. Completed-run logs survive reopening.", parameters: Type.Object({ run_id: Type.Optional(Type.String()), cursor: Type.Optional(Type.Integer({ minimum: 0 })), raw: Type.Optional(Type.Boolean()), severity: Type.Optional(Type.Union([Type.Literal("error"), Type.Literal("warning"), Type.Literal("info")])), limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100 })) }) },
    { name: "stop_test_game", description: "Stop a separate test process. Requests graceful Godot shutdown, then forcibly terminates it after a short shutdown grace period if needed. Waits for the process exit and reports how it stopped; forced termination does not prove a hang.", parameters: Type.Object({ run_id: Type.String() }) },
    { name: "test_game_action", description: hostTools.test_game_action.description, parameters: Type.Unsafe({type: "object", properties: hostTools.test_game_action.properties, required: ["run_id", "action"], additionalProperties: false}) },
  ]) {
    if (tool.name === "blender" && process.env.GAMESMITH_BLENDER_ENABLED === "0") continue;
    pi.registerTool({
      ...tool, label: tool.name,
      async execute(id, params, signal) {
        const result = await callHost(id, tool.name, params, signal);
        if (!result?.ok) throw new Error(JSON.stringify(result));
        if (result.image_base64) {
          const { image_base64, mime_type, ...metadata } = result;
          return { content: [{ type: "text" as const, text: JSON.stringify(metadata) }, { type: "image" as const, data: image_base64, mimeType: mime_type }], details: metadata };
        }
        return textResult(JSON.stringify(result), result);
      },
    });
  }

  pi.registerTool({
    name: "reload_game",
    label: "reload_game",
    description: "After successful headless testing, request compiling/instantiating the workspace when a full reload is needed; replace the active game only if valid. Successful live parameter patches need no reload. Waits without timeout for Shift+F5 or Allow Reload in chat unless automatic approval is enabled. Stop cancels the wait. Loads the workspace as it exists when allowed, including edits made while waiting; the request does not freeze a revision.",
    promptSnippet: "reload_game: Compile and reload the generated Godot game when a full refresh is needed",
    parameters: Type.Object({}),
    annotations: { destructiveHint: false, idempotentHint: true, openWorldHint: false },
    executionMode: "sequential",
    async execute(id, _params, signal, _onUpdate, ctx) {
      const result = await callHost(id, "reload_game", {}, signal);
      const receipt = result.delivery_id;
      delete result.delivery_id;
      delivery.retain({ delivery_id: receipt }, ctx.sessionManager, { toolCallId: id }, JSON.stringify(result));
      if (!result?.ok) throw new Error(JSON.stringify(result));
      return textResult(JSON.stringify(result), result);
    },
  });

  pi.registerTool({
    name: "read_runtime_log",
    label: "read_runtime_log",
    description: "Read durable per-game runtime diagnostics. Default summarizes errors, warnings and latest load outcome. Use raw=true with cursor=0 for chronological records; next_cursor is exclusive and session-scoped. Reports retention, overflow and persistence failures. session_id selects earlier sessions.",
    promptSnippet: "read_runtime_log: Inspect generated-game load/runtime diagnostics",
    parameters: Type.Object({
      session_id: Type.Optional(Type.String()),
      attempt: Type.Optional(Type.Integer({ minimum: 1 })),
      severity: Type.Optional(Type.Union([Type.Literal("error"), Type.Literal("warning"), Type.Literal("info")])),
      cursor: Type.Optional(Type.Integer({ minimum: 0 })),
      limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100 })),
      raw: Type.Optional(Type.Boolean()),
    }),
    annotations: { readOnlyHint: true, openWorldHint: false },
    async execute(id, params, signal, _onUpdate, ctx) {
      const result = await callHost(id, "read_runtime_log", params, signal);
      const receipt = result.delivery_id;
      delete result.delivery_id;
      const text = result?.ok ? String(result?.content || JSON.stringify(result)) : JSON.stringify(result);
      delivery.retain({ delivery_id: receipt }, ctx.sessionManager, { toolCallId: id }, text);
      if (!result?.ok) throw new Error(JSON.stringify(result));
      return textResult(String(result?.content || JSON.stringify(result)), result);
    },
  });
}
