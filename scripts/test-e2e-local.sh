#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASTARTE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS="${1:-3}"
WAIT_TOOL="$ASTARTE_DIR/wait-for-astarte-docker-compose"

cd "$ASTARTE_DIR"

# Download wait-for-astarte tool if not present
if [[ ! -x "$WAIT_TOOL" ]]; then
  echo ">>> Downloading wait-for-astarte-docker-compose..."
  wget -q https://github.com/astarte-platform/wait-for-astarte-docker-compose/releases/download/v1.1.0/wait-for-astarte-docker-compose_1.1.0_linux_amd64.tar.gz
  tar xf wait-for-astarte-docker-compose_1.1.0_linux_amd64.tar.gz
  rm wait-for-astarte-docker-compose_1.1.0_linux_amd64.tar.gz
fi

PASSED=0
FAILED=0

for i in $(seq 1 "$RUNS"); do
  echo ""
  echo "========================================="
  echo " Run $i / $RUNS"
  echo "========================================="

  echo ">>> Tearing down..."
  docker compose down -v --remove-orphans 2>/dev/null || true

  echo ">>> Initializing compose files..."
  docker run --rm -v "$ASTARTE_DIR/compose:/compose" astarte/docker-compose-initializer

  echo ">>> Starting Astarte..."
  docker compose up -d --build

  echo ">>> Waiting for Astarte to come up..."
  if "$WAIT_TOOL"; then
    echo ">>> Run $i: PASSED"
    PASSED=$((PASSED + 1))
  else
    echo ">>> Run $i: FAILED"
    FAILED=$((FAILED + 1))
    echo "--- Docker compose logs (vernemq, appengine, dup) ---"
    docker compose logs --tail=50 vernemq astarte-appengine-api astarte-data-updater-plant
  fi
done

echo ""
echo "========================================="
echo " Results: $PASSED passed, $FAILED failed (out of $RUNS runs)"
echo "========================================="

docker compose down -v --remove-orphans 2>/dev/null || true

[[ $FAILED -eq 0 ]]
