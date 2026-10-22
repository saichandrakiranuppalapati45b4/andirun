#!/usr/bin/env python3
"""serve_win_android.py - Orchestrator for Backburner on Windows PC + Android Phones.

Connects Windows host (llama-server / llama-split) to an Android phone running
Backburner's tail worker (Vulkan/OpenCL) via high-speed USB-C (ADB or USB tethering).
"""

import argparse
import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

SPTL_MAGIC = 0x4C545053  # "SPTL"
PATN_MAGIC = 0x4E544150  # "PATN"
DEFAULT_TAIL_PORT = 50060
DEFAULT_ATTN_PORT = 50062

def log(msg: str):
    print(f"[\033[36mAndiRun\033[0m] {msg}", flush=True)

def error(msg: str):
    print(f"[\033[31mERROR\033[0m] {msg}", file=sys.stderr, flush=True)

def get_adb_binary() -> str:
    """Finds adb binary in PATH or local platform-tools directory."""
    local_adb_win = Path(__file__).resolve().parent.parent.parent / "platform-tools" / "adb.exe"
    local_adb_posix = Path(__file__).resolve().parent.parent.parent / "platform-tools" / "adb"
    if local_adb_win.exists():
        return str(local_adb_win)
    if local_adb_posix.exists():
        return str(local_adb_posix)
    return "adb"

def check_adb_devices() -> list[str]:
    """Finds all connected Android devices via ADB."""
    adb_bin = get_adb_binary()
    try:
        out = subprocess.check_output([adb_bin, "devices"], text=True)
    except FileNotFoundError:
        error(f"`{adb_bin}` not found. Ensure Android platform-tools is installed.")
        return []
    except subprocess.CalledProcessError as e:
        error(f"adb devices failed: {e}")
        return []

    devices = []
    for line in out.strip().splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    return devices

def setup_adb_forwarding(serial: str | None = None, tail_port: int = DEFAULT_TAIL_PORT, attn_port: int = DEFAULT_ATTN_PORT) -> bool:
    """Configures local TCP forward tunnels through ADB to the phone's loopback listeners."""
    cmd_base = [get_adb_binary()]
    if serial:
        cmd_base += ["-s", serial]

    try:
        subprocess.check_call(cmd_base + ["forward", f"tcp:{tail_port}", f"tcp:{tail_port}"])
        subprocess.check_call(cmd_base + ["forward", f"tcp:{attn_port}", f"tcp:{attn_port}"])
        log(f"ADB port forwarding established: 127.0.0.1:{tail_port} and :{attn_port} -> Android")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to forward ports via ADB: {e}")
        return False

def probe_sptl_worker(host: str = "127.0.0.1", port: int = DEFAULT_TAIL_PORT, timeout: float = 3.0) -> dict | None:
    """Probes the tail worker using the SPTL protocol PING (type 11)."""
    try:
        t0 = time.perf_counter()
        with socket.create_connection((host, port), timeout=timeout) as s:
            # MSG_PING = 11: payload: u32 reply_len (e.g. 4 bytes)
            payload = struct.pack("<I", 4)
            hdr = struct.pack("<IIQ", SPTL_MAGIC, 11, len(payload))
            s.sendall(hdr + payload)
            
            # Read header
            rep_hdr = s.recv(16)
            if len(rep_hdr) < 16:
                return None
            magic, mtype, plen = struct.unpack("<IIQ", rep_hdr)
            if magic != SPTL_MAGIC or mtype != 12:  # MSG_PONG = 12
                return None
            
            body = s.recv(plen) if plen else b""
            rtt_ms = (time.perf_counter() - t0) * 1000.0
            return {"magic": magic, "type": mtype, "len": plen, "rtt_ms": rtt_ms}
    except (socket.timeout, ConnectionRefusedError, OSError):
        return None

def probe_patn_worker(host: str = "127.0.0.1", port: int = DEFAULT_ATTN_PORT, timeout: float = 2.0) -> int | None:
    """Probes the phone-attention worker using the PATN protocol HELLO."""
    try:
        with socket.create_connection((host, port), timeout=timeout) as s:
            # HELLO (1), len 0
            hdr = struct.pack("<IIQ", PATN_MAGIC, 1, 0)
            s.sendall(hdr)
            rep_hdr = s.recv(16)
            if len(rep_hdr) < 16:
                return None
            magic, mtype, plen = struct.unpack("<IIQ", rep_hdr)
            if magic != PATN_MAGIC or mtype != 2:  # HELLO_OK = 2
                return None
            rep_body = s.recv(plen)
            if len(rep_body) >= 4:
                version = struct.unpack("<I", rep_body[:4])[0]
                return version
            return 1
    except (socket.timeout, ConnectionRefusedError, OSError):
        return None

