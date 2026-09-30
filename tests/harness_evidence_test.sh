#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
SOURCE="$ROOT/files/shared/skills/harness-evidence"
HELPER="$ROOT/files/shared/lib/install-shared-skill.sh"
test -f "$SOURCE/SKILL.md" || fail 'shared evidence skill missing'
test -f "$HELPER" || fail 'scoped installer missing'
# shellcheck source=files/shared/lib/install-shared-skill.sh
source "$HELPER"
python3 - "$SOURCE" <<'PY'
import json
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
skill = (root / 'SKILL.md').read_text()
assert re.search(r'^description: "Trigger: [^\n]{1,240}"$', skill, re.M)
for key in ('name: harness-evidence', 'license:', 'author:', 'version:'):
    assert key in skill, key
headings = ['Activation Contract', 'Hard Rules', 'Decision Gates', 'Execution Steps', 'Output Contract', 'References']
assert sorted(headings, key=lambda h: skill.index('## ' + h)) == headings
for rule in ('PASS', 'FAIL', 'BLOCKED', 'UNTESTED', 'local', 'dirty', 'checksum', 'SDD'):
    assert rule in skill, rule
report = json.loads((root / 'references/report-template.json').read_text())
assert report['version'] == 1
assert report['repository']['dirty'] is None
assert report['repository']['commit'] is None
for key in ('branch', 'path', 'snapshot_limitations'):
    assert key in report['repository'], key
for key in ('timestamp_utc', 'scope', 'target', 'environment', 'limitations', 'sensitive_data'):
    assert key in report, key
check = report['checks'][0]
assert check['status'] == 'UNTESTED'
assert check['exit_code'] is None and check['exit_code_reason']
for key in ('expected', 'observed', 'command_or_interaction'):
    assert key in check, key
for phase in ('before', 'after'):
    assert report[phase]['reference'] is None and report[phase]['unavailable_reason']
assert report['artifacts'][0]['sha256'] is None and report['artifacts'][0]['unavailable_reason']
assert report['artifacts'][0]['path'] is None
print('PASS: original skill and honest untested template contract')
PY
install_shared_skill "$SOURCE" "$TMP/fresh" "$TMP/backup-fresh"
for client in claude codex; do
  shared_skill_matches "$SOURCE" "$TMP/fresh/.$client/skills/harness-evidence" || fail 'fresh parity'
done
install_shared_skill "$SOURCE" "$TMP/fresh" "$TMP/backup-unused"
test ! -e "$TMP/backup-unused" || fail 'identical rerun made backups'
for client in claude codex; do
  home="$TMP/custom home/.$client"
  mkdir -p "$home/skills/harness-evidence" "$home/skills/other"
  printf '{"model":"kept"}\n' > "$home/settings.json"
  printf 'model = "kept"\n' > "$home/config.toml"
  printf 'other skill\n' > "$home/skills/other/SKILL.md"
  printf 'previous skill\n' > "$home/skills/harness-evidence/SKILL.md"
done
install_shared_skill "$SOURCE" "$TMP/custom home" "$TMP/backup"
for client in claude codex; do
  dest="$TMP/custom home/.$client/skills/harness-evidence"
  shared_skill_matches "$SOURCE" "$dest" || fail 'custom parity'
  grep -qx '{"model":"kept"}' "$TMP/custom home/.$client/settings.json" || fail 'Claude preferences changed'
  grep -qx 'model = "kept"' "$TMP/custom home/.$client/config.toml" || fail 'Codex preferences changed' 
  grep -qx 'other skill' "$TMP/custom home/.$client/skills/other/SKILL.md" || fail 'other skill changed'
  grep -qx 'previous skill' "$TMP/backup/$client/harness-evidence/SKILL.md" || fail 'backup missing'
  printf 'drift\n' >> "$dest/references/report-template.json"
  if shared_skill_matches "$SOURCE" "$dest"; then fail 'supporting-file drift hidden'; fi
  if [ "$client" = claude ]; then
    if install_shared_skill "$SOURCE" "$TMP/custom home" "$TMP/backup" 2>/dev/null; then fail 'backup collision accepted'; fi
    grep -qx 'previous skill' "$TMP/backup/claude/harness-evidence/SKILL.md" || fail 'backup overwritten'
    grep -qx 'drift' "$dest/references/report-template.json" || fail 'collision changed installed files'
  fi
  rm -rf "$dest"
  cp -a "$TMP/backup/$client/harness-evidence" "$dest"
  grep -qx 'previous skill' "$dest/SKILL.md" || fail 'restore failed'
done
printf 'PASS: isolated fresh/custom installation, idempotence, backup/restore, and full-tree drift\n'
# Execute the real scoped bootstrap and parity stanzas against another fixture HOME.
install_block=$(sed -n '/^# BEGIN harness-evidence installation/,/^# END harness-evidence installation/p' "$ROOT/bootstrap.sh")
parity_block=$(sed -n '/^# BEGIN harness-evidence parity/,/^# END harness-evidence parity/p' "$ROOT/tests/standalone_runtime_parity_test.sh")
test -n "$install_block" && test -n "$parity_block" || fail 'bootstrap/parity wiring missing'
(
  export HOME="$TMP/bootstrap"
  FILES="$ROOT/files"; BACKUP_DIR="$TMP/bootstrap-backup"
  # shellcheck disable=SC2034 # Used by the extracted production stanza.
  : "$FILES" "$BACKUP_DIR"
  eval "$install_block"
  eval "$parity_block"
  echo extra > "$HOME/.codex/skills/harness-evidence/unexpected.txt"
  if (eval "$parity_block") >/dev/null 2>&1; then fail 'full-tree parity missed an extra file'; fi
)
echo 'PASS: real scoped bootstrap and standalone parity wiring'
