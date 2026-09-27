/**
 * context-broker.ts — request correlation for editor tools (ADR-005/006).
 *
 * The `editor_context` custom tool needs an answer from Neovim, which is the
 * *client* of this host — so the usual command/response direction is
 * inverted: the host emits `editor_context_request` and waits for a matching
 * `editor_context_response`. This broker owns the pending-request map and
 * the timeout so a missing/closed editor can never hang the agent. Unnamed
 * buffer operations share this correlation path through requestBuffer().
 */
import { randomUUID } from "node:crypto";

import type {
  EditorContextRequestEvent,
  EditorBufferRequestEvent,
  EditorBufferOperation,
} from "./protocol.js";

export const EDITOR_CONTEXT_TIMEOUT_MS = 10_000;

export class EditorContextBroker {
  private readonly pending = new Map<
    string,
    { resolve: (context: string) => void; timer: NodeJS.Timeout }
  >();

  constructor(
    private readonly emit: (event: EditorContextRequestEvent | EditorBufferRequestEvent) => void,
    private readonly timeoutMs: number = EDITOR_CONTEXT_TIMEOUT_MS,
  ) {}

  /** Emit a request and resolve with the editor's answer (or a timeout note). */
  request(): Promise<string> {
    return this.send({ type: "editor_context_request", requestId: randomUUID() });
  }

  /** Read or edit an unnamed buffer, with an editor-enforced delivery deadline. */
  requestBuffer(operation: EditorBufferOperation): Promise<string> {
    return this.send({
      ...operation,
      type: "editor_buffer_request",
      requestId: randomUUID(),
      expiresAt: Date.now() + this.timeoutMs,
    });
  }

  private send(event: EditorContextRequestEvent | EditorBufferRequestEvent): Promise<string> {
    const requestId = event.requestId;
    return new Promise<string>((resolve) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        resolve("Error: editor request timed out; read current state before retrying.");
      }, this.timeoutMs);
      this.pending.set(requestId, {
        resolve: (context: string) => {
          clearTimeout(timer);
          resolve(context);
        },
        timer,
      });
      this.emit(event);
    });
  }

  /** Complete a pending request. Returns false for unknown/stale ids. */
  resolve(requestId: string, context: string): boolean {
    const entry = this.pending.get(requestId);
    if (entry === undefined) return false;
    this.pending.delete(requestId);
    entry.resolve(context);
    return true;
  }

  /** Number of unanswered requests (diagnostics/tests). */
  pendingCount(): number {
    return this.pending.size;
  }
}
