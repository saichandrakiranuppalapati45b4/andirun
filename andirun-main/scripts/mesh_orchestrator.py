#!/usr/bin/env python3
"""mesh_orchestrator.py - Multi-Device Mesh Orchestrator for AndiRun.

Distributes LLM layers and long-context Attention across 2+ Android phones simultaneously
connected to a Windows PC host via high-speed USB-C.
"""

from __future__ import annotations

import argparse
import os
import socket
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

SPTL_MAGIC = 0x4C545053  # "SPTL"
PATN_MAGIC = 0x4E544150  # "PATN"
BASE_TAIL_PORT = 8080
BASE_ATTN_PORT = 50062


def log(msg: str) -> None:
    print(f"[\033[36mAndiRun Mesh\033[0m] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[\033[33mWARN\033[0m] {msg}", flush=True)


def error(msg: str) -> None:
    print(f"[\033[31mERROR\033[0m] {msg}", file=sys.stderr, flush=True)


def get_adb_binary() -> str:
    if os.name == "nt":
        local_adb_win = Path(__file__).resolve().parent.parent.parent / "platform-tools" / "adb.exe"
        if local_adb_win.exists():
            return str(local_adb_win)
        return "adb.exe"
    local_adb_posix = Path(__file__).resolve().parent.parent.parent / "platform-tools" / "adb"
    if local_adb_posix.exists():
        return str(local_adb_posix)
    return "adb"


@dataclass
class AndroidNode:
    serial: str
    model: str
    ram_mb: int
    tail_port: int
    attn_port: int
    layer_start: int = 0
    layer_end: int = 0


def discover_android_nodes() -> list[AndroidNode]:
    adb = get_adb_binary()
    try:
        out = subprocess.check_output([adb, "devices"], text=True)
    except Exception as e:
        error(f"Failed to run adb devices: {e}")
        return []

    nodes: list[AndroidNode] = []
    lines = [line.strip() for line in out.strip().splitlines()[1:] if line.strip()]

    idx = 0
    for line in lines:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            serial = parts[0]
            # Probe model name
            try:
                model = subprocess.check_output(
                    [adb, "-s", serial, "shell", "getprop", "ro.product.model"],
                    text=True,
                    timeout=2
                ).strip()
            except Exception:
                model = "Android Device"

            # Probe RAM
            try:
                mem_out = subprocess.check_output(
                    [adb, "-s", serial, "shell", "cat", "/proc/meminfo"],
                    text=True,
                    timeout=2
                )
                total_kb = 0
                for mline in mem_out.splitlines():
                    if mline.startswith("MemTotal:"):
                        total_kb = int(mline.split()[1])
                        break
                ram_mb = total_kb // 1024
            except Exception:
                ram_mb = 8192

            node = AndroidNode(
                serial=serial,
                model=model,
                ram_mb=ram_mb,
                tail_port=BASE_TAIL_PORT + idx,
                attn_port=BASE_ATTN_PORT + idx
            )
            nodes.append(node)
            idx += 1

    return nodes


def setup_node_forwarding(node: AndroidNode) -> bool:
    adb = get_adb_binary()
    try:
        subprocess.check_call([adb, "-s", node.serial, "forward", f"tcp:{node.tail_port}", f"tcp:{node.tail_port}"])
        subprocess.check_call([adb, "-s", node.serial, "forward", f"tcp:{node.attn_port}", f"tcp:{node.attn_port}"])
        log(f"[{node.serial} - {node.model}] Ports forwarded: 127.0.0.1:{node.tail_port} (SPTL) & :{node.attn_port} (PATN)")
        return True
    except subprocess.CalledProcessError as e:
        error(f"Failed to forward ports for {node.serial}: {e}")
        return False


def probe_sptl(port: int, timeout: float = 2.0) -> bool:
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


def probe_patn(port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout) as s:
            hdr = struct.pack("<IIQ", PATN_MAGIC, 1, 0)  # HELLO
            s.sendall(hdr)
            rep_hdr = s.recv(16)
            if len(rep_hdr) < 16:
                return False
            magic, mtype, _ = struct.unpack("<IIQ", rep_hdr)
            return magic == PATN_MAGIC and mtype == 2  # HELLO_OK
    except Exception:
        return False


