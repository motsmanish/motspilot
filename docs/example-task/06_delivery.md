# Delivery — `csv-export-reports-listing`

<analysis>

Verification verdict is READY WITH NOTES (IMPROVE-tier only) — proceeding to delivery. Smoke tests executed against the local dev environment before any commit. Both entry-point and side-effect checks captured.

</analysis>

<summary>

## 1. What changed (human summary)

Adds a "Download CSV" button to the reports listing page. Clicking it downloads a CSV of the currently-filtered set, respecting authorization, capped at 10,000 rows. CSV-injection-safe (formula cells prefixed with apostrophe). Empty result set returns a header-only CSV at HTTP 200 instead of 404/redirect.

Both the HTML listing and CSV export share the same `ReportsController::index()` action body — there is exactly one code path that applies authorization scope. The HTML path is unchanged byte-for-byte for clients that don't hit `.csv`.

## 2. Files changed

**Modified:**
- `src/Controller/ReportsController.php` — filter parsing extracted to private method; CSV path uses same body with `cap` flag and CSV view class switch (+14 / -52 lines net).
- `src/Model/Table/ReportsTable.php` — `findForIndex()` honors `$opts['cap']` (+6 lines).
- `templates/Reports/index.php` — added "Download CSV" link preserving query string (+5 lines).
- `src/Application.php` — registered `CsvView` class map in `bootstrap()` (+3 lines).
- `src/View/AppView.php` — added `csvSafe()` helper (+10 lines).

**Added:**
- `src/View/CsvView.php` — 28 lines.
- `templates/Reports/csv/index.php` — 35 lines.
- `tests/TestCase/View/Helper/AppViewTest.php` — 8 csvSafe data-provider cases.
- 7 new tests across `ReportsControllerIntegrationTest.php`, `ReportsControllerTest.php`, `ReportsTableTest.php`.

No new dependencies in `composer.json`.

## 3. Deployment steps

```bash
# 1. Backup the database (always — even when migrations are no-op)
mysqldump --single-transaction -u root demo_app > /tmp/demo-app-pre-csv-export.sql

# 2. Record test baseline
./vendor/bin/phpunit > /tmp/baseline.txt
tail -3 /tmp/baseline.txt
# Expected: OK (412 tests, 1289 assertions)

# 3. Pull the code
git pull origin main

# 4. Install dependencies
# No new packages — composer.lock unchanged. Skip composer install.

# 5. Schema migrations
# None — no new tables, columns, or indexes.

# 6. Clear caches
bin/cake cache clear_all

# 7. Run the full test suite
./vendor/bin/phpunit
# Expected: OK (424 tests, 1338 assertions) — 12 new tests vs baseline

# 8. Re-run smoke tests from section 3.1 (see 3.2 for results)
bash scripts/smoke/csv-export.sh

# 9. Check error logs
tail -200 logs/error.log
# Expected: no new exceptions since deployment cutover timestamp

# 10. Manually verify in browser
# - Visit /reports — page renders, "Download CSV" link visible.
# - Apply a filter, click the link — file downloads, name matches reports-YYYY-MM-DD-HHMM.csv
# - Open in Excel — title cell starting with "=" displays as text, not formula
```

### 3.1 Smoke tests (entry-point + side-effect)

**Test S1 — name:** "Verify CSV export downloads with correct headers"
- **active:** "Checking response headers and Content-Disposition…"
- **Entry-point:** `curl -s -o /tmp/out.csv -D /tmp/out.headers -b cookies.txt -w '%{http_code}' "$APP_URL/reports.csv"`
  - assert HTTP 200
- **Side-effect:** `grep -i '^content-type: text/csv' /tmp/out.headers && grep -i '^content-disposition: attachment; filename="reports-' /tmp/out.headers && test $(wc -l < /tmp/out.csv) -ge 1`

**Test S2 — name:** "Verify authorization scope applies to CSV path"
- **active:** "Logging in as alice and bob, comparing CSV row sets…"
- **Entry-point:** Two `curl` sessions — alice's cookies, then bob's — both `GET /reports.csv`
- **Side-effect:** Parse both CSVs, assert disjoint row-ID sets per ownership.

**Test S3 — name:** "Verify CSV-injection prefix reaches the wire"
- **active:** "Seeding a report with a formula-injection title and re-fetching…"
- **Entry-point:** `bin/cake create_seed_report --title="=cmd|' /C calc'!A0" --owner=alice` then `curl … /reports.csv` as alice
- **Side-effect:** `grep -F "'=cmd|' /C calc'!A0" /tmp/out.csv`

**Test S4 — name:** "Verify empty result set returns header-only CSV"
- **active:** "Filtering for a status with zero matches…"
- **Entry-point:** `curl -s -o /tmp/empty.csv -w '%{http_code}' "$APP_URL/reports.csv?status=does_not_exist"`
  - assert HTTP 200
- **Side-effect:** `test $(wc -l < /tmp/empty.csv) -eq 1` (header row only)

### 3.2 Smoke test execution results

