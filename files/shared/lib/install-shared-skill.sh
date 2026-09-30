#!/usr/bin/env bash
# Scoped shared-skill install; callers provide an explicit home and backup root.
shared_skill_matches() { [ -d "$2" ] && diff -qr "$1" "$2" >/dev/null 2>&1; }
install_shared_skill() {
  local source=${1:?} user_home=${2:?} backup_root=${3:?} name client dest saved
  [ -f "$source/SKILL.md" ] || return 1
  name=$(basename "$source")
  for client in claude codex; do
    dest="$user_home/.$client/skills/$name"
    shared_skill_matches "$source" "$dest" && continue
    saved="$backup_root/$client/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if [ -e "$saved" ] || [ -L "$saved" ]; then
        printf 'Backup already exists: %s; choose a fresh backup root\n' "$saved" >&2
        return 1
      fi
      mkdir -p "$(dirname "$saved")" || return 1
      cp -a "$dest" "$saved" || return 1
    fi
    mkdir -p "$(dirname "$dest")" || return 1
    rm -rf "$dest" || return 1
    cp -a "$source" "$dest" || return 1
  done
}
