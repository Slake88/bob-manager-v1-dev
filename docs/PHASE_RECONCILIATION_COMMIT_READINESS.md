# Commit readiness

## READY TO COMMIT

Scope: local evidence/tooling readiness only. No staging, commit, push, deployment or production access. rc1-rebuild remains at de53a2945d67653a8f41cb5939175ebaa9d0e6de.

## Blockers resolved

1. Structural drift: all three announcement INSERT fixtures now provide deterministic synthetic body text. Schema unchanged. Original 23502 reproduced; corrected negative and positive permission cases pass.
2. Snapshot: test_high_risk serialized runtime pg_proc trigger bodies verbatim, reintroducing a project endpoint. Pure sanitizeCatalog normalizes endpoint strings before evidence serialization and omits runtime capture clock/build metadata. Database definitions stay untouched. Existing https://<project-ref>.supabase.co placeholder is preserved. Two clean sequential runs and another isolated capture produce byte-identical snapshots; closure comparisons pass. Synthetic endpoint-variation assertion proves normalization does not require credentials.
3. Both reconciliation harnesses consumed the same historical argv[3] catalog. They now default to tools/fixtures/reconciliation_catalog.json, with explicit override retained. The frozen fixture contains schema metadata only, with six restore-required fields, no row data or runtime metadata, and sanitized URLs. Source and fixture SHA-256 and transformation provenance are adjacent. Current migrations cannot recreate the historical intermediate baseline without changing what these harnesses test, so the historical metadata is versioned as a fixed fixture. No external catalog required at runtime; both restores pass twice and in isolated reruns.

## Validation

18/18 original checks pass twice in order, including clean 154/154 migration replay with explicit local adapters. The two formerly omitted catalog harnesses also pass: 20/20 total per round. Five blocker-related isolated reruns pass. Full results and snapshot hashes: PHASE_RECONCILIATION_REPRODUCIBILITY_RESULTS.json.

Run in an isolated repository copy containing the base tracked tools/migrations plus the allowlist:

    node tools/run_reconciliation_suite.mjs <local-postgres-driver-entry>

Requires Node 24, postgres driver 3.4.9, native PostgreSQL on fixed 127.0.0.1:55440. The runner writes disposable databases and evidence only in that copy. No real Supabase credentials required. PostgreSQL extension adapters do not validate real Supabase services or external consumers.

Application SQL and preflight files remain byte-identical to the previous validation; only four existing harnesses and new test tooling/fixture changed. git diff --check and empty staging verified. Full candidate raw/decoded scans and manifest verification are recorded in the PII report. The manifest excludes its own hash and includes its byte size in the stable total.

Historical 275 medium F findings and 39 provenance gaps remain documented limitations outside these three blockers. Other retained historical reports describe previous runs; this decision and the new reproducibility report supersede their blocker status.

## Exact files changed this phase

- docs/PHASE_HIGH_RISK_LOCAL_SNAPSHOT.json
- docs/PHASE_RECONCILIATION_COMMIT_ALLOWLIST.txt
- docs/PHASE_RECONCILIATION_COMMIT_READINESS.md
- docs/PHASE_RECONCILIATION_FINAL_CLOSURE_MANIFEST.json
- docs/PHASE_RECONCILIATION_PII_SCAN_RESULTS.json
- docs/PHASE_RECONCILIATION_REPRODUCIBILITY_RESULTS.json
- tools/fixtures/reconciliation_catalog.json
- tools/fixtures/reconciliation_catalog.provenance.json
- tools/run_reconciliation_suite.mjs
- tools/sanitize_catalog.mjs
- tools/test_high_risk.mjs
- tools/test_reconciliation.mjs
- tools/test_reconciliation_final.mjs
- tools/test_structural_drift.mjs
