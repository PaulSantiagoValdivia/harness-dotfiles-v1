#!/usr/bin/env bash
# Source-only, read-only Git inspection. 0=checkout, 1=missing, 2=uncertain.
health_git() { GIT_OPTIONAL_LOCKS=0 git "$@"; }
health_checkout() {
  local root=$1 physical top
  [ -d "$root" ] && { [ -e "$root/.git" ] || [ -L "$root/.git" ]; } || return 1
  physical=$(cd "$root" && pwd -P) || return 2
  top=$(health_git -C "$root" rev-parse --show-toplevel 2>/dev/null) || return 2
  top=$(cd "$top" && pwd -P) || return 2
  [ "$physical" = "$top" ] || return 2
}
health_generated() {
  case "$1" in
    .atl/skill-registry.md|*/.atl/skill-registry.md|.atl/.skill-registry.cache.json|*/.atl/.skill-registry.cache.json) return 0 ;;
    *) return 1 ;;
  esac
}
health_counts() (
  local tmp record path original state tracked=0 untracked=0 generated=0
  tmp=$(mktemp) || return 2
  trap 'rm -f "$tmp"' EXIT
  health_git -C "$1" status --porcelain=v1 -z --untracked-files=all > "$tmp" 2>/dev/null || return 2
  while IFS= read -r -d '' record; do
    state=${record:0:2}; path=${record:3}; original=$path
    case "$state" in *R*|*C*) IFS= read -r -d '' original || return 2 ;; esac
    if health_generated "$path" && health_generated "$original"; then
      generated=$((generated + 1))
    elif [ "$state" = '??' ]; then
      untracked=$((untracked + 1))
    else
      tracked=$((tracked + 1))
    fi
  done < "$tmp"
  printf '%s %s %s\n' "$tracked" "$untracked" "$generated"
)
health_audit_root() {
  local root=$1 rc=0 counts tracked untracked generated refs
  health_checkout "$root" || rc=$?
  case "$rc" in
    1) warn "$root: stale checkout; owner must inspect residual data before recovery"; return ;;
    2) warn "$root: checkout inspection unavailable; owner must inspect Git metadata"; return ;;
  esac
  if counts=$(health_counts "$root"); then
    read -r tracked untracked generated <<< "$counts"
    if [ "$tracked" -gt 0 ] || [ "$untracked" -gt 0 ]; then
      warn "$root: pending owner work (tracked=$tracked untracked=$untracked); preserve and coordinate"
    elif [ "$generated" -gt 0 ]; then
      info "$root: only known generated registry files ($generated), no pending source work"
    fi
  else
    warn "$root: status inspection unavailable; cleanliness unknown"
  fi
  if refs=$(health_git -C "$root" branch -r --contains HEAD 2>/dev/null); then
    [ -n "$refs" ] || warn "$root: HEAD absent from locally available remote-tracking refs; owner must verify publication"
  else
    warn "$root: remote-ref inspection unavailable; publication unknown"
  fi
}
health_each_root() {
  local repo=$1 callback=$2 tmp record
  shift 2
  health_checkout "$repo" || { health_audit_root "$repo"; return; }
  tmp=$(mktemp) || { warn "$repo: worktree inspection unavailable (temporary file)"; return; }
  if ! health_git -C "$repo" worktree list --porcelain -z > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    warn "$repo: worktree inspection unavailable; inventory unknown"
    return
  fi
  while IFS= read -r -d '' record; do
    case "$record" in worktree\ *) "$callback" "$@" "${record#worktree }" ;; esac
  done < "$tmp"
  rm -f "$tmp"
}
