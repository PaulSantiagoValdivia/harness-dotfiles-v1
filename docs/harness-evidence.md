# Read harness health without taking over other work

Run `bash tests/worktree_health_test.sh` for isolated checkout/ownership regression coverage. Run `./verify.sh` for installed-state acceptance; that command also checks live configured repositories.

- A stale checkout warning means metadata or the directory is missing. Inspect residual files with the owner; do not delete or prune automatically.
- An unavailable inspection means health is unknown, not clean.
- Pending work includes meaningful tracked and untracked files. Only the two recognized generated registry filenames are excluded from those counts.
- Publication warnings describe locally available remote-tracking refs, not a fresh server query. Coordinate with the owner before any fetch, commit, or push.
- Verification does not repair ignores. Use the explicit local procedure below; never global bootstrap or sibling tracked-file edits to silence warnings.

Rollback this diagnostics slice by reverting `verify.sh`, its source-only health helper, and the focused fixture suite together. No sibling files or Git registrations need restoration because the audit does not change them.

## Protect local worktree paths explicitly

Coordinate ownership first; do not run while another process edits Git exclusions. The source-only tool changes only the validated repository's shared `info/exclude`, protecting main and linked checkouts. It does not commit, push, prune, or delete working data.

```bash
tool="$PWD/files/shared/bin/harness-local-protect"
repo="/absolute/path/to/owned-checkout"
receipt="/private/operator-owned-directory/protection.json"
python3 "$tool" prepare "$repo" "$receipt"
# Inspect the receipt and planned additions before applying.
python3 "$tool" apply "$receipt"
git -C "$repo" check-ignore -v -- .claude/worktrees/probe .atl/probe
# If rollback is needed:
python3 "$tool" rollback "$receipt"
```

The receipt directory must already exist. Keep the immutable receipt: it contains the exact previous bytes (base64), their SHA-256, and only missing `/.claude/worktrees/` / `/.atl/` rules. Private application/rollback sidecars bind state to that receipt. Never edit or publish them.

Apply is idempotent while content matches the recorded result. Existing permissions are retained. An exclusive lock and observed-content checks refuse conflicting writes; symlinks and nonregular targets are rejected. On refusal, inspect ownership/drift rather than forcing the operation or deleting a lock.

Rollback removes only this operation's unambiguous additions, preserves concurrent additions, and closes the receipt so later rollback cannot remove a new owner's rules. An originally absent exclude remains an empty file after restoration. Retain backups; do not restore the entire old file over concurrent edits. A crash between replacement and receipt creation requires manual inspection, not automatic recovery.

Reproduce safety checks with `python3 tests/local_protection_test.py`. A future team-wide `.gitignore` change belongs in the product owner's dev-based PR; this operation is local machine protection only. Cache age/size never establishes deletion permission, especially for live session or SQLite data.

## Record evidence without publishing it

Load `harness-evidence` for regression or verification receipts. Copy `references/report-template.json` from the installed skill into a verified ignored directory or a private directory outside the repository. It starts UNTESTED: null values and unavailable reasons are not proof of success.

Fill repository/revision and dirty-state limitations, actual runtime target, UTC time, expected/observed results, command or interaction, and exit code or reason. Keep before/after states comparable; mark unavailable history explicitly instead of recreating it destructively. Compute SHA-256 only for retained, inspected artifacts (for example, `shasum -a 256 /private/path/output.log`). A hash binds bytes, not the truth of a claim.

Separate source tests, installed/deployed probes, and external-owner findings. Preserve FAIL/BLOCKED/UNTESTED outcomes. Do not execute command strings from reports. Redact sensitive values; do not record screens, bypass protections, or upload without explicit scope/destination approval. Existing SDD verification and the selected review lane remain authoritative.

### Scoped installation and rollback

From this repository, after reviewing source changes:

```bash
source files/shared/lib/install-shared-skill.sh
backup=$(mktemp -d "$HOME/.harness-evidence-backup.XXXXXX")
install_shared_skill "$PWD/files/shared/skills/harness-evidence" "$HOME" "$backup"
```

Only the two managed skill directories change. Existing trees are retained under `$backup/claude/harness-evidence` and `$backup/codex/harness-evidence`; identical reruns are no-ops. A colliding backup is refused, never overwritten. Record the backup path. After deployment, refresh the skill registry through the existing `gentle-ai skill-registry refresh --force --no-gitignore` workflow.

To roll back, inspect each installed tree for later user changes first. Restore its saved tree, or remove only the newly installed managed tree if no predecessor existed. Preserve subsequent edits and backups; do not overwrite global instructions/settings or remove other skills. Verify restored parity against the corresponding source revision. Run `bash tests/harness_evidence_test.sh` for isolated installation proof; live installed parity remains a separate check.
