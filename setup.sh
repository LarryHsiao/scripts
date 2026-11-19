# Source this file, do not run it: `source ~/scripts/setup.sh` (bash, zsh, Git Bash).
# Running it would define everything in a subshell that exits at once.

if [ -n "${BASH_VERSION:-}" ]; then
  _scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  _scripts_dir="$(cd "$(dirname "${(%):-%x}")" && pwd)"
fi

for _scripts_file in .adb_alias .fvm_alias .git_alias bitwarden.zsh; do
  source "$_scripts_dir/$_scripts_file"
done
unset _scripts_dir _scripts_file
