#!/bin/bash
set -e

BINARY=".build/release/apple-llm"
RESULTS=""

echo "============================================"
echo "  apple-llm benchmarks"
echo "  $(date)"
echo "  $(sw_vers -productName) $(sw_vers -productVersion)"
echo "  $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")"
echo "============================================"
echo ""

# --- Cold start latency (first run after build) ---
echo ">> Cold start + short prompt (no-stream)"
for i in 1 2 3; do
  START=$(python3 -c "import time; print(time.time())")
  OUTPUT=$($BINARY --prompt "Say hi" --no-stream 2>&1)
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f'{$END - $START:.3f}')")
  CHARS=${#OUTPUT}
  echo "  run $i: ${ELAPSED}s (${CHARS} chars)"
done
echo ""

# --- Streaming latency (time to first byte) ---
echo ">> Time to first byte (streaming)"
for i in 1 2 3; do
  START=$(python3 -c "import time; print(time.time())")
  echo "Say one word" | $BINARY 2>/dev/null | head -c 1 > /dev/null
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f'{$END - $START:.3f}')")
  echo "  run $i: ${ELAPSED}s"
done
echo ""

# --- Throughput: medium prompt ---
echo ">> Medium response (~100 tokens target)"
for i in 1 2 3; do
  START=$(python3 -c "import time; print(time.time())")
  OUTPUT=$($BINARY --prompt "List 10 interesting facts about the ocean. Be concise." --no-stream --max-tokens 200 2>&1)
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f'{$END - $START:.3f}')")
  WORDS=$(echo "$OUTPUT" | wc -w | tr -d ' ')
  CHARS=${#OUTPUT}
  echo "  run $i: ${ELAPSED}s, ${WORDS} words, ${CHARS} chars"
done
echo ""

# --- Throughput: longer prompt ---
echo ">> Longer response (~300 tokens target)"
for i in 1 2 3; do
  START=$(python3 -c "import time; print(time.time())")
  OUTPUT=$($BINARY --prompt "Write a short essay about why the sky is blue. Include scientific explanation." --no-stream --max-tokens 500 2>&1)
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f'{$END - $START:.3f}')")
  WORDS=$(echo "$OUTPUT" | wc -w | tr -d ' ')
  CHARS=${#OUTPUT}
  WORDS_PER_SEC=$(python3 -c "print(f'{$WORDS / $ELAPSED:.1f}')")
  echo "  run $i: ${ELAPSED}s, ${WORDS} words, ${CHARS} chars (~${WORDS_PER_SEC} words/s)"
done
echo ""

# --- JSON mode overhead ---
echo ">> JSON mode overhead"
for i in 1 2 3; do
  START=$(python3 -c "import time; print(time.time())")
  OUTPUT=$(echo '{"prompt":"What is 2+2?","max_tokens":50}' | $BINARY --json 2>&1)
  END=$(python3 -c "import time; print(time.time())")
  ELAPSED=$(python3 -c "print(f'{$END - $START:.3f}')")
  echo "  run $i: ${ELAPSED}s  $OUTPUT"
done
echo ""

# --- Memory usage ---
echo ">> Peak memory usage (single inference)"
echo "What is 2+2?" | /usr/bin/time -l $BINARY --no-stream 2>&1 | grep -E "(maximum resident|real)" | head -5
echo ""

echo ">> Peak memory usage (longer inference)"
echo "Write a paragraph about dogs" | /usr/bin/time -l $BINARY --no-stream --max-tokens 200 2>&1 | grep -E "(maximum resident|real)" | head -5
echo ""

echo "============================================"
echo "  Benchmark complete"
echo "============================================"
