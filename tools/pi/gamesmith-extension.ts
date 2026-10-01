import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

const execFileAsync = promisify(execFile);
const bridgeDir = process.env.GAMESMITH_HOST_BRIDGE_DIR || "";
const legacyTranscriptPath = process.env.GAMESMITH_LEGACY_TRANSCRIPT || "";
const delayMs = Math.max(0, Number(process.env.GAMESMITH_LLM_DELAY_MS || "0"));

let startedWithoutMain = false;
let requestRequiresChange = false;
let turnMutation = false;
let successfulReload = false;
let pendingCodeChanges = false;
let verifierRetries = 0;

function textResult(text: string, details: unknown = undefined) {
  return { content: [{ type: "text" as const, text }], details };
}

function safePath(cwd: string, value: string): string | null {
  if (!value || isAbsolute(value)) return null;
  const abs = resolve(cwd, value);
  const rel = relative(cwd, abs);
  if (rel === "" || (!rel.startsWith("..") && !isAbsolute(rel))) return abs;
  return null;
}

function touchesGitMetadata(cwd: string, value: string): boolean {
  const abs = safePath(cwd, value);
  if (!abs) return false;
  const rel = relative(cwd, abs).replaceAll("\\", "/");
  return rel === ".git" || rel.startsWith(".git/");
}

function requestLooksLikeChange(text: string): boolean {
  const lower = text.trim().toLowerCase();
  for (const prefix of ["what ", "why ", "where ", "when ", "who ", "which ", "how ", "explain ", "tell me ", "describe ", "list ", "show me ", "is ", "are ", "does ", "do "]) {
    if (lower.startsWith(prefix)) return false;
  }
  return ["create", "build", "make", "add", "change", "update", "modify", "fix", "remove", "delete", "rename", "replace", "increase", "decrease", "faster", "slower", "speed up", "slow down", "implement", "rework", "recolor", "resize", "spawn"].some((marker) => lower.includes(marker));
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

  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (signal?.aborted) throw new Error(`GameSmith host tool ${command} was aborted.`);
    try {
      const raw = await readFile(responsePath, "utf8");
      await rm(responsePath, { force: true });
      return JSON.parse(raw);
    } catch {
      // Host has not answered yet.
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 25));
  }
  throw new Error(`Timed out waiting for GameSmith host tool ${command}.`);
}

function mutationPath(event: any): string {
  if (event.toolName === "move_path") return String(event.input?.to || event.input?.from || "");
  return String(event.input?.path || "");
}

export default function (pi: ExtensionAPI) {
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
      if (safePath(ctx.cwd, value) === null) {
        return { block: true, reason: `Path "${value}" is outside the current game workspace.` };
      }
      if (["edit", "write", "delete_path", "move_path"].includes(event.toolName) && touchesGitMetadata(ctx.cwd, value)) {
        return { block: true, reason: "GameSmith reserves .git metadata; use the Git tools instead." };
      }
    }
  });

  pi.on("before_agent_start", async (event, ctx) => {
    startedWithoutMain = !(await stat(join(ctx.cwd, "main.gd")).then(() => true).catch(() => false));
    requestRequiresChange = requestLooksLikeChange(event.prompt);
    turnMutation = false;
    successfulReload = false;
    pendingCodeChanges = false;
    verifierRetries = 0;
  });

  pi.on("tool_result", async (event) => {
    if (event.isError) return;
    if (["write", "edit", "delete_path", "move_path"].includes(event.toolName)) {
      turnMutation = true;
      const path = mutationPath(event).toLowerCase();
      if (event.toolName === "delete_path" || event.toolName === "move_path" || path.endsWith(".gd") || path.endsWith(".gdshader")) {
        pendingCodeChanges = true;
      }
    }
    if (event.toolName === "reload_game") {
      successfulReload = true;
      pendingCodeChanges = false;
    }
  });

  pi.on("turn_end", async (event) => {
    if (delayMs > 0 && event.toolResults.length > 0) {
      await new Promise((resolvePromise) => setTimeout(resolvePromise, delayMs));
    }
  });

  pi.on("agent_before_settle", async (_event, ctx) => {
    const hasMain = await stat(join(ctx.cwd, "main.gd")).then(() => true).catch(() => false);
    let reason = "";
    if (startedWithoutMain && !hasMain) reason = "new game still has no main.gd";
    else if (requestRequiresChange && !turnMutation) reason = "requested game change made no workspace mutation";
    else if (pendingCodeChanges) reason = "code changes were not successfully reloaded";
    else if ((startedWithoutMain || turnMutation) && !successfulReload) reason = "changed game was not successfully reloaded";
    if (!reason) return;

    verifierRetries += 1;
    const content = `GameSmith verification rejected completion: ${reason}. Continue the same player request with tools now. Do not claim completion again until the condition is actually satisfied.`;
    if (verifierRetries >= 3) {
      return {
        entries: [{ type: "custom_message", customType: "gamesmith-verifier-failed", content, display: false }],
        continue: false,
      };
    }
    return {
      entries: [{ type: "custom_message", customType: "gamesmith-verifier", content, display: false }],
      continue: true,
    };
  });

  pi.on("session_start", async (_event, ctx) => {
    if (!legacyTranscriptPath) return;
    const existing = ctx.sessionManager.getEntries();
    if (existing.length > 0) return;
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
      const path = safePath(ctx.cwd, params.path);
      if (!path) throw new Error("Unsafe path.");
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
      const from = safePath(ctx.cwd, params.from);
      const to = safePath(ctx.cwd, params.to);
      if (!from || !to) throw new Error("Unsafe path.");
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
    description: "Ask the GameSmith host to compile/instantiate main.gd and replace the active game only if the candidate is valid.",
    promptSnippet: "reload_game: Compile and hot-reload the generated Godot game",
    parameters: Type.Object({}),
    annotations: { destructiveHint: false, idempotentHint: true, openWorldHint: false },
    executionMode: "sequential",
    async execute(id, _params, signal) {
      const result = await callHost(id, "reload_game", {}, signal);
      if (!result?.ok) throw new Error(String(result?.error || "Game reload failed."));
      return textResult(JSON.stringify(result), result);
    },
  });

  pi.registerTool({
    name: "read_runtime_log",
    label: "read_runtime_log",
    description: "Read the GameSmith generated-game runtime/load log after a failed reload or reported runtime problem.",
    promptSnippet: "read_runtime_log: Inspect generated-game load/runtime diagnostics",
    parameters: Type.Object({}),
    annotations: { readOnlyHint: true, openWorldHint: false },
    async execute(id, _params, signal) {
      const result = await callHost(id, "read_runtime_log", {}, signal);
      if (!result?.ok) throw new Error(String(result?.error || "Could not read runtime log."));
      return textResult(String(result?.content || JSON.stringify(result)), result);
    },
  });
}
