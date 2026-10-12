"""Stage a bundle exported by the visual Puzzle Editor before a Godot export.

Usage: python tools/import_campaign.py path/to/campaign.zip
Then run the GUT campaign suites in the target engine.
"""
import json
import pathlib
import re
import sys
import zipfile

def import_bundle(bundle_path, destination):
    """Validate and stage only JSON campaign data into the selected directory."""
    destination = pathlib.Path(destination)
    with zipfile.ZipFile(bundle_path) as bundle:
        pending = []
        chapter_path = destination.parent / "campaign_chapters.json"
        chapter_data = None
        if "campaign_chapters.json" in bundle.namelist():
            entry = bundle.getinfo("campaign_chapters.json")
            if entry.file_size > 1_000_000:
                raise ValueError("Chapter manifest exceeds size limit")
            incoming = json.loads(bundle.read(entry))
            if incoming.get("version") != 1 or not isinstance(incoming.get("chapters"), list):
                raise ValueError("Unsupported chapter manifest")
            existing = json.loads(chapter_path.read_text(encoding="utf-8")) if chapter_path.exists() else {"chapters": []}
            chapters = {c["id"]: c for c in existing["chapters"]}
            for chapter in incoming["chapters"]:
                if not re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", chapter.get("id", "")) or not chapter.get("name"):
                    raise ValueError("Invalid chapter metadata")
                if not isinstance(chapter.get("levels", []), list) or not isinstance(chapter.get("prerequisites", []), list):
                    raise ValueError("Chapter membership and requirements must be lists")
                if chapter.get("introduction") and not chapter.get("optional"):
                    raise ValueError("Introduction chapters must be optional")
                old_members = chapters.get(chapter["id"], {}).get("levels", [])
                chapter["levels"] = list(dict.fromkeys(old_members + chapter.get("levels", [])))
                chapters[chapter["id"]] = {**chapters.get(chapter["id"], {}), **chapter}
            chapter_data = {"version": 1, "chapters": list(chapters.values())}
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
        if chapter_data is not None:
            chapter_path.write_text(json.dumps(chapter_data, indent=2), encoding="utf-8")
    return len(pending)


if __name__ == "__main__":
    destination = pathlib.Path(__file__).resolve().parents[1] / "resources" / "campaign"
    count = import_bundle(sys.argv[1], destination)
    print(f"Staged {count} puzzles. Run the GUT campaign tests before exporting the game.")