def start_worker_on_phone(serial: str | None, tail_model_remote: str, port: int = DEFAULT_TAIL_PORT) -> bool:
    """Attempts to launch the worker on the Android phone via app service or adb daemon."""
    cmd_base = [get_adb_binary()]
    if serial:
        cmd_base += ["-s", serial]

    # Strategy 1: Launch via installed AndiRun Android App Foreground Service
    try:
        app_check = subprocess.check_output(cmd_base + ["shell", "pm path com.andirun.worker"], text=True).strip()
        if "package:" in app_check:
            log("Detected AndiRun Android App (com.andirun.worker)! Starting Foreground WorkerService...")
            start_cmd = cmd_base + [
                "shell", "am", "start-foreground-service",
                "-n", "com.andirun.worker/.WorkerService",
                "--ei", "PORT", str(port),
                "--es", "MODEL_PATH", tail_model_remote
            ]
            subprocess.call(start_cmd)
            time.sleep(2)
            return True
    except Exception:
        pass

    # Strategy 2: Check for executable in /data/local/tmp/
    remote_bin = "/data/local/tmp/llama-split-prefill"
    try:
        res = subprocess.check_output(cmd_base + ["shell", f"test -s {remote_bin} && echo OK"], text=True).strip()
        if "OK" in res:
            log(f"Launching Android daemon: {remote_bin} --serve-tail {port} --tail-model {tail_model_remote}")
            launch_cmd = cmd_base + [
                "shell",
                f"export LD_LIBRARY_PATH=/data/local/tmp:$LD_LIBRARY_PATH; "
                f"nohup {remote_bin} --serve-tail {port} --tail-model {tail_model_remote} > /data/local/tmp/worker.log 2>&1 &"
            ]
            subprocess.call(launch_cmd)
            time.sleep(2)
            return True
    except subprocess.CalledProcessError:
        pass

    # Strategy 3: Check staged binary in /sdcard/Download/
    try:
        sd_check = subprocess.check_output(cmd_base + ["shell", "test -s /sdcard/Download/llama-split-prefill && echo OK"], text=True).strip()
        if "OK" in sd_check:
            log("Staging worker binary and libraries from /sdcard/Download/ to /data/local/tmp/...")
            subprocess.call(cmd_base + ["shell", "cp /sdcard/Download/llama-split-prefill /data/local/tmp/ 2>/dev/null"])
            subprocess.call(cmd_base + ["shell", "cp /sdcard/Download/*.so* /data/local/tmp/ 2>/dev/null"])
            subprocess.call(cmd_base + ["shell", "chmod 755 /data/local/tmp/llama-split-prefill /data/local/tmp/*.so* 2>/dev/null"])
            log(f"Launching Android daemon: {remote_bin} --serve-tail {port} --tail-model {tail_model_remote}")
            launch_cmd = cmd_base + [
                "shell",
                f"export LD_LIBRARY_PATH=/data/local/tmp:$LD_LIBRARY_PATH; "
                f"nohup {remote_bin} --serve-tail {port} --tail-model {tail_model_remote} > /data/local/tmp/worker.log 2>&1 &"
            ]
            subprocess.call(launch_cmd)
            time.sleep(2)
            return True
    except Exception:
        pass

    error(f"Neither AndiRun App nor {remote_bin} is active or installed.")
    log("Option A (Zero-Termux Daemon): Run .\\setup-daemon-worker.ps1 to install background worker.")
    log("Option B (Termux manual): Run inside Termux:")
    log("   cd ~/andirun/andirun-main/llama.cpp")
    log(f"   ./build/bin/llama-split-prefill --serve-tail {port} --tail-model {tail_model_remote}")
    return False

