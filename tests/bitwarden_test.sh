#!/usr/bin/env bash
# Tests for bitwarden.zsh against a stubbed `bw` — no real vault is touched.

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
subject="$(dirname "$here")/bitwarden.zsh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export STUB_LOG="$work/bw.log"
export STUB_STATUS_JSON='{"status":"locked","userEmail":"test@example.com"}'
export STUB_SESSION="stub-session-token"
export STUB_SERVER_PID="$work/server.pid"
export TMPDIR="$work"
shell_name="${BASH_VERSION:+bash}${ZSH_VERSION:+zsh}"
unset BW_SESSION BW_SERVE_PORT

cat > "$work/bw" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1" in
  status) printf '%s\n' "$STUB_STATUS_JSON" ;;
  unlock) echo "$STUB_SESSION" ;;
  serve)
    # No env: exit at once, as a crashed server would. STUB_SERVE_STAY keeps it
    # alive; STUB_SERVE_INTERRUPT also mimics Ctrl-C reaching the shell STUB_INTERRUPT_PID.
    [ -n "$STUB_SERVER_PID" ] && echo $$ > "$STUB_SERVER_PID"
    if [ -n "$STUB_SERVE_INTERRUPT" ]; then ( sleep 1; kill -INT "$STUB_INTERRUPT_PID" ) & fi
    [ -n "$STUB_SERVE_STAY" ] && exec sleep 5
    ;;
esac
EOF
cat > "$work/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$STUB_LOG"
exit "${STUB_CURL_RC:-7}"
EOF
chmod +x "$work/bw" "$work/curl"
export PATH="$work:$PATH"

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

# Stdin is held open for two seconds in the next few checks: with input at its end
# bw-serve quits at once, possibly before the background stub server has logged.
expected="serve --port 8087"
: > "$STUB_LOG"
{ sleep 2; } | ( source "$subject"; bw-serve >/dev/null 2>&1 )
check "bw-serve defaults to port 8087" "$expected" "$(grep '^serve' "$STUB_LOG")"

expected="serve --port 9999"
: > "$STUB_LOG"
{ sleep 2; } | ( source "$subject"; BW_SERVE_PORT=9999 bw-serve >/dev/null 2>&1 )
check "BW_SERVE_PORT overrides the port" "$expected" "$(grep '^serve' "$STUB_LOG")"

expected="1"
: > "$STUB_LOG"
( source "$subject"; STUB_CURL_RC=0 bw-serve >/dev/null 2>&1 )
check "bw-serve fails when the port is taken" "$expected" "$?"

expected=""
check "bw-serve does not launch bw serve when the port is taken" "$expected" "$(grep '^serve' "$STUB_LOG")"

expected="port 8087 is already in use"
actual=$( (source "$subject"; STUB_CURL_RC=0 bw-serve 2>&1) | grep -o 'port 8087 is already in use' )
check "bw-serve names the busy port" "$expected" "$actual"

expected="1"
: > "$STUB_LOG"
{ sleep 2; } | ( source "$subject"; bw-serve >/dev/null 2>&1 )
check "port probe bypasses any HTTP proxy" "$expected" "$(grep -c -- "--noproxy" "$STUB_LOG")"

expected="lock"
: > "$STUB_LOG"
{ sleep 2; } | ( source "$subject"; bw-serve >/dev/null 2>&1 )
check "bw-serve locks the vault when bw serve exits" "$expected" "$(grep '^lock' "$STUB_LOG")"

expected="exited early"
actual=$( { sleep 3; } | "$shell_name" -c 'source "$1"; bw-serve 2>&1 >/dev/null' _ "$subject" | grep -o 'exited early' )
check "bw-serve says so when the server exits on its own" "$expected" "$actual"

# Runs bw-serve in a child shell of the shell under test, with a server that stays alive.
# $1 is fed to it as keystrokes; $2 holds extra env assignments; $3 keeps stdin
# open that many seconds after the keys (end of input would otherwise quit). It
# waits a second first, so the stub server has started before any key arrives.
serve_with_keys() {
  : > "$STUB_LOG"; rm -f "$STUB_SERVER_PID"
  { sleep 1; printf '%s' "$1"; sleep "${3:-0}"; } | env STUB_SERVE_STAY=1 $2 "$shell_name" -c \
    'export STUB_INTERRUPT_PID=$$; source "$1"; start=$SECONDS; bw-serve >/dev/null 2>&1; echo "${BW_SESSION-unset}" > "$2"; echo $((SECONDS - start)) > "$3"' \
    _ "$subject" "$work/after" "$work/elapsed"
}

# The staying stub lives five seconds; a bw-serve that waits it out is not listening.
returned_promptly() {
  [ "$(cat "$work/elapsed")" -le 3 ] && echo "prompt" || echo "slow"
}

# Polls up to three seconds for the stub server to die, then reaps it.
server_state() {
  local pid i
  pid=$(cat "$STUB_SERVER_PID" 2>/dev/null)
  [ -n "$pid" ] || { echo "never-started"; return; }
  for i in 1 2 3 4 5 6; do
    kill -0 "$pid" 2>/dev/null || { echo "stopped"; return; }
    sleep 0.5
  done
  kill "$pid" 2>/dev/null; echo "still-running"
}

serve_with_keys "q"
expected="lock unset"
check "q locks the vault and clears the session" "$expected" "$(grep '^lock' "$STUB_LOG") $(cat "$work/after")"
expected="prompt"
check "q returns promptly" "$expected" "$(returned_promptly)"
expected="stopped"
check "q stops the background server" "$expected" "$(server_state)"

serve_with_keys ""
expected="lock"
check "end of input locks the vault" "$expected" "$(grep '^lock' "$STUB_LOG")"
expected="prompt"
check "end of input returns promptly" "$expected" "$(returned_promptly)"
expected="stopped"
check "end of input stops the background server" "$expected" "$(server_state)"

serve_with_keys "" "STUB_SERVE_INTERRUPT=1" 4
expected="lock unset"
check "Ctrl-C locks the vault and clears the session" "$expected" "$(grep '^lock' "$STUB_LOG") $(cat "$work/after")"
expected="prompt"
check "Ctrl-C returns promptly" "$expected" "$(returned_promptly)"
expected="stopped"
check "Ctrl-C stops the background server" "$expected" "$(server_state)"

finish
