#!/usr/bin/env bash
# Tests for gitf in .git_alias, run in throwaway repos — no real repo is touched.

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
subject="$(dirname "$here")/.git_alias"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

new_repo() {
  git init -q -b main "$work/$1" && cd "$work/$1" && git commit -q --allow-empty -m init
}

branches() {
  git branch --format='%(refname:short)' | paste -sd' ' -
}

new_repo full
for b in develop master demo feature; do git branch "$b"; done
git checkout -q -b wip && git commit -q --allow-empty -m unmerged && git checkout -q main
expected="demo develop main master wip"
( source "$subject"; gitf >/dev/null 2>&1 )
check "gitf deletes a merged branch, keeps protected and unmerged ones" "$expected" "$(branches)"

new_repo sparse
git branch feature
expected="0 main"
( source "$subject"; gitf >/dev/null 2>&1 )
check "gitf does not stop when develop and demo are absent" "$expected" "$? $(branches)"

new_repo current
git checkout -q -b feature
expected="feature main"
( source "$subject"; gitf >/dev/null 2>&1 )
check "gitf keeps the checked-out branch" "$expected" "$(branches)"

finish
