#!/usr/bin/env python3
"""setup_daemon_worker.py - Zero-Touch Background Worker Setup for Android.

Transfers the compiled llama-split-prefill binary to /data/local/tmp/ and launches it
as a persistent background daemon on port 8080 over USB.
"""

from __future__ import annotations

import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

SPTL_MAGIC = 0x4C545053  # "SPTL"


def log(msg: str) -> None:
    print(f"[\033[36mAndiRun\033[0m] {msg}", flush=True)


def error(msg: str) -> None:
    print(f"[\033[31mERROR\033[0m] {msg}", file=sys.stderr, flush=True)


def get_adb_binary() -> str:
    local_adb_win = Path(__file__).resolve().parent.parent.parent / "platform-tools" / "adb.exe"
    local_adb_posix = Path(__file__).resolve().parent.parent.parent / "platform-tools" / "adb"
    if local_adb_win.exists():
        return str(local_adb_win)
    if local_adb_posix.exists():
        return str(local_adb_posix)
    return "adb"


def get_connected_device() -> str | None:
    adb = get_adb_binary()
    try:
        out = subprocess.check_output([adb, "devices"], text=True)
    except Exception as e:
        error(f"Failed to run adb devices: {e}")
        return None

    for line in out.strip().splitlines()[1:]:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1] == "device":
            return parts[0]
    return None


def probe_worker(port: int = 8080, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout) as s:
            payload = struct.pack("<I", 4)
            hdr = struct.pack("<IIQ", SPTL_MAGIC, 11, len(payload))  # MSG_PING
            s.sendall(hdr + payload)
            rep_hdr = s.recv(16)
            if len(rep_hdr) < 16:
                return False
            magic, mtype, plen = struct.unpack("<IIQ", rep_hdr)
            return magic == SPTL_MAGIC and mtype == 12  # MSG_PONG
    except Exception:
        return False


def main() -> None:
    log("=" * 60)
    log("AndiRun Background Worker Setup (No Termux Needed)")
    log("=" * 60)

    adb = get_adb_binary()
    device = get_connected_device()

    if not device:
        error("No Android phone detected via USB debugging.")
        log("Please connect phone via USB-C and enable USB Debugging.")
        sys.exit(1)

    log(f"Connected Phone: \033[32m{device}\033[0m")

    # Step 1: Check if /data/local/tmp/llama-split-prefill is already installed and non-empty
    log("Checking /data/local/tmp/llama-split-prefill...")
    res = subprocess.call([adb, "-s", device, "shell", "test -s /data/local/tmp/llama-split-prefill"])
    installed = (res == 0)

    if not installed:
        # Step 2: Try copying from /sdcard/Download/
        log("Checking for staged binary in /sdcard/Download/...")
        sd_res = subprocess.call([adb, "-s", device, "shell", "test -s /sdcard/Download/llama-split-prefill"])
        
        if sd_res != 0:
            print("\n" + "=" * 60)
            print("\033[33m[ACTION NEEDED IN TERMUX]\033[0m")
            print("Please run this command in Termux ONCE to stage the binary and libraries:")
            print("\n    \033[1mcd ~/andirun/andirun-main/llama.cpp && cp build/bin/llama-split-prefill build/bin/*.so $PREFIX/lib/libc++_shared.so ~/storage/downloads/ 2>/dev/null\033[0m\n")
            print("=" * 60)
            input("Press Enter after running the command in Termux...")

        log("Installing to /data/local/tmp/llama-split-prefill via ADB...")
        subprocess.call([adb, "-s", device, "shell", "cp /sdcard/Download/llama-split-prefill /data/local/tmp/llama-split-prefill 2>/dev/null"])
        subprocess.call([adb, "-s", device, "shell", "cp /sdcard/Download/*.so /data/local/tmp/ 2>/dev/null"])
        subprocess.call([adb, "-s", device, "shell", "chmod 755 /data/local/tmp/llama-split-prefill /data/local/tmp/*.so 2>/dev/null"])

    # Verify installation
    check = subprocess.call([adb, "-s", device, "shell", "test -s /data/local/tmp/llama-split-prefill"])
    if check != 0:
        error("Worker binary in /data/local/tmp/ is missing or empty. Please run the staging command in Termux.")
        sys.exit(1)

    log("\033[32m[✓] Worker binary is installed and executable at /data/local/tmp/llama-split-prefill!\033[0m")

    # Step 3: Find tail model
    tail_candidates = [
        "/data/local/tmp/tail-L20.gguf",
        "/sdcard/Download/tail-L20.gguf",
        "/data/local/tmp/tail.gguf",
        "/sdcard/Download/tail.gguf",
    ]
    tail_model = None
    for cand in tail_candidates:
        if subprocess.call([adb, "-s", device, "shell", f"test -f {cand}"]) == 0:
            tail_model = cand
            break

    if not tail_model:
        error("Could not find tail model on phone (/sdcard/Download/tail-L20.gguf or /data/local/tmp/tail-L20.gguf).")
        log("Please ensure `split-gguf.py` was used to push `tail-L20.gguf` to phone via ADB.")
        sys.exit(1)

    log(f"Using tail model: \033[32m{tail_model}\033[0m")

    # Step 4: Stop previous instances and launch daemon
    log("Stopping any previous worker instances...")
    subprocess.call([adb, "-s", device, "shell", "pkill -f llama-split-prefill 2>/dev/null"])
    time.sleep(1)

    log(f"Launching background daemon on phone (:8080) with {tail_model}...")
    launch_cmd = [
        adb, "-s", device, "shell",
        f"export LD_LIBRARY_PATH=/data/local/tmp:$LD_LIBRARY_PATH; "
        f"nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model {tail_model} > /data/local/tmp/worker.log 2>&1 &"
    ]
    subprocess.call(launch_cmd)
    time.sleep(2)

    # Step 5: Set up port forwarding
    log("Configuring USB port forwarding (127.0.0.1:8080 -> Phone)...")
    subprocess.call([adb, "-s", device, "forward", "tcp:8080", "tcp:8080"])
    subprocess.call([adb, "-s", device, "forward", "tcp:50062", "tcp:50062"])

    # Step 6: Probe worker
    sptl_ok = False
    for attempt in range(5):
        if probe_worker(8080):
            sptl_ok = True
            break
        time.sleep(1)

    if sptl_ok:
        log("\033[32m[✓] SUCCESS: Android worker daemon is active and responding on port 8080!\033[0m")
        log("\033[32m[✓] You can now close Termux completely. The worker will run automatically.\033[0m")
    else:
        log("\033[33m[!] Warning: Worker daemon was launched, but did not respond on port 8080.\033[0m")
        try:
            log_content = subprocess.check_output([adb, "-s", device, "shell", "cat /data/local/tmp/worker.log"], text=True)
            if log_content.strip():
                log("--- Phone worker.log output ---")
                print(log_content.strip())
                log("-------------------------------")
        except Exception:
            pass

    log("=" * 60)
    log("Ready! Now run:")
    log("  python andirun-main\\scripts\\serve_win_android.py -m qwen-7b.gguf -L 20 --tail-port 8080 --port 8000 --server-bin build-win\\bin\\llama-server.exe --extra-args \"--lora andirun-lora.gguf\"")
    log("=" * 60)


if __name__ == "__main__":
    main()
