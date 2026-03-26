#!/bin/bash
set -e

APPLE_BIN=".build/release/apple-llm"
OLLAMA_MODEL="llama3.2:3b"
RUNS=3

echo "============================================"
echo "  apple-llm vs Ollama ($OLLAMA_MODEL)"
echo "  $(date)"
echo "  $(sw_vers -productName) $(sw_vers -productVersion)"
echo "  $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
echo "  $RUNS runs per test, reporting median"
echo "============================================"
echo ""

time_cmd() {
    python3 -c "import time; print(time.time())"
}

median() {
    echo "$@" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END{if(NR%2==1)print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2}'
}

# Warm up Ollama (first call loads model into RAM)
echo ">> Warming up Ollama..."
ollama run "$OLLAMA_MODEL" "hi" --nowordwrap > /dev/null 2>&1
echo "   done"
echo ""

# --- Test 1: Short prompt (buffered) ---
echo ">> Test 1: Short prompt — \"What is 2+2?\""
echo ""

APPLE_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$($APPLE_BIN --prompt "What is 2+2?" --no-stream 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    APPLE_TIMES+=("$T")
    echo "   apple-llm  run $i: ${T}s (${#OUTPUT} chars)"
done
echo ""

OLLAMA_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$(ollama run "$OLLAMA_MODEL" "What is 2+2?" --nowordwrap 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    OLLAMA_TIMES+=("$T")
    echo "   ollama     run $i: ${T}s (${#OUTPUT} chars)"
done
echo ""
echo "   median — apple-llm: $(median ${APPLE_TIMES[@]})s | ollama: $(median ${OLLAMA_TIMES[@]})s"
echo ""

# --- Test 2: Medium prompt ---
echo ">> Test 2: Medium response — \"List 10 facts about the ocean\""
echo ""

APPLE_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$($APPLE_BIN --prompt "List 10 interesting facts about the ocean. Be concise." --no-stream --max-tokens 200 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    W=$(echo "$OUTPUT" | wc -w | tr -d ' ')
    APPLE_TIMES+=("$T")
    echo "   apple-llm  run $i: ${T}s, ${W} words"
done
echo ""

OLLAMA_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$(ollama run "$OLLAMA_MODEL" "List 10 interesting facts about the ocean. Be concise." --nowordwrap 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    W=$(echo "$OUTPUT" | wc -w | tr -d ' ')
    OLLAMA_TIMES+=("$T")
    echo "   ollama     run $i: ${T}s, ${W} words"
done
echo ""
echo "   median — apple-llm: $(median ${APPLE_TIMES[@]})s | ollama: $(median ${OLLAMA_TIMES[@]})s"
echo ""

# --- Test 3: Longer prompt ---
echo ">> Test 3: Longer response — \"Write a short essay about why the sky is blue\""
echo ""

APPLE_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$($APPLE_BIN --prompt "Write a short essay about why the sky is blue. Include scientific explanation." --no-stream --max-tokens 500 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    W=$(echo "$OUTPUT" | wc -w | tr -d ' ')
    WPS=$(python3 -c "print(f'{$W / $T:.1f}')")
    APPLE_TIMES+=("$T")
    echo "   apple-llm  run $i: ${T}s, ${W} words (~${WPS} w/s)"
done
echo ""

OLLAMA_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$(ollama run "$OLLAMA_MODEL" "Write a short essay about why the sky is blue. Include scientific explanation." --nowordwrap 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    W=$(echo "$OUTPUT" | wc -w | tr -d ' ')
    WPS=$(python3 -c "print(f'{$W / $T:.1f}')")
    OLLAMA_TIMES+=("$T")
    echo "   ollama     run $i: ${T}s, ${W} words (~${WPS} w/s)"
done
echo ""
echo "   median — apple-llm: $(median ${APPLE_TIMES[@]})s | ollama: $(median ${OLLAMA_TIMES[@]})s"
echo ""

# --- Test 4: JSON / API mode ---
echo ">> Test 4: API mode — short prompt"
echo ""

APPLE_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$(echo '{"prompt":"What is 2+2?","max_tokens":50}' | $APPLE_BIN --json 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    APPLE_TIMES+=("$T")
    echo "   apple-llm  run $i: ${T}s"
done
echo ""

OLLAMA_TIMES=()
for i in $(seq 1 $RUNS); do
    START=$(time_cmd)
    OUTPUT=$(curl -s http://localhost:11434/api/generate -d "{\"model\":\"$OLLAMA_MODEL\",\"prompt\":\"What is 2+2?\",\"stream\":false}" 2>&1)
    END=$(time_cmd)
    T=$(python3 -c "print(f'{$END - $START:.3f}')")
    OLLAMA_TIMES+=("$T")
    echo "   ollama API run $i: ${T}s"
done
echo ""
echo "   median — apple-llm: $(median ${APPLE_TIMES[@]})s | ollama API: $(median ${OLLAMA_TIMES[@]})s"
echo ""

# --- Memory comparison ---
echo ">> Memory comparison"
echo ""

echo "   apple-llm (during inference):"
echo "What is 2+2?" | /usr/bin/time -l $APPLE_BIN --no-stream 2>&1 | grep "maximum resident" | awk '{printf "     CLI process RSS: %.1f MB\n", $1/1024/1024}'
echo ""

echo "   Ollama (model loaded):"
ollama ps 2>&1 | sed 's/^/     /'
echo ""
ps aux | grep -E 'ollama' | grep -v grep | awk '{printf "     PID:%-6s RSS: %6.1f MB  %s\n", $2, $6/1024, $11}'
echo ""

echo "   Apple Neural Engine daemons (always running):"
ps aux | grep -iE '(aned|ANECompiler|aneuser)' | grep -v grep | awk '{printf "     PID:%-6s RSS: %5.1f MB  %s\n", $2, $6/1024, $11}'
echo ""

echo "============================================"
echo "  Benchmark complete"
echo "============================================"
