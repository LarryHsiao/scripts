#!/usr/bin/env bash
# Tests for setup.sh: sourced from an unrelated directory, it must define every
# alias and function the repo offers. Run in a child shell of the shell under test.

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
subject="$(dirname "$here")/setup.sh"
shell_name="${BASH_VERSION:+bash}${ZSH_VERSION:+zsh}"

defined() {
  "$shell_name" -c 'cd /; source "$1"; alias "$2" >/dev/null 2>&1 || type "$2" >/dev/null 2>&1' \
    _ "$subject" "$1" && echo defined
}

for name in adb_home adb_view fclean fi18n gitl gits gitf bw-unlock bw-serve; do
  expected="defined"
  check "setup.sh defines $name from another directory" "$expected" "$(defined "$name")"
done

finish
