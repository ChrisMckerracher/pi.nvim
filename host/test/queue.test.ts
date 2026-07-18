import { describe, expect, it } from "vitest";
import { createCommandQueue } from "../src/queue.js";

describe("createCommandQueue", () => {
  it("runs tasks in FIFO order even when earlier tasks are slow", async () => {
    const order: number[] = [];
    const queue = createCommandQueue();
    const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

    queue.enqueue(async () => {
      await sleep(30);
      order.push(1);
    });
    queue.enqueue(async () => {
      order.push(2);
    });
    queue.enqueue(async () => {
      order.push(3);
    });

    await queue.idle();
    expect(order).toEqual([1, 2, 3]);
  });

  it("keeps running after a task rejects", async () => {
    const order: string[] = [];
    const queue = createCommandQueue();

    queue.enqueue(async () => {
      order.push("before");
    });
    queue.enqueue(async () => {
      order.push("boom");
      throw new Error("task failure");
    });
    queue.enqueue(async () => {
      order.push("after");
    });

    await queue.idle();
    expect(order).toEqual(["before", "boom", "after"]);
  });
});
