#!/usr/bin/env python3
"""Measure Koderkatins' steady-state CPU with `top`.

Usage: python3 tools/bench.py [label] [--warm 45] [--samples 6] [key=value ...]
key=value pairs are written to the app's defaults before launch (ints, floats, true/false).
Example: python3 tools/bench.py still motion=0
"""
import subprocess
import sys
import time
from pathlib import Path

DOMAIN = "io.github.koderkatins"
APP = Path.home() / "Applications/Koderkatins.app"


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()


def write_default(key, value):
    if value in ("true", "false"):
        t = "-bool"
    elif value.lstrip("-").isdigit():
        t = "-int"
    else:
        t = "-float"
    subprocess.run(["defaults", "write", DOMAIN, key, t, value])


def main():
    args = sys.argv[1:]
    label = args.pop(0) if args and "=" not in args[0] and not args[0].startswith("--") else "run"
    warm, samples = 45, 6
    while args and args[0].startswith("--"):
        flag, val = args.pop(0), args.pop(0)
        warm = int(val) if flag == "--warm" else warm
        samples = int(val) if flag == "--samples" else samples
    for kv in args:
        k, v = kv.split("=", 1)
        write_default(k, v)
    subprocess.run(["pkill", "-x", "Koderkatins"])
    time.sleep(1)
    subprocess.run(["open", str(APP)])
    time.sleep(warm)
    pid = sh("pgrep -x Koderkatins")
    out = sh(f"top -l {samples + 1} -s 5 -pid {pid} -stats pid,cpu,idlew,mem")
    rows = [l.split() for l in out.splitlines() if l.strip().startswith(pid)][1:]
    cpu = [float(r[1]) for r in rows]
    print(f"{label:40s} avg CPU {sum(cpu) / len(cpu):5.2f}%  samples {cpu}  mem {rows[-1][3]}")


if __name__ == "__main__":
    main()
