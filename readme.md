scripts
---

Some of scripts I'm using for development.

## bitwarden.zsh

Bitwarden CLI helpers (`bw-unlock`, `bw-lock`, `bw-get`, `bw-field`, `bw-sync`, `bw-serve`). Source it (`source bitwarden.zsh`) from zsh or bash, including Git Bash on Windows; `curl` is required for the port check. `bw-serve` listens on port 8087 (override with `BW_SERVE_PORT`) and locks the vault when it exits or is stopped with Ctrl-C (not on SIGTERM or a closed terminal).

Tests run against a stubbed `bw`; run them under each shell:

    bash tests/bitwarden_test.sh && zsh tests/bitwarden_test.sh

Verified on macOS only. On Windows, run the bash line above in Git Bash, then try `bw-serve` and stop it with Ctrl-C, then confirm `bw status` reports `locked`.
