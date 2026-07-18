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
      case "list_sessions":
        return reply(command, { success: true, data: await host.listSessions() });
      case "switch_session": {
        if (!("path" in command) || typeof command.path !== "string" || command.path === "") {
          throw new Error("Command 'switch_session' requires a non-empty 'path' field");
        }
        return reply(command, { success: true, data: await host.switchSession(command.path) });
      }
      case "get_messages":
        return reply(command, { success: true, data: host.getMessages() });
      case "list_models":
        return reply(command, { success: true, data: await host.listModels() });
      case "set_model": {
        if (
          !("provider" in command) ||
          typeof command.provider !== "string" ||
          !("modelId" in command) ||
          typeof command.modelId !== "string"
        ) {
          throw new Error("Command 'set_model' requires 'provider' and 'modelId' strings");
        }
        return reply(command, {
          success: true,
          data: await host.setModel(command.provider, command.modelId),
        });
      }
      case "cycle_model":
        return reply(command, { success: true, data: await host.cycleModel() });
      case "editor_context_response": {
        const delivered = host.resolveEditorContext(command.requestId, command.context);
        return reply(command, {
          success: delivered,
          ...(delivered ? {} : { error: "Unknown or stale requestId" }),
        });
      }
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
