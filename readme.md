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
| `bitwarden.zsh` | `bw-unlock`, `bw-lock`, `bw-get`, `bw-field`, `bw-sync`, `bw-serve`. `bw-serve` listens on port 8087 (override with `BW_SERVE_PORT`), refuses to start if the port is taken (needs `curl`), and locks the vault when it exits or is stopped with Ctrl-C (not on SIGTERM or a closed terminal). Works in zsh and bash. |
| `resize_jpg_fhd.sh` | Run inside a folder: writes a 2000px-wide copy of every jpg/jpeg/png beneath it into `./resized/`, leaving the originals alone. Needs ImageMagick (`magick`, or a real `convert`). |

## Tests

Each script has a test in `tests/` that runs against stubs or throwaway data, never your real vault, repos or photos. Run them under each shell:

    for t in tests/*_test.sh; do bash "$t" && zsh "$t"; done

`resize_test.sh` skips itself, saying so, when ImageMagick is absent.

Verified on macOS only. On Windows, run `for t in tests/*_test.sh; do bash "$t"; done` in Git Bash. Then try `bw-serve`, stop it with Ctrl-C, and confirm `bw status` reports `locked`.
