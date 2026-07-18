import { describe, expect, it, vi } from "vitest";
import { EditorContextBroker } from "../src/context-broker.js";
import type { EditorContextRequestEvent } from "../src/protocol.js";

function makeBroker(timeoutMs = 50) {
  const emitted: EditorContextRequestEvent[] = [];
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
