#!/usr/bin/env bash

echo "| Mode | Endpoint | Reqs | Success Rate | Avg Latency | p95 Latency | Web CPU% (Peak) | Proxy CPU% | DB CPU% |"
echo "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |"

for mode in single scaled; do
  for log in benchmark/results/$mode/*.log; do
    [ -f "$log" ] || continue
    fname=$(basename "$log" .log)
    endpoint=$(echo "$fname" | cut -d'_' -f1)
    reqs=$(echo "$fname" | grep -o '[0-9]\+')
    
    # Extract k6 metrics
    success=$(grep -m1 'checks_succeeded' "$log" | awk '{print $2}' || echo "N/A")
    avg_lat=$(grep -m1 'http_req_duration' "$log" | grep -o 'avg=[^ ]*' | cut -d'=' -f2 || echo "N/A")
    p95_lat=$(grep -m1 'http_req_duration' "$log" | grep -o 'p(95)=[^ ]*' | cut -d'=' -f2 || echo "N/A")
    
    # Extract CPU stats from AFTER/PEAK section
    proxy_cpu=$(awk '/Resource Usage AFTER\/PEAK/{flag=1; next} /Process Thread Counts/{flag=0} flag' "$log" | grep 'haproxy' | awk '{print $2}' || echo "N/A")
    db_cpu=$(awk '/Resource Usage AFTER\/PEAK/{flag=1; next} /Process Thread Counts/{flag=0} flag' "$log" | grep 'mongodb' | awk '{print $2}' || echo "N/A")
    
    # Sum web CPU if scaled, or take single web CPU
    web_cpu=$(awk '/Resource Usage AFTER\/PEAK/{flag=1; next} /Process Thread Counts/{flag=0} flag' "$log" | grep 'web' | awk '{print $2}' | tr -d '%' | paste -sd+ - | bc 2>/dev/null || echo "N/A")
    [ "$web_cpu" != "N/A" ] && web_cpu="${web_cpu}%"

    echo "| $mode | $endpoint | $reqs | $success | $avg_lat | $p95_lat | $web_cpu | $proxy_cpu | $db_cpu |"
  done
done
