#!/bin/bash
# Quality comparison: run identical prompts through apple-llm and one or more Ollama models.
# Usage: ./quality-test.sh [ollama-model-name]
# Example: ./quality-test.sh llama3.1:8b
#          ./quality-test.sh  (defaults to llama3.2:3b)

set -e

APPLE_BIN=".build/release/apple-llm"
OLLAMA_MODEL="${1:-llama3.2:3b}"

strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b\[?[0-9]*[a-zA-Z]//g' | sed '/^$/d'
}

echo "============================================"
echo "  Quality: apple-llm vs Ollama ($OLLAMA_MODEL)"
echo "  $(date)"
echo "============================================"
echo ""

# --- Test 1: Summarize structured data ---
PROMPT_1='Summarize this JSON health check in one sentence: {"services": [{"name": "postgres", "status": "healthy", "latency_ms": 12}, {"name": "redis", "status": "healthy", "latency_ms": 3}, {"name": "nginx", "status": "degraded", "latency_ms": 450}, {"name": "minio", "status": "healthy", "latency_ms": 8}]}'

echo ">> 1. Summarize structured data"
echo "---apple-llm---"
echo "$PROMPT_1" | $APPLE_BIN --no-stream 2>&1
echo ""
echo "---$OLLAMA_MODEL---"
ollama run "$OLLAMA_MODEL" "$PROMPT_1" --nowordwrap 2>&1 | strip_ansi
echo ""

# --- Test 2: Extract action items ---
PROMPT_2='Extract action items as a bullet list: "Met with design team about the new dashboard. Need to update the color palette by Friday. Backend API for user preferences is blocked on the schema migration — Jake is handling that. Should follow up with QA about the regression in the notification system."'

echo ">> 2. Extract action items"
echo "---apple-llm---"
echo "$PROMPT_2" | $APPLE_BIN --no-stream 2>&1
echo ""
echo "---$OLLAMA_MODEL---"
ollama run "$OLLAMA_MODEL" "$PROMPT_2" --nowordwrap 2>&1 | strip_ansi
echo ""

# --- Test 3: Classify error log ---
PROMPT_3='Classify this error log line into one of: [database, network, auth, application, unknown]. Reply with just the category. "2026-03-25 14:32:01 ERROR ConnectionPool: Failed to acquire connection after 30000ms timeout. Pool exhausted (active=50, idle=0, waiting=23)"'

echo ">> 3. Classify error log"
echo "---apple-llm---"
echo "$PROMPT_3" | $APPLE_BIN --no-stream 2>&1
echo ""
echo "---$OLLAMA_MODEL---"
ollama run "$OLLAMA_MODEL" "$PROMPT_3" --nowordwrap 2>&1 | strip_ansi
echo ""

# --- Test 4: Format for Slack ---
PROMPT_4='Rewrite as a brief Slack status message with emoji: Token refresh completed. 3 tokens rotated successfully. 1 token failed (Spotify - invalid grant). Next refresh scheduled in 6 hours.'

echo ">> 4. Format for Slack"
echo "---apple-llm---"
echo "$PROMPT_4" | $APPLE_BIN --no-stream 2>&1
echo ""
echo "---$OLLAMA_MODEL---"
ollama run "$OLLAMA_MODEL" "$PROMPT_4" --nowordwrap 2>&1 | strip_ansi
echo ""

# --- Test 5: JSON extraction ---
PROMPT_5_APPLE='{"prompt":"Given this list of Docker containers, return ONLY the names of unhealthy ones as a JSON array, no markdown, no explanation: [{\"name\":\"postgres\",\"state\":\"running\"},{\"name\":\"redis\",\"state\":\"running\"},{\"name\":\"searxng\",\"state\":\"restarting\"},{\"name\":\"grafana\",\"state\":\"exited\"},{\"name\":\"nginx\",\"state\":\"running\"}]","system":"Return only valid JSON, no explanation, no markdown.","max_tokens":100}'
PROMPT_5_OLLAMA='Given this list of Docker containers, return ONLY the names of unhealthy ones as a JSON array, no markdown, no explanation: [{"name":"postgres","state":"running"},{"name":"redis","state":"running"},{"name":"searxng","state":"restarting"},{"name":"grafana","state":"exited"},{"name":"nginx","state":"running"}]'

echo ">> 5. JSON extraction"
echo "---apple-llm (--json)---"
echo "$PROMPT_5_APPLE" | $APPLE_BIN --json 2>&1
echo ""
echo "---$OLLAMA_MODEL (API)---"
curl -s http://localhost:11434/api/generate -d "{\"model\":\"$OLLAMA_MODEL\",\"prompt\":$(echo "$PROMPT_5_OLLAMA" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'),\"system\":\"Return only valid JSON, no explanation, no markdown.\",\"stream\":false}" 2>&1 | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['response'])"
echo ""

# --- Test 6: Simple reasoning ---
PROMPT_6='Given these disk usage numbers, should I be concerned? Answer yes or no, then one sentence why. /dev/disk1s1  460Gi  412Gi   48Gi    90%  /System/Volumes/Data'

echo ">> 6. Disk usage reasoning"
echo "---apple-llm---"
echo "$PROMPT_6" | $APPLE_BIN --no-stream 2>&1
echo ""
echo "---$OLLAMA_MODEL---"
ollama run "$OLLAMA_MODEL" "$PROMPT_6" --nowordwrap 2>&1 | strip_ansi
echo ""

echo "============================================"
echo "  Quality test complete"
echo "============================================"
