/**
 * Protocol v2 — versioned JSONL framing between the Neovim Lua frontend and
 * this host. This file is the source of truth for both sides (ADR-002,
 * extended by ADR-005).
 *
 * Framing discipline (mirrors pi's RPC mode): records are delimited by LF
 * only. Split on "\n" exclusively — never on Unicode line/paragraph
 * separators (U+2028/U+2029), which are valid inside JSON strings.
 *
 * Event modeling note: agent events produced by the pi SDK are FORWARDED,
 * not remodeled (same choice as pi's own RPC mode). Their wire type is
 * `ForwardedEvent` — consumers narrow by `type`. Commands, responses, and
 * host-synthetic events are fully modeled below.
 *
 * v2 changes (ADR-005): session management commands, message history, and a
 * host-initiated request/response sub-channel (`editor_context_request` →
 * `editor_context_response`) for the agent-pull editor context tool.
 */

export const PROTOCOL_VERSION = 2 as const;

// ---------------------------------------------------------------------------
// Commands (nvim → host)
// ---------------------------------------------------------------------------

export type Command =
  | { id?: string; type: "hello" }
  | { id?: string; type: "prompt"; message: string }
  | { id?: string; type: "steer"; message: string }
  | { id?: string; type: "follow_up"; message: string }
  | { id?: string; type: "abort" }
  | { id?: string; type: "get_state" }
  | { id?: string; type: "new_session" }
  | { id?: string; type: "list_sessions" }
  | { id?: string; type: "switch_session"; path: string }
  | { id?: string; type: "get_messages" }
  | { id?: string; type: "list_models" }
  | { id?: string; type: "set_model"; provider: string; modelId: string }
  | { id?: string; type: "cycle_model" }
  | { id?: string; type: "cycle_thinking" }
  | { id?: string; type: "editor_context_response"; requestId: string; context: string }
  | { id?: string; type: "dispose" };

// ---------------------------------------------------------------------------
// Responses and events (host → nvim)
// ---------------------------------------------------------------------------

/** Responses correlate to a command by id. */
export interface Response {
  id?: string;
  type: "response";
  command: string;
  success: boolean;
  data?: unknown;
  error?: string;
}

/** State snapshot returned by `hello` / `get_state` and after session changes. */
export interface HostState {
  model: { provider: string; id: string; name: string } | null;
  thinkingLevel: string;
  isStreaming: boolean;
  sessionId: string;
  sessionFile: string | undefined;
  messageCount: number;
  stats: {
    totalTokens: number;
    cost: number;
    contextPercent: number | null;
  };
}

/** One entry in the model catalog for `list_models`. */
export interface ModelListItem {
  provider: string;
  id: string;
  name: string;
  contextWindow: number | undefined;
  isCurrent: boolean;
}

/** One entry in the session list for `list_sessions`. */
export interface SessionListItem {
  path: string;
  id: string;
  name: string | undefined;
  created: string;
  modified: string;
  messageCount: number;
  firstMessage: string;
  isCurrent: boolean;
}

/** Host-side boot/init failure event. */
export interface HostErrorEvent {
  type: "host_error";
  message: string;
}

/** Host-initiated request for the editor's current context (ADR-005). */
export interface EditorContextRequestEvent {
  type: "editor_context_request";
  requestId: string;
}

/** Events the host synthesizes itself (not forwarded from the SDK). */
export type HostSyntheticEvent = HostErrorEvent | EditorContextRequestEvent;

/**
 * An agent event forwarded from the pi SDK. Shapes are owned by the SDK
 * (`AgentSessionEvent`); the Lua side narrows by `type`. Forwarded verbatim —
 * see the modeling note at the top of this file.
 */
export interface ForwardedEvent {
  type: string;
  [key: string]: unknown;
}

export type OutboundMessage = Response | HostSyntheticEvent | ForwardedEvent;

// ---------------------------------------------------------------------------
// Framing
// ---------------------------------------------------------------------------

/** Encode one outbound message as a single LF-terminated JSONL record. */
export function encode(message: OutboundMessage): string {
  return JSON.stringify(message) + "\n";
}

/**
 * Incremental splitter for LF-delimited JSONL over arbitrary chunk
 * boundaries. Strips a single trailing CR per record (accepts CRLF input).
 */
export function createLineSplitter(onLine: (line: string) => void): (chunk: string) => void {
  let buffer = "";
  return (chunk: string): void => {
    buffer += chunk;
    for (;;) {
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex === -1) return;
      let line = buffer.slice(0, newlineIndex);
      buffer = buffer.slice(newlineIndex + 1);
      if (line.endsWith("\r")) line = line.slice(0, -1);
      onLine(line);
    }
  };
}

/** Parse one JSONL record into a command, or throw with a clear boundary error. */
export function parseCommand(line: string): Command {
  const parsed: unknown = JSON.parse(line);
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed) ||
    !("type" in parsed)
  ) {
    throw new Error("Invalid command: expected an object with a 'type' field");
  }
  return parsed as Command;
}

/** Narrow a parsed command to one carrying a non-empty `message`, or throw. */
export function requireMessage(command: Command): string {
  if (!("message" in command) || typeof command.message !== "string" || command.message === "") {
    throw new Error(`Command '${command.type}' requires a non-empty 'message' field`);
  }
  return command.message;
}
