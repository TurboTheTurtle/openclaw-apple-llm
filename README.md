# openclaw-apple-llm

An [OpenClaw](https://github.com/TurboTheTurtle/openclaw) plugin that bridges Apple's on-device Foundation Models (Apple Intelligence) to any application via stdin/stdout. Run cron jobs, format reports, triage logs, and summarize data — all using free, private, on-device inference instead of burning tokens on expensive cloud LLMs.

No daemon, no HTTP server — load, infer, exit. Zero idle RAM cost.

## Why

OpenClaw runs a multi-agent system with cron jobs, health checks, dashboard refreshes, and routine automation. Many of these tasks are simple — summarize some JSON, format a Slack message, classify a log line — and don't need a frontier model. Sending them to GPT-4 or Claude costs real money over time.

Apple's Foundation Models run a ~3B parameter model on the Neural Engine with OS-level memory management. The model loads on demand and unloads automatically — zero idle cost. But there's no CLI or API to call it from non-Swift apps. This bridge fixes that.

### What it's good for

- **Summarization** — health check results, API responses, cron output
- **Formatting** — rewriting plain text into Slack messages, Apple Notes, reports
- **Triage/classification** — routing error logs, categorizing alerts
- **Simple Q&A** — quick lookups that don't need web search or deep reasoning

### What it's not for

- Code generation or complex reasoning (use a frontier model)
- Precise structured output (the 3B model sometimes wraps JSON in markdown)
- Tasks requiring up-to-date knowledge (no internet access)

## Requirements

- macOS 26+ (Tahoe) on Apple Silicon
- Apple Intelligence enabled (System Settings > Apple Intelligence & Siri)
- Xcode 26+ (for building)

## Install

```bash
git clone https://github.com/TurboTheTurtle/openclaw-apple-llm.git
cd openclaw-apple-llm
make install    # builds release + symlinks to /usr/local/bin
```

Or build manually:

```bash
swift build -c release
# binary at .build/release/apple-llm
```

## Usage

### Basic

```bash
# Pipe text via stdin
echo "Summarize this: Apple announced new features today" | apple-llm

# Use --prompt flag
apple-llm --prompt "What is 2+2?"

# With system instructions
apple-llm --prompt "Translate to French" --system "You are a translator"

# Buffered output (no streaming)
apple-llm --prompt "Hello" --no-stream
```

### JSON Mode

For programmatic use and OpenClaw integration, use `--json` mode:

```bash
# JSON input/output
echo '{"prompt":"What is 2+2?","max_tokens":100}' | apple-llm --json
# => {"content":"2+2 equals 4.","model":"apple-foundation","tokens_used":null}

# With system prompt and temperature
echo '{"prompt":"Hello","system":"You are a pirate","temperature":1.5}' | apple-llm --json
```

### OpenClaw Integration

OpenClaw spawns `apple-llm --json` as a child process — no server, no network surface:

```bash
# From a cron job or agent script
RESULT=$(echo '{"prompt":"Summarize this health check: ...","max_tokens":200}' | apple-llm --json)

# Parse with jq
CONTENT=$(echo "$RESULT" | jq -r '.content')
```

### Options

```
--prompt <text>       Prompt text (alternative to stdin)
--system <text>       System instructions for the model
--max-tokens <n>      Maximum response tokens
--temperature <n>     Sampling temperature (0.0-2.0)
--json                JSON input/output mode
--no-stream           Disable streaming (buffer full response)
--version             Show version
--help                Show help
```

### Error Handling

Errors go to stderr with exit code 1:

```bash
apple-llm --prompt "" 2>/dev/null || echo "failed"
```

## Benchmarks

Head-to-head comparison on Mac mini M4, macOS 26.4. Ollama running `llama3.2:3b` (same ~3B parameter class). All times wall-clock, median of 3 runs.

### Latency & Throughput

| Test | apple-llm | Ollama (llama3.2:3b) | Diff |
|---|---|---|---|
| **Short prompt** ("What is 2+2?") | 0.30s | 0.42s | 1.4x faster |
| **Medium response** (~120 words) | 2.93s | 4.84s | 1.7x faster |
| **Longer response** (~350 words) | 6.42s | 9.70s | 1.5x faster |
| **JSON/API mode** (short prompt) | 0.31s | 0.41s | 1.3x faster |
| **Throughput** (longer response) | ~55 words/s | ~35 words/s | 1.6x faster |

### Memory

| | apple-llm | Ollama |
|---|---|---|
| **During inference** | ~19 MB (CLI process) | ~2,300 MB (model in RAM) |
| **Idle** | 0 MB (process exits) | ~2,300 MB (model stays resident) |

The `apple-llm` process is just an IPC client — the actual inference runs on Apple's Neural Engine via system daemons:

| Process | RSS | Role |
|---|---|---|
| `apple-llm` | ~19 MB | CLI process (Swift runtime + IPC stubs) |
| `aned` | ~8 MB | ANE daemon — hosts model execution |
| `aneuserd` | ~3 MB | User-space ANE interface |

The ~3B parameter model weights are loaded directly onto the Neural Engine hardware and managed by the OS kernel — they don't appear in any process's RSS. The ANE daemons (~11MB combined) run regardless of whether `apple-llm` is active, so the marginal cost of running inference is just the 19MB CLI process, which exits immediately after.

Ollama keeps the full model weights resident in userspace RAM (2.3GB for llama3.2:3b) and its server process (93MB) runs continuously.

## Security

- **No network access** — all inference runs on-device, nothing leaves the machine
- **No persistent state** — load, infer, exit. No files written, no config stored
- **No secrets** — doesn't touch API keys, credentials, or user data
- **Apple guardrails** — built-in content safety that cannot be disabled
- **Direct spawn** — OpenClaw pipes JSON in/out via child process, no HTTP server or open ports

## License

MIT