def calculate_layer_distribution(total_layers: int, host_share: float, nodes: list[AndroidNode]) -> None:
    """Distributes remaining layers evenly across all connected Android nodes."""
    host_layers = max(1, int(total_layers * host_share))
    remaining = total_layers - host_layers
    layers_per_node = max(1, remaining // len(nodes))

    curr = host_layers
    for i, node in enumerate(nodes):
        node.layer_start = curr
        if i == len(nodes) - 1:
            node.layer_end = total_layers  # Last node gets remaining
        else:
            node.layer_end = curr + layers_per_node
        curr = node.layer_end


def main() -> None:
    parser = argparse.ArgumentParser(description="AndiRun Multi-Device Mesh Orchestrator")
    parser.add_argument("-m", "--model", required=True, help="Full model GGUF path on host")
    parser.add_argument("--total-layers", type=int, default=28, help="Total transformer layers in the model (e.g. 28 for Qwen2.5-7B)")
    parser.add_argument("--host-share", type=float, default=0.5, help="Fraction of layers retained on host PC (default: 0.5)")
    parser.add_argument("--port", type=int, default=8000, help="Local host server port (default: 8000)")
    parser.add_argument("--server-bin", default="build-win\\bin\\llama-server.exe", help="Host server executable")
    parser.add_argument("--dry-run", action="store_true", help="Print mesh topology without launching")

    args = parser.parse_args()

    log("Scanning for Android devices across USB-C mesh...")
    nodes = discover_android_nodes()

    if not nodes:
        error("No Android devices detected via ADB. Connect phones with USB debugging enabled.")
        sys.exit(1)

    log(f"Discovered {len(nodes)} Android Mesh Node(s):")
    for i, n in enumerate(nodes, 1):
        log(f"  {i}. [{n.serial}] {n.model} | {n.ram_mb} MB RAM | Ports: {n.tail_port}/{n.attn_port}")

    if len(nodes) < 2:
        warn("Only 1 Android phone detected. Multi-Device Mesh will run in single-accelerator mode.")
    else:
        log(f"\033[32m[✓] Multi-Device Mesh topology ACTIVE with {len(nodes)} Android co-processors!\033[0m")

    calculate_layer_distribution(args.total_layers, args.host_share, nodes)

    host_end = nodes[0].layer_start
    log("=" * 60)
    log("MESH WORKLOAD DISTRIBUTION:")
    log(f"  💻 Windows Host PC   : Layers 0 .. {host_end - 1}")
    for i, n in enumerate(nodes, 1):
        log(f"  📱 Phone {i} ({n.model}) : Layers {n.layer_start} .. {n.layer_end - 1} " +
            (" (+ Output Head)" if n.layer_end == args.total_layers else " (Intermediate Stage)"))
    log("=" * 60)

    log("Configuring ADB Port Forwarding tunnels for all nodes...")
    for n in nodes:
        if not setup_node_forwarding(n):
            error(f"Aborting due to ADB forwarding failure on {n.serial}")
            sys.exit(1)

    log("Verifying node health over USB...")
    for i, n in enumerate(nodes, 1):
        sptl_ok = probe_sptl(n.tail_port)
        patn_ok = probe_patn(n.attn_port)
        sptl_str = "\033[32mREADY\033[0m" if sptl_ok else "\033[33mOFFLINE (Needs start)\033[0m"
        patn_str = "\033[32mREADY (Vulkan)\033[0m" if patn_ok else "\033[90mINACTIVE\033[0m"
        log(f"  Node {i} ({n.serial}): Split-Prefill: {sptl_str} | Attn-Offload: {patn_str}")

    if args.dry_run:
        log("Dry run complete. Exiting without launching host server.")
        return

    # Build environment for multi-device mesh
    env = os.environ.copy()
    tail_endpoints = ",".join(f"127.0.0.1:{n.tail_port}" for n in nodes)
    attn_endpoints = ",".join(f"127.0.0.1:{n.attn_port}" for n in nodes)

    env["LLAMA_SPLIT_TAIL"] = f"127.0.0.1:{nodes[0].tail_port}"
    env["LLAMA_SPLIT_TAIL_MESH"] = tail_endpoints
    env["LLAMA_KV_REMOTE"] = attn_endpoints
    env["LLAMA_SPLIT_L"] = str(host_end)
    env["LLAMA_SPLIT_VERBOSE"] = "1"

    cmd = [
        args.server_bin,
        "-m", os.path.abspath(args.model),
        "-c", "65536",
        "-ngl", "999",
        "--port", str(args.port),
        "--host", "127.0.0.1"
    ]

    log(f"Launching Windows Host Server across {len(nodes)}-node Android mesh...")
    log(f"Command: {' '.join(cmd)}")
    log(f"API Endpoint: http://127.0.0.1:{args.port}/v1")

    try:
        subprocess.run(cmd, env=env)
    except KeyboardInterrupt:
        log("Mesh shutting down cleanly.")


if __name__ == "__main__":
    main()
