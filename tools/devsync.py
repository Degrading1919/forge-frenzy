"""Minimal repo -> Studio sync server (Rojo-compatible file conventions).

Serves the source tree described by default.project.json as one JSON bundle at
http://127.0.0.1:34872/bundle. tools/sync.luau (run through the Studio MCP
execute_luau tool or the command bar) fetches it and mirrors the scripts into the
open place. Rojo is the long-term option; this exists because Rojo isn't installed.

Conventions: Foo.server.luau -> Script, Foo.client.luau -> LocalScript,
Foo.luau -> ModuleScript, folder/init.luau -> folder becomes that ModuleScript.
"""
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(os.environ.get("FF_SYNC_PORT", "34872"))


def classify(name):
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if name.endswith(suffix):
            return name[: -len(suffix)], cls
    return None, None


def walk(fs_path, inst_path, out):
    entries = sorted(os.listdir(fs_path))
    init = next((e for e in entries if e.startswith("init.") and classify(e)[1]), None)
    if init:
        with open(os.path.join(fs_path, init), encoding="utf-8") as f:
            out.append({"path": inst_path, "class": classify(init)[1], "source": f.read().replace("
", "
")})
    else:
        out.append({"path": inst_path, "class": "Folder"})
    for e in entries:
        full = os.path.join(fs_path, e)
        if e == init:
            continue
        if os.path.isdir(full):
            walk(full, inst_path + [e], out)
        else:
            name, cls = classify(e)
            if cls:
                with open(full, encoding="utf-8") as f:
                    out.append({"path": inst_path + [name], "class": cls, "source": f.read().replace("
", "
")})


def bundle():
    with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as f:
        project = json.load(f)
    out, roots = [], []

    def visit(node, path):
        for key, child in node.items():
            if key.startswith("$") or not isinstance(child, dict):
                continue
            if "$path" in child:
                roots.append(path + [key])
                walk(os.path.join(ROOT, child["$path"]), path + [key], out)
            else:
                visit(child, path + [key])

    visit(project["tree"], [])
    return {"roots": roots, "items": out}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(bundle()).encode("utf-8") if self.path.startswith("/bundle") else b"{}"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    if "--print" in sys.argv:
        b = bundle()
        print(len(b["items"]), "items", b["roots"])
        sys.exit(0)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