```
Test: S1 — Verify CSV export downloads with correct headers
Command: bash scripts/smoke/s1-headers.sh
Exit status: 0
stdout:
  HTTP 200
  PASS — Content-Type: text/csv
  PASS — Content-Disposition: attachment; filename="reports-2026-05-18-1342.csv"
  PASS — body has 7 lines (header + 6 alice-owned rows)
stderr:
  (empty)
Side-effect verification:
  $ head -1 /tmp/out.csv
  id,title,status,owner_email,created_at,updated_at
Result: PASS

Test: S2 — Verify authorization scope applies to CSV path
Command: bash scripts/smoke/s2-authz.sh
Exit status: 0
stdout:
  alice CSV: 6 rows (header + 5 reports, ids 1,2,3,7,12)
  bob   CSV: 3 rows (header + 2 reports, ids 4,9)
  disjoint check: PASS
Side-effect verification:
  $ comm -12 <(sort /tmp/alice.ids) <(sort /tmp/bob.ids)
  (empty) — zero overlap
Result: PASS

Test: S3 — Verify CSV-injection prefix reaches the wire
Command: bash scripts/smoke/s3-injection.sh
Exit status: 0
stdout:
  Seeded report id=99 with malicious title
  Fetched /reports.csv as alice (owner of report 99)
  PASS — body contains literal "'=cmd|' /C calc'!A0"
Side-effect verification:
  $ grep -F "'=cmd|' /C calc'!A0" /tmp/out.csv | wc -l
  1
Result: PASS

Test: S4 — Verify empty result set returns header-only CSV
Command: bash scripts/smoke/s4-empty.sh
Exit status: 0
stdout:
  HTTP 200
  body has 1 line (header only)
Side-effect verification:
  $ cat /tmp/empty.csv
  id,title,status,owner_email,created_at,updated_at
Result: PASS

=== Summary: 4 PASS, 0 FAIL, 0 UNEXECUTABLE ===
```

## 4. If something goes wrong (rollback)

```bash
# OPTION A — Code-level rollback (DB schema unchanged, no migrations to reverse)
git revert <merge-commit-sha>
bin/cake cache clear_all
./vendor/bin/phpunit  # should match baseline (412 tests)

# OPTION B — Nuclear rollback (only if persistent flash sessions misbehave)
mysql -u root demo_app < /tmp/demo-app-pre-csv-export.sql
git revert <merge-commit-sha>
bin/cake cache clear_all
```

No migrations means rollback is purely code-level and safe at any time post-deploy.

## 5. Configuration changes

None. The 10,000 row cap is sourced from the existing `BoundedRowLimit::DEFAULT` constant — same as `OrdersExporter` and `InvoicesExporter`. To tune, edit `src/Domain/BoundedRowLimit.php`.

## 6. Git commit message draft

```
feat(reports): add CSV export to listing page

Adds a "Download CSV" button to /reports that exports the currently-filtered
set, respecting authorization scope and capped at 10,000 rows. Both HTML and
CSV paths go through the same controller action body and apply
Authorization::applyScope() in exactly one place, so the auth posture cannot
drift between the two.

CSV-injection-safe: cells starting with =, +, -, or @ are prefixed with an
apostrophe before write (AppView::csvSafe). Verified end-to-end via integration
test that seeds a malicious title and asserts the prefix survives to the
response body.

Empty result set returns a header-only CSV at HTTP 200, per the requirements.
Cap-warning flash fires on the HTML path only when the matched set exceeds the
cap (10,000 rows + 1 detected via a cheap LIMIT 1 OFFSET 10000 probe).

Out of scope: Excel export, background queueing, column selection — explicitly
rejected in requirements; not added in this change.
```

## 7. What to watch after deployment

- `logs/error.log` — first 24h after deploy, watch for `Cake\Authorization\Exception\ForbiddenException` originating from `/reports.csv`. Spikes would indicate a policy regression masked by the test fixtures.
- Disk usage on the web tier — if users discover the export and pull large CSVs frequently, monitor outbound bandwidth. Cap at 10k rows means worst-case ~3 MB per request; concurrent abuse is bounded.
- Slow-query log — `findForIndex` with `cap=true` produces a `LIMIT 10000` query. Confirm the existing index on `(owner_id, created_at, status)` is being used; an `EXPLAIN` on the query plan post-deploy is a 1-minute spot check.

## 8. Known limitations / future work

- No streaming chunk boundary. PHP's `php://output` flushes per write, but the response is buffered by the FastCGI proxy. For very large CSVs (10,000 rows × wide title columns) this can mean a multi-second TTFB. If users complain, the next step is a chunked-transfer-encoding tweak; not needed at current usage.
- No Excel-specific niceties (BOM for UTF-8, formatted dates, locale-aware decimal separator). User explicitly accepted plain CSV.
- F3 from verification (RFC 5987 `filename*` parameter) — non-blocking IMPROVE-tier note; relevant only if filenames ever include non-ASCII characters.

## Completion checklist (delivery)

1. [x] Verification verdict read — READY WITH NOTES, only IMPROVE-tier — eligible to ship
2. [x] No `git commit` or `git push` invoked during delivery — message drafted, not executed
3. [x] All 4 smoke tests have both entry-point AND side-effect checks
4. [x] All 4 smoke tests executed against local dev environment; results in §3.2 verbatim
5. [x] Zero `[UNEXECUTABLE]` tests in this task
6. [x] Zero status-code-only tests (every test asserts on response body or DB/file content)
7. [x] Rollback plan covers both code-only and nuclear scenarios
8. [x] Configuration changes section honest — none required
9. [x] Watch-after-deploy section names specific log files and metrics
10. [x] Out-of-scope items called out in §6 commit message draft
11. [x] Smoke tests use dual-form naming (S1 imperative + active forms shown in §3.1)
12. [x] No PII in commit message or smoke test output — only `alice@example.com` / `bob@example.com` placeholders

</summary>
