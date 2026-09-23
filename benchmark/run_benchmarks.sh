#!/usr/bin/env bash
set -e

NAME=$1
URL=$2
COUNT=$3
MODE=${4:-single} # "single" or "scaled"

if [ -z "$COUNT" ]; then
  echo "Usage: ./benchmark/run_benchmarks.sh <name> <url> <count> [single|scaled]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/results/$MODE"
LOG_FILE="$LOG_DIR/${NAME}_${COUNT}req.log"

echo "=========================================================="
echo "Running: $NAME ($COUNT reqs) against $URL [$MODE]"
echo "Log: $LOG_FILE"
echo "=========================================================="

{
  echo "=========================================================="
  echo "Test: $NAME | Volume: $COUNT requests | Target: $URL"
  echo "Timestamp: $(date -u)"
  echo "=========================================================="

  # 1. Warm-up request
  echo "--- Sending Warm-Up Request ---"
  curl -k -s -o /dev/null -w "Warm-up HTTP Status: %{http_code} | Total Time: %{time_total}s\n" "$URL"
  sleep 1

  # 2. Pre-test container stats
  echo ""
  echo "--- Resource Baseline BEFORE Test ---"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

  # 3. Execute k6 via Docker
  echo ""
  echo "--- k6 Execution Output ---"
  docker run --rm -i \
    --net=host \
    -e TARGET_URL="$URL" \
    -e REQUESTS="$COUNT" \
    grafana/k6 run - < "$SCRIPT_DIR/load_test.js"

  # 4. Post-test container stats
  echo ""
  echo "--- Resource Usage AFTER/PEAK Test ---"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

  # 5. OS Thread Counts
  echo ""
  echo "--- Process Thread Counts ---"
  for c in $(docker ps --filter "name=software_arch" --format "{{.Names}}"); do
    THREADS=$(docker exec "$c" sh -c 'grep -s Threads /proc/[0-9]*/status | awk "{sum+=\$2} END {print sum}"' 2>/dev/null || echo "N/A")
    echo "Container $c: $THREADS threads"
  done
  echo "=========================================================="
} | tee "$LOG_FILE"
