#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"
REPO_DIR="$ROOT"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); }
# Exercise the actual helper, never the whole machine verification suite.
[ -r "$ROOT/files/shared/lib/verification-diagnostics.sh" ] || exit 1
source "$ROOT/files/shared/lib/verification-diagnostics.sh"
verify_receipts_init
initial_umask=$(umask)
check 'success' bash -c 'echo success-output'
check $'failure\twith\nlabel' bash -c 'echo retained-error >&2; exit 7'
# shellcheck disable=SC2016
check 'argv kept literal' bash -c 'test "$1" = '"'"'$(exit 99)'"'"'' literal '$(exit 99)'
check 'delay' sleep 1
[ "$PASS" = 3 ] || exit 1
[ "$FAIL" = 1 ] || exit 1
[ "$(umask)" = "$initial_umask" ]
[ -f "$VERIFY_RECEIPTS/000002.log" ]
grep -qx 'retained-error' "$VERIFY_RECEIPTS/000002.log"
[ ! -e "$VERIFY_RECEIPTS/000001.log" ]
python3 - "$VERIFY_RECEIPTS" "$ROOT" <<'PY'
import pathlib,stat,sys
p=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2])
assert stat.S_IMODE(p.stat().st_mode)==0o700
assert 'source_head=' in (p/'run.txt').read_text()
assert 'source_dirty=' in (p/'run.txt').read_text()
rows=(p/'checks.tsv').read_text().splitlines()
assert rows[0]=='id\texit_code\telapsed_seconds\tdescription'
assert len(rows)==5
fields=[row.split('\t') for row in rows[1:]]
assert all(len(row)==4 for row in fields)
assert fields[1][1]=='7'
assert int(fields[3][2])>=1
for f in p.iterdir(): assert stat.S_IMODE(f.stat().st_mode)==0o600
text=(root/'verify.sh').read_text()
assert 'source "$REPO_DIR/files/shared/lib/verification-diagnostics.sh"' in text
assert 'verify_receipts_init || exit 1' in text
assert 'Smoke test dual-review sobre un commit real (5 fases completas)' not in text
PY
# A failed receipt write cannot be disguised as a passed verification.
mv "$VERIFY_RECEIPTS" "$TMP/preserved"
printf 'not a directory' > "$VERIFY_RECEIPTS"
marker="$TMP/executed"
check 'receipt unavailable' touch "$marker"
[ "$FAIL" = 2 ] || exit 1
[ ! -e "$marker" ] || exit 1
printf 'PASS: exit codes, retained failure output, safe argv, timings, permissions and receipt failure\n'
