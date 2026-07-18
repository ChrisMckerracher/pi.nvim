/**
 * queue.ts — FIFO serializer for protocol commands.
 *
 * Commands against one agent session are order-sensitive (a prompt followed
 * by an abort must run in that order; dispose must wait for everything
 * in flight). Events are not queued — they stream as the agent emits them.
 */
export interface CommandQueue {
  /** Append a task; it runs after all previously enqueued tasks settle. */
  enqueue(task: () => Promise<void>): void;
  /** Resolves when every enqueued task has settled (used by tests). */
  idle(): Promise<void>;
}

export function createCommandQueue(): CommandQueue {
  let tail: Promise<void> = Promise.resolve();
  return {
    enqueue(task) {
      // Tasks report their own errors (error responses / host_error events);
      // the catch keeps the chain alive so one failure can't stall the queue.
      tail = tail.then(task).catch(() => undefined);
    },
    idle() {
      return tail;
    },
  };
}
