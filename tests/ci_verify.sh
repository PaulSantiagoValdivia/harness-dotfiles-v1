#!/usr/bin/env bash
# Source-only delivery checks. No installed HOME, models, or remote services.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for tool in bash python3 git jq shellcheck; do
  command -v "$tool" >/dev/null || { printf 'FAIL: missing prerequisite %s\n' "$tool" >&2; exit 1; }
done
FAIL=0
run() {
  local label="$1" rc
  shift
  printf '\nRUN: %s\n' "$label"
  if "$@"; then
    printf 'PASS: %s\n' "$label"
  else
    rc=$?
    printf 'FAIL: %s (exit %s)\n' "$label" "$rc" >&2
    FAIL=$((FAIL+1))
  fi
}
# Explicit argv mapping: no eval, optional selections, or swallowed failures.
run 'runner syntax' bash -n tests/ci_verify.sh
run 'runner fixture syntax' bash -n tests/ci_verify_test.sh
run 'runner shellcheck' shellcheck tests/ci_verify.sh tests/ci_verify_test.sh
run 'runner failure propagation' bash tests/ci_verify_test.sh
run 'memory snapshot contract' bash tests/memory_snapshot_test.sh
run 'memory snapshot shellcheck' shellcheck files/shared/bin/memory-snapshot tests/memory_snapshot_test.sh
run 'memory lint contract' python3 tests/memory_lint_test.py
run 'memory consolidate contract' python3 tests/memory_consolidate_test.py
run 'closure evidence gate' python3 tests/closure_gate_test.py
run 'DevTools Git boundaries' python3 tests/cocoa_devtools_test.py
run 'recoverable coordination' bash tests/triangulate_handoff_test.sh
run 'receipt dispatch guard' python3 tests/receipt_dispatch_guard_test.py
run 'verification consolidation' python3 tests/verification_consolidation_test.py
run 'session process discovery' python3 tests/session_discovery_test.py
run 'integration autonomy policy' python3 tests/integration_autonomy_test.py
run 'Engram concurrent Git fixtures' python3 tests/engram_sync_concurrency_test.py
run 'Engram source contract' bash files/claude/hooks/tests/engram-git-sync-tests.sh \
  "$ROOT/files/claude/hooks/engram-git-sync.sh"
run 'verification diagnostics' bash tests/verification_diagnostics_test.sh
run 'evidence skill fixtures' bash tests/harness_evidence_test.sh
printf '\nDelivery checks: %s failed\n' "$FAIL"
[ "$FAIL" -eq 0 ]
