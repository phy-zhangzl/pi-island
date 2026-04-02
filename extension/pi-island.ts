import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { basename } from "node:path";

type VibeState =
  | "idle"
  | "thinking"
  | "reading"
  | "running"
  | "patching"
  | "done"
  | "error";

interface PiEventPayload {
  source: "pi";
  sessionId: string;
  projectName: string;
  sessionName?: string;
  cwd: string;
  terminalApp?: string;
  terminalSessionID?: string;
  state: VibeState;
  detail?: string;
  contextTokens?: number;
  contextWindow?: number;
  timestamp: number;
}

export default function (pi: ExtensionAPI) {
  let currentState: VibeState | null = null;
  let currentDetail: string | undefined;
  let currentContextTokens: number | undefined;
  let currentContextWindow: number | undefined;
  let hadError = false;
  const sessionNameCache = new Map<string, string>();

  function getSessionFile(ctx: any): string | undefined {
    const file = ctx.sessionManager.getSessionFile?.();
    return typeof file === "string" && file.length > 0 ? file : undefined;
  }

  function getSessionId(ctx: any): string {
    return getSessionFile(ctx) ?? `${ctx.cwd}#ephemeral`;
  }

  function getProjectName(ctx: any): string {
    return basename(ctx.cwd);
  }

  function getSessionNameFromFile(ctx: any): string | undefined {
    const sessionFile = getSessionFile(ctx);
    if (!sessionFile) return undefined;

    const cached = sessionNameCache.get(sessionFile);
    if (cached) return cached;

    try {
      const content = readFileSync(sessionFile, "utf8");
      const lines = content.split("\n");
      for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i]?.trim();
        if (!line) continue;
        try {
          const entry = JSON.parse(line);
          const candidate =
            entry?.type === "session_info" || entry?.type === "session"
              ? typeof entry.name === "string"
                ? entry.name.trim()
                : undefined
              : undefined;
          if (candidate) {
            sessionNameCache.set(sessionFile, candidate);
            return candidate;
          }
        } catch {
          continue;
        }
      }
    } catch {
      return undefined;
    }

    return undefined;
  }

  function getSessionName(ctx: any): string | undefined {
    const sessionFile = getSessionFile(ctx);
    if (!sessionFile) return undefined;
    return sessionNameCache.get(sessionFile) ?? getSessionNameFromFile(ctx);
  }

  function terminalInfo() {
    const itermSessionID = process.env.ITERM_SESSION_ID;
    if (typeof itermSessionID === "string" && itermSessionID.length > 0) {
      return {
        terminalApp: "iTerm2",
        terminalSessionID: itermSessionID,
      };
    }

    const terminalSessionID = process.env.TERM_SESSION_ID;
    if (typeof terminalSessionID === "string" && terminalSessionID.length > 0) {
      return {
        terminalApp: "Terminal",
        terminalSessionID,
      };
    }

    return {
      terminalApp: undefined,
      terminalSessionID: undefined,
    };
  }

  async function send(payload: PiEventPayload) {
    try {
      await fetch("http://127.0.0.1:47831/event", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
    } catch {
      // App may not be running; never interrupt pi.
    }
  }

  async function setState(
    ctx: any,
    state: VibeState,
    detail?: string,
    usageOverride?: { contextTokens?: number; contextWindow?: number },
  ) {
    const usage = usageOverride ?? getContextUsage(ctx);
    if (
      currentState === state &&
      currentDetail === detail &&
      currentContextTokens === usage.contextTokens &&
      currentContextWindow === usage.contextWindow
    ) return;

    currentState = state;
    currentDetail = detail;
    currentContextTokens = usage.contextTokens;
    currentContextWindow = usage.contextWindow;

    await send({
      source: "pi",
      sessionId: getSessionId(ctx),
      projectName: getProjectName(ctx),
      sessionName: getSessionName(ctx),
      cwd: ctx.cwd,
      ...terminalInfo(),
      state,
      detail,
      contextTokens: usage.contextTokens,
      contextWindow: usage.contextWindow,
      timestamp: Date.now() / 1000,
    });
  }

  function readDetail(input: any): string | undefined {
    const path = input?.path;
    if (typeof path !== "string") return undefined;
    return path;
  }

  function bashDetail(input: any): string | undefined {
    const command = input?.command;
    if (typeof command !== "string") return undefined;
    return command.length > 72 ? `${command.slice(0, 69)}...` : command;
  }

  function patchDetail(input: any): string | undefined {
    const path = input?.path;
    if (typeof path === "string") return path;
    return "Updating files";
  }

  function getContextUsage(ctx: any): { contextTokens?: number; contextWindow?: number } {
    try {
      const usage = ctx.getContextUsage?.();
      if (usage) {
        return {
          contextTokens: typeof usage.tokens === "number" && usage.tokens > 0 ? usage.tokens : undefined,
          contextWindow:
            typeof usage.contextWindow === "number" && usage.contextWindow > 0 ? usage.contextWindow : undefined,
        };
      }

      const contextWindow = typeof ctx.model?.contextWindow === "number" ? ctx.model.contextWindow : undefined;
      return { contextWindow };
    } catch {
      return {};
    }
  }

  pi.on("session_start", async (_event, ctx) => {
    currentState = null;
    currentDetail = undefined;
    currentContextTokens = undefined;
    currentContextWindow = undefined;
    hadError = false;
    getSessionName(ctx);
    await setState(ctx, "idle", "Ready");
  });

  pi.on("agent_start", async (_event, ctx) => {
    hadError = false;
    await setState(ctx, "thinking", "Processing request");
  });

  pi.on("message_update", async (_event, ctx) => {
    if (hadError) return;

    if (currentState !== "reading" && currentState !== "running" && currentState !== "patching") {
      await setState(ctx, "thinking", "Processing request");
    } else if (currentState) {
      await setState(ctx, currentState, currentDetail);
    }
  });

  pi.on("message_end", async (_event, ctx) => {
    if (hadError || !currentState) return;
    await setState(ctx, currentState, currentDetail);
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (!currentState) return;
    await setState(ctx, currentState, currentDetail);
  });

  pi.on("tool_execution_start", async (event: any, ctx) => {
    if (event.toolName === "read") {
      await setState(ctx, "reading", readDetail(event.args));
    } else if (event.toolName === "bash") {
      await setState(ctx, "running", bashDetail(event.args));
    } else if (event.toolName === "edit" || event.toolName === "write") {
      await setState(ctx, "patching", patchDetail(event.args));
    }
  });

  pi.on("tool_result", async (event: any, ctx) => {
    if (event.isError) {
      hadError = true;
      await setState(ctx, "error", "Something went wrong");
    }
  });

  pi.on("agent_end", async (_event, ctx) => {
    if (hadError) return;
    await setState(ctx, "done", "Task completed");
  });
}
