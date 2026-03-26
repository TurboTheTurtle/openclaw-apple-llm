# apple-llm

A Swift CLI that bridges Apple's on-device Foundation Models (Apple Intelligence) to any application via stdin/stdout. Run scripts, cron jobs, and automation pipelines using free, private, on-device inference.

No daemon, no HTTP server -- load, infer, exit. Zero idle RAM cost.

## Why

Apple's Foundation Models run a ~3B parameter model on the Neural Engine with OS-level memory management. The model loads on demand and unloads automatically. But there's no CLI or API to call it from non-Swift apps. This bridge fixes that.

### What it's good for

- **Summarization** -- health check results, API responses, log output
- **Formatting** -- rewriting plain text into Slack messages, reports, notes
- **Triage/classification** -- routing error logs, categorizing alerts
- **Simple Q&A** -- quick lookups that don't need web search or deep reasoning

### What it's not for

- Code generation or complex reasoning (use a frontier model)
- Precise structured output (the 3B model sometimes wraps JSON in markdown)
- Tasks requiring up-to-date knowledge (no internet access)
- Large context (see [Known Limitations](#known-limitations))

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

For programmatic use in scripts and automation:

```bash
# JSON input/output via stdin
echo '{"prompt":"What is 2+2?","max_tokens":100}' | apple-llm --json
# => {"content":"2+2 equals 4.","model":"apple-foundation","tokens_used":null}

# With system prompt and temperature
echo '{"prompt":"Hello","system":"You are a pirate","temperature":1.5}' | apple-llm --json

# In a shell script
RESULT=$(echo '{"prompt":"Summarize: ...","max_tokens":200}' | apple-llm --json)
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

## Known Limitations

**Context window:** The on-device ~3B model has a hard context limit of approximately 4,500 tokens (~18,000 characters). Prompts exceeding this limit are rejected with an error. This means:
- System prompt + user message + expected output must fit within ~18k characters total
- Large documents need to be chunked or summarized before sending
- Multi-turn conversations are not practical (no conversation history fits)

For tasks that need larger context, use a cloud model or a local model via Ollama.

## Benchmarks

Head-to-head comparison on Mac mini M4 (16GB), macOS 26.4. All Ollama models use default quantization (Q4_0/Q4_K_M). All times wall-clock, median of 3 runs. Nine models tested across three size classes: 3B, 7-9B, and 12-14B.

### Latency & Throughput

| Model | Short prompt | Medium (~150 words) | Longer (~350 words) | Throughput |
|---|---|---|---|---|
| **apple-llm** (Apple FM ~3B) | **0.30s** | **2.93s** | **5.65s** | **~55 w/s** |
| Ollama llama3.2 (3B) | 0.42s | 4.84s | 9.70s | ~35 w/s |
| Ollama phi3 (3.8B) | 2.01s | 16.16s | 13.07s | ~28 w/s |
| Ollama qwen2.5 (7B) | 0.62s | 12.99s | 19.06s | ~18 w/s |
| Ollama llama3.1 (8B) | 0.61s | 14.08s | 18.90s | ~17 w/s |
| Ollama mistral (7B) | 0.71s | 19.17s | 24.23s | ~16 w/s |
| Ollama gemma2 (9B) | 0.71s | 13.78s | 21.54s | ~14 w/s |
| Ollama mistral-nemo (12B) | 1.73s | 16.53s | 26.69s | ~12 w/s |
| Ollama phi3 (14B) | 9.58s | 30.90s | 45.81s | ~9 w/s |

apple-llm remains the fastest by a wide margin thanks to Neural Engine acceleration.

### Memory

| Model | Process RSS | Headroom on 16GB (after ~6GB baseline) |
|---|---|---|
| **apple-llm** (Apple FM ~3B) | ~19 MB (+ ~860 MB system, reclaimable) | ~9.1 GB |
| Ollama llama3.2 (3B) | ~2,300 MB | ~7.7 GB |
| Ollama phi3 (3.8B) | ~3,100 MB | ~6.9 GB |
| Ollama llama3.1 (8B) | ~4,300 MB | ~5.7 GB |
| Ollama mistral (7B) | ~4,700 MB | ~5.3 GB |
| Ollama qwen2.5 (7B) | ~4,800 MB | ~5.2 GB |
| Ollama gemma2 (9B) | ~6,800 MB | ~3.2 GB |
| Ollama mistral-nemo (12B) | ~7,300 MB | ~2.7 GB |
| Ollama phi3 (14B) | ~8,000 MB | ~2.0 GB |

**How apple-llm works under the hood:** The CLI process (~19MB) is just an IPC client. It sends the prompt to Apple's Neural Engine daemons (`aned`, `aneuserd`), which are always-on system services (~11MB combined). The ~3B model weights are loaded by the OS onto the Neural Engine hardware -- they don't appear in any process's RSS, but they do consume ~860MB of system memory on first load.

**Key differences from Ollama:**
- Apple's model memory is **OS-managed and reclaimable** -- the system can evict it under memory pressure. Ollama's memory is pinned in userspace until its idle timeout (default 5 minutes).
- The apple-llm CLI process **exits immediately** after inference. Ollama's server stays resident.
- The 7B class models (mistral, qwen2.5, llama3.1) use 4.3-4.8GB -- roughly **5x more** than apple-llm's system footprint and non-reclaimable.

### Model Quality

We ran 6 identical prompts through all models for typical automation tasks: summarize JSON, extract action items, classify an error log, format a Slack message, extract JSON from structured data, and reason about disk usage.

| Test | apple-llm (~3B) | llama3.2 (3B) | phi3 (3.8B) | mistral (7B) | qwen2.5 (7B) | gemma2 (9B) | llama3.1 (8B) | mistral-nemo (12B) | phi3 (14B) |
|---|---|---|---|---|---|---|---|---|---|
| **Summarize JSON** | Correct | Correct | Correct | Correct | Correct | Correct | Correct | Correct | Correct |
| **Extract action items** | 2 of 3 | 3 of 3 | 3 of 3 | 2 of 3 | 3 of 3 | 2 of 3 | 3 of 3 | 3 of 3 | 3 of 3 |
| **Classify error** | "network" x | "application" x | **"database"** | **"database"** | "network" x | **"database"** | **"database"** | **"database"** | **"database"** |
| **Format for Slack** | Clean | Verbose x | Inaccurate x | Clean | Garbled x | Clean | Clean | Clean | Wrong count x |
| **JSON extraction** | Correct, md-wrapped | Missed one | Correct, md-wrapped | **Clean JSON** | **Clean JSON** | **Clean JSON** | **Clean JSON** | **Clean JSON** | Verbose x |
| **Disk reasoning** | Wrong x | Correct | Correct | Correct | Correct | Correct | Correct | Correct | Wrong x |
| **Score** | 3/6 | 3/6 | 4/6 | 5/6 | 4/6 | **5/6** | **5/6** | **6/6** | 3/6 |

**Key findings:**
- **mistral-nemo:12b scored 6/6** -- the only model to ace every task
- **gemma2:9b, mistral:7b, and llama3.1:8b tied at 5/6** -- all nail classification and produce clean JSON
- The 3B class (apple-llm and llama3.2) reliably handles summarization and formatting but struggles with classification and structured output
- **phi3:14b was a disappointment at 3/6** -- despite being the largest model tested

### Choosing a Local Model

apple-llm handles the easy stuff -- summarization, formatting, simple Q&A -- at 55 w/s with near-zero memory cost. For tasks needing precise classification, clean JSON, or careful reasoning, pair it with a larger model via Ollama:

| Recommendation | Model | Why | Memory | Speed |
|---|---|---|---|---|
| **Best quality** | mistral-nemo:12b | Only model to score 6/6 | 7.3 GB | ~12 w/s |
| **Best balance** | gemma2:9b | 5/6 quality, concise output, best quality-per-GB | 6.8 GB | ~14 w/s |
| **Budget pick** | mistral:7b | 5/6 quality, lower memory, clean JSON | 4.7 GB | ~16 w/s |

## Security

- **No network access** -- all inference runs on-device, nothing leaves the machine
- **No persistent state** -- load, infer, exit. No files written, no config stored
- **No secrets** -- doesn't touch API keys, credentials, or user data
- **Apple guardrails** -- built-in content safety that cannot be disabled

## License

MIT
