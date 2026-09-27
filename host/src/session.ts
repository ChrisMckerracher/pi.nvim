/**
 * session.ts — the only module that talks to the pi SDK (ADR-001: one owner
 * for SDK API drift). Boots an AgentSessionRuntime against the user's real
 * ~/.pi/agent config (ADR-003, validated by scripts/smoke.ts) and translates
 * between SDK sessions and the protocol boundary (ADR-002, ADR-005).
 */
import {
  createAgentSessionFromServices,
  createAgentSessionRuntime,
  createAgentSessionServices,
  defineTool,
  getAgentDir,
  SessionManager,
  type AgentSession,
  type AgentSessionEvent,
  type AgentSessionRuntime,
  type CreateAgentSessionRuntimeFactory,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

import { EditorContextBroker } from "./context-broker.js";
import type {
  ForwardedEvent,
  HostState,
  HostSyntheticEvent,
  ModelListItem,
  SessionListItem,
} from "./protocol.js";

/** Minimal model shape the wire needs (structurally satisfied by SDK Models). */
interface ModelSummary {
  provider: string;
  id: string;
  name: string;
  contextWindow?: number;
}

/** Map the model catalog to wire items, marking the session's active model. */
export function mapModelList(
  models: readonly ModelSummary[],
  current: ModelSummary | undefined,
): ModelListItem[] {
  return models.map((model) => ({
    provider: model.provider,
    id: model.id,
    name: model.name,
    contextWindow: model.contextWindow,
    isCurrent:
      current !== undefined && model.provider === current.provider && model.id === current.id,
  }));
}

/** Anything the host may put on the wire besides command responses. */
export type EmittedEvent = ForwardedEvent | HostSyntheticEvent;

/** Project an SDK event onto the wire — forwarded verbatim (protocol.ts note). */
function forward(event: AgentSessionEvent): ForwardedEvent {
  return event as unknown as ForwardedEvent;
}

/** Build the state snapshot returned by `hello` / `get_state` / session changes. */
export function buildState(session: AgentSession): HostState {
  const model = session.model;
  const sessionStats = session.getSessionStats();
  return {
    model: model ? { provider: model.provider, id: model.id, name: model.name } : null,
    thinkingLevel: session.thinkingLevel,
    isStreaming: session.isStreaming,
    sessionId: session.sessionId,
    sessionFile: session.sessionFile,
    messageCount: session.messages.length,
    stats: {
      totalTokens: sessionStats.tokens.total,
      cost: sessionStats.cost,
      contextPercent: sessionStats.contextUsage?.percent ?? null,
    },
  };
}

export class AgentHost {
  private runtime: AgentSessionRuntime | undefined;
  private unsubscribe: (() => void) | undefined;
  private readonly contextBroker: EditorContextBroker;

  private constructor(private readonly emit: (event: EmittedEvent) => void) {
    this.contextBroker = new EditorContextBroker((event) => {
      this.emit(event);
    });
  }

  /** Boot the runtime against the user's real config. Throws on boot failure. */
  static async start(cwd: string, emit: (event: EmittedEvent) => void): Promise<AgentHost> {
    const host = new AgentHost(emit);

    const createRuntime: CreateAgentSessionRuntimeFactory = async (options) => {
      const services = await createAgentSessionServices({
        cwd: options.cwd,
        agentDir: options.agentDir,
      });
      return {
        ...(await createAgentSessionFromServices({
          services,
          sessionManager: options.sessionManager,
          ...(options.sessionStartEvent ? { sessionStartEvent: options.sessionStartEvent } : {}),
          customTools: [host.buildEditorContextTool(), host.buildEditorBufferTool()],
        })),
        services,
        diagnostics: services.diagnostics,
      };
    };

    host.runtime = await createAgentSessionRuntime(createRuntime, {
      cwd,
      agentDir: getAgentDir(),
      sessionManager: SessionManager.create(cwd),
    });

    // Session replacement (new_session, switch_session) invalidates the old
    // session — re-subscribe to the new one.
    host.runtime.setRebindSession(() => {
      host.bindSession();
      return Promise.resolve();
    });
    host.bindSession();
    return host;
  }

  /** The agent-pull `editor_context` tool (ADR-005). Answers come from nvim. */
  private buildEditorContextTool() {
    const broker = this.contextBroker;
    return defineTool({
      name: "editor_context",
      label: "Editor Context",
      description:
        "Get the user's current Neovim state: file or unnamed buffer, cursor position, " +
        "visual selection, and diagnostics. Use when the user refers to what " +
        "they are looking at, the current file, or the selected code.",
      parameters: Type.Object({}),
      execute: async () => {
        const context = await broker.request();
        return { content: [{ type: "text", text: context }], details: {} };
      },
    });
  }

  /** In-memory edits stay owned by Neovim, with stale-version protection. */
  private buildEditorBufferTool() {
    const broker = this.contextBroker;
    return defineTool({
      name: "editor_buffer",
      label: "Editor Buffer",
      description:
        "Read or edit an unnamed Neovim code buffer exposed in editor context. " +
        "Use this instead of filesystem tools for unnamed buffers. Read first to get " +
        "text and changedtick; edit requires that changedtick and an exact unique oldText " +
        "to replace with newText. Empty oldText only works on an empty buffer. " +
        "Edits remain unsaved and can be undone in Neovim. If stale, read again.",
      parameters: Type.Object({
        action: Type.Union([Type.Literal("read"), Type.Literal("edit")]),
        bufferId: Type.Integer({ minimum: 1 }),
        changedtick: Type.Optional(Type.Integer({ minimum: 0 })),
        oldText: Type.Optional(Type.String()),
        newText: Type.Optional(Type.String()),
      }),
      execute: async (_toolCallId, params) => {
        const result = await broker.requestBuffer(params);
        return {
          content: [{ type: "text", text: result }],
          details: {},
          isError: result.startsWith("Error:"),
        };
      },
    });
  }

  /** Complete an editor-context request from the editor (ADR-005). */
  resolveEditorContext(requestId: string, context: string): boolean {
    return this.contextBroker.resolve(requestId, context);
  }

  private session(): AgentSession {
    if (this.runtime === undefined) throw new Error("AgentHost not started");
    return this.runtime.session;
  }

  private bindSession(): void {
    this.unsubscribe?.();
    this.unsubscribe = this.session().subscribe((event) => {
      this.emit(forward(event));
    });
  }

  state(): HostState {
    return buildState(this.session());
  }

  /**
   * Accept a prompt. Throws for pre-acceptance rejection (agent already
   * streaming — caller should steer/follow_up instead). Failures after
   * acceptance surface through the event stream, matching pi semantics;
   * the catch is a last resort so nothing fails silently.
   */
  async prompt(message: string): Promise<void> {
    const session = this.session();
    if (session.isStreaming) {
      throw new Error("Agent is streaming — use steer or follow_up to queue");
    }
    void session.prompt(message).catch((error: unknown) => {
      this.emit({ type: "host_error", message: errorMessage(error) });
    });
  }

  async steer(message: string): Promise<void> {
    await this.session().steer(message);
  }

  async followUp(message: string): Promise<void> {
    await this.session().followUp(message);
  }

  async abort(): Promise<void> {
    await this.session().abort();
  }

  async newSession(): Promise<HostState> {
    if (this.runtime === undefined) throw new Error("AgentHost not started");
    const { cancelled } = await this.runtime.newSession();
    if (cancelled) throw new Error("new_session cancelled by extension");
    return this.state();
  }

  /** List sessions for the current project, most recently modified first. */
  async listSessions(): Promise<SessionListItem[]> {
    if (this.runtime === undefined) throw new Error("AgentHost not started");
    const current = this.session().sessionFile;
    const infos = await SessionManager.list(this.runtime.cwd);
    return infos.map((info) => ({
      path: info.path,
      id: info.id,
      name: info.name,
      created: info.created.toISOString(),
      modified: info.modified.toISOString(),
      messageCount: info.messageCount,
      firstMessage: info.firstMessage,
      isCurrent: info.path === current,
    }));
  }

  async switchSession(path: string): Promise<HostState> {
    if (this.runtime === undefined) throw new Error("AgentHost not started");
    const { cancelled } = await this.runtime.switchSession(path);
    if (cancelled) throw new Error("switch_session cancelled by extension");
    return this.state();
  }

  /**
   * Recent messages of the active session (for chat replay after switching).
   * Capped — full history lives in the session file, not the wire.
   */
  getMessages(limit = 50): unknown[] {
    return this.session().messages.slice(-limit);
  }

  /** List authenticated models for the model picker. */
  async listModels(): Promise<ModelListItem[]> {
    if (this.runtime === undefined) throw new Error("AgentHost not started");
    const models = await this.runtime.services.modelRuntime.getAvailable();
    return mapModelList(models, this.session().model);
  }

  /** Switch the active session's model (session-scoped; settings untouched). */
  async setModel(provider: string, modelId: string): Promise<HostState> {
    if (this.runtime === undefined) throw new Error("AgentHost not started");
    const model = this.runtime.services.modelRuntime.getModel(provider, modelId);
    if (model === undefined) throw new Error(`Model not found: ${provider}/${modelId}`);
    await this.session().setModel(model);
    return this.state();
  }

  /** Cycle to the next model (pi's Ctrl+P semantics). */
  async cycleModel(): Promise<HostState> {
    const result = await this.session().cycleModel();
    if (result === undefined) {
      throw new Error("Only one model available — nothing to cycle to");
    }
    return this.state();
  }

  cycleThinking(): string | undefined {
    return this.session().cycleThinkingLevel();
  }

  async dispose(): Promise<void> {
    this.unsubscribe?.();
    if (this.runtime !== undefined) await this.runtime.dispose();
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
