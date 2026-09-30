#!/usr/bin/env bash
# Orchestration-only fixtures; these do NOT assert harness runtime behavior.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tests" "$TMP/files/claude/hooks/tests" "$TMP/files/shared/bin"
cp "$ROOT/tests/ci_verify.sh" "$TMP/tests/ci_verify.sh"
# The copied runner executes controlled subprocesses, never production tests.
for file in ci_verify_test verification_diagnostics_test harness_evidence_test triangulate_handoff_test memory_snapshot_test; do
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nprintf "visited:%%s\\n" "${0##*/}"\n' > "$TMP/tests/$file.sh"
done
printf '#!/usr/bin/env bash\n' > "$TMP/files/shared/bin/memory-snapshot"
printf '#!/usr/bin/env python3\n' > "$TMP/files/shared/bin/memory-lint"
printf 'print("visited:memory-lint")\n' > "$TMP/tests/memory_lint_test.py"
printf 'print("visited:memory-consolidate")\n' > "$TMP/tests/memory_consolidate_test.py"
printf 'print("visited:closure")\n' > "$TMP/tests/closure_gate_test.py"
printf 'print("visited:devtools")\n' > "$TMP/tests/cocoa_devtools_test.py"
printf 'print("visited:dispatch")\n' > "$TMP/tests/receipt_dispatch_guard_test.py"
printf 'print("visited:verification")\n' > "$TMP/tests/verification_consolidation_test.py"
printf 'print("visited:discovery")\n' > "$TMP/tests/session_discovery_test.py"
printf 'print("visited:autonomy")\n' > "$TMP/tests/integration_autonomy_test.py"
printf 'print("visited:engram-concurrency")\n' > "$TMP/tests/engram_sync_concurrency_test.py"
cat > "$TMP/files/claude/hooks/tests/engram-git-sync-tests.sh" <<'STUB'
#!/usr/bin/env bash
case "$1" in /*/files/claude/hooks/engram-git-sync.sh) ;; *) exit 91 ;; esac
[ -f "$1" ] || exit 92
printf 'visited:engram-contract\n'
STUB
printf '#!/usr/bin/env bash\n' > "$TMP/files/claude/hooks/engram-git-sync.sh"
bash "$TMP/tests/ci_verify.sh" > "$TMP/pass.log" 2>&1
# Each real suite slot must propagate a failed subprocess to a nonzero result.
for file in tests/closure_gate_test.py tests/cocoa_devtools_test.py tests/ci_verify_test.sh tests/memory_snapshot_test.sh tests/memory_lint_test.py tests/memory_consolidate_test.py tests/triangulate_handoff_test.sh tests/receipt_dispatch_guard_test.py tests/verification_consolidation_test.py tests/session_discovery_test.py tests/integration_autonomy_test.py tests/engram_sync_concurrency_test.py \
  files/claude/hooks/tests/engram-git-sync-tests.sh tests/verification_diagnostics_test.sh \
  tests/harness_evidence_test.sh; do
  cp "$TMP/$file" "$TMP/original"
  if [[ "$file" == *.py ]]; then
    printf 'raise SystemExit(7)\n' > "$TMP/$file"
  else
    printf '#!/usr/bin/env bash\nexit 7\n' > "$TMP/$file"
  fi
  if bash "$TMP/tests/ci_verify.sh" > "$TMP/fail.log" 2>&1; then
    printf 'FAIL: failed subcheck was green: %s\n' "$file" >&2
    exit 1
  fi
  grep -q 'FAIL: .*exit 7' "$TMP/fail.log"
  cp "$TMP/original" "$TMP/$file"
done
rm "$TMP/tests/verification_diagnostics_test.sh"
if bash "$TMP/tests/ci_verify.sh" > "$TMP/missing.log" 2>&1; then
  printf 'FAIL: missing suite was green\n' >&2
  exit 1
fi
printf 'PASS: all fifteen failing suite slots and missing suite fail closed; absolute source hook passed\n'
