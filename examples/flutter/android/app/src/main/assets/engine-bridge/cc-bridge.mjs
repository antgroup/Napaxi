#!/usr/bin/env node
// cc-bridge.mjs — Bridge between Flutter chat UI and Claude Agent SDK.
//
// Protocol:
//   stdin  ← JSON lines from Flutter: {"type":"send","text":"..."} | {"type":"cancel"}
//   stdout → JSON lines to Flutter:   {"type":"ready"} | {"type":"assistant_delta","text":"..."}
//                                      {"type":"tool_call_start","id":"...","name":"...","input":"..."}
//                                      {"type":"tool_call_done","id":"...","output":"..."}
//                                      {"type":"turn_completed"} | {"type":"turn_failed","error":"..."}
//                                      {"type":"status","message":"..."}

import { query } from "@anthropic-ai/claude-agent-sdk";
import { createInterface } from "readline";

const CWD = process.env.WORKSPACE_DIR || "/workspace";

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

let currentAbort = null;

function stringifyToolOutput(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value
      .map((item) => {
        if (typeof item === "string") return item;
        if (item && typeof item.text === "string") return item.text;
        try {
          return JSON.stringify(item);
        } catch {
          return String(item ?? "");
        }
      })
      .filter(Boolean)
      .join("\n");
  }
  if (value && typeof value.text === "string") return value.text;
  if (value == null) return "";
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function emitToolResults(message) {
  const content = message?.message?.content;
  if (!Array.isArray(content)) return;
  for (const block of content) {
    if (block?.type === "tool_result") {
      emit({
        type: "tool_call_done",
        id: block.tool_use_id ?? "",
        output: stringifyToolOutput(block.content).slice(0, 2000),
      });
    }
  }
}

async function handleSend(text) {
  const abortController = new AbortController();
  currentAbort = abortController;
  let resultError = null;

  try {
    const messages = query({
      prompt: text,
      options: {
        abortController,
        cwd: CWD,
        maxTurns: 30,
        includePartialMessages: true,
        permissionMode: "bypassPermissions",
        allowDangerouslySkipPermissions: true,
      },
    });

    for await (const message of messages) {
      if (abortController.signal.aborted) break;

      switch (message.type) {
        case "assistant":
          for (const block of message.message?.content ?? []) {
            if (block.type === "tool_use") {
              emit({
                type: "tool_call_start",
                id: block.id,
                name: block.name,
                input: JSON.stringify(block.input ?? {}).slice(0, 500),
              });
            }
          }
          break;

        case "user":
          emitToolResults(message);
          break;

        case "tool_progress":
          emit({ type: "status", message: `Running ${message.tool_name}...` });
          break;

        case "stream_event":
          if (message.event?.type === "content_block_delta") {
            const delta = message.event?.delta;
            if (delta?.type === "text_delta" && delta.text) {
              emit({ type: "assistant_delta", text: delta.text });
            }
          }
          break;

        case "result":
          if (message.subtype !== "success") {
            resultError = message.result || "Claude run failed";
          }
          break;
      }
    }

    if (resultError && !abortController.signal.aborted) {
      emit({ type: "turn_failed", error: resultError });
    } else {
      emit({ type: "turn_completed" });
    }
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

// Main loop: read JSON lines from stdin.
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

// Signal ready.
emit({ type: "ready" });
