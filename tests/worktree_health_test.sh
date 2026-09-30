#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
test -f "$ROOT/files/shared/lib/worktree-health.sh" || fail "health helper missing"
# shellcheck source=files/shared/lib/worktree-health.sh
source "$ROOT/files/shared/lib/worktree-health.sh"
git init -q "$TMP/repo space"
repo="$TMP/repo space"
git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial --allow-empty
expect_checkout() {
  local expected=$1 path=$2 rc=0
  health_checkout "$path" || rc=$?
  [ "$rc" = "$expected" ] || fail "checkout $path: expected $expected, got $rc"
}
expect_checkout 0 "$repo"
expect_checkout 1 "$TMP/absent"
mkdir "$repo/residual"
expect_checkout 1 "$repo/residual"
printf 'gitdir: /does/not/exist\n' > "$repo/residual/.git"
expect_checkout 2 "$repo/residual"
git -C "$repo" worktree add -q --detach "$TMP/linked space"
expect_checkout 0 "$TMP/linked space"
ln -s "$repo" "$TMP/alias"
expect_checkout 0 "$TMP/alias"
(cd "$TMP" && expect_checkout 0 'repo space')
echo 'PASS: checkout identity (7 cases)'
test "$(health_counts "$repo")" = '0 0 0' || fail 'clean checkout counts'
printf 'original\n' > "$repo/tracked"
printf 'rename\n' > "$repo/old name"
git -C "$repo" add tracked 'old name'
git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm tracked
printf 'modified\n' >> "$repo/tracked"
git -C "$repo" mv 'old name' $'new\nname'
printf 'new\n' > "$repo/untracked"
mkdir "$repo/.atl"
printf 'generated\n' > "$repo/.atl/skill-registry.md"
printf 'generated\n' > "$repo/.atl/.skill-registry.cache.json"
printf 'user\n' > "$repo/.atl/user-notes"
before=$(shasum "$repo/.git/index" "$repo/tracked")
registration=$(git -C "$repo" worktree list --porcelain)
test "$(health_counts "$repo")" = '2 2 2' || fail 'tracked/untracked/generated counts'
test "$before" = "$(shasum "$repo/.git/index" "$repo/tracked")" || fail 'audit mutated index/files'
test "$registration" = "$(git -C "$repo" worktree list --porcelain)" || fail 'audit mutated registration'
warn() { echo "WARN $*"; }
info() { echo "INFO $*"; }
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; }
check() { local label=$1; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
output=$(health_audit_root "$repo")
[[ "$output" == *'tracked=2 untracked=2'* ]] || fail 'pending work not visible'
[[ "$output" == *'locally available remote-tracking refs'* ]] || fail 'unqualified remote assertion'
output=$(health_audit_root "$repo/residual")
[[ "$output" == *'inspection unavailable'* ]] || fail 'malformed checkout not reported'
output=$(health_audit_root "$TMP/absent")
[[ "$output" == *'stale'* ]] || fail 'stale checkout not reported'
mkdir -p "$TMP/linked space/.atl"
printf 'generated\n' > "$TMP/linked space/.atl/skill-registry.md"
test "$(health_counts "$TMP/linked space")" = '0 0 1' || fail 'generated-only counts'
output=$(health_audit_root "$TMP/linked space")
[[ "$output" == *'only known generated'* && "$output" != *'pending owner work'* ]] || fail 'generated-only diagnosis'
command git -C "$repo" update-ref refs/remotes/fixture/main HEAD
output=$(health_audit_root "$repo")
[[ "$output" != *'HEAD absent'* ]] || fail 'existing local ref ignored'
roots=$(health_each_root "$repo" printf '%s\n')
[[ "$roots" == *"$repo"* && "$roots" == *'linked space'* ]] || fail 'registered roots missing'
mkdir "$repo/not-a-root"
output=$(health_each_root "$repo/not-a-root" printf 'CALLBACK %s\n')
[[ "$output" != *'CALLBACK'* && "$output" == *'stale'* ]] || fail 'configured subdirectory discovered ancestor worktrees'
# One fault-injection seam; all ordinary cases use actual Git repositories.
# shellcheck disable=SC2329 # Invoked by sourced health_git for fault injection.
git() {
  [ "${GIT_OPTIONAL_LOCKS:-}" = 0 ] || fail 'optional Git index writes enabled'
  printf '%s\n' "$*" >> "$TMP/git-calls"
  if [[ "$*" == *"${FAIL_GIT:?}"* ]]; then return 128; fi
  command git "$@"
}
FAIL_GIT='rev-parse'
expect_checkout 2 "$repo"
for FAIL_GIT in status 'branch -r' 'worktree list'; do
  if [ "$FAIL_GIT" = 'worktree list' ]; then
    output=$(health_each_root "$repo" printf '%s\n')
  else
    output=$(health_audit_root "$repo")
  fi
  [[ "$output" == *'inspection unavailable'* ]] || fail "hidden Git failure: $FAIL_GIT"
  if [ "$FAIL_GIT" = 'branch -r' ]; then
    [[ "$output" != *'HEAD absent'* ]] || fail 'error asserted unpublished commits'
  fi
done
! grep -Eq '(^| )(fetch|push|commit|prune|reset)( |$)' "$TMP/git-calls" || fail 'mutating Git command'
unset -f git
# Exercise existing validator entry points without executing the live verifier.
eval "$(sed -n '/^validate_core_root() {/,/^}/p; /^validate_cocoa_root() {/,/^}/p' "$ROOT/verify.sh")"
for validator in validate_core_root validate_cocoa_root; do
  output=$($validator "$repo/residual" 2>/dev/null)
  [[ "$output" != *'CLAUDE.md'* ]] || fail 'stale root produced instruction failures'
  output=$($validator "$repo" 2>/dev/null)
  [[ "$output" == *'FAIL '*'/CLAUDE.md existe'* ]] || fail 'real missing instructions hidden'
done
echo 'PASS: status, ownership, failures, nonmutation, and validator integration'
