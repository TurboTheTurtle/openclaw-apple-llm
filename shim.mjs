#!/usr/bin/env node
// apple-llm HTTP shim — standalone server process
// Spawned by the apple-llm OpenClaw plugin, runs detached.
// Translates OpenAI /v1/chat/completions → apple-llm CLI subprocess.

import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { writeFileSync, unlinkSync, existsSync } from "node:fs";
import { dirname } from "node:path";

const BINARY_PATH = process.argv[2];
const TOKEN = process.argv[3];
const PORT_FILE = process.argv[4];

if (!BINARY_PATH || !TOKEN || !PORT_FILE) {
  process.exit(1);
}

const server = createServer((req, res) => {
  const auth = req.headers.authorization;
  if (auth !== `Bearer ${TOKEN}`) {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: "Unauthorized", type: "auth_error" } }));
    return;
  }

  // Serve /v1/models for openai-completions API probes
  if (req.method === "GET" && (req.url?.startsWith("/v1/models") || req.url?.startsWith("/models"))) {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      object: "list",
      data: [{ id: "foundation", object: "model", created: 0, owned_by: "apple" }],
    }));
    return;
  }

  if (req.method !== "POST" || !(req.url?.startsWith("/v1/chat/completions") || req.url?.startsWith("/chat/completions"))) {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: "Not found" } }));
    return;
  }

  let body = "";
  req.on("data", (chunk) => { body += chunk.toString(); });
  req.on("end", () => {
    let request;
    try {
      request = JSON.parse(body);
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: { message: "Invalid request body", type: "invalid_request" } }));
      return;
    }

    const messages = request.messages || [];
    const systemMsg = messages.find((m) => m.role === "system")?.content || "";
    const lastUserMsg = messages.filter((m) => m.role === "user").pop();
    let prompt = "";
    if (typeof lastUserMsg?.content === "string") {
      prompt = lastUserMsg.content;
    } else if (Array.isArray(lastUserMsg?.content)) {
      prompt = lastUserMsg.content
        .filter((c) => c.type === "text")
        .map((c) => c.text)
        .join("\n");
    }

    const payload = JSON.stringify({
      prompt,
      system: systemMsg,
      max_tokens: typeof request.max_tokens === "number" ? request.max_tokens : 4096,
      temperature: typeof request.temperature === "number" ? request.temperature : 0.7,
    });

    const child = spawn(BINARY_PATH, ["--json", "--no-stream"], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (c) => { stdout += c.toString(); });
    child.stderr.on("data", (c) => { stderr += c.toString(); });

    child.on("error", (err) => {
      if (!res.headersSent) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          error: { message: `apple-llm spawn error: ${err.message}`, type: "server_error" },
        }));
      }
    });

    child.on("close", (code) => {
      if (res.headersSent) return;
      if (code !== 0) {
        res.writeHead(502, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          error: { message: stderr.trim() || `apple-llm exited with code ${code}`, type: "server_error" },
        }));
        return;
      }
      try {
        const result = JSON.parse(stdout.trim());
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          id: `apple-${Date.now()}`,
          object: "chat.completion",
          created: Math.floor(Date.now() / 1000),
          model: "apple/foundation",
          choices: [{
            index: 0,
            message: { role: "assistant", content: result.content || "" },
            finish_reason: "stop",
          }],
          usage: {
            prompt_tokens: Math.ceil(body.length / 4),
            completion_tokens: Math.ceil((result.content || "").length / 4),
            total_tokens: Math.ceil(body.length / 4) + Math.ceil((result.content || "").length / 4),
          },
        }));
      } catch {
        res.writeHead(502, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          error: { message: "Failed to parse apple-llm output", type: "server_error" },
        }));
      }
    });

    child.stdin.write(payload);
    child.stdin.end();
  });
});

// Auto-shutdown after 4 hours of inactivity (outlives any cron interval)
const IDLE_TIMEOUT_MS = 4 * 60 * 60 * 1000;
let idleTimer = setTimeout(() => { cleanup(); process.exit(0); }, IDLE_TIMEOUT_MS);
server.on("request", () => {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => { cleanup(); process.exit(0); }, IDLE_TIMEOUT_MS);
});

function cleanup() {
  server.close();
  try { if (existsSync(PORT_FILE)) unlinkSync(PORT_FILE); } catch {}
}

process.on("SIGTERM", () => { cleanup(); process.exit(0); });
process.on("SIGINT", () => { cleanup(); process.exit(0); });

server.on("error", (err) => {
  if (err.code === "EADDRINUSE" && tryPort !== 0) {
    // Fixed port is taken — fall back to random
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      const port = typeof addr === "object" && addr ? addr.port : 0;
      writeFileSync(PORT_FILE, JSON.stringify({ port, token: TOKEN, pid: process.pid }));
    });
  } else {
    process.exit(1);
  }
});

// Use a fixed port derived from the token to avoid port drift across restarts.
// If the fixed port is taken (old shim still dying), fall back to random.
const FIXED_PORT = 18787;
const tryPort = process.argv[5] === "--random-port" ? 0 : FIXED_PORT;
server.listen(tryPort, "127.0.0.1", () => {
  const addr = server.address();
  const port = typeof addr === "object" && addr ? addr.port : 0;
  // Write port + token to file so the plugin can read it
  writeFileSync(PORT_FILE, JSON.stringify({ port, token: TOKEN, pid: process.pid }));
});
