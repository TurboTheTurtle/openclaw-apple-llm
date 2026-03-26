import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import {
  definePluginEntry,
  type OpenClawPluginApi,
  type ProviderAuthContext,
  type ProviderAuthMethodNonInteractiveContext,
  type ProviderAuthResult,
  type ProviderCatalogContext,
} from "openclaw/plugin-sdk/plugin-entry";
import { upsertAuthProfileWithLock } from "openclaw/plugin-sdk/agent-runtime";

const PROVIDER_ID = "apple";
const MODEL_ID = "foundation";
const SHIM_DIR = join(process.env.HOME ?? "/tmp", ".openclaw", "apple-llm-shim");
const PORT_FILE = join(SHIM_DIR, "shim.json");

function resolveAppleLlmBinary(): string | null {
  try {
    const result = execFileSync("which", ["apple-llm"], {
      encoding: "utf-8",
      timeout: 3000,
    }).trim();
    if (result) return result;
  } catch {}
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
    } catch {}
  }
  return null;
}

function readShimState(): { port: number; token: string; pid: number } | null {
  try {
    if (!existsSync(PORT_FILE)) return null;
    const data = JSON.parse(readFileSync(PORT_FILE, "utf-8"));
    if (!data.port || !data.token || !data.pid) return null;
    // Check if PID is still alive
    try {
      process.kill(data.pid, 0);
    } catch {
      return null; // process is dead
    }
    return data;
  } catch {
    return null;
  }
}

function ensureShimRunning(binaryPath: string): { port: number; token: string } {
  // Check if shim is already running
  const existing = readShimState();
  if (existing) {
    return { port: existing.port, token: existing.token };
  }

  // Ensure state directory exists
  mkdirSync(SHIM_DIR, { recursive: true });

  const token = randomBytes(32).toString("hex");
  const shimScript = join(__dirname, "shim.mjs");

  // Spawn detached shim process
  const child = spawn(
    process.execPath,
    [shimScript, binaryPath, token, PORT_FILE],
    {
      detached: true,
      stdio: "ignore",
    },
  );
  child.unref();

  // Wait for the shim to write its port file (up to 3 seconds)
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    const state = readShimState();
    if (state) {
      return { port: state.port, token: state.token };
    }
    // Busy-wait 50ms
    execFileSync("sleep", ["0.05"]);
  }

  throw new Error("apple-llm shim failed to start within 3 seconds");
}

export default definePluginEntry({
  id: "apple-llm",
  name: "Apple Foundation Models Provider",
  description: "Local Apple Foundation Models provider via apple-llm CLI",
  register(api: OpenClawPluginApi) {
    const binaryPath = resolveAppleLlmBinary();
    if (!binaryPath) return;

    api.registerProvider({
      id: PROVIDER_ID,
      label: "Apple Foundation Models",
      auth: [
        {
          id: "local",
          label: "Apple Foundation Models (local)",
          hint: "Local on-device model via apple-llm CLI",
          kind: "custom",
          run: async (
            _ctx: ProviderAuthContext,
          ): Promise<ProviderAuthResult> => {
            const shim = ensureShimRunning(binaryPath);
            return {
              profiles: [
                {
                  profileId: "apple:default",
                  credential: {
                    type: "api_key",
                    provider: PROVIDER_ID,
                    key: shim.token,
                  },
                },
              ],
            };
          },
          runNonInteractive: async (
            _ctx: ProviderAuthMethodNonInteractiveContext,
          ) => null,
        },
      ],
      prepareRuntimeAuth: async (ctx) => {
        if (ctx.provider !== PROVIDER_ID) return null;
        // Restart shim if it died between runs (e.g. idle timeout)
        const shim = ensureShimRunning(binaryPath);
        return {
          apiKey: shim.token,
          baseUrl: `http://127.0.0.1:${shim.port}`,
        };
      },
      catalog: {
        order: "late",
        run: async (_ctx: ProviderCatalogContext) => {
          if (!resolveAppleLlmBinary()) return null;

          const shim = ensureShimRunning(binaryPath);
          const baseUrl = `http://127.0.0.1:${shim.port}`;

          // Store auth credential with the shim's token
          await upsertAuthProfileWithLock({
            profileId: "apple:default",
            credential: {
              type: "api_key",
              provider: PROVIDER_ID,
              key: shim.token,
            },
          }).catch(() => {});

          return {
            provider: {
              baseUrl,
              apiKey: shim.token,
              api: "openai-completions" as const,
              models: [
                {
                  id: MODEL_ID,
                  name: "Apple Foundation Model (~3B)",
                  api: "openai-completions" as const,
                  reasoning: false,
                  input: ["text"] as Array<"text" | "image">,
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 262144,
                  maxTokens: 4096,
                },
              ],
            },
          };
        },
      },
    });
  },
});
