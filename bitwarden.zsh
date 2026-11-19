# Bitwarden CLI helpers.
# `bw-unlock`  — unlock vault, export BW_SESSION for this shell.
# `bw-lock`    — lock vault, clear BW_SESSION.
# `bw-get`     — fetch a password by item name.
# `bw-field`   — fetch an arbitrary field (e.g. username, notes).
# `bw-sync`    — pull latest vault changes.

bw-unlock() {
  local status_json
  status_json=$(bw status 2>/dev/null)

  case "$status_json" in
    *'"status":"unauthenticated"'*)
      echo "Not logged in. Run: bw login"
      return 1
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

bw-serve() {
  # Unlock (exports BW_SESSION via bw-unlock), print the auth result, then run
  # `bw serve` in the foreground so secret.sh's REST helper can reach the vault.
  bw-unlock || return 1

  local port="${BW_SERVE_PORT:-8087}"

  bw status | jq -r '"status: \(.status)   user: \(.userEmail)"' 2>/dev/null \
    || bw status

  bw serve --port "${port}"
}
