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
  sync) [ "${STUB_SYNC_RC:-0}" -eq 0 ] || { echo "stub sync error"; exit "$STUB_SYNC_RC"; } ;;
  serve)
    # No env: exit at once, as a crashed server would. STUB_SERVE_STAY keeps it
    # alive; STUB_SERVE_INTERRUPT=<signal> also sends that signal to the shell STUB_INTERRUPT_PID.
    [ -n "$STUB_SERVER_PID" ] && echo $$ > "$STUB_SERVER_PID"
    if [ -n "$STUB_SERVE_INTERRUPT" ]; then ( sleep 1; kill -"$STUB_SERVE_INTERRUPT" "$STUB_INTERRUPT_PID" ) & fi
    [ -n "$STUB_SERVE_STAY" ] && exec sleep 10
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
expected="serve --hostname 127.0.0.1 --port 8087"
: > "$STUB_LOG"
{ sleep 2; } | ( source "$subject"; bw-serve >/dev/null 2>&1 )
check "bw-serve defaults to port 8087" "$expected" "$(grep '^serve' "$STUB_LOG")"

expected="serve --hostname 127.0.0.1 --port 9999"
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

# Windows takes about 2.1 s to refuse a connection to a free port; a shorter limit
# makes curl time out (28) and the free port read as busy.
expected="--max-time 5"
: > "$STUB_LOG"
{ sleep 2; } | ( source "$subject"; bw-serve >/dev/null 2>&1 )
check "the port probe waits long enough for Windows to refuse" "$expected" "$(grep -o -e '--max-time 5' "$STUB_LOG" | head -1)"

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
    'export STUB_INTERRUPT_PID=$$; source "$1"; start=$SECONDS; bw-serve >"$4" 2>&1; echo "${BW_SESSION-unset}" > "$2"; echo $((SECONDS - start)) > "$3"' \
    _ "$subject" "$work/after" "$work/elapsed" "$work/serve.out"
}

# The staying stub lives ten seconds; a bw-serve that waits it out is not listening.
returned_promptly() {
  [ "$(cat "$work/elapsed")" -le 4 ] && echo "prompt" || echo "slow"
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

serve_with_keys "s"
expected="sync"
check "s triggers a bw sync" "$expected" "$(grep -x 'sync' "$STUB_LOG" | head -1)"
expected="synced at"
check "s reports the sync" "$expected" "$(grep -o 'synced at' "$work/serve.out" | head -1)"
server_state >/dev/null

serve_with_keys "s" "STUB_SYNC_RC=1"
expected="sync failed: stub sync error"
check "a failed sync is reported with bw's message" "$expected" "$(grep -o 'sync failed: stub sync error' "$work/serve.out" | head -1)"
server_state >/dev/null

serve_with_keys "x" "" 2
expected="0"
check "an unknown key triggers no sync" "$expected" "$(grep -cx 'sync' "$STUB_LOG")"
server_state >/dev/null

serve_with_keys "S"
expected="1"
check "uppercase S also syncs" "$expected" "$(grep -cx 'sync' "$STUB_LOG")"
server_state >/dev/null

serve_with_keys "Q" "" 4
expected="prompt"
check "uppercase Q also quits, without waiting for end of input" "$expected" "$(returned_promptly)"
server_state >/dev/null

serve_with_keys "q"
expected="yes"
actual=$([ -f "$work/bw-serve-8087.log" ] && echo yes)
check "the server log is named for its port" "$expected" "$actual"
server_state >/dev/null

serve_with_keys "" "BW_SYNC_INTERVAL=1" 4
expected="yes"
actual=$([ "$(grep -cx 'sync' "$STUB_LOG")" -ge 1 ] && echo yes)
check "bw-serve syncs by itself after BW_SYNC_INTERVAL seconds" "$expected" "$actual"
server_state >/dev/null

serve_with_keys "" "" 3
expected="0"
check "the default interval does not sync within seconds" "$expected" "$(grep -cx 'sync' "$STUB_LOG")"
server_state >/dev/null

for bad in abc 0 -5 12345678; do
  expected="1 BW_SYNC_INTERVAL must be a whole number of seconds"
  output=$( (source "$subject"; BW_SYNC_INTERVAL=$bad bw-serve 2>&1 </dev/null) )
  actual="$? $(printf '%s' "$output" | grep -o 'BW_SYNC_INTERVAL must be a whole number of seconds')"
  check "BW_SYNC_INTERVAL=$bad is refused" "$expected" "$actual"
done

# zsh only: a closed stdin must end the session, not spin until the server dies. Bash
# has no such guard, and once bw-serve opens its own pipes it may reuse fd 0, so a
# closed stdin has no stable meaning there.
if [ -n "$ZSH_VERSION" ]; then
  : > "$STUB_LOG"; rm -f "$STUB_SERVER_PID"
  STUB_SERVE_STAY=1 "$shell_name" -c \
    'source "$1"; start=$SECONDS; bw-serve >/dev/null 2>&1 <&-; echo $((SECONDS - start)) > "$2"' _ "$subject" "$work/elapsed"
  expected="prompt lock"
  check "closed stdin quits and locks (zsh)" "$expected" "$(returned_promptly) $(grep '^lock' "$STUB_LOG")"
  server_state >/dev/null
fi

serve_with_keys "" "STUB_SERVE_INTERRUPT=INT" 4
expected="lock unset"
check "Ctrl-C locks the vault and clears the session" "$expected" "$(grep '^lock' "$STUB_LOG") $(cat "$work/after")"
expected="prompt"
check "Ctrl-C returns promptly" "$expected" "$(returned_promptly)"
expected="stopped"
check "Ctrl-C stops the background server" "$expected" "$(server_state)"

serve_with_keys "" "STUB_SERVE_INTERRUPT=TERM" 4
expected="lock unset"
check "SIGTERM locks the vault and clears the session" "$expected" "$(grep '^lock' "$STUB_LOG") $(cat "$work/after")"
expected="prompt"
check "SIGTERM returns promptly" "$expected" "$(returned_promptly)"
expected="stopped"
check "SIGTERM stops the background server" "$expected" "$(server_state)"

finish
