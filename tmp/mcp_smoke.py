#!/usr/bin/env python3
"""Smoke-test the godot MCP server over stdio (newline-delimited JSON-RPC)."""
import json, os, subprocess, sys, threading, time

env = dict(os.environ, GODOT_PATH="/opt/homebrew/bin/godot")
proc = subprocess.Popen(
    ["npx", "-y", "@coding-solo/godot-mcp"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    env=env, text=True, bufsize=1,
)

responses = {}
def reader():
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            if "id" in msg:
                responses[msg["id"]] = msg
        except json.JSONDecodeError:
            print("NON-JSON LINE:", line[:200], file=sys.stderr)

t = threading.Thread(target=reader, daemon=True)
t.start()

def send(msg):
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()

def wait_for(rid, timeout=90):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if rid in responses:
            return responses[rid]
        time.sleep(0.1)
    return None

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"protocolVersion": "2024-11-05",
                 "capabilities": {},
                 "clientInfo": {"name": "kimi-smoke-test", "version": "0.1"}}})
init = wait_for(1)
if not init:
    err = proc.stderr.read() if proc.stderr else ""
    print("FAIL: no initialize response within timeout"); print("STDERR:", err[:2000]); sys.exit(1)
if "error" in init:
    print("FAIL: initialize error:", json.dumps(init["error"])[:500]); sys.exit(1)
server = init.get("result", {}).get("serverInfo", {})
print(f"initialize OK — server: {server.get('name')} {server.get('version')}")

send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
tools = wait_for(2)
if not tools or "result" not in tools:
    print("FAIL: tools/list:", json.dumps(tools)[:500] if tools else "timeout"); sys.exit(1)
names = [t["name"] for t in tools["result"].get("tools", [])]
print(f"tools/list OK — {len(names)} tools:")
for n in names:
    print(" -", n)

proc.terminate()
print("SMOKE TEST PASSED")
