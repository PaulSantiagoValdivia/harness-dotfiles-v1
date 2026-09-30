#!/usr/bin/env bash
# Private per-check receipts. Do not print command arguments or raw output.
verify_receipts_init() {
  VERIFY_RECEIPTS=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/harness-verify.XXXXXX") || return 1
  VERIFY_CHECK_ID=0
  (umask 077
    printf 'timestamp_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'source_head=%s\n' "$(git -C "${REPO_DIR:-$PWD}" rev-parse HEAD 2>/dev/null || printf unknown)"
    if git -C "${REPO_DIR:-$PWD}" status --porcelain > "$VERIFY_RECEIPTS/status.tmp" 2>/dev/null; then
      if [ -s "$VERIFY_RECEIPTS/status.tmp" ]; then printf 'source_dirty=true\n'; else printf 'source_dirty=false\n'; fi
    else printf 'source_dirty=unknown\n'; fi
    rm -f "$VERIFY_RECEIPTS/status.tmp"
    printf 'scope=check() calls only; whole-second timing; raw failure output is private\n'
  ) > "$VERIFY_RECEIPTS/run.txt" || return 1
  chmod 600 "$VERIFY_RECEIPTS/run.txt" || return 1
  (umask 077; printf 'id\texit_code\telapsed_seconds\tdescription\n' > "$VERIFY_RECEIPTS/checks.tsv") || return 1
  printf '  INFO Per-check receipts (private): %s\n' "$VERIFY_RECEIPTS"
}

check() {
  local desc="$1" start=$SECONDS rc log id elapsed
  shift
  VERIFY_CHECK_ID=$((VERIFY_CHECK_ID+1))
  printf -v id '%06d' "$VERIFY_CHECK_ID"
  log="$VERIFY_RECEIPTS/$id.log"
  if ! (umask 077; set -C; : > "$log"); then
    bad "$desc (receipt unavailable; command not executed)"
    return 0
  fi
  desc=${desc//$'\t'/ }
  desc=${desc//$'\n'/ }
  desc=${desc//$'\r'/ }
  printf '  INFO Check %s starting: %s\n' "$id" "$desc"
  # Preserve the exact argv and the existing in-shell execution semantics.
  if "$@" > "$log" 2>&1; then rc=0; else rc=$?; fi
  elapsed=$((SECONDS-start))
  if ! printf '%s\t%s\t%s\t%s\n' "$id" "$rc" "$elapsed" "$desc" >> "$VERIFY_RECEIPTS/checks.tsv"; then
    bad "$desc (receipt write failed; output retained at $log)"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then
    rm -f "$log"
    ok "$desc (${elapsed}s)"
  else
    bad "$desc (rc=$rc, ${elapsed}s; private output: $log)"
  fi
}
