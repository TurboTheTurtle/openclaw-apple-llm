import { execFileSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import {
  definePluginEntry,
  type OpenClawPluginApi,
  type ProviderAuthContext,
  type ProviderAuthMethodNonInteractiveContext,
  type ProviderAuthResult,
  type ProviderCatalogContext,
} from "openclaw/plugin-sdk/plugin-entry";
import { createAssistantMessageEventStream } from "@mariozechner/pi-ai";
import type {
  AssistantMessage,
  Context,
  Model,
  Api,
  SimpleStreamOptions,
} from "@mariozechner/pi-ai";

const PROVIDER_ID = "apple";
const MODEL_ID = "apple/foundation";
const DUMMY_API_KEY = "apple-local";

function resolveAppleLlmBinary(): string | null {
  // 1. Check PATH
  try {
    const result = execFileSync("which", ["apple-llm"], {
      encoding: "utf-8",
      timeout: 3000,
    }).trim();
    if (result) return result;
  } catch {
    // not in PATH
  }

  // 2. Known fallback locations
  const fallbacks = [
    `${process.env.HOME}/bin/apple-llm`,
    "/usr/local/bin/apple-llm",
  ];
  for (const p of fallbacks) {
    try {
      if (existsSync(p)) {
        execFileSync("test", ["-x", p], { timeout: 1000 });
        return p;
      }
    } catch {
      // not executable or doesn't exist
    }
  }

  return null;
}

function extractPromptFromContext(context: Context): {
  prompt: string;
  system: string;
} {
  const system = context.systemPrompt ?? "";

  // Find the last user message
  let prompt = "";
  for (let i = context.messages.length - 1; i >= 0; i--) {
    const msg = context.messages[i];
    if (msg.role === "user") {
      if (typeof msg.content === "string") {
        prompt = msg.content;
      } else if (Array.isArray(msg.content)) {
        prompt = msg.content
          .filter((c): c is { type: "text"; text: string } => c.type === "text")
          .map((c) => c.text)
          .join("\n");
      }
      break;
    }
  }

  return { prompt, system };
}

function makeEmptyUsage() {
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  };
}

function buildAssistantMessage(
  text: string,
  stopReason: "stop" | "error",
  errorMessage?: string,
): AssistantMessage {
  return {
    role: "assistant",
    content: [{ type: "text", text }],
    api: "openai-completions",
    provider: PROVIDER_ID,
    model: "apple-foundation",
    usage: makeEmptyUsage(),
    stopReason,
    ...(errorMessage ? { errorMessage } : {}),
    timestamp: Date.now(),
  };
}

export default definePluginEntry({
  id: "apple-llm",
  name: "Apple Foundation Models Provider",
  description: "Local Apple Foundation Models provider via apple-llm CLI",
  register(api: OpenClawPluginApi) {
    api.registerProvider({
      id: PROVIDER_ID,
      label: "Apple Foundation Models",
      auth: [
        {
          id: "local",
          label: "Apple Foundation Models (local)",
          hint: "Local on-device model via apple-llm CLI",
          kind: "custom",
          run: async (_ctx: ProviderAuthContext): Promise<ProviderAuthResult> => {
            return {
              profiles: [
                {
                  profileId: "apple:default",
                  credential: {
                    type: "api_key",
                    provider: PROVIDER_ID,
                    key: DUMMY_API_KEY,
                  },
                },
              ],
            };
          },
          runNonInteractive: async (
            _ctx: ProviderAuthMethodNonInteractiveContext,
          ) => {
            return null;
          },
        },
      ],
      catalog: {
        order: "late",
        run: async (_ctx: ProviderCatalogContext) => {
          const binaryPath = resolveAppleLlmBinary();
          if (!binaryPath) {
            return null;
          }

          return {
            provider: {
              baseUrl: "http://localhost:0",
              apiKey: DUMMY_API_KEY,
              api: "openai-completions" as const,
              models: [
                {
                  id: MODEL_ID,
                  name: "Apple Foundation Model (~3B)",
                  api: "openai-completions" as const,
                  reasoning: false,
                  input: ["text"] as Array<"text" | "image">,
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 4096,
                  maxTokens: 4096,
                },
              ],
            },
          };
        },
      },
      wrapStreamFn: (_ctx) => {
        const binaryPath = resolveAppleLlmBinary();
        if (!binaryPath) {
          return null;
        }

        return (
          model: Model<Api>,
          context: Context,
          options?: SimpleStreamOptions,
        ) => {
          const stream = createAssistantMessageEventStream();

          const { prompt, system } = extractPromptFromContext(context);

          const payload = JSON.stringify({
            prompt,
            system,
            max_tokens: options?.maxTokens ?? 4096,
            temperature: options?.temperature ?? 0.7,
          });

          const child = spawn(binaryPath, ["--json", "--no-stream"], {
            stdio: ["pipe", "pipe", "pipe"],
          });

          let stdout = "";
          let stderr = "";

          child.stdout.on("data", (chunk: Buffer) => {
            stdout += chunk.toString();
          });

          child.stderr.on("data", (chunk: Buffer) => {
            stderr += chunk.toString();
          });

          child.on("error", (err) => {
            const msg = buildAssistantMessage(
              "",
              "error",
              `apple-llm spawn error: ${err.message}`,
            );
            stream.push({ type: "start", partial: msg });
            stream.end(msg);
          });

          child.on("close", (code) => {
            if (code !== 0) {
              const errText = stderr.trim() || `apple-llm exited with code ${code}`;
              const msg = buildAssistantMessage("", "error", errText);
              stream.push({ type: "start", partial: msg });
              stream.end(msg);
              return;
            }

            try {
              const result = JSON.parse(stdout.trim()) as {
                content: string;
                model: string;
                tokens_used: number | null;
              };

              const responseText = result.content ?? "";
              const partial = buildAssistantMessage(responseText, "stop");

              stream.push({ type: "start", partial });
              stream.push({
                type: "text_start",
                contentIndex: 0,
                partial,
              });
              stream.push({
                type: "text_end",
                contentIndex: 0,
                content: responseText,
                partial,
              });
              stream.end(partial);
            } catch (parseErr) {
              const errMsg =
                parseErr instanceof Error ? parseErr.message : String(parseErr);
              const msg = buildAssistantMessage(
                "",
                "error",
                `Failed to parse apple-llm output: ${errMsg}\nRaw: ${stdout.slice(0, 200)}`,
              );
              stream.push({ type: "start", partial: msg });
              stream.end(msg);
            }
          });

          // Write payload to stdin and close
          child.stdin.write(payload);
          child.stdin.end();

          return stream;
        };
      },
    });
  },
});
