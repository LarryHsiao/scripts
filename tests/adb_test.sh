#!/usr/bin/env bash
# Tests for .adb_alias against a stubbed `adb` that prints its arguments, `|`-joined.

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
subject="$(dirname "$here")/.adb_alias"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/adb" <<'EOF'
#!/bin/sh
printf '%s|' "$@"; echo
EOF
chmod +x "$work/adb"
export PATH="$work:$PATH"

expected="shell|am|start|-a|android.intent.action.VIEW|-d|https://example.com|"
actual=$( (source "$subject"; adb_view https://example.com) )
check "adb_view passes the URL as the -d value" "$expected" "$actual"

expected="shell|am|start|-a|com.google.android.gms.actions.SEARCH_ACTION|-e|query|hello world|"
actual=$( (source "$subject"; adb_search hello world) )
check "adb_search passes a multi-word query as one value" "$expected" "$actual"

finish
