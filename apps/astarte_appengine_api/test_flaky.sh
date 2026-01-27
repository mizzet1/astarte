#!/usr/bin/env bash

run_tests() {
  for i in $(seq 1 100); do
    if ! mix test &>test_log.log; then
      return 1
    fi
    echo "Run #$i: ok"  
  done
}

run_tests && rm -f test_log.log && echo "ok" || echo "failed"