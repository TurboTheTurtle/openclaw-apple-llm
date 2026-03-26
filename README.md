# apple-llm

A lightweight CLI that bridges Apple's on-device Foundation Models (Apple Intelligence) to stdin/stdout. No daemon, no HTTP server — load, infer, exit. Zero idle RAM cost.

## Why

Ollama keeps models resident in RAM (3-4GB+). Apple's Foundation Models use the Neural Engine with OS-level memory management — the model loads on demand and unloads automatically. But there's no CLI to call it from non-Swift apps. This bridge fixes that.

## Requirements

- macOS 26+ (Tahoe) on Apple Silicon
- Apple Intelligence enabled (System Settings > Apple Intelligence & Siri)
- Xcode 26+ (for building)

## Install

```bash
git clone https://github.com/youruser/apple-llm.git
cd apple-llm
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

```bash
# JSON input/output
echo '{"prompt":"What is 2+2?","max_tokens":100}' | apple-llm --json

# Output: {"content":"2+2 equals 4.","model":"apple-foundation","tokens_used":null}

# Full JSON input with system prompt
echo '{"prompt":"Hello","system":"You are a pirate","temperature":1.5}' | apple-llm --json
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

### Integration

For programmatic use (e.g., from Node.js, Python, or shell scripts), use `--json` mode:

```bash
# From a script
RESULT=$(echo '{"prompt":"Summarize: ...","max_tokens":200}' | apple-llm --json)
```

### Error Handling

Errors go to stderr with exit code 1:

```bash
apple-llm --prompt "" 2>/dev/null || echo "failed"
```

## Benchmarks

Tested on Mac mini M4, macOS 26.4. All times are wall-clock, averaged over 3 runs.

| Metric | Result |
|---|---|
| **Cold start + short prompt** | ~0.33s (warm), ~0.64s (first run) |
| **Time to first byte (streaming)** | ~0.22s |
| **Medium response (~120 words)** | ~2.8s (~42 words/s) |
| **Longer response (~300 words)** | ~5.6s (~58 words/s) |
| **JSON mode (short prompt)** | ~0.28s |
| **Peak RSS (single inference)** | ~19 MB |
| **Peak RSS (longer inference)** | ~19 MB |
| **Idle memory** | 0 MB (process exits) |

For comparison, Ollama typically keeps 3-4GB+ resident in RAM even when idle. apple-llm's process-per-request model means zero memory cost between calls — Apple's OS-level Neural Engine handles model lifecycle.

## License

MIT
