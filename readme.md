scripts
---

Shell helpers I use for development, on macOS and Windows (Git Bash).

## Setup

Source `setup.sh` from your `~/.zshrc` or `~/.bashrc`; it loads every file below from its own location, whatever the working directory:

    source ~/scripts/setup.sh

Running it instead of sourcing it defines everything in a subshell that exits at once.

## What's inside

| File | Gives you |
|---|---|
| `.adb_alias` | `adb_home`, `adb_back`, `adb_view <url>`, `adb_search <words>` and other Android shortcuts. Needs `adb` on `PATH`. |
| `.fvm_alias` | `fclean`, `fget`, `fanalyze`, `ftest`, `fdbuild`, `fdwatch`, `fi18n` for Flutter through `fvm`. |
| `.git_alias` | `gitl` (graph log), `gits` (status), `gitf` (fetch and prune, then delete local branches merged into `main`, `master`, `develop` or `demo`; never those four or the checked-out branch). |
| `bitwarden.zsh` | `bw-unlock`, `bw-lock`, `bw-get`, `bw-field`, `bw-sync`, `bw-serve`. `bw-serve` unlocks the vault and runs `bw serve` in the background on port 8087 (override with `BW_SERVE_PORT`; it refuses to start if the port is taken, which needs `curl`), then waits for a key: `s` syncs now (via `bw sync`, not the server's REST API), `q` or Ctrl-C quits and locks the vault. It also syncs by itself every 600 seconds (override with `BW_SYNC_INTERVAL`, 1 to 9999999). SIGTERM and a closed terminal also stop the server and lock. The server's output goes to `${TMPDIR:-/tmp}/bw-serve-<port>.log`. Needs zsh, or bash 4+ for piped input (macOS's own bash 3.2 works on a terminal only). |
| `resize_jpg_fhd.sh` | Run inside a folder: writes a copy of every jpg/jpeg/png beneath it into `./resized/`, shrunk to 2000px wide (narrower images are copied as they are), leaving the originals alone. Needs ImageMagick (`magick`, or a real `convert`). |

## Tests

Each script has a test in `tests/` that runs against stubs or throwaway data, never your real vault, repos or photos. Run them under each shell:

    for t in tests/*_test.sh; do bash "$t" && zsh "$t"; done

`resize_test.sh` skips itself, saying so, when ImageMagick is absent; `bitwarden_tty_test.sh` does the same without python3 or a Unix pty. That one drives `bw-serve` on a real pseudo-terminal, because piped keys cannot show how a terminal behaves.

Verified on macOS only. On Windows, run `for t in tests/*_test.sh; do bash "$t"; done` in Git Bash. Then try `bw-serve`: press `s` and look for a `synced at` line, fetch a secret through `secret.sh` while it runs, press `q`, and confirm `bw status` reports `locked`. The terminal test skips there, so press the keys yourself. On macOS, `bw-serve` has also been tried by hand against a real vault, with no problems reported; that check is not part of the automated tests.
