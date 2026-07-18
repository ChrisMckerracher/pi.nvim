import type { AgentSession } from "@earendil-works/pi-coding-agent";
import { describe, expect, it } from "vitest";
import { buildState } from "../src/session.js";

/** Test double carrying only the fields buildState reads. */
function fakeSession(overrides: Record<string, unknown>): AgentSession {
  return {
    model: undefined,
    thinkingLevel: "medium",
    isStreaming: false,
    sessionId: "test-id",
    sessionFile: undefined,
    messages: [],
    ...overrides,
  } as unknown as AgentSession;
}

describe("buildState", () => {
  it("maps a session with no model resolved", () => {
    expect(buildState(fakeSession({}))).toEqual({
      model: null,
      thinkingLevel: "medium",
      isStreaming: false,
      sessionId: "test-id",
      sessionFile: undefined,
      messageCount: 0,
    });
  });

  it("maps model info and message count when present", () => {
    const state = buildState(
      fakeSession({
        model: { provider: "zai", id: "glm-5.2", name: "GLM-5.2" },
        thinkingLevel: "max",
        isStreaming: true,
        sessionFile: "/tmp/session.jsonl",
        messages: [{}, {}, {}],
      }),
    );
    expect(state.model).toEqual({ provider: "zai", id: "glm-5.2", name: "GLM-5.2" });
    expect(state.thinkingLevel).toBe("max");
    expect(state.isStreaming).toBe(true);
    expect(state.sessionFile).toBe("/tmp/session.jsonl");
    expect(state.messageCount).toBe(3);
  });
});
