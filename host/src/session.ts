/**
 * session.ts — the only module that talks to the pi SDK (ADR-001: one owner
 * for SDK API drift). Boots an AgentSessionRuntime against the user's real
 * ~/.pi/agent config (ADR-003, validated by scripts/smoke.ts) and translates
 * between SDK sessions and the protocol boundary (ADR-002).
 */
import {
  createAgentSessionFromServices,
  createAgentSessionRuntime,
  createAgentSessionServices,
  getAgentDir,
  SessionManager,
  type AgentSession,
  type AgentSessionEvent,
  type AgentSessionRuntime,
  type CreateAgentSessionRuntimeFactory,
} from "@earendil-works/pi-coding-agent";
import type { ForwardedEvent, HostState, HostSyntheticEvent } from "./protocol.js";

/** Anything the host may put on the wire besides command responses. */
export type EmittedEvent = ForwardedEvent | HostSyntheticEvent;

/** Project an SDK event onto the wire — forwarded verbatim (protocol.ts note). */
function forward(event: AgentSessionEvent): ForwardedEvent {
  return event as unknown as ForwardedEvent;
}

/** Build the state snapshot returned by `hello` / `get_state` / `new_session`. */
export function buildState(session: AgentSession): HostState {
  const model = session.model;
  return {
    model: model ? { provider: model.provider, id: model.id, name: model.name } : null,
    thinkingLevel: session.thinkingLevel,
    isStreaming: session.isStreaming,
    sessionId: session.sessionId,
    sessionFile: session.sessionFile,
    messageCount: session.messages.length,
  };
}

export class AgentHost {
  private runtime: AgentSessionRuntime | undefined;
  private unsubscribe: (() => void) | undefined;

  private constructor(private readonly emit: (event: EmittedEvent) => void) {}

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

    // Session replacement (new_session now; switch/fork in Phase 4)
    // invalidates the old session — re-subscribe to the new one.
    host.runtime.setRebindSession(() => {
      host.bindSession();
      return Promise.resolve();
    });
    host.bindSession();
    return host;
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
