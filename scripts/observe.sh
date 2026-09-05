#!/usr/bin/env bash
set -u

CONTAINER_NAME="${CONTAINER_NAME:-deepseek-vllm}"

docker logs -f --since 1m "$CONTAINER_NAME" 2>&1 | \
  grep --line-buffered -E \
  'Received request|Added request|Generated response|Aborted request|Avg prompt throughput|SpecDecoding|ERROR|WARNING|Traceback'

