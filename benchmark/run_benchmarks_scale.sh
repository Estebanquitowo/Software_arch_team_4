#!/usr/bin/env bash
set -e

# Boot scaled environment
docker compose -f docker-compose.scale.yml up -d
sleep 20

# Define endpoints and request volumes
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
    ./benchmark/run_benchmarks.sh "$NAME" "$URL" "$COUNT" "scaled"
    sleep 3
  done
done

# Check load distribution
echo "--- Final Request Count per Web Container ---"
echo "Web 1: $(docker compose -f docker-compose.scale.yml logs web1 | grep -c 'Completed 200 OK')"
echo "Web 2: $(docker compose -f docker-compose.scale.yml logs web2 | grep -c 'Completed 200 OK')"
echo "Web 3: $(docker compose -f docker-compose.scale.yml logs web3 | grep -c 'Completed 200 OK')"

# Stop environment
docker compose -f docker-compose.scale.yml down
