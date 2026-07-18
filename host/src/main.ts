/**
 * pi.nvim host — stdio entry point.
 *
 * Phase 0 scope: protocol handshake (`hello`), clean shutdown (`dispose`),
 * and clear errors for everything else. Phase 1 wires `prompt` to
 * createAgentSessionRuntime() from the pi SDK.
 */
import process from "node:process";

import {
  PROTOCOL_VERSION,
  createLineSplitter,
  encode,
  parseCommand,
  type Response,
} from "./protocol.js";

function respond(response: Response): void {
  process.stdout.write(encode(response));
}

/** Build a response, attaching `id` only when the command carried one. */
function replyTo(
  command: { id?: string; type: string },
  rest: Omit<Response, "type" | "command" | "id">,
): Response {
  return {
    ...(command.id !== undefined ? { id: command.id } : {}),
    type: "response",
    command: command.type,
    ...rest,
  };
}

const split = createLineSplitter((line) => {
  if (line.trim() === "") return;

  let command;
  try {
    command = parseCommand(line);
  } catch (error) {
    respond({
      type: "response",
      command: "parse",
      success: false,
      error: error instanceof Error ? error.message : String(error),
    });
    return;
  }

  switch (command.type) {
    case "hello":
      respond(
        replyTo(command, {
          success: true,
          data: {
            protocol: PROTOCOL_VERSION,
            host: "pi-nvim-host",
            node: process.version,
          },
        }),
      );
      break;
    case "dispose":
      process.exit(0);
      break;
    default:
      respond(
        replyTo(command, {
          success: false,
          error: `Not implemented in Phase 0: ${command.type}`,
        }),
      );
  }
});

process.stdin.setEncoding("utf8");
process.stdin.on("data", split);
