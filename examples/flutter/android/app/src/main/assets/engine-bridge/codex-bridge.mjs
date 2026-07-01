#!/usr/bin/env node
// codex-bridge.mjs — Bridge between Flutter chat UI and Codex (OpenCode) SDK.
//
// Protocol: same JSON lines as cc-bridge.mjs.

import { createInterface } from "readline";

// Codex SDK import — the package name may vary; adjust after confirming.
let codexSdk;
try {
  codexSdk = await import("@opencode-ai/sdk");
} catch {
  try {
    codexSdk = await import("codex");
  } catch (err) {
    process.stdout.write(
      JSON.stringify({
        type: "turn_failed",
        error: `Failed to import codex SDK: ${err?.message ?? err}`,
      }) + "\n"
    );
    process.exit(1);
  }
}

const CWD = process.env.WORKSPACE_DIR || "/workspace";

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

let currentAbort = null;

async function handleSend(text) {
  const abortController = new AbortController();
  currentAbort = abortController;

  try {
    // Attempt the v2 API first (structured session), fall back to simple exec.
    if (codexSdk.unstable_v2_prompt) {
      const result = await codexSdk.unstable_v2_prompt({
        prompt: text,
        cwd: CWD,
        abortSignal: abortController.signal,
      });

      if (typeof result === "string") {
        emit({ type: "assistant_delta", text: result });
      } else if (result && typeof result[Symbol.asyncIterator] === "function") {
        for await (const chunk of result) {
          if (abortController.signal.aborted) break;
          if (typeof chunk === "string") {
            emit({ type: "assistant_delta", text: chunk });
          } else if (chunk?.type === "text") {
            emit({ type: "assistant_delta", text: chunk.text ?? "" });
          } else if (chunk?.type === "tool_use") {
            emit({
              type: "tool_call_start",
              id: chunk.id ?? "",
              name: chunk.name ?? "tool",
              input: JSON.stringify(chunk.input ?? {}).slice(0, 500),
            });
          } else if (chunk?.type === "tool_result") {
            emit({
              type: "tool_call_done",
              id: chunk.tool_use_id ?? "",
              output: String(chunk.content ?? "").slice(0, 2000),
            });
          }
        }
      }
    } else if (codexSdk.query) {
      const messages = await codexSdk.query({
        prompt: text,
        options: { cwd: CWD },
        abortSignal: abortController.signal,
      });

      for await (const message of messages) {
        if (abortController.signal.aborted) break;
        if (message.type === "assistant") {
          for (const block of message.message?.content ?? []) {
            if (block.type === "text") {
              emit({ type: "assistant_delta", text: block.text ?? "" });
            }
          }
        }
      }
    } else {
      emit({
        type: "turn_failed",
        error: "No compatible SDK API found (need query or unstable_v2_prompt)",
      });
      return;
    }

    emit({ type: "turn_completed" });
  } catch (err) {
    if (abortController.signal.aborted) {
      emit({ type: "turn_completed" });
    } else {
      emit({ type: "turn_failed", error: err?.message ?? String(err) });
    }
  } finally {
    currentAbort = null;
  }
}

function handleCancel() {
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
  }
}

const rl = createInterface({ input: process.stdin });

rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed || !trimmed.startsWith("{")) return;
  try {
    const msg = JSON.parse(trimmed);
    switch (msg.type) {
      case "send":
        handleSend(msg.text ?? "");
        break;
      case "cancel":
        handleCancel();
        break;
    }
  } catch {
    // Ignore malformed input.
  }
});

rl.on("close", () => process.exit(0));

emit({ type: "ready" });
