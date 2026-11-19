# Bitwarden CLI helpers.
# `bw-unlock`  — unlock vault, export BW_SESSION for this shell.
# `bw-lock`    — lock vault, clear BW_SESSION.
# `bw-get`     — fetch a password by item name.
# `bw-field`   — fetch an arbitrary field (e.g. username, notes).
# `bw-sync`    — pull latest vault changes.
# `bw-serve`   — unlock, serve the REST API in the background; s syncs, q quits and locks.

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
# A terminal has no end of input, so there any failed read just means no key yet
# (and old bash 3.2 reports its timeout as 1, which it must not read as the end).
# Piped input: zsh's read cannot tell a timeout from the end, so it asks zselect
# first (timeout in hundredths of a second); bash 4+ returns above 128 on timeout.
_bw-read-key() {
  local key rc
  if [[ -t 0 ]]; then
    if [[ -n "$ZSH_VERSION" ]]; then
      read -rsk1 -t 1 key || return 2   # no -u0: it makes zsh wait for Enter
    else
      read -rsn1 -t 1 key || return 2
    fi
  elif [[ -n "$ZSH_VERSION" ]]; then
    { : <&0; } 2>/dev/null || return 1
    zmodload zsh/zselect 2>/dev/null || { echo "bw-serve: zsh/zselect is unavailable" >&2; return 1; }
    zselect -t 100 -r 0 >/dev/null 2>&1 || return 2
    read -rsk1 -u0 key || return 1
  else
    read -rsn1 -t 1 key
    rc=$?
    [[ $rc -gt 128 ]] && return 2
    [[ $rc -ne 0 ]] && return 1
  fi
  printf '%s' "$key"
}

# `bw sync`, with one line saying how it went.
_bw-serve-sync() {
  local out
  if out=$(bw sync 2>&1); then
    echo "synced at $(date +%H:%M:%S)"
  else
    echo "sync failed: ${out}" >&2
  fi
}

# Runs until q, end of input, a signal (the trap sets the flag), or the server
# dying; syncs on s and every $2 seconds. $1 is the server's pid.
_bw-serve-loop() {
  local key rc sync_now last=$SECONDS
  while kill -0 "$1" 2>/dev/null && [[ -z "$_bw_interrupted" ]]; do
    key=$(_bw-read-key)
    rc=$?
    [[ $rc -eq 1 ]] && return 0
    sync_now=""
    case "$key" in
      [qQ]) return 0 ;;
      [sS]) sync_now=1 ;;
    esac
    if [[ -n "$sync_now" ]] || (( SECONDS - last >= $2 )); then
      _bw-serve-sync
      last=$SECONDS
    fi
  done
}

# $1 is the server's pid, $2 its log file.
_bw-serve-stop() {
  kill "$1" 2>/dev/null || [[ -n "$_bw_interrupted" ]] \
    || echo "bw-serve: server exited early; see $2" >&2
  bw-lock
}

# Refuses a bad interval or a busy port. $1 is the port, $2 the interval.
_bw-serve-preflight() {
  if [[ ! "$2" =~ ^[1-9][0-9]{0,6}$ ]]; then
    echo "bw-serve: BW_SYNC_INTERVAL must be a whole number of seconds, 1 to 9999999" >&2
    return 1
  fi
  if _bw-port-busy "$1"; then
    echo "bw-serve: port $1 is already in use" >&2
    return 1
  fi
}

bw-serve() {
  # Unlock (exports BW_SESSION via bw-unlock), then run `bw serve` in the
  # background so secret.sh's REST helper can reach the vault while this shell
  # listens for keys. INT, TERM and HUP stop the server and lock the vault; the
  # trap replaces any of your own on those signals and resets them afterwards.
  local port="${BW_SERVE_PORT:-8087}" interval="${BW_SYNC_INTERVAL:-600}" server
  local log="${TMPDIR:-/tmp}/bw-serve-${port}.log"

  _bw-serve-preflight "${port}" "${interval}" || return 1
  bw-unlock || return 1

  bw status | jq -r '"status: \(.status)   user: \(.userEmail)"' 2>/dev/null \
    || bw status

  server=$(bw serve --port "${port}" >"${log}" 2>&1 & echo $!)
  echo "bw-serve: serving on port ${port} (log: ${log})"
  echo "[s] sync   [q] quit and lock   (auto-sync every ${interval}s)"

  trap '_bw_interrupted=1' INT TERM HUP
  _bw-serve-loop "${server}" "${interval}"
  _bw-serve-stop "${server}" "${log}"
  trap - INT TERM HUP
  unset _bw_interrupted
}
