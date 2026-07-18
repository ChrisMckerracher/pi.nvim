/**
 * Live E2E: real host + real ~/.pi/agent config + ONE near-free prompt
 * (thinking cycled to off first). Asserts the exact event fields the Lua
 * renderer consumes — the wire contract the panel relies on (ADR-002).
 *
 * Costs a handful of tokens. Not part of `make check`. Run: make e2e-live
 */
import { spawn } from "node:child_process";
import process from "node:process";
import { fileURLToPath } from "node:url";

/** host/.smoke/e2e-live.js → host/dist/main.js, regardless of caller cwd. */
const hostEntry = fileURLToPath(new URL("../dist/main.js", import.meta.url));

interface WireMsg {
  type: string;
  id?: string;
  success?: boolean;
  data?: { level?: string };
  message?: { role?: string };
  assistantMessageEvent?: { type?: string; delta?: string };
}

const host = spawn("node", [hostEntry], { cwd: process.cwd() });
host.stderr.on("data", (chunk: Buffer | string) => {
  process.stderr.write(`host stderr: ${chunk.toString()}`);
});
let buffer = "";
const events: WireMsg[] = [];
const responses: WireMsg[] = [];

host.stdout.on("data", (chunk: Buffer | string) => {
  buffer += chunk.toString();
  for (;;) {
    const index = buffer.indexOf("\n");
    if (index === -1) break;
    const line = buffer.slice(0, index);
    buffer = buffer.slice(index + 1);
    const msg = JSON.parse(line) as WireMsg;
    if (msg.type === "response") responses.push(msg);
    else events.push(msg);
  }
});

const send = (cmd: Record<string, unknown>): void => {
  host.stdin.write(JSON.stringify(cmd) + "\n");
};
const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

async function until(condition: () => boolean, timeoutMs: number, what: string): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (condition()) return;
    await sleep(100);
  }
  throw new Error(`timeout waiting for ${what}`);
}

try {
  send({ id: "h", type: "hello" });
  await until(() => responses.some((r) => r.id === "h"), 60000, "hello");

  // thinking → off, so the live prompt costs almost nothing
  for (let i = 0; i < 6; i++) {
    const id = `c${i}`;
    send({ id, type: "cycle_thinking" });
    await until(() => responses.some((r) => r.id === id), 10000, "cycle_thinking");
    if (responses.find((r) => r.id === id)?.data?.level === "off") break;
  }

  send({ id: "p", type: "prompt", message: "Reply with exactly: ok" });
  await until(
    () => responses.some((r) => r.id === "p" && r.success === true),
    15000,
    "prompt accepted",
  );
  await until(() => events.some((e) => e.type === "agent_settled"), 120000, "agent settled");

  // Contract assertions — exactly what lua/pi_nvim/chat.lua consumes.
  const checks: [string, boolean][] = [
    ["agent_start", events.some((e) => e.type === "agent_start")],
    [
      "message_start role=assistant",
      events.some((e) => e.type === "message_start" && e.message?.role === "assistant"),
    ],
    [
      "text_delta via assistantMessageEvent",
      events.some(
        (e) =>
          e.type === "message_update" &&
          e.assistantMessageEvent?.type === "text_delta" &&
          typeof e.assistantMessageEvent.delta === "string",
      ),
    ],
    ["turn_end", events.some((e) => e.type === "turn_end")],
    ["agent_settled", events.some((e) => e.type === "agent_settled")],
  ];
  const text = events
    .filter((e) => e.type === "message_update" && e.assistantMessageEvent?.type === "text_delta")
    .map((e) => e.assistantMessageEvent?.delta ?? "")
    .join("");
  checks.push(["final text is 'ok'", text.trim() === "ok"]);

  send({ type: "dispose" });
  let failed = 0;
  for (const [name, ok] of checks) {
    console.log(`LIVE ${ok ? "OK  " : "FAIL"} ${name}`);
    if (!ok) failed++;
  }
  console.log(failed === 0 ? "LIVE PASS" : `LIVE FAIL (${failed})`);
  process.exit(failed === 0 ? 0 : 1);
} catch (error) {
  console.error("LIVE ERROR", error instanceof Error ? error.message : String(error));
  send({ type: "dispose" });
  process.exit(1);
}
