#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTML="$ROOT/files/shared/devtools/cocoa-reference.html"
WRAPPER="$ROOT/files/shared/bin/devtools"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

test -f "$HTML" || fail 'managed Cocoa DevTools HTML missing'
test -x "$WRAPPER" || fail 'devtools launcher missing or not executable'
grep -q 'Auditoría QA' "$HTML" || fail 'QA audit control is missing'
grep -q '/api/triangulations' "$HTML" || fail 'multi-repo inventory endpoint is not used'
grep -q 'Integrar verificado a dev' "$HTML" || fail 'dev integration action is missing'
grep -q '/api/promote-dev' "$HTML" || fail 'verified QA does not target dev'
grep -q '/api/archive-triangulation' "$HTML" || fail 'closed triangulations cannot be archived durably'
grep -q 'Mostrar cerradas' "$HTML" || fail 'closed triangulations cannot be inspected on demand'
grep -q 'if(d.archive)' "$HTML" || fail 'dev promotion does not consume the server archive receipt'
! grep -q 'const archived=await fetch' "$HTML" || fail 'dev promotion still depends on a second browser archive request'
! grep -q 'Publicar verificados' "$HTML" || fail 'feature-only publication action still appears'
! grep -q 'Conductor' "$HTML" || fail 'retired Conductor terminology remains in the UI'

printf 'PASS: Cocoa DevTools manages standalone three-repository QA audits\n'
