# Shared by tests/*_test.sh — source it, do not run it.
# Each test file must work in both shells, so run it under each:
#   bash tests/<name>_test.sh && zsh tests/<name>_test.sh

failures=0

check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected '$2', got '$3')"
    failures=$((failures + 1))
  fi
}

finish() {
  [ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
  echo "all passed"
}
