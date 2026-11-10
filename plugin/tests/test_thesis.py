import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SERVER = Path(__file__).resolve().parents[1] / "scripts" / "thesis_pro_mcp.py"
spec = importlib.util.spec_from_file_location("thesis", SERVER)
thesis = importlib.util.module_from_spec(spec)
with patch.dict(os.environ, {"THESIS_PRO_HOME": tempfile.gettempdir()}):
    spec.loader.exec_module(thesis)


class ThesisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        thesis.ROOT = (Path(self.temp.name) / "projects").resolve()
        self.project = thesis.tool_create({"title": "Synthetic library accessibility study", "target_words": 5000})["project"]
        self.pid = self.project["id"]

    def tearDown(self):
        self.temp.cleanup()

    def test_reconcile_preview_conflict_and_backup(self):
        thesis.tool_save_section({"project_id": self.pid, "chapter": 1, "section_title": "a", "content": "1.1 Question\n\n" + "Research requires bounded evidence. " * 8})
        preview = thesis.tool_reconcile_map({"project_id": self.pid})
        self.assertFalse(preview["applied"])
        with self.assertRaises(ValueError):
            thesis.tool_reconcile_map({"project_id": self.pid, "apply": True, "expected_sha256": "stale"})
        result = thesis.tool_reconcile_map({"project_id": self.pid, "apply": True, "expected_sha256": preview["project_sha256"]})
        self.assertTrue(Path(result["backup"]).exists())
        self.assertEqual(len(thesis.load_project(self.pid)["academic_journey"]), 1)

    def test_budget_persistence_and_export(self):
        self.assertEqual(sum(c["target_words"] for c in self.project["chapters"]), 5000)
        thesis.tool_save_section({"project_id": self.pid, "chapter": 1, "section_title": "Proposal", "content": "Synthetic example only. No participants or results."})
        dashboard = thesis.tool_dashboard({"project_id": self.pid})
        self.assertGreater(dashboard["words"], 0)
        exported = thesis.tool_export({"project_id": self.pid})
        self.assertIn("Synthetic example only", Path(exported["path"]).read_text())

    def test_export_traversal_rejected(self):
        for name in ("../outside.md", "/tmp/outside.md", "nested/file.md", "..\\outside.md", "\0bad"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                thesis.tool_export({"project_id": self.pid, "filename": name})

    def test_identity_and_symlink_boundaries(self):
        for pid in ("../other", "", "a/b", "a.b"):
            with self.assertRaises(ValueError):
                thesis.project_path(pid)
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (thesis.ROOT / "linked").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            thesis.load_project("linked")
        path = thesis.project_path(self.pid)
        data = json.loads(path.read_text())
        data["id"] = "different"
        path.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            thesis.load_project(self.pid)

    def test_atomic_failure_preserves_previous_project(self):
        path = thesis.project_path(self.pid)
        before = path.read_bytes()
        with patch.object(thesis.os, "replace", side_effect=OSError("synthetic interruption")):
            with self.assertRaises(OSError):
                thesis.tool_save_section({"project_id": self.pid, "chapter": 1, "section_title": "Draft", "content": "Replacement"})
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(list(path.parent.iterdir()), [path])

    def test_audit_and_source_identity(self):
        issues = thesis.tool_audit({"project_id": self.pid})
        self.assertFalse(issues["passed"])
        with self.assertRaises(ValueError):
            thesis.tool_add_claim({"project_id": self.pid, "claim": "Synthetic", "source_ids": ["unknown"]})
        source = thesis.tool_add_source({"project_id": self.pid, "citation": "Synthetic fixture; not a real publication", "verified": False})["source"]
        thesis.tool_add_claim({"project_id": self.pid, "claim": "Illustrative claim", "source_ids": [source["id"]]})
        self.assertIn("sources", [x["area"] for x in thesis.tool_audit({"project_id": self.pid})["issues"]])

    def test_argument_types(self):
        for name, args in (("add_source", {"project_id": self.pid, "citation": "Fixture", "verified": "false"}), ("create_project", {"title": "Fixture", "target_words": True})):
            with self.assertRaises(ValueError):
                thesis.handle({"method": "tools/call", "params": {"name": name, "arguments": args}})

    def test_stdio_isolated_startup(self):
        requests = [{"jsonrpc": "2.0", "id": 1, "method": "initialize"}, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "list_projects", "arguments": {}}}]
        env = dict(os.environ, THESIS_PRO_HOME=str(Path(self.temp.name) / "empty"))
        run = subprocess.run([sys.executable, str(SERVER)], input="\n".join(map(json.dumps, requests)) + "\n", text=True, capture_output=True, env=env, timeout=10, check=True)
        replies = [json.loads(line) for line in run.stdout.splitlines()]
        self.assertEqual(replies[0]["result"]["serverInfo"]["version"], "0.3.0")
        self.assertEqual(len(replies[1]["result"]["tools"]), 13)
        self.assertEqual(replies[2]["result"]["structuredContent"]["projects"], [])

    def test_source_and_claim_corrections_resolve_audit(self):
        thesis.tool_design({"project_id": self.pid, "fields": {k: "Synthetic provisional plan" for k in ("problem", "gap", "aim", "objectives", "questions", "methodology", "expected_contribution")}})
        source = thesis.tool_add_source({"project_id": self.pid, "citation": "Synthetic fixture", "verified": False})["source"]
        claim = thesis.tool_add_claim({"project_id": self.pid, "claim": "Illustrative external claim"})["claim"]
        self.assertFalse(thesis.tool_audit({"project_id": self.pid})["passed"])
        with self.assertRaises(ValueError):
            thesis.tool_update_source({"project_id": self.pid, "source_id": source["id"], "verified": True})
        thesis.tool_update_source({"project_id": self.pid, "source_id": source["id"], "verified": True, "notes": "Synthetic verification-record fixture, not a real paper"})
        thesis.tool_update_claim({"project_id": self.pid, "claim_id": claim["id"], "source_ids": [source["id"]]})
        audit = thesis.tool_audit({"project_id": self.pid})
        self.assertTrue(audit["passed"])
        self.assertFalse(audit["word_budget_met"])
        self.assertEqual(audit["scope"], "structure_and_recorded_flags_only")
        self.assertEqual(thesis.load_project(self.pid)["claims"][0]["history"][0]["previous"]["source_ids"], [])

    def test_changed_citation_invalidates_verification_and_unknown_links_reject(self):
        source = thesis.tool_add_source({"project_id": self.pid, "citation": "Synthetic fixture", "verified": True})["source"]
        updated = thesis.tool_update_source({"project_id": self.pid, "source_id": source["id"], "url_or_doi": "https://example.org/changed"})["source"]
        self.assertFalse(updated["verified"])
        self.assertEqual(updated["history"][0]["previous"]["verified"], True)
        claim = thesis.tool_add_claim({"project_id": self.pid, "claim": "Fixture"})["claim"]
        with self.assertRaises(ValueError):
            thesis.tool_update_claim({"project_id": self.pid, "claim_id": claim["id"], "source_ids": ["unknown"]})
        self.assertEqual(thesis.load_project(self.pid)["claims"][0]["source_ids"], [])

    def test_reference_counts_and_legacy_reads_preserve_stored_bytes(self):
        thesis.tool_save_section({"project_id": self.pid, "chapter": 1, "section_title": "Plan", "content": "Main text only"})
        thesis.tool_save_section({"project_id": self.pid, "chapter": 6, "section_title": "References", "content": "One recorded citation"})
        current = thesis.load_project(self.pid)
        for chapter in current["chapters"]:
            chapter["target_words"] = 500
        thesis.save_project(current)
        path = thesis.project_path(self.pid)
        before = path.read_bytes()
        dashboard = thesis.tool_dashboard({"project_id": self.pid})
        self.assertEqual((dashboard["words"], dashboard["reference_words"], dashboard["total_section_words"]), (3, 3, 6))
        self.assertIsNotNone(dashboard["budget_note"])
        self.assertEqual(path.read_bytes(), before)
        exported = thesis.tool_export({"project_id": self.pid})
        self.assertEqual(exported["main_text_words"], 3)
        self.assertNotIn("Chapter 2:", Path(exported["path"]).read_text())


if __name__ == "__main__":
    unittest.main()
