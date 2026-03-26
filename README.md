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

Tested on Mac mini M4, macOS 26.4. All times are wall-clock, averaged over 3 runs.

### Latency & Throughput

| Metric | Result |
|---|---|
| **Cold start + short prompt** | ~0.33s (warm), ~0.64s (first run) |
| **Time to first byte (streaming)** | ~0.22s |
| **Medium response (~120 words)** | ~2.8s (~42 words/s) |
| **Longer response (~300 words)** | ~5.6s (~58 words/s) |
| **JSON mode (short prompt)** | ~0.28s |

### Memory

The `apple-llm` process itself is lightweight (~19MB RSS) — it's just an IPC client. The actual inference runs in Apple's system daemons that manage the Neural Engine:

| Process | RSS | Role |
|---|---|---|
| `apple-llm` | ~19 MB | CLI process (Swift runtime + IPC stubs) |
| `aned` | ~38 MB | ANE daemon — hosts model execution |
| `ANECompilerService` | ~5 MB | Compiles model graphs for Neural Engine |
| `aneuserd` | ~4 MB | User-space ANE interface |

The ~3B parameter model weights are loaded directly onto the Neural Engine hardware and managed by the OS kernel — they don't appear in any process's RSS. Apple's ANE daemons (~47MB combined) run regardless of whether `apple-llm` is active, so the marginal cost of running inference is effectively just the 19MB CLI process, which exits immediately after.

For comparison, Ollama keeps the full model weights resident in userspace RAM (3-4GB+ for a comparable model) even when idle.

## Security

- **No network access** — all inference runs on-device, nothing leaves the machine
- **No persistent state** — load, infer, exit. No files written, no config stored
- **No secrets** — doesn't touch API keys, credentials, or user data
- **Apple guardrails** — built-in content safety that cannot be disabled
- **Direct spawn** — OpenClaw pipes JSON in/out via child process, no HTTP server or open ports

## License

MIT
