#!/usr/bin/env python3
"""Local-first MCP server for ThesisPRO. Uses only the Python standard library."""

import json
import os
import tempfile
import re
import sys
import uuid
import hashlib
import importlib.util
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ["THESIS_PRO_HOME"]).expanduser().resolve() if os.environ.get("THESIS_PRO_HOME") else (Path.home() / "Documents" / "ThesisPRO").resolve()

_map_spec = importlib.util.spec_from_file_location('thesis_evidence_map', Path(__file__).with_name('evidence_map.py'))
evidence_map = importlib.util.module_from_spec(_map_spec)
_map_spec.loader.exec_module(evidence_map)


def tool_reconcile_map(a):
    path = project_path(a['project_id'])
    before = path.read_bytes()
    fingerprint = hashlib.sha256(before).hexdigest()
    project = json.loads(before)
    if project.get('id') != a['project_id']:
        raise ValueError('Project identity mismatch')
    links, archived = evidence_map.reconcile(project)
    report = {'project_sha256': fingerprint, 'current_passages': len(links),
              'changed_or_removed': len(archived), 'applied': False,
              'note': 'Exact passage reconciliation only. No source support or academic approval inferred.'}
    if not a.get('apply', False):
        return {**report, 'links': links}
    if a.get('expected_sha256') != fingerprint:
        raise ValueError('Project changed or expected_sha256 missing; preview again before applying')
    backup = path.parent / 'history' / ('evidence-map-' + fingerprint + '.json')
    if backup.parent.is_symlink() or backup.is_symlink() or not backup.resolve().is_relative_to(path.parent.resolve()):
        raise ValueError('History path leaves project')
    if backup.exists() and backup.read_bytes() != before:
        raise ValueError('Existing history record conflicts with its digest')
    if not backup.exists():
        atomic_write(backup, before.decode('utf-8'))
    project.setdefault('academic_journey_history', []).extend(archived)
    project['academic_journey'] = links
    project['academic_journey_schema'] = 2
    if path.read_bytes() != before:
        raise ValueError('Concurrent project change; no write performed')
    save_project(project)
    return {**report, 'applied': True, 'backup': str(backup)}


def now():
    return datetime.now(timezone.utc).isoformat()


def slugify(value):
    value = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip()).strip("-").lower()
    return value[:60] or "thesis"


