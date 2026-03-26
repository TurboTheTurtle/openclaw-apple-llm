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

| Test | apple-llm (~3B) | Ollama llama3.2 (3B) | Ollama llama3.1 (8B) |
|---|---|---|---|
| **Short prompt** ("What is 2+2?") | **0.30s** | 0.42s | 0.61s |
| **Medium response** (~120 words) | **2.93s** | 4.84s | 14.08s |
| **Longer response** (~350 words) | **5.65s** | 9.70s | 18.90s |
| **Throughput** (longer response) | **~55 w/s** | ~35 w/s | ~17 w/s |

The 8B model is 3x slower than apple-llm on this machine due to memory pressure (4.3GB model on a 16GB system with ~5-8GB available).

### Memory

These two tools manage memory very differently. Per-process RSS (`ps`) doesn't tell the full story for apple-llm because the model runs on the Neural Engine, outside any userspace process. To get a real comparison, we measured **total system memory delta** via `vm_stat` before, during, and after inference.

| | apple-llm | Ollama (llama3.2:3b) |
|---|---|---|
| **System memory delta (cold start)** | ~860 MB | ~2,330 MB |
| **System memory delta (warm)** | ~20-250 MB | ~0 MB (already loaded) |
| **Residual after inference** | ~800 MB (OS-managed, reclaimable) | ~2,300 MB (pinned until idle timeout) |
| **Per-process RSS** | ~19 MB (CLI wrapper only) | ~2,300 MB (model weights in process) |

**How apple-llm works under the hood:** The CLI process (~19MB) is just an IPC client. It sends the prompt to Apple's Neural Engine daemons (`aned`, `aneuserd`), which are always-on system services (~11MB combined). The ~3B model weights are loaded by the OS onto the Neural Engine hardware — they don't appear in any process's RSS, but they do consume ~860MB of system memory on first load.

**Key differences from Ollama:**
- Apple's model memory is **OS-managed and reclaimable** — the system can evict it under memory pressure. Ollama's 2.3GB is pinned in userspace until its idle timeout (default 5 minutes).
- The apple-llm CLI process **exits immediately** after inference. Ollama's server stays resident.
- Total system cost is roughly **2.5-3x less** than Ollama for a comparable 3B model, with the added benefit that the OS can reclaim the memory when needed.

### Model Quality

We ran identical prompts through three models for tasks typical of OpenClaw cron jobs:

| Test | apple-llm (Apple FM ~3B) | Ollama llama3.2 (3B) | Ollama llama3.1 (8B) |
|---|---|---|---|
| **Summarize JSON** | Correct, listed all services | Correct, grouped by status | Correct |
| **Extract action items** | Got 2 of 3 | Got 3 of 3 | Got 3 of 3 |
| **Classify error log** | "network" (wrong) | "application" (wrong) | **"database" (correct)** |
| **Format for Slack** | Clean one-liner | Verbose with hashtags | Clean one-liner |
| **JSON extraction** | Both correct, but markdown-wrapped | Missed one container | **Both correct, clean JSON** |
| **Disk usage reasoning** | Wrong ("not concerned" at 90%) | Correct | Correct |

**Verdict:** The 8B model is noticeably better — nails classification, produces clean JSON, and follows instructions more precisely. The two 3B models (Apple FM and llama3.2) are roughly comparable, trading wins depending on the task. For OpenClaw cron jobs, apple-llm handles summarization and formatting well; tasks requiring precise structured output or classification would benefit from a larger model.

### Why apple-llm on a Mac mini

Real-world memory budget on a 16GB Mac mini M4 running OpenClaw, Plex, Scrypted, AdGuard, and other home lab services:

| Scenario | Baseline used | Available for inference |
|---|---|---|
| **Headless** (normal operation) | ~6 GB | **~8 GB** |
| **With VS Code remote session** | ~8.7 GB | **~5.4 GB** |

*Note: VS Code's remote server + language servers consume ~2.6GB when actively connected. This is transient — it's not running during cron jobs.*

How each model fits into that budget:

| Model | Memory cost | Fits headless? | Fits with VS Code? | Speed |
|---|---|---|---|---|
| **apple-llm** (Apple FM ~3B) | ~860 MB (reclaimable) | Yes, plenty | Yes, plenty | ~55 w/s |
| **Ollama llama3.2** (3B) | 2.3 GB (pinned) | Yes | Yes, tight | ~35 w/s |
| **Ollama llama3.1** (8B) | 4.3 GB (pinned) | Yes | Causes swap pressure | ~17 w/s |

The 8B model is the best quality option, but on a 16GB Mac mini it's impractical during development sessions — 4.3GB pinned leaves almost nothing for spikes. In headless mode it fits, but runs 3x slower than apple-llm due to memory pressure.

apple-llm is the sweet spot: good-enough quality for routine cron jobs, fastest inference, and minimal memory impact. For the occasional task that needs higher quality (precise classification, clean JSON), route it to a cloud API instead of paying the memory tax of a local 8B model.

## Security

- **No network access** — all inference runs on-device, nothing leaves the machine
- **No persistent state** — load, infer, exit. No files written, no config stored
- **No secrets** — doesn't touch API keys, credentials, or user data
- **Apple guardrails** — built-in content safety that cannot be disabled
- **Direct spawn** — OpenClaw pipes JSON in/out via child process, no HTTP server or open ports

## License

MIT
