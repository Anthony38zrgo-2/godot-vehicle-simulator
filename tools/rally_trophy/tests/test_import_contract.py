import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.rally_trophy.common import within
from tools.rally_trophy.config_parser import parse_config
from tools.rally_trophy.integrate import install


class ImportContract(unittest.TestCase):
    def test_config_never_evaluates_unknown_expression(self):
        result = parse_config(b'A={1,-2,.5}; # comment\nName="a#b"; A=3; Unknown=call();')
        self.assertEqual(result["values"], {"A": 3, "Name": "a#b", "Unknown": {"unparsed": "call()"}})
        self.assertEqual(len(result["issues"]), 2)

    def test_paths_cannot_escape(self):
        for value in ["../other", r"..\other", "C:/other", "/other"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                within(Path.cwd(), value)

    def test_install_isolated_and_registry_committed_last(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            repo, payload = base / "repo", base / "payload"
            registry = repo / "game/data/vehicles/registry.json"
            registry.parent.mkdir(parents=True)
            registry.write_text('{"default":"fulvia","vehicles":{}}')
            recipe = {"id": "rt-test", "display_name": "Test"}
            relative = Path("game/scenes/rally/rt/rt-test.tscn")
            (payload / relative).parent.mkdir(parents=True)
            (payload / relative).write_text("scene")
            with patch("tools.rally_trophy.integrate.write_json", side_effect=OSError("commit failed")):
                with self.assertRaises(OSError):
                    install(payload, recipe, repo)
            self.assertFalse((repo / relative).exists())
            install(payload, recipe, repo)
            result = json.loads(registry.read_text())
            self.assertEqual(result["default"], "fulvia")
            self.assertIn("rt-test", result["vehicles"])
            with self.assertRaises(FileExistsError):
                install(payload, recipe, repo)
            unrelated = payload / "game/scenes/rally/rt/rt-test-other.tscn"
            unrelated.touch()
            with self.assertRaises(ValueError):
                install(payload, recipe, repo, replace=True)


if __name__ == "__main__":
    unittest.main()
