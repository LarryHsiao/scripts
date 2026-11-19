#!/usr/bin/env bash
# Tests for bitwarden.zsh against a stubbed `bw` — no real vault is touched.
# The file must work in both shells, so run it under each:
#   bash tests/bitwarden_test.sh && zsh tests/bitwarden_test.sh

here="$(cd "$(dirname "$0")" && pwd)"
subject="$(dirname "$here")/bitwarden.zsh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export STUB_LOG="$work/bw.log"
export STUB_STATUS_JSON='{"status":"locked","userEmail":"test@example.com"}'
export STUB_SESSION="stub-session-token"
unset BW_SESSION BW_SERVE_PORT

cat > "$work/bw" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1" in
  status) printf '%s\n' "$STUB_STATUS_JSON" ;;
  unlock) echo "$STUB_SESSION" ;;
esac
EOF
chmod +x "$work/bw"
export PATH="$work:$PATH"

failures=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected '$2', got '$3')"
    failures=$((failures + 1))
  fi
}

for name in bw-unlock bw-lock bw-get bw-field bw-sync bw-serve; do
  expected="defined"
  actual=$( (source "$subject"; type "$name" >/dev/null 2>&1 && echo defined) )
  check "$name is defined" "$expected" "$actual"
done

expected="1"
( source "$subject"; STUB_STATUS_JSON='{"status":"unauthenticated"}' bw-unlock >/dev/null )
check "bw-unlock fails when not logged in" "$expected" "$?"

expected="$STUB_SESSION"
actual=$( (source "$subject"; bw-unlock >/dev/null; echo "$BW_SESSION") )
check "bw-unlock exports BW_SESSION" "$expected" "$actual"

expected="0 existing-token"
: > "$STUB_LOG"
actual=$( (source "$subject"
  export BW_SESSION="existing-token"
  STUB_STATUS_JSON='{"status":"unlocked"}' bw-unlock >/dev/null
  echo "$? $BW_SESSION") )
check "bw-unlock reuses a valid session" "$expected" "$actual"

expected=""
check "bw-unlock does not prompt when already unlocked" "$expected" "$(grep '^unlock' "$STUB_LOG")"

expected="serve --port 8087"
: > "$STUB_LOG"
( source "$subject"; bw-serve >/dev/null 2>&1 )
check "bw-serve defaults to port 8087" "$expected" "$(grep '^serve' "$STUB_LOG")"

expected="serve --port 9999"
: > "$STUB_LOG"
( source "$subject"; BW_SERVE_PORT=9999 bw-serve >/dev/null 2>&1 )
check "BW_SERVE_PORT overrides the port" "$expected" "$(grep '^serve' "$STUB_LOG")"

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "all passed"
