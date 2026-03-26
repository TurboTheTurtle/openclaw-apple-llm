import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
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
const SHIM_PORT = 18787;
// Static token — must be identical across all shim restarts so the auth
// profile stored at gateway startup matches the shim spawned during catalog.
const STATIC_TOKEN = "apple-llm-local-provider-token-v1";
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
    try {
      process.kill(data.pid, 0);
    } catch {
      return null;
    }
    return data;
  } catch {
    return null;
  }
}

function spawnShim(binaryPath: string, token: string): void {
  mkdirSync(SHIM_DIR, { recursive: true });
  const shimScript = join(__dirname, "shim.mjs");
  const child = spawn(
    process.execPath,
    [shimScript, binaryPath, token, PORT_FILE],
    { detached: true, stdio: "ignore" },
  );
  child.unref();
}

/** Non-blocking: returns existing shim state or spawns a new one and polls async. */
async function ensureShimRunning(binaryPath: string): Promise<{ port: number; token: string }> {
  const existing = readShimState();
  if (existing) {
    return { port: existing.port, token: existing.token };
  }

  spawnShim(binaryPath, STATIC_TOKEN);

  // Poll for port file with async sleep (does NOT block the event loop)
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 100));
    const state = readShimState();
    if (state) {
      return { port: state.port, token: state.token };
    }
  }

  throw new Error("apple-llm shim failed to start within 5 seconds");
}

export default definePluginEntry({
  id: "apple-llm",
  name: "Apple Foundation Models Provider",
  description: "Local Apple Foundation Models provider via apple-llm CLI",
  register(api: OpenClawPluginApi) {
    const binaryPath = resolveAppleLlmBinary();
    if (!binaryPath) return;

    // Pre-seed auth credential synchronously so the gateway's AuthStorage
    // loads it at startup, before catalog discovery spawns the shim.
    upsertAuthProfileWithLock({
      profileId: "apple:default",
      credential: { type: "api_key", provider: PROVIDER_ID, key: STATIC_TOKEN },
    }).catch(() => {});

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
            const shim = await ensureShimRunning(binaryPath);
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
      catalog: {
        order: "late",
        run: async (_ctx: ProviderCatalogContext) => {
          if (!resolveAppleLlmBinary()) return null;

          const shim = await ensureShimRunning(binaryPath);
          // Use actual shim port (usually SHIM_PORT unless EADDRINUSE fallback)
          const baseUrl = `http://127.0.0.1:${shim.port}`;

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
                  contextWindow: 16384,
                  maxTokens: 2048,
                },
              ],
            },
          };
        },
      },
    });
  },
});
