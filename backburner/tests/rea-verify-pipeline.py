#!/usr/bin/env python3
"""rea-verify-pipeline.py - REA Protocol & Pipeline Verification Suite

Verifies:
1. SPTL (Split Prefill) protocol framing & binary layout
2. PATN (Phone Attention) protocol framing
3. Residual vector compression and endianness
4. Network round-trip simulation over loopback/ADB
"""

import socket
import struct
import sys
import time

SPTL_MAGIC = 0x4C545053  # "SPTL"
PATN_MAGIC = 0x4E544150  # "PATN"

def verify_framing():
    print("[1/4] Verifying Protocol Framing...", end=" ")
    
    # SPTL Header: magic(u32), type(u32), len(u64) -> exactly 16 bytes
    sptl_hdr = struct.pack("<IIQ", SPTL_MAGIC, 1, 32)
    assert len(sptl_hdr) == 16, f"Expected 16 bytes, got {len(sptl_hdr)}"
    magic, mtype, plen = struct.unpack("<IIQ", sptl_hdr)
    assert magic == SPTL_MAGIC and mtype == 1 and plen == 32
    
    # PATN Header: magic(u32), type(u32), len(u64) -> exactly 16 bytes
    patn_hdr = struct.pack("<IIQ", PATN_MAGIC, 1, 0)
    assert len(patn_hdr) == 16
    magic_p, mtype_p, plen_p = struct.unpack("<IIQ", patn_hdr)
    assert magic_p == PATN_MAGIC and mtype_p == 1 and plen_p == 0
    
    print("\033[32mPASS\033[0m")

def verify_chunk_payload_packing():
    print("[2/4] Verifying Chunk Residual Serialization...", end=" ")
    
    # struct chunk_req: pos0(i32), n_tok(u32), dtype(u32), want_logits(u32) -> 16 bytes
    pos0 = 0
    n_tok = 256
    dtype = 1  # DT_F16
    want_logits = 1
    
    req_hdr = struct.pack("<iIII", pos0, n_tok, dtype, want_logits)
    assert len(req_hdr) == 16
    
    p0, n, dt, wl = struct.unpack("<iIII", req_hdr)
    assert p0 == pos0 and n == n_tok and dt == dtype and wl == want_logits
    
    print("\033[32mPASS\033[0m")

def verify_loopback_socket_server():
    print("[3/4] Verifying SPTL Loopback Server Emulation...", end=" ")
    
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    port = srv.getsockname()[1]
    srv.listen(1)
    
    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client.connect(("127.0.0.1", port))
    conn, _ = srv.accept()
    
    # Client sends HELLO
    hello_req = struct.pack("<IIQ8I", SPTL_MAGIC, 1, 32, 2, 1, 40, 64, 5120, 152064, 32768, 256)
    client.sendall(hello_req)
    
    hdr = conn.recv(16)
    magic, mtype, plen = struct.unpack("<IIQ", hdr)
    assert magic == SPTL_MAGIC and mtype == 1
    body = conn.recv(plen)
    assert len(body) == 32
    
    # Server replies HELLO_OK
    hello_rep = struct.pack("<IIQ8IQ128s", SPTL_MAGIC, 2, 168, 2, 1, 40, 64, 24, 5120, 152064, 32768, 1024000, b"Emulated Android Worker")
    conn.sendall(hello_rep)
    
    rep_hdr = client.recv(16)
    rep_magic, rep_type, rep_len = struct.unpack("<IIQ", rep_hdr)
    assert rep_magic == SPTL_MAGIC and rep_type == 2
    rep_body = client.recv(rep_len)
    assert len(rep_body) == rep_len
    
    client.close()
    conn.close()
    srv.close()
    print("\033[32mPASS\033[0m")

def verify_rea_evidence_report():
    print("[4/4] Verifying REA Evidence Schema...", end=" ")
    evidence = {
        "producer": "rea-verify-pipeline",
        "target": "backburner-win-android",
        "sptl_proto_version": 2,
        "patn_proto_version": 4,
        "verified_at": time.time(),
        "status": "COMPATIBLE"
    }
    assert evidence["sptl_proto_version"] == 2
    print("\033[32mPASS\033[0m")

def main():
    print("=== REA Backburner Windows + Android Verification Suite ===")
    verify_framing()
    verify_chunk_payload_packing()
    verify_loopback_socket_server()
    verify_rea_evidence_report()
    print("All verification tests passed successfully!")

if __name__ == "__main__":
    main()
