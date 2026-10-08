"""Assemble a verified Edit-mode service-container model; never publish or touch Studio.

python tools/assemble-playtest.py [--export-id GUID] [--backups PATH] [--output-dir PATH]
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path


def assemble(backups: Path, output_dir: Path, export_id: str | None = None) -> dict:
    groups: dict[str, list[tuple[Path, dict]]] = {}
    for path in sorted(backups.glob("studio-export-*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("kind") == "releaseModelPart":
            guid = payload.get("exportId")
            if not isinstance(guid, str) or not guid:
                raise ValueError(f"Missing exportId in {path.name}")
            groups.setdefault(guid, []).append((path, payload))
    if not groups:
        raise ValueError("No releaseModelPart exports found")
    if export_id is None:
        # The newest attempt must be complete; never silently deliver an older export.
        export_id = max(groups, key=lambda guid: max(path.name for path, _ in groups[guid]))
    if export_id not in groups:
        raise ValueError(f"Export {export_id} not found")
    entries = groups[export_id]
    total_parts, total_bytes = entries[0][1].get("totalParts"), entries[0][1].get("totalBytes")
    if type(total_parts) is not int or type(total_bytes) is not int or total_parts <= 0 or total_bytes <= 0:
        raise ValueError("Invalid part/byte counts")
    parts, metadata = {}, None
    for path, payload in entries:
        if payload.get("totalParts") != total_parts or payload.get("totalBytes") != total_bytes:
            raise ValueError(f"Inconsistent counts in {path.name}")
        index = payload.get("part")
        if type(index) is not int or not 1 <= index <= total_parts:
            raise ValueError(f"Invalid part index in {path.name}")
        raw = bytes.fromhex(payload["modelHex"])
        if index in parts and parts[index] != raw:
            raise ValueError(f"Conflicting duplicate part {index}")
        parts[index] = raw
        if payload.get("metadata") is not None:
            if metadata is not None and metadata != payload["metadata"]:
                raise ValueError("Conflicting metadata")
            metadata = payload["metadata"]
    if set(parts) != set(range(1, total_parts + 1)):
        raise ValueError(f"Incomplete export: {len(parts)}/{total_parts} parts")
    model = b"".join(parts[index] for index in range(1, total_parts + 1))
    if len(model) != total_bytes or not model.startswith(b"<roblox!"):
        raise ValueError("Model byte count or Roblox binary header mismatch")
    if not isinstance(metadata, dict) or metadata.get("exportId") != export_id:
        raise ValueError("Missing matching metadata")
    if metadata.get("verifiedUnparentedRoundTrip") is not True or metadata.get("sourceMode") != "Edit":
        raise ValueError("Export did not verify an unparented Edit-mode round-trip")
    if metadata.get("totalBytes") != total_bytes or metadata.get("totalParts") != total_parts:
        raise ValueError("Metadata count mismatch")
    metadata = dict(metadata)
    metadata.update({
        "modelFile": "ForgeFrenzy-1.0-playtest.rbxm",
        "sha256": hashlib.sha256(model).hexdigest(),
        "assembledAtUtc": datetime.now(timezone.utc).isoformat(),
        "exportPartFiles": [path.name for path, _ in entries],
    })
    output_dir.mkdir(parents=True, exist_ok=True)
    model_path = output_dir / metadata["modelFile"]
    metadata_path = output_dir / "ForgeFrenzy-1.0-playtest.metadata.json"
    # Build fully before replacing the deliverable. Prior Studio backups remain untouched.
    temporary = model_path.with_suffix(".rbxm.tmp")
    temporary.write_bytes(model)
    temporary.replace(model_path)
    temporary = metadata_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(metadata_path)
    return {"model": str(model_path.resolve()), "metadata": str(metadata_path.resolve()),
            "bytes": total_bytes, "sha256": metadata["sha256"], "exportId": export_id}


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export-id")
    parser.add_argument("--backups", type=Path, default=root / ".local/backups")
    parser.add_argument("--output-dir", type=Path, default=root / "artifacts")
    args = parser.parse_args()
    print(json.dumps(assemble(args.backups, args.output_dir, args.export_id), indent=2))
