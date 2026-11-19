# Bitwarden CLI helpers.
# `bw-unlock`  — unlock vault, export BW_SESSION for this shell.
# `bw-lock`    — lock vault, clear BW_SESSION.
# `bw-get`     — fetch a password by item name.
# `bw-field`   — fetch an arbitrary field (e.g. username, notes).
# `bw-sync`    — pull latest vault changes.
# `bw-serve`   — unlock, then serve the REST API in the foreground; locks on exit.

bw-unlock() {
  local status_json
  status_json=$(bw status 2>/dev/null)

  case "$status_json" in
    *'"status":"unauthenticated"'*)
      echo "Not logged in. Run: bw login"
      return 1
      ;;
    *'"status":"unlocked"'*)
      echo "Vault already unlocked."
      return 0
      ;;
  esac

  local session
  session=$(bw unlock --raw) || return 1
  export BW_SESSION="$session"
  echo "Vault unlocked for this shell."
}

bw-lock() {
  bw lock >/dev/null 2>&1
  unset BW_SESSION
  echo "Vault locked."
}

bw-get() {
  if [[ -z "$1" ]]; then
    echo "Usage: bw-get <item-name>" >&2
    return 1
  fi
  if [[ -z "$BW_SESSION" ]]; then
    bw-unlock || return 1
  fi
  bw get password "$1"
}

bw-field() {
  if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage: bw-field <item-name> <field>" >&2
    return 1
  fi
  if [[ -z "$BW_SESSION" ]]; then
    bw-unlock || return 1
  fi
  bw get "$2" "$1"
}

bw-sync() {
  if [[ -z "$BW_SESSION" ]]; then
    bw-unlock || return 1
  fi
  bw sync
}

# A port is busy unless curl is refused outright (exit 7). curl ships with both
# macOS and Git Bash, unlike lsof; with no curl at all (127) we assume it is free.
_bw-port-busy() {
  curl -s -o /dev/null --noproxy '*' --max-time 1 "http://127.0.0.1:$1/" 2>/dev/null
  local rc=$?
  [[ $rc -ne 7 && $rc -ne 127 ]]
}

bw-serve() {
  # Unlock (exports BW_SESSION via bw-unlock), print the auth result, then run
  # `bw serve` in the foreground so secret.sh's REST helper can reach the vault.
  local port="${BW_SERVE_PORT:-8087}"

  if _bw-port-busy "${port}"; then
    echo "bw-serve: port ${port} is already in use" >&2
    return 1
  fi

  bw-unlock || return 1

  bw status | jq -r '"status: \(.status)   user: \(.userEmail)"' 2>/dev/null \
    || bw status

  # The no-op INT trap keeps this function alive when Ctrl-C stops `bw serve`,
  # so the vault is locked afterwards. It replaces any INT trap of your own and
  # resets it to default on the way out; SIGTERM and a closed terminal skip the lock.
  trap : INT
  bw serve --port "${port}"
  local rc=$?
  trap - INT
  bw-lock
  return "${rc}"
}
