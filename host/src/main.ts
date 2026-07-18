/**
 * main.ts — stdio entry point. Boots the AgentHost against the user's real
 * ~/.pi/agent config, then serves protocol commands until `dispose` or
 * stdin EOF. Agent events stream to stdout as they arrive.
 */
import process from "node:process";

import {
  PROTOCOL_VERSION,
  createLineSplitter,
  encode,
  parseCommand,
  requireMessage,
  type Command,
  type OutboundMessage,
  type Response,
} from "./protocol.js";
import { createCommandQueue } from "./queue.js";
import { AgentHost } from "./session.js";

function write(message: OutboundMessage): void {
  process.stdout.write(encode(message));
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function reply(command: Command, rest: Omit<Response, "type" | "command" | "id">): Response {
  return {
    ...(command.id !== undefined ? { id: command.id } : {}),
    type: "response",
    command: command.type,
    ...rest,
  };
}

/** Execute one command. Returns null only for `dispose` (caller exits). */
async function dispatch(host: AgentHost, command: Command): Promise<Response | null> {
  try {
    switch (command.type) {
      case "hello":
        return reply(command, {
          success: true,
          data: {
            protocol: PROTOCOL_VERSION,
            host: "pi-nvim-host",
            node: process.version,
            state: host.state(),
          },
        });
      case "get_state":
        return reply(command, { success: true, data: host.state() });
      case "prompt":
        await host.prompt(requireMessage(command));
        return reply(command, { success: true });
      case "steer":
        await host.steer(requireMessage(command));
        return reply(command, { success: true });
      case "follow_up":
        await host.followUp(requireMessage(command));
        return reply(command, { success: true });
      case "abort":
        await host.abort();
        return reply(command, { success: true });
      case "new_session":
        return reply(command, { success: true, data: await host.newSession() });
      case "cycle_thinking":
        return reply(command, { success: true, data: { level: host.cycleThinking() ?? null } });
      case "dispose":
        return null;
    }
  } catch (error) {
    return reply(command, { success: false, error: errorMessage(error) });
  }
}

async function boot(): Promise<AgentHost> {
  try {
    return await AgentHost.start(process.cwd(), write);
  } catch (error) {
    write({ type: "host_error", message: `boot failed: ${errorMessage(error)}` });
    process.exit(1);
  }
}

const host = await boot();
const queue = createCommandQueue();

const split = createLineSplitter((line) => {
  if (line.trim() === "") return;

  let command: Command;
  try {
    command = parseCommand(line);
  } catch (error) {
    write({ type: "response", command: "parse", success: false, error: errorMessage(error) });
    return;
  }

  queue.enqueue(async () => {
    if (command.type === "dispose") {
      await host.dispose();
      process.exit(0);
    }
    const response = await dispatch(host, command);
    if (response !== null) write(response);
  });
});

process.stdin.setEncoding("utf8");
process.stdin.on("data", split);
process.stdin.on("end", () => {
  queue.enqueue(async () => {
    await host.dispose();
    process.exit(0);
  });
});
