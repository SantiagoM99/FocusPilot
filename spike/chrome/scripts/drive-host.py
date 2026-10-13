"""Exercises the host outside Chrome: python3 drive-host.py HOST [ORIGIN]."""
import json, struct, subprocess, sys

host = sys.argv[1]
origin = sys.argv[2] if len(sys.argv) > 2 else "chrome-extension://nnebgihjjgaokjddhlkfmijogibdpfjj/"
p = subprocess.Popen([host, origin], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

def send(obj):
    body = json.dumps(obj).encode()
    p.stdin.write(struct.pack("=I", len(body)) + body)
    p.stdin.flush()

def recv():
    header = p.stdout.read(4)
    if len(header) < 4:
        return None
    return json.loads(p.stdout.read(struct.unpack("=I", header)[0]))

send({"type": "hello", "source": "drive-host.py"})
msg = recv()
print("received:", json.dumps(msg)[:300] if msg else None)
if msg:
    send({"type": "ack", "revision": msg["policy"]["revision"], "checksum": msg["checksum"]})
p.stdin.close()
print("exit code:", p.wait())
