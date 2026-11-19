"""Runs `source <subject>; bw-serve` in <shell> on a real pseudo-terminal and types keys.

usage: pty_drive.py <shell> <subject> <keys>

<keys> is one character per keystroke, with escapes (\\x03 is Ctrl-C); each is sent
0.6s after the last, once the shell has had 1.5s to start. Prints `exited` if the
shell ends within 4s of the last key, else `serving` (and kills it). Standard
library only; Unix ptys only.
"""
import os
import pty
import select
import shlex
import signal
import sys
import time

START_SECONDS = 1.5
KEY_GAP_SECONDS = 0.6
WAIT_SECONDS = 4


def drain(fd):
    """Reads and discards terminal output, so the child never blocks on a full pty."""
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try:
            os.read(fd, 4096)
        except OSError:
            pass


def main():
    shell, subject, keys = sys.argv[1:4]
    keys = keys.encode().decode("unicode_escape")
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(shell, [shell, "-c", f"source {shlex.quote(subject)}; bw-serve"])
    time.sleep(START_SECONDS)
    for key in keys:
        os.write(fd, key.encode())
        time.sleep(KEY_GAP_SECONDS)
    outcome = "serving"
    deadline = time.time() + WAIT_SECONDS
    while time.time() < deadline:
        drain(fd)
        finished, _ = os.waitpid(pid, os.WNOHANG)
        if finished:
            outcome = "exited"
            break
    if outcome == "serving":
        os.kill(pid, signal.SIGKILL)
    print(outcome)


main()
