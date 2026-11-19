#!/usr/bin/env bash
# bw-serve on a real pseudo-terminal, which the pipe-fed bitwarden_test.sh cannot
# reach: single-key reads, no-key idling, and a real group-wide Ctrl-C.
# Needs python3 and a Unix pty; elsewhere it skips, saying so (check by hand there).

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
subject="$(dirname "$here")/bitwarden.zsh"
shell_name="${BASH_VERSION:+bash}${ZSH_VERSION:+zsh}"

if ! python3 -c 'import pty' 2>/dev/null; then
  echo "skipped: python3 with a Unix pty is not available, so no terminal can be driven"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export STUB_LOG="$work/bw.log" STUB_SERVER_PID="$work/server.pid" TMPDIR="$work"
cat > "$work/bw" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1" in
  status) echo '{"status":"locked","userEmail":"t@t"}' ;;
  unlock) echo "stub-session-token" ;;
  serve) echo $$ > "$STUB_SERVER_PID"; exec sleep 20 ;;
esac
EOF
printf '#!/bin/sh\nexit 7\n' > "$work/curl"
chmod +x "$work/bw" "$work/curl"
export PATH="$work:$PATH"

# Types $1 into bw-serve on a pty; prints "exited" or "serving", then reaps the stub server.
drive() {
  : > "$STUB_LOG"; rm -f "$STUB_SERVER_PID"
  python3 -I "$here/pty_drive.py" "$shell_name" "$subject" "$1" "$work/transcript"
  kill "$(cat "$STUB_SERVER_PID" 2>/dev/null)" 2>/dev/null
}

expected="exited lock"
actual="$(drive 'q') $(grep -x 'lock' "$STUB_LOG")"
check "q alone quits and locks on a terminal" "$expected" "$actual"

expected="exited 1 lock"
actual="$(drive 'sq') $(grep -cx 'sync' "$STUB_LOG") $(grep -x 'lock' "$STUB_LOG")"
check "s syncs once, then q quits and locks, on a terminal" "$expected" "$actual"

expected="exited lock"
actual="$(drive '\x03') $(grep -x 'lock' "$STUB_LOG")"
check "a real Ctrl-C quits and locks" "$expected" "$actual"

expected="0"
check "a real Ctrl-C does not claim the server exited early" "$expected" "$(grep -c 'exited early' "$work/transcript")"

expected="serving"
check "with no key pressed bw-serve keeps serving" "$expected" "$(drive '')"

finish