def main():
    parser = argparse.ArgumentParser(description="Backburner Host Orchestrator for Windows PC + Android Phones")
    parser.add_argument("-m", "--model", required=True, help="Path to the full GGUF model on the host PC")
    parser.add_argument("-L", "--split-layer", type=int, default=40, help="First layer offloaded to the Android worker (default: 40)")
    parser.add_argument("--tail-model", help="Path to the tail GGUF model on host or phone")
    parser.add_argument("--device", help="Specific Android device serial (from adb devices)")
    parser.add_argument("--min-tokens", type=int, default=512, help="Minimum prompt tokens before splitting (default: 512)")
    parser.add_argument("--port", type=int, default=8080, help="Local host API port (default: 8080)")
    parser.add_argument("--tail-port", type=int, default=DEFAULT_TAIL_PORT, help=f"Tail worker port (default: {DEFAULT_TAIL_PORT})")
    parser.add_argument("--server-bin", default="llama-server", help="Path or name of host llama-server executable")
    parser.add_argument("--extra-args", default="", help="Additional arguments forwarded to llama-server")

    args = parser.parse_args()

    log("Scanning for Android phones via ADB...")
    devices = check_adb_devices()
    if not devices:
        error("No Android phone detected. Please connect phone via USB-C and enable USB Debugging.")
        sys.exit(1)

    target_device = args.device or devices[0]
    log(f"Selected Android Phone: {target_device} (total connected: {len(devices)})")

    log("Configuring USB port forwarding...")
    if not setup_adb_forwarding(target_device, tail_port=args.tail_port):
        sys.exit(1)

    # Check if worker is answering
    log(f"Probing Android Split-Prefill Worker (SPTL :{args.tail_port})...")
    sptl_status = probe_sptl_worker("127.0.0.1", args.tail_port)
    if not sptl_status:
        log("Tail worker not currently answering on Android.")
        adb_bin = get_adb_binary()
        tail_candidates = [
            f"/sdcard/Download/tail-L{args.split_layer}.gguf",
            f"/data/local/tmp/tail-L{args.split_layer}.gguf",
            "/sdcard/Download/tail.gguf",
            "/data/local/tmp/tail.gguf",
        ]
        remote_tail_path = None
        for cand in tail_candidates:
            if subprocess.call([adb_bin, "-s", target_device, "shell", f"test -f {cand}"]) == 0:
                remote_tail_path = cand
                break
        if not remote_tail_path:
            remote_tail_path = f"/sdcard/Download/tail-L{args.split_layer}.gguf"

        log(f"Attempting to launch worker daemon on phone with {remote_tail_path}...")
        start_worker_on_phone(target_device, remote_tail_path, args.tail_port)
        
        # Retry probe
        for _ in range(10):
            time.sleep(1)
            sptl_status = probe_sptl_worker("127.0.0.1", args.tail_port)
            if sptl_status:
                break

    if sptl_status:
        log("\033[32m[✓] Android Split-Prefill Worker is READY!\033[0m")
    else:
        error("Could not establish connection with Android worker. Please ensure `llama-split-prefill` or the Android app is running.")
        try:
            log_content = subprocess.check_output([get_adb_binary(), "-s", target_device, "shell", "cat /data/local/tmp/worker.log"], text=True)
            if log_content.strip():
                log("--- Phone worker.log output ---")
                print(log_content.strip())
                log("-------------------------------")
        except Exception:
            pass
        sys.exit(1)

    # Check Phone Attn worker (:50062)
    patn_ver = probe_patn_worker("127.0.0.1", DEFAULT_ATTN_PORT)
    if patn_ver:
        log(f"\033[32m[✓] Phone Attention Worker is READY (protocol v{patn_ver})\033[0m")
    else:
        log("Phone Attention (:50062) inactive (Remote KV off; standard split prefill active).")

    # Check if host port is already bound, fallback if occupied
    host_port = args.port
    for offset in range(10):
        test_port = args.port + offset
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            if s.connect_ex(("127.0.0.1", test_port)) != 0:
                host_port = test_port
                break
    if host_port != args.port:
        log(f"\033[33m[!] Port {args.port} is already in use by another app. Automatically switching to port {host_port}.\033[0m")

    # Set Environment Variables for host llama.cpp
    env = os.environ.copy()
    env["LLAMA_SPLIT_TAIL"] = f"127.0.0.1:{args.tail_port}"
    env["LLAMA_SPLIT_L"] = str(args.split_layer)
    env["LLAMA_SPLIT_MIN"] = str(args.min_tokens)
    env["LLAMA_SPLIT_VERBOSE"] = "1"

    server_exe = os.path.abspath(args.server_bin)
    cmd = [
        server_exe,
        "-m", os.path.abspath(args.model),
        "-c", "32768",
        "-ngl", "999",
        "--port", str(host_port),
        "--host", "127.0.0.1"
    ]
    if args.extra_args:
        cmd.extend(args.extra_args.split())

    log(f"Launching Host Server with Android Co-Processor (Split L={args.split_layer})...")
    log(f"Command: {' '.join(cmd)}")
    log(f"API will be available at: http://127.0.0.1:{host_port}/v1")

    try:
        subprocess.run(cmd, env=env)
    except KeyboardInterrupt:
        log("Shutting down Backburner host.")

if __name__ == "__main__":
    main()
