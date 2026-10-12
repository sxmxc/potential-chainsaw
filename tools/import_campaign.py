"""Stage a bundle exported by the visual Puzzle Editor before a Godot export.

Usage: python tools/import_campaign.py path/to/campaign.zip
Then run tests/campaign.gd to verify all reference solutions in the target engine.
"""
import json
import pathlib
import re
import sys
import zipfile

destination = pathlib.Path(__file__).resolve().parents[1] / "resources" / "campaign"
with zipfile.ZipFile(sys.argv[1]) as bundle:
    pending = []
    for entry in bundle.infolist():
        if not entry.filename.startswith("campaign/") or not entry.filename.endswith(".json"):
            continue
        if entry.file_size > 5_000_000:
            raise ValueError("Puzzle file exceeds size limit")
        data = json.loads(bundle.read(entry))
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", data.get("id", "")):
            raise ValueError("Invalid puzzle ID")
        if data.get("version") != 1 or data.get("status") != "published":
            raise ValueError("Bundle contains unsupported or unpublished content")
        if not data.get("validation", {}).get("physics_success") or not data.get("solution"):
            raise ValueError("Bundle contains untested content")
        pending.append((destination / (data["id"] + ".json"), data))
    destination.mkdir(parents=True, exist_ok=True)
    for path, data in pending:
        matches = [p for p in destination.glob("*.json") if json.loads(p.read_text(encoding="utf-8")).get("id") == data["id"]]
        if matches:
            path = matches[0]
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")
print(f"Staged {len(pending)} puzzles. Run tests/campaign.gd before exporting the game.")
