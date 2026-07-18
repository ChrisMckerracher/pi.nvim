/**
 * Smoke test — boots the REAL user config (~/.pi/agent) through the pi SDK.
 * Validates ADR-003 assumptions end to end without touching the Neovim side.
 *
 * Run: node scripts/smoke.ts   (Node 24 strips types natively)
 *
 * Uses an in-memory session (user's session store is NOT polluted) and one
 * near-free prompt with thinking off (user's `max` default is unaffected).
 */
import { tmpdir } from "node:os";
import process from "node:process";
import { createAgentSession, SessionManager } from "@earendil-works/pi-coding-agent";

const cwd = tmpdir(); // clean discovery surface: no AGENTS.md, no .pi/

console.log("== createAgentSession with user defaults ==");
const { session, extensionsResult, modelFallbackMessage } = await createAgentSession({
  cwd,
  sessionManager: SessionManager.inMemory(cwd),
  thinkingLevel: "off", // cheap round-trip only
});

console.log("\nextensions loaded:");
for (const ext of extensionsResult.extensions) {
  const e = ext as { path?: string; name?: string };
  console.log("  -", e.path ?? e.name ?? JSON.stringify(ext).slice(0, 120));
}
if (extensionsResult.errors.length > 0) {
  console.log("extension ERRORS:");
  for (const err of extensionsResult.errors) console.log("  !", err.path, "-", err.error);
}

console.log(
  "\nmodel:",
  session.model
    ? `${session.model.provider}/${session.model.id} (${session.model.name})`
    : "(none)",
);
console.log("thinkingLevel (smoke override):", session.thinkingLevel);
if (modelFallbackMessage) console.log("model fallback:", modelFallbackMessage);

console.log("\n== prompt round-trip (1 prompt, thinking off) ==");
let text = "";
session.subscribe((event) => {
  if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") {
    text += event.assistantMessageEvent.delta;
  }
});
await session.prompt("Reply with exactly: ok");
console.log("assistant said:", JSON.stringify(text.trim()));

session.dispose();
console.log("\nSMOKE OK");
process.exit(0);
