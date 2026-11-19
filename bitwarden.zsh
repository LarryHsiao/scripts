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

# Waits up to a second for one key and prints it.
# Exit 0: a key was read. 2: none yet. 1: input has ended.
# zsh's read cannot tell a timeout from end of input, so it asks zselect first.
_bw-read-key() {
  local key rc
  if [[ -n "$ZSH_VERSION" ]]; then
    zmodload zsh/zselect 2>/dev/null
    zselect -t 100 -r 0 >/dev/null || return 2
    read -rsk1 -u0 key || return 1
  else
    read -rsn1 -t 1 key
    rc=$?
    [[ $rc -gt 128 ]] && return 2
    [[ $rc -ne 0 ]] && return 1
  fi
  printf '%s' "$key"
}

# Runs until q, end of input, Ctrl-C (the INT trap sets the flag), or the server
# dying. $1 is the server's pid.
_bw-serve-loop() {
  local key rc
  while kill -0 "$1" 2>/dev/null && [[ -z "$_bw_interrupted" ]]; do
    key=$(_bw-read-key)
    rc=$?
    [[ $rc -eq 1 ]] && return 0
    [[ "$key" == "q" ]] && return 0
  done
}

# $1 is the server's pid, $2 its log file.
_bw-serve-stop() {
  kill "$1" 2>/dev/null || echo "bw-serve: server exited early; see $2" >&2
  bw-lock
}

bw-serve() {
  # Unlock (exports BW_SESSION via bw-unlock), then run `bw serve` in the
  # background so secret.sh's REST helper can reach the vault while this shell
  # listens for keys. The vault is locked on every way out except SIGTERM and a
  # closed terminal. The INT trap replaces any INT trap of your own and resets
  # it to default afterwards.
  local port="${BW_SERVE_PORT:-8087}" log="${TMPDIR:-/tmp}/bw-serve.log" server

  if _bw-port-busy "${port}"; then
    echo "bw-serve: port ${port} is already in use" >&2
    return 1
  fi

  bw-unlock || return 1

  bw status | jq -r '"status: \(.status)   user: \(.userEmail)"' 2>/dev/null \
    || bw status

  server=$(bw serve --port "${port}" >"${log}" 2>&1 & echo $!)
  echo "bw-serve: serving on port ${port} (log: ${log})"
  echo "[q] quit and lock"

  trap '_bw_interrupted=1' INT
  _bw-serve-loop "${server}"
  trap - INT
  unset _bw_interrupted
  _bw-serve-stop "${server}" "${log}"
}