def project_path(project_id):
    if not isinstance(project_id, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", project_id):
        raise ValueError("Invalid project_id")
    folder = ROOT / project_id
    path = folder / "project.json"
    if folder.is_symlink() or path.is_symlink() or not path.resolve().is_relative_to(ROOT):
        raise ValueError("Project path leaves the configured workspace")
    return path


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            temp = Path(stream.name)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp is not None and temp.exists():
            temp.unlink()


def load_project(project_id):
    path = project_path(project_id)
    if not path.exists():
        raise ValueError(f"Project not found: {project_id}")
    project = json.loads(path.read_text(encoding="utf-8"))
    if project.get("id") != project_id:
        raise ValueError("Project identity mismatch")
    return project


def save_project(project):
    path = project_path(project["id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    project["updated_at"] = now()
    atomic_write(path, json.dumps(project, ensure_ascii=False, indent=2))


def words(text):
    return len(re.findall(r"\b[\w’'-]+\b", text or "", flags=re.UNICODE))


def chapter_template(target, degree):
    ratios = [0.10, 0.30, 0.20, 0.20, 0.20, 0.0]
    names = [
        "Introduction", "Literature Review", "Methodology",
        "Results / Findings", "Discussion, Recommendations and Conclusion",
        "References and Appendices"
    ]
    if degree.lower().startswith("master"):
        ratios = [0.12, 0.28, 0.22, 0.20, 0.18, 0.0]
    budgets = [round(target * ratio) for ratio in ratios]
    budgets[-2] += target - sum(budgets)
    return [{"number": i + 1, "title": n, "target_words": budgets[i], "sections": {}}
            for i, n in enumerate(names)]


def tool_create(a):
    title = a["title"].strip()
    degree = a.get("degree", "PhD")
    target = int(a.get("target_words", 80000 if degree.lower() == "phd" else 40000))
    pid = f"{slugify(title)}-{uuid.uuid4().hex[:6]}"
    project = {
        "id": pid, "title": title, "degree": degree,
        "discipline": a.get("discipline", "To be confirmed"),
        "target_words": target, "language": a.get("language", "English"),
        "citation_style": a.get("citation_style", "APA 7 (provisional)"),
        "status": "Foundation", "created_at": now(), "updated_at": now(),
        "research_design": {}, "chapters": chapter_template(target, degree),
        "sources": [], "claims": [], "decisions": [], "notes": []
    }
    save_project(project)
    return {"message": "Thesis project created", "project": project,
            "next_action": "Define the research problem, gap, aim, objectives, questions, context, and proposed methodology."}


def tool_list(_a):
    projects = []
    for path in ROOT.glob("*/project.json"):
        try:
            p = json.loads(path.read_text(encoding="utf-8"))
            projects.append({k: p.get(k) for k in ("id", "title", "degree", "status", "updated_at")})
        except Exception:
            pass
    return {"projects": sorted(projects, key=lambda x: x.get("updated_at", ""), reverse=True)}


def tool_dashboard(a):
    p = load_project(a["project_id"])
    chapter_rows, total, reference_words = [], 0, 0
    for ch in p["chapters"]:
        actual = sum(words(v.get("content", "")) for v in ch.get("sections", {}).values())
        if ch["number"] == 6:
            reference_words += actual
        else:
            total += actual
        chapter_rows.append({"chapter": ch["number"], "title": ch["title"],
                             "words": actual, "target_words": ch["target_words"],
                             "sections": list(ch.get("sections", {}).keys())})
    unsupported = [c for c in p["claims"] if not c.get("source_ids")]
    return {"id": p["id"], "title": p["title"], "degree": p["degree"],
            "discipline": p["discipline"], "status": p["status"],
            "words": total, "reference_words": reference_words, "total_section_words": total + reference_words,
            "word_count_method": "regex section words; chapter6 references/appendices excluded from main text",
            "target_words": p["target_words"], "chapters": chapter_rows,
            "budget_note": "Existing budgets are preserved; review if main-text targets differ" if sum(c["target_words"] for c in p["chapters"] if c["number"] != 6) != p["target_words"] else None,
            "source_count": len(p["sources"]), "claim_count": len(p["claims"]),
            "unsupported_claims": len(unsupported), "research_design": p["research_design"],
            "next_action": next_action(p, total)}


def next_action(p, total):
    required = ["problem", "gap", "aim", "objectives", "questions", "methodology"]
    missing = [x for x in required if not p["research_design"].get(x)]
    if missing:
        return "Complete the research foundation: " + ", ".join(missing)
    if not p["sources"]:
        return "Build the evidence base and record verified scholarly sources."
    if total < p["target_words"]:
        return "Draft and audit the next incomplete section."
    return "Run the final alignment, evidence, citation, and integrity audit."


def tool_design(a):
    p = load_project(a["project_id"])
    allowed = {"problem", "gap", "aim", "objectives", "questions", "hypotheses",
               "constructs", "theoretical_framework", "methodology", "context",
               "scope", "ethics", "expected_contribution"}
    p["research_design"].update({k: v for k, v in a["fields"].items() if k in allowed})
    save_project(p)
    return {"message": "Research foundation updated", "research_design": p["research_design"]}


def tool_save_section(a):
    p = load_project(a["project_id"])
    number = int(a["chapter"])
    chapter = next((c for c in p["chapters"] if c["number"] == number), None)
    if not chapter:
        raise ValueError("Chapter not found")
    title = a["section_title"].strip()
    chapter.setdefault("sections", {})[title] = {
        "content": a["content"], "status": a.get("status", "draft"),
        "updated_at": now(), "word_count": words(a["content"])
    }
    save_project(p)
    return {"message": "Section saved", "chapter": number, "section": title,
            "word_count": words(a["content"])}


def tool_get_section(a):
    p = load_project(a["project_id"])
    chapter = next((c for c in p["chapters"] if c["number"] == int(a["chapter"])), None)
    if not chapter:
        raise ValueError("Chapter not found")
    if "section_title" not in a:
        return {"chapter": chapter}
    return {"chapter": chapter["number"], "section_title": a["section_title"],
            "section": chapter.get("sections", {}).get(a["section_title"])}


def tool_add_source(a):
    p = load_project(a["project_id"])
    source = {"id": f"src-{uuid.uuid4().hex[:8]}", "type": a.get("type", "article"),
              "citation": a["citation"], "url_or_doi": a.get("url_or_doi", ""),
              "verified": bool(a.get("verified", False)), "notes": a.get("notes", ""),
              "added_at": now()}
    p["sources"].append(source)
    save_project(p)
    return {"message": "Source recorded", "source": source}


def tool_add_claim(a):
    p = load_project(a["project_id"])
    known = {s["id"] for s in p["sources"]}
    source_ids = a.get("source_ids", [])
    unknown = [s for s in source_ids if s not in known]
    if unknown:
        raise ValueError("Unknown source IDs: " + ", ".join(unknown))
    claim = {"id": f"claim-{uuid.uuid4().hex[:8]}", "text": a["claim"],
             "source_ids": source_ids, "location": a.get("location", ""),
             "kind": a.get("kind", "external"), "added_at": now()}
    p["claims"].append(claim)
    save_project(p)
    return {"message": "Claim recorded", "claim": claim,
            "warning": None if source_ids or claim["kind"] in ("interpretation", "original contribution")
            else "This external claim has no supporting source."}


def tool_update_source(a):
    p = load_project(a["project_id"])
    source = next((s for s in p["sources"] if s["id"] == a["source_id"]), None)
    if source is None:
        raise ValueError("Source not found")
    changes = {k: v for k, v in a.items() if k in ("citation", "url_or_doi", "type", "verified", "notes")}
    if not changes:
        raise ValueError("Supply source changes")
    if any(k in changes and changes[k] != source.get(k) for k in ("citation", "url_or_doi")):
        changes.setdefault("verified", False)
    if changes.get("verified") and not (changes.get("notes") or source.get("notes", "")).strip():
        raise ValueError("Record how the source was checked in notes")
    previous = {k: source.get(k) for k in changes}
    source.update(changes)
    source["updated_at"] = now()
    source.setdefault("history", []).append({"at": now(), "previous": previous})
    if any(previous[k] != value for k, value in changes.items()):
        for link in p.get("academic_journey", []):
            if source["id"] in link.get("sourceIDs", []):
                link["evidenceStatus"] = "needs_review"
                link["reviewNotes"] = link.get("reviewNotes", "") + "\nSource updated; recheck passage support: " + source["id"]
    save_project(p)
    return {"message": "Source updated; verification remains a recorded assertion", "source": source}


def tool_update_claim(a):
    p = load_project(a["project_id"])
    claim = next((c for c in p["claims"] if c["id"] == a["claim_id"]), None)
    if claim is None:
        raise ValueError("Claim not found")
    changes = {k: v for k, v in a.items() if k in ("text", "source_ids", "location", "kind")}
    if not changes:
        raise ValueError("Supply claim changes")
    known = {s["id"] for s in p["sources"]}
    if any(s not in known for s in changes.get("source_ids", [])):
        raise ValueError("Unknown source IDs")
    previous = {k: claim.get(k) for k in changes}
    claim.update(changes)
    claim["updated_at"] = now()
    claim.setdefault("history", []).append({"at": now(), "previous": previous})
    save_project(p)
    return {"message": "Claim updated", "claim": claim}


def tool_audit(a):
    p = load_project(a["project_id"])
    d = p["research_design"]
    required = ["problem", "gap", "aim", "objectives", "questions", "methodology", "expected_contribution"]
    issues = [{"severity": "high", "area": x, "message": f"Research {x.replace('_', ' ')} is missing."}
              for x in required if not d.get(x)]
    unverified = [s["id"] for s in p["sources"] if not s.get("verified")]
    unsupported = [c["id"] for c in p["claims"]
                   if c.get("kind", "external") == "external" and not c.get("source_ids")]
    if unverified:
        issues.append({"severity": "medium", "area": "sources", "message": f"{len(unverified)} source(s) are not marked verified.", "ids": unverified})
    if unsupported:
        issues.append({"severity": "high", "area": "evidence", "message": f"{len(unsupported)} external claim(s) lack sources.", "ids": unsupported})
    if not p["sources"]:
        issues.append({"severity": "high", "area": "literature", "message": "No scholarly sources are recorded."})
    return {"project_id": p["id"], "passed": not issues, "scope": "structure_and_recorded_flags_only", "issues": issues,
            "main_text_words": tool_dashboard(a)["words"],
            "word_budget_met": tool_dashboard(a)["words"] >= p["target_words"],
            "note": "This structural audit supports, but does not replace, expert academic review."}


def tool_export(a):
    p = load_project(a["project_id"])
    filename = a.get("filename") or "thesis.md"
    if filename in (".", "..") or any(c in filename for c in ("/", "\\", "\0")) or Path(filename).name != filename:
        raise ValueError("Export filename must be a plain filename")
    out = project_path(p["id"]).parent / filename
    if out.is_symlink():
        raise ValueError("Export cannot replace a symbolic link")
    if out.suffix.lower() != ".md":
        out = out.with_suffix(".md")
    lines = [f"# {p['title']}", "", f"**Degree:** {p['degree']}", f"**Language:** {p['language']}", ""]
    for ch in p["chapters"]:
        if not ch.get("sections"):
            continue
        lines += [f"# Chapter {ch['number']}: {ch['title']}", ""]
        for title, sec in ch.get("sections", {}).items():
            lines += [f"## {title}", "", sec.get("content", ""), ""]
    if p["sources"]:
        lines += ["# Recorded source ledger", "", "Recorded citations and verification flags; not an automatically formatted bibliography.", ""]
        for source in p["sources"]:
            state = "marked verified" if source.get("verified") else "unverified"
            lines += [f"- {source['id']}: {source['citation']} ({state})", source.get("url_or_doi", ""), ""]
    atomic_write(out, "\n".join(lines))
    counts = tool_dashboard({"project_id": p["id"]})
    return {"message": "Markdown manuscript exported", "path": str(out), "word_count": words("\n".join(lines)), "main_text_words": counts["words"], "reference_words": counts["reference_words"], "total_section_words": counts["total_section_words"]}


TOOLS = {
    "reconcile_evidence_map": (tool_reconcile_map, {"title": "Reconcile evidence map", "description": "Preview literal passage reconciliation. Apply requires the preview project hash. Changed notes are archived, not silently attached to new claims. Manuscript and PDF are unchanged.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "apply": {"type": "boolean"}, "expected_sha256": {"type": "string"}}, "required": ["project_id"]}}),
    "update_source": (tool_update_source, {"title": "Correct and verify a source", "description": "Update an existing source with a checked citation, recorded verification notes and retained history. Changed citation/URL invalidates the prior verification flag unless explicitly reverified.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "source_id": {"type": "string"}, "citation": {"type": "string"}, "url_or_doi": {"type": "string"}, "type": {"type": "string"}, "verified": {"type": "boolean"}, "notes": {"type": "string"}}, "required": ["project_id", "source_id"]}}),
    "update_claim": (tool_update_claim, {"title": "Correct a claim and its evidence links", "description": "Update an existing claim, validate source IDs and retain previous values.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "claim_id": {"type": "string"}, "text": {"type": "string"}, "source_ids": {"type": "array", "items": {"type": "string"}}, "location": {"type": "string"}, "kind": {"type": "string", "enum": ["external", "interpretation", "original contribution"]}}, "required": ["project_id", "claim_id"]}}),
    "create_project": (tool_create, {"title": "Create thesis project", "description": "Start a Master's or PhD thesis from a title; no imported file is required.", "inputSchema": {"type": "object", "properties": {"title": {"type": "string"}, "degree": {"type": "string", "enum": ["PhD", "Master's"]}, "discipline": {"type": "string"}, "target_words": {"type": "integer", "minimum": 5000}, "language": {"type": "string"}, "citation_style": {"type": "string"}}, "required": ["title"]}}),
    "list_projects": (tool_list, {"title": "List thesis projects", "description": "List locally stored ThesisPRO projects.", "inputSchema": {"type": "object", "properties": {}}}),
    "get_dashboard": (tool_dashboard, {"title": "Show thesis dashboard", "description": "Show topic, progress, structure, evidence status, and the clearest next action.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}}, "required": ["project_id"]}}),
    "update_research_design": (tool_design, {"title": "Update research foundation", "description": "Store the thesis problem, gap, aim, objectives, questions, theory, method, scope, ethics, and contribution.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "fields": {"type": "object"}}, "required": ["project_id", "fields"]}}),
    "save_section": (tool_save_section, {"title": "Save chapter section", "description": "Save or replace a thesis section in persistent project memory.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "chapter": {"type": "integer"}, "section_title": {"type": "string"}, "content": {"type": "string"}, "status": {"type": "string", "enum": ["outline", "draft", "reviewed", "approved"]}}, "required": ["project_id", "chapter", "section_title", "content"]}}),
    "get_section": (tool_get_section, {"title": "Read chapter or section", "description": "Retrieve a full chapter record or one named section.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "chapter": {"type": "integer"}, "section_title": {"type": "string"}}, "required": ["project_id", "chapter"]}}),
    "add_source": (tool_add_source, {"title": "Record scholarly source", "description": "Add a verified or provisional citation to the project's evidence library.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "citation": {"type": "string"}, "url_or_doi": {"type": "string"}, "type": {"type": "string"}, "verified": {"type": "boolean"}, "notes": {"type": "string"}}, "required": ["project_id", "citation"]}}),
    "add_claim": (tool_add_claim, {"title": "Link claim to evidence", "description": "Record an important claim and the source IDs that support it.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "claim": {"type": "string"}, "source_ids": {"type": "array", "items": {"type": "string"}}, "location": {"type": "string"}, "kind": {"type": "string", "enum": ["external", "interpretation", "original contribution"]}}, "required": ["project_id", "claim"]}}),
    "audit_project": (tool_audit, {"title": "Audit academic integrity", "description": "Check research-foundation completeness, unverified sources, and unsupported claims.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}}, "required": ["project_id"]}}),
    "export_markdown": (tool_export, {"title": "Export manuscript", "description": "Compile all stored sections into a Markdown manuscript.", "inputSchema": {"type": "object", "properties": {"project_id": {"type": "string"}, "filename": {"type": "string"}}, "required": ["project_id"]}})
}


def result(value):
    return {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False, indent=2)}], "structuredContent": value}


def handle(request):
    method = request.get("method")
    if method == "initialize":
        return {"protocolVersion": request.get("params", {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}}, "serverInfo": {"name": "thesis-pro", "version": "0.3.0"}}
    if method == "notifications/initialized":
        return None
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [{"name": name, **spec} for name, (_fn, spec) in TOOLS.items()]}
    if method == "tools/call":
        params = request.get("params", {})
        name = params.get("name")
        if name not in TOOLS:
            raise ValueError(f"Unknown tool: {name}")
        args = params.get("arguments", {})
        schema = TOOLS[name][1]["inputSchema"]
        if not isinstance(args, dict):
            raise ValueError("Arguments must be an object")
        for field in schema.get("required", []):
            if field not in args:
                raise ValueError("Missing argument: " + field)
        types = {"string": str, "integer": int, "boolean": bool, "array": list, "object": dict}
        for key, value in args.items():
            rule = schema["properties"].get(key)
            if rule is None:
                raise ValueError("Unknown argument: " + key)
            if not isinstance(value, types[rule["type"]]) or (rule["type"] == "integer" and isinstance(value, bool)):
                raise ValueError("Invalid argument type: " + key)
            if "enum" in rule and value not in rule["enum"]:
                raise ValueError("Invalid argument value: " + key)
            if "minimum" in rule and value < rule["minimum"]:
                raise ValueError("Argument below minimum: " + key)
            if rule["type"] == "array" and any(not isinstance(item, str) for item in value):
                raise ValueError("Array items must be strings: " + key)
        return result(TOOLS[name][0](args))
    raise ValueError(f"Unsupported method: {method}")


def main():
    for line in sys.stdin:
        try:
            req = json.loads(line)
            response = handle(req)
            if "id" in req and response is not None:
                print(json.dumps({"jsonrpc": "2.0", "id": req["id"], "result": response}, ensure_ascii=False), flush=True)
        except Exception as exc:
            rid = req.get("id") if "req" in locals() and isinstance(req, dict) else None
            if rid is not None:
                print(json.dumps({"jsonrpc": "2.0", "id": rid, "error": {"code": -32000, "message": str(exc)}}), flush=True)


if __name__ == "__main__":
    main()
