#!/usr/bin/env bash
set -e

# Boot single-instance environment
docker compose -f docker-compose.full.yml up -d
sleep 15

# Endpoints and request volumes
ENDPOINTS=(
  "static:https://app.localhost/images/books/074c88e2c7f294af.jpg"
  "aggregation:https://app.localhost/reports/top_selling_books"
  "search:https://app.localhost/search?query=the"
  "dynamic_read:https://app.localhost/books/6a867bf64d01d5c7c51115c4"
)
REQUEST_VOLUMES=(1 10 100 1000 5000)

# Run benchmarks
for item in "${ENDPOINTS[@]}"; do
  NAME="${item%%:*}"
  URL="${item#*:}"
  for COUNT in "${REQUEST_VOLUMES[@]}"; do
    ./benchmark/run_benchmarks.sh "$NAME" "$URL" "$COUNT" "single"
    sleep 3
  done
done

# Stop environment
docker compose -f docker-compose.full.yml down
