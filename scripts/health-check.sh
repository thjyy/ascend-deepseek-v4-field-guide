#!/usr/bin/env bash
set -u

CONTAINER_NAME="${CONTAINER_NAME:-deepseek-vllm}"
API_BASE="${API_BASE:-http://127.0.0.1:7000}"

echo "== container =="
docker inspect -f \
  'Status={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} RestartCount={{.RestartCount}} Image={{.Config.Image}}' \
  "$CONTAINER_NAME"

echo "== health =="
curl --max-time 5 -sS -o /dev/null \
  -w 'HTTP=%{http_code} time=%{time_total}s\n' \
  "$API_BASE/health"

echo "== scheduler =="
curl --max-time 5 -sS "$API_BASE/metrics" | \
  grep -E '^vllm:(num_requests_running|num_requests_waiting|kv_cache_usage_perc|prompt_tokens_total|generation_tokens_total){' || true

