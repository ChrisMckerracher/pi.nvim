import { describe, expect, it, vi } from "vitest";
import { EditorContextBroker } from "../src/context-broker.js";
import type { EditorContextRequestEvent, EditorBufferRequestEvent } from "../src/protocol.js";

function makeBroker(timeoutMs = 50) {
  const emitted: (EditorContextRequestEvent | EditorBufferRequestEvent)[] = [];
  const broker = new EditorContextBroker((event) => emitted.push(event), timeoutMs);
  return { broker, emitted };
}

describe("EditorContextBroker", () => {
  it("emits a request and resolves with the editor's answer", async () => {
    const { broker, emitted } = makeBroker(500);
    const pending = broker.request();
    expect(emitted).toHaveLength(1);
    expect(broker.pendingCount()).toBe(1);

    const requestId = emitted[0]?.requestId;
    if (requestId === undefined) throw new Error("expected a requestId");
    expect(broker.resolve(requestId, "file: main.lua, line 42")).toBe(true);

    await expect(pending).resolves.toBe("file: main.lua, line 42");
    expect(broker.pendingCount()).toBe(0);
  });

  it("correlates buffer edits independently of context reads", async () => {
    const { broker, emitted } = makeBroker(500);
    const context = broker.request();
    const edit = broker.requestBuffer({
      action: "edit",
      bufferId: 7,
      changedtick: 4,
      oldText: "old",
      newText: "new",
    });
    expect(emitted[1]).toMatchObject({
      type: "editor_buffer_request",
      bufferId: 7,
      oldText: "old",
      newText: "new",
    });
    const first = emitted[0];
    const second = emitted[1];
    if (!first || !second || second.type !== "editor_buffer_request")
      throw new Error("missing requests");
    expect(second.expiresAt).toBeGreaterThan(Date.now());
    broker.resolve(second.requestId, "edited");
    broker.resolve(first.requestId, "context");
    await expect(edit).resolves.toBe("edited");
    await expect(context).resolves.toBe("context");
    expect(broker.pendingCount()).toBe(0);
  });

  it("rejects unknown or already-resolved request ids", async () => {
    const { broker, emitted } = makeBroker(500);
    const pending = broker.request();
    const requestId = emitted[0]?.requestId;
    if (requestId === undefined) throw new Error("expected a requestId");

    expect(broker.resolve("nope", "x")).toBe(false);
    expect(broker.resolve(requestId, "ctx")).toBe(true);
    expect(broker.resolve(requestId, "again")).toBe(false);
    await pending;
  });

  it("times out cleanly instead of hanging the agent", async () => {
    vi.useFakeTimers();
    try {
      const { broker } = makeBroker(50);
      const pending = broker.request();
      await vi.advanceTimersByTimeAsync(60);
      await expect(pending).resolves.toMatch(/timed out/);
      expect(broker.pendingCount()).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });
});
