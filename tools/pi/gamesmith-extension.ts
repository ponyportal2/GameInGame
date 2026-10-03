import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { workspacePath } from "./workspace-paths.mjs";
import { modelCapabilities } from "./model-capabilities.mjs";
import { DiagnosticDelivery } from "./diagnostic-delivery.mjs";

const execFileAsync = promisify(execFile);
const bridgeDir = process.env.GAMESMITH_HOST_BRIDGE_DIR || "";
const legacyTranscriptPath = process.env.GAMESMITH_LEGACY_TRANSCRIPT || "";
const delayMs = Math.max(0, Number(process.env.GAMESMITH_LLM_DELAY_MS || "0"));

function textResult(text: string, details: unknown = undefined) {
  return { content: [{ type: "text" as const, text }], details };
}

async function runGit(cwd: string, args: string[]) {
  try {
    const { stdout, stderr } = await execFileAsync("git", args, { cwd, maxBuffer: 1024 * 1024 });
    return { ok: true, output: (stdout + stderr).trim() };
  } catch (error: any) {
    return { ok: false, output: String(error?.stderr || error?.stdout || error?.message || error) };
  }
}

async function callHost(toolCallId: string, command: string, args: unknown, signal?: AbortSignal) {
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

export default async function (pi: ExtensionAPI) {
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
    Object.assign(model, modelCapabilities(process.env.GAMESMITH_MODEL_PROVIDER || "", model.id, lookup));
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

  pi.registerTool({
    name: "reload_game",
    label: "reload_game",
    description: "Request permission to compile/instantiate the current workspace and replace the active game only if valid. Waits without timeout for Shift+F5 or Allow Reload in chat, or agent cancellation. Loads the workspace as it exists when allowed, including edits made while waiting; the request does not freeze a revision.",
    promptSnippet: "reload_game: Compile and hot-reload the generated Godot game",
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
