# Changes

## Development snapshot: native 2.1

* Added a bundled 13-direction showcase with separate personal-paper creation, preserving private libraries.
* Ported the V2 bookshelf, reading, evidence and navigation views.
* Added six host-operated review roles through start_review, record_review and get_review_status. Reports retain evidence scope, disagreements and revision history; no academic approval is inferred.
* Expanded public documentation and contribution guidance. No private manuscripts or recovered source publications are distributed.


## Unreleased counting repair

* Count main text by explicit chapter role or English/Malay back-matter heading, rather than assuming Chapter 6 contains references.
* Preserve read-only compatibility with legacy projects missing the optional discipline field.
* Added regression coverage for discussion in Chapter 6, references in Chapter 7, role overrides, Malay headings and unchanged legacy records. All 18 plugin tests passed through the supervised Python worker; installed stdio checks also passed.


## Native 0.8.0 / plugin 0.3.0

* Public branding changed to ThesisPro while preserving legacy data identifiers.
* Reconciliation archives changed passage records rather than transferring old approval.
* Source review states remain distinct from the presence of a note.
* Removed project-specific starter assertions and private demo manuscript from the app.
* MCP preview/apply reconciliation checks the inspected project hash and creates a backup.
* Added portable reconciliation tests, including changed text and project isolation.

The print manuscript is not part of the software release.
* Source revisions invalidate linked passage review states.
* Reference headings in English and Malay are excluded consistently from passage indexing.
