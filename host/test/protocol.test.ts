import { describe, expect, it } from "vitest";
import {
  PROTOCOL_VERSION,
  createLineSplitter,
  encode,
  parseCommand,
  requireMessage,
} from "../src/protocol.js";

describe("protocol framing", () => {
  it("splits records on LF across arbitrary chunk boundaries", () => {
    const lines: string[] = [];
    const push = createLineSplitter((line) => lines.push(line));
    push('{"type":"hel');
    push('lo"}\n{"type":"prompt"');
    push(',"message":"hi"}\n');
    expect(lines).toEqual(['{"type":"hello"}', '{"type":"prompt","message":"hi"}']);
  });

  it("accepts CRLF input by stripping the trailing CR", () => {
    const lines: string[] = [];
    const push = createLineSplitter((line) => lines.push(line));
    push('{"type":"hello"}\r\n');
    expect(lines).toEqual(['{"type":"hello"}']);
  });

  it("does NOT split on Unicode line separators inside JSON strings", () => {
    const lines: string[] = [];
    const push = createLineSplitter((line) => lines.push(line));
    push(JSON.stringify({ type: "prompt", message: "a\u2028b\u2028c" }) + "\n");
    expect(lines).toHaveLength(1);
    const first = lines[0];
    if (first === undefined) throw new Error("expected exactly one record");
    expect(parseCommand(first)).toMatchObject({ type: "prompt" });
  });

  it("encode produces exactly one LF-terminated record", () => {
    const out = encode({
      type: "response",
      command: "hello",
      success: true,
      data: { protocol: PROTOCOL_VERSION },
    });
    expect(out.endsWith("\n")).toBe(true);
    expect(out.indexOf("\n")).toBe(out.length - 1);
  });

  it("parseCommand rejects non-command JSON with a clear error", () => {
    expect(() => parseCommand("[1,2,3]")).toThrow(/'type' field/);
    expect(() => parseCommand('"hello"')).toThrow(/'type' field/);
  });

  it("requireMessage extracts a valid message and rejects missing ones", () => {
    expect(requireMessage({ type: "prompt", message: "hi" })).toBe("hi");
    expect(() => requireMessage({ type: "prompt", message: "" })).toThrow(/message/);
    expect(() => requireMessage({ type: "abort" })).toThrow(/message/);
  });
});
