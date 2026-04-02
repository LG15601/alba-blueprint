#!/usr/bin/env bash
# run-tests.sh — Unified TAP test runner for Alba blueprint
# Discovers and runs all TAP test suites, aggregates results.
# Exit 0 = all pass, exit 1 = any failure or plan mismatch.

set -uo pipefail
# NOTE: not using set -e — we capture each suite's exit code individually

SUITES=(
  scripts/verify-watchdog-status.sh
  scripts/verify-keepalive.sh
  scripts/verify-auth-alerts.sh
  scripts/verify-guard.sh
  scripts/verify-memory.sh
  scripts/verify-consolidation.sh
  scripts/verify-context-injection.sh
  tests/verify-learning-pipeline.sh
  tests/verify-pattern-promotion.sh
  tests/verify-skill-extraction.sh
  tests/verify-gstack.sh
  tests/test-delegation-gate.sh
  tests/test-delegation-cleanup.sh
  tests/test-delegation-lanes.sh
  tests/test-handoff-handler.sh
  tests/test-heartbeat-proactive.sh
  tests/test-goals.sh
)

total_tests=0
total_pass=0
total_fail=0
total_suites=0
total_suites_ok=0
total_suites_fail=0
plan_mismatches=0
failed_suites=""

for suite in "${SUITES[@]}"; do
  suite_name="$(basename "$suite")"
  echo "# Suite: $suite_name"

  if [[ ! -f "$suite" ]]; then
    echo "# SKIP: $suite not found"
    echo ""
    continue
  fi

  total_suites=$((total_suites + 1))

  # Run suite in subshell, capture output and exit code
  output="$(bash "$suite" 2>&1)" || true
  suite_exit=$?

  # Print the suite output
  echo "$output"
  echo ""

  # Parse TAP plan line (1..N or 1..0 # SKIP ...)
  plan_count=""
  plan_line="$(echo "$output" | grep -E '^1\.\.[0-9]+' | head -1)" || true
  if [[ -n "$plan_line" ]]; then
    plan_count="$(echo "$plan_line" | sed 's/^1\.\.//' | sed 's/ .*//')"
  fi

  # Count ok / not ok lines
  suite_pass=0
  suite_fail=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^ok\ [0-9] ]]; then
      suite_pass=$((suite_pass + 1))
    elif [[ "$line" =~ ^not\ ok\ [0-9] ]]; then
      suite_fail=$((suite_fail + 1))
    fi
  done <<< "$output"

  suite_total=$((suite_pass + suite_fail))

  # Check plan mismatch
  if [[ -n "$plan_count" && "$plan_count" != "0" ]]; then
    if [[ "$suite_total" -ne "$plan_count" ]]; then
      echo "# PLAN MISMATCH in $suite_name: planned $plan_count, ran $suite_total"
      plan_mismatches=$((plan_mismatches + 1))
    fi
  fi

  # Accumulate
  total_tests=$((total_tests + suite_total))
  total_pass=$((total_pass + suite_pass))
  total_fail=$((total_fail + suite_fail))

  if [[ "$suite_fail" -gt 0 || "$suite_exit" -ne 0 ]]; then
    total_suites_fail=$((total_suites_fail + 1))
    failed_suites="$failed_suites $suite_name"
  else
    total_suites_ok=$((total_suites_ok + 1))
  fi
done

# Summary
echo "# =============================="
echo "# TAP Summary"
echo "# =============================="
echo "# Suites: $total_suites ($total_suites_ok ok, $total_suites_fail failed)"
echo "# Tests:  $total_tests ($total_pass passed, $total_fail failed)"
echo "# Plan mismatches: $plan_mismatches"

if [[ -n "$failed_suites" ]]; then
  echo "# Failed suites:$failed_suites"
fi

if [[ "$total_fail" -gt 0 || "$plan_mismatches" -gt 0 ]]; then
  echo "# Result: FAIL"
  exit 1
else
  echo "# Result: PASS"
  exit 0
fi
