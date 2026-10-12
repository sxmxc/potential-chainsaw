"""Campaign bundle checks using only JSON fixtures in an auto-cleaned temp folder."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from import_campaign import import_bundle


class CampaignImportTests(unittest.TestCase):
    def test_existing_ids_paths_and_chapters_survive_round_trip(self):
        with tempfile.TemporaryDirectory(prefix="marble-engineer-bundle-") as temporary:
            resources = Path(temporary) / "resources"
            destination = resources / "campaign"
            destination.mkdir(parents=True)
            originals = {}
            for source in (ROOT / "resources/campaign").glob("*.json"):
                data = json.loads(source.read_text(encoding="utf-8"))
                originals[data["id"]] = (source.name, data)
                (destination / source.name).write_text(json.dumps(data), encoding="utf-8")
            manifest = json.loads((ROOT / "resources/campaign_chapters.json").read_text(encoding="utf-8"))
            manifest_path = resources / "campaign_chapters.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            bundle_path = Path(temporary) / "export.zip"
            with zipfile.ZipFile(bundle_path, "w") as bundle:
                for puzzle_id, (_, data) in originals.items():
                    bundle.writestr(f"campaign/{puzzle_id}.json", json.dumps(data))
                bundle.writestr("campaign_chapters.json", json.dumps(manifest))
            self.assertEqual(import_bundle(bundle_path, destination), 10)
            self.assertEqual(len(list(destination.glob("*.json"))), 10)
            for filename, data in originals.values():
                self.assertEqual(json.loads((destination / filename).read_text(encoding="utf-8")), data)
            self.assertEqual(json.loads(manifest_path.read_text(encoding="utf-8")), manifest)

    def test_future_chapters_preserve_existing_membership(self):
        with tempfile.TemporaryDirectory(prefix="marble-engineer-bundle-") as temporary:
            resources = Path(temporary) / "resources"
            resources.mkdir()
            original = json.loads((ROOT / "resources/campaign_chapters.json").read_text(encoding="utf-8"))
            manifest_path = resources / "campaign_chapters.json"
            manifest_path.write_text(json.dumps(original), encoding="utf-8")
            incoming = {"version": 1, "chapters": [
                {"id": "introduction", "name": "Introduction", "optional": True, "introduction": True, "levels": ["campaign-01"]},
                {"id": "chapter-2", "name": "Chapter 2", "order": 2, "prerequisites": [], "levels": []},
            ]}
            bundle_path = Path(temporary) / "future.zip"
            with zipfile.ZipFile(bundle_path, "w") as bundle:
                bundle.writestr("campaign_chapters.json", json.dumps(incoming))
            self.assertEqual(import_bundle(bundle_path, resources / "campaign"), 0)
            merged = json.loads(manifest_path.read_text(encoding="utf-8"))
            chapters = {chapter["id"]: chapter for chapter in merged["chapters"]}
            self.assertEqual(chapters["introduction"]["levels"], original["chapters"][0]["levels"])
            self.assertIn("chapter-1", chapters)
            self.assertIn("chapter-2", chapters)

    def test_invalid_bundle_leaves_destination_untouched(self):
        with tempfile.TemporaryDirectory(prefix="marble-engineer-bundle-") as temporary:
            destination = Path(temporary) / "resources/campaign"
            bundle_path = Path(temporary) / "invalid.zip"
            data = json.loads(next((ROOT / "resources/campaign").glob("*.json")).read_text(encoding="utf-8"))
            with zipfile.ZipFile(bundle_path, "w") as bundle:
                bundle.writestr("campaign/good.json", json.dumps(data))
                bundle.writestr("campaign/bad.json", json.dumps({"id": "../escape"}))
            with self.assertRaises(ValueError):
                import_bundle(bundle_path, destination)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
