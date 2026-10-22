import argparse
import json
import sys
import urllib.request


def main():
    parser = argparse.ArgumentParser(description="Test AndiRun Distributed LLM inference")
    parser.add_argument("--port", type=int, default=8002, help="API port (default: 8002)")
    parser.add_argument("--prompt", default="Explain how AndiRun splits LLM inference across Windows and Android.", help="Prompt text")
    parser.add_argument("--max-tokens", type=int, default=128, help="Max output tokens (default: 128)")
    parser.add_argument("--stream", action="store_true", default=True, help="Stream tokens in real time (default: True)")
    args = parser.parse_args()

    # Auto-detect which port llama-server is listening on
    candidate_ports = [args.port] + [p for p in [8002, 8001, 8000] if p != args.port]
    target_port = args.port
    for p in candidate_ports:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{p}/health", timeout=1.0) as r:
                if r.status == 200:
                    target_port = p
                    break
        except Exception:
            pass

    url = f"http://127.0.0.1:{target_port}/v1/chat/completions"
    payload = {
        "messages": [
            {"role": "user", "content": args.prompt}
        ],
        "temperature": 0.7,
        "max_tokens": args.max_tokens,
        "stream": args.stream
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    print(f"\n[AndiRun] Connected to host server at {url}")
    print(f"[User] {args.prompt}\n")
    print("[AndiRun Assistant]\n" + "-" * 50)

    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            if args.stream:
                total_tokens = 0
                for raw_line in resp:
                    line = raw_line.decode("utf-8").strip()
                    if not line:
                        continue
                    if line.startswith("data: "):
                        chunk_str = line[6:].strip()
                        if chunk_str == "[DONE]":
                            break
                        try:
                            chunk = json.loads(chunk_str)
                            delta = chunk["choices"][0].get("delta", {})
                            token = delta.get("content", "")
                            if token:
                                sys.stdout.write(token)
                                sys.stdout.flush()
                                total_tokens += 1
                        except Exception:
                            continue
                print("\n" + "-" * 50)
                print(f"[✓] Stream complete (~{total_tokens} tokens).")
            else:
                data = json.loads(resp.read().decode("utf-8"))
                content = data["choices"][0]["message"]["content"]
                print(content)
                print("-" * 50)
                if "usage" in data:
                    u = data["usage"]
                    print(f"Tokens: Prompt {u.get('prompt_tokens', 0)}, Completion {u.get('completion_tokens', 0)}, Total {u.get('total_tokens', 0)}")
    except urllib.error.URLError as e:
        print(f"[Error] Could not connect to llama-server on port {target_port}: {e.reason}")
        print("\nEnsure the host server is running in Window 1 with:")
        print("  python andirun-main\\scripts\\serve_win_android.py -m qwen-7b.gguf -L 20 --tail-port 8080 --port 8001 --server-bin build-win\\bin\\llama-server.exe --extra-args \"--lora andirun-lora.gguf\"")
        sys.exit(1)
    except Exception as e:
        print(f"[Error] Query failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
