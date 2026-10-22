import argparse
import json
import sys
import urllib.request


def main():
    parser = argparse.ArgumentParser(description="Test AndiRun Distributed LLM inference")
    parser.add_argument("--port", type=int, default=8002, help="API port (default: 8002)")
    parser.add_argument("--prompt", default="Explain how AndiRun splits LLM inference across Windows and Android.", help="Prompt text")
    args = parser.parse_args()

    url = f"http://127.0.0.1:{args.port}/v1/chat/completions"
    payload = {
        "messages": [
            {"role": "user", "content": args.prompt}
        ],
        "temperature": 0.7,
        "max_tokens": 256
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    print(f"\n[AndiRun] Sending prompt to {url}...")
    print(f"[User] {args.prompt}\n")

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            print("[AndiRun Assistant]\n" + "-" * 50)
            print(content)
            print("-" * 50)
            if "usage" in data:
                u = data["usage"]
                print(f"Tokens: Prompt {u.get('prompt_tokens', 0)}, Completion {u.get('completion_tokens', 0)}, Total {u.get('total_tokens', 0)}")
    except Exception as e:
        print(f"[Error] Failed to connect: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
