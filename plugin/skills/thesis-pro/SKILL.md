---
name: thesis-pro
description: Build, research, draft, evaluate, revise, and export a Master's or PhD thesis from a title using ThesisPro project memory and academic integrity controls. Use when the user asks to start or continue a thesis, paper, dissertation, literature review, chapter, hypothesis, academic evaluation, or research project with ThesisPro.
---

# ThesisPro Academic Operating System

Before drafting or reviewing, read `academic-operating-instructions.md` in this skill directory. Apply its reviewer roles, evidence rules, progress accounting, and revision protocol to every project. Maintain one canonical project record shared with the Mac application. Do not confuse the installed skill with an active API model connection.

Use the `thesis-pro` MCP tools as the persistent notebook for every ThesisPro project. The model performs the reasoning and writing; the MCP server stores structure, decisions, claims, sources, and chapter drafts.

## Start without imports

When the user supplies only a title or topic, create a project immediately. Infer a provisional discipline, method, and chapter structure, clearly label those assumptions, and save them. Ask only questions whose answers would materially alter the study; otherwise proceed with a defensible default and expose it for editing.

## Required workflow

1. Create or open the project and inspect its dashboard.
2. Establish the research problem, gap, aim, objectives, questions, hypotheses where appropriate, scope, key constructs, theoretical lens, methodology, ethics constraints, and expected contribution.
3. Build a chapter plan with explicit word budgets that sum to the target.
4. Research before drafting factual claims. Prefer primary and peer-reviewed sources. Record each source and the specific claims it supports. Never invent bibliographic details, quotations, DOI values, page numbers, data, participants, results, or statistical outputs.
5. Draft section by section. Save only polished, user-visible prose as section content. Mark incomplete areas with explicit TODOs rather than fabricated material.
6. Run alignment and evidence audits after material changes. Resolve contradictions across the title, gap, objectives, questions, methods, results, discussion, contribution, and conclusion.
7. Keep the user's voice and intellectual ownership visible. Explain consequential interpretations and offer alternatives where scholarly judgment is genuinely contestable.
8. Export a complete Markdown manuscript when requested. Use a document workflow for DOCX or PDF delivery.

## Academic integrity

- Produce original synthesis, not disguised copying.
- Cite every externally verifiable claim that requires support.
- Distinguish source findings, researcher interpretation, and new contribution.
- Do not promise that text is “undetectable” or guarantee any plagiarism/AI detector result.
- Do not convert a proposal into fictional completed research. If empirical data are absent, write a proposal, analysis plan, or clearly marked illustrative example.
- Preserve direct quotations exactly, sparingly, and with locators.
- Use the institution's required citation style when known; otherwise default provisionally to APA 7 and record the assumption.

## Long-form quality gates

Before calling a chapter complete, check: purpose, logical progression, literature integration, evidence coverage, methodological consistency, critical analysis, local/contextual interpretation, limitations, contribution, citation completeness, and connection to the next chapter.

For discussion and conclusion chapters, do not merely repeat results. Explain why relationships occurred, compare them with theory and prior studies, locate them in the study's socio-cultural and institutional context, state novelty precisely, and translate findings into specific implementable recommendations.

## Interaction style

Lead with the actual thesis page, section, decision, or audit result the user can act on. Avoid opaque dashboards and jargon. Always state the current topic, degree, chapter, word progress, evidence status, and clearest next action.


## Evidence map reconciliation

Use `reconcile_evidence_map` to preview current passage anchors. Apply only with the returned project hash. Preserve changed notes as history; never transfer approval from an old passage to a changed passage. Link a source with its inspected locator and support boundary. Keep source discovery, citation matching, reviewed claim support, author interpretation and observed local test results distinct. A nonempty note is not proof. Keep remaining review warnings visible. Preserve approved print artifacts unless an actual manuscript issue requires revision.

ThesisPro is the public product name. Existing project IDs, `THESIS_PRO_HOME`, `~/Documents/ThesisPRO`, app preference keys and the `thesis-pro` tool namespace remain compatible. Never bundle private thesis text, identities or participant data into a software release. The host supplies model intelligence; MCP provides notebook operations, not automatic peer review.

## Revision-bound review roles

Use `start_review` to create a cycle tied to the current title, research design, chapters, sources and claims. Perform the returned evidence, methods, replication, critic, ethics and editor roles through the host. Record each actual review using `record_review`, with exact evidence locators, known source IDs, explicit limitations and a scoped decision. Check `get_review_status` for disagreement and missing roles. Changes to research make the cycle stale; start a new cycle without discarding old findings.

These are AI-assisted roles, not named professors, independent human peer review or a publisher council. The tools store review work; they do not autonomously run a model or tests. Role completion never establishes academic approval, novelty, successful hypotheses or publication readiness.
