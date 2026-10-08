"""Compare a preserved Studio script export to Git HEAD without overwriting either."""
import importlib.util
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("devsync", root / "tools/devsync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)
backups = root / ".local/backups"
exports = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(backups.glob("studio-export-*.json"))]
source = next(e for e in exports if e.get("kind") == "scripts")
parts = sorted((e for e in exports if e.get("kind") == "modelPart"), key=lambda e: e["part"])
if parts:
    model = b"".join(bytes.fromhex(e["modelHex"]) for e in parts)
    assert len(model) == parts[0]["totalBytes"]
    (backups / "ForgeFrenzy-before-Codex.rbxm").write_bytes(model)
live = {s["path"]: s for s in source["scripts"]}
expected = {}
for item in sync.bundle()["items"]:
    if "source" not in item:
        continue
    path = ".".join(item["path"])
    mount = {"ReplicatedStorage.Shared": "src/shared", "ServerScriptService.Server": "src/server",
             "ServerStorage.Build": "src/build", "StarterPlayer.StarterPlayerScripts.Client": "src/client"}
    for prefix, directory in mount.items():
        if path.startswith(prefix + "."):
            name = path[len(prefix) + 1:].replace(".", "/")
            # Names may contain dots (e.g. Economy.spec).
            name = name.replace("/spec", ".spec")
            suffix = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}[item["class"]]
            repo_file = directory + "/" + name + suffix
            result = subprocess.run(["git", "show", "HEAD:" + repo_file], cwd=root, capture_output=True)
            if result.returncode == 0:
                expected[path] = result.stdout.decode("utf-8").replace("\r\n", "\n")
differences = []
for path, script in live.items():
    if path not in expected or script["source"].replace("\r\n", "\n") != expected[path]:
        differences.append(path)
print(json.dumps({"placeId": source["placeId"], "liveScripts": len(live), "headScripts": len(expected),
                  "differentOrLiveOnly": differences, "missingInStudio": sorted(set(expected) - set(live)),
                  "preservedModelBytes": len(model) if parts else 0}, indent=2))
