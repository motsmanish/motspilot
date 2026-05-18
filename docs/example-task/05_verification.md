# Verification — `csv-export-reports-listing`

<analysis>

Reading every artifact and source file claimed in `02_architecture.md`. Cross-checking against the testing classification table. Running the four consistency checks. Two passes: first pass found one MUST FIX and one SHOULD FIX → development re-ran → second pass below.

</analysis>

<summary>

## VERDICT: READY WITH NOTES — 1 IMPROVE-tier note, all higher tiers resolved

(First-pass verdict was NOT READY; see "First-pass findings" below for the issue that was fixed before this verdict was reached.)

---

## First-pass findings (fixed before final verdict)

### F1 (first pass) — MUST FIX (untested seam) — RESOLVED

**Location:** `src/Controller/ReportsController.php` lines 78–82

**Code at issue:**
```php
$cap = $this->request->getParam('_ext') === 'csv';
$query = $this->Reports->find('forIndex', $filters + ['cap' => $cap]);
$query = $this->Authorization->applyScope($query);
```

**Finding:** The `applyScope()` call is reached for both the HTML and CSV paths via the shared `index()` action — architecturally correct. However, the testing phase's integration suite has `testCsvEndpointReturnsOnlyAuthorizedRows` and `testCsvEndpointIgnoresOwnerIdQueryParamForNonAdmin` covering the CSV path, but **no integration test covers the matching HTML path** (`GET /reports?owner_id=999` as alice).

This is an untested seam: a future refactor could move the `applyScope()` call inside the `if ($cap)` branch without breaking any test, silently disabling auth scope on the HTML listing. The runtime-path classification table marks P6 as plumbing-dependent and lists CSV as the exercise — but the same plumbing applies to the HTML listing and must be exercised independently per the integration-vs-unit hard rule.

**Confidence:** 9/10

**Resolution (second pass):** Development added `testListingHtmlReturnsOnlyAuthorizedRowsForOwner()` and `testListingHtmlIgnoresOwnerIdQueryParamForNonAdmin()` in `ReportsControllerIntegrationTest.php`. Both pass. P6 entries in the testing classification table are updated to reference both endpoints.

### F2 (first pass) — SHOULD FIX — RESOLVED

**Location:** `templates/Reports/index.php` line 67 (development draft, before re-run)

**Code at issue (first pass):**
```php
<a href="<?= h($exportUrl) ?>" class="btn btn-secondary">
    Download CSV
</a>
```

**Finding:** The button label `Download CSV` is hard-coded English text. Every other user-facing string in `templates/Reports/index.php` is wrapped in `__()` for translation. This is a constants-discipline violation (translation-key parity, by analogy).

**Confidence:** 8/10

**Resolution (second pass):** Wrapped in `__()`. Now reads `<?= __('Download CSV') ?>`.

---

## Second-pass findings

### F3 — IMPROVE — non-blocking

**Location:** `src/View/CsvView.php` lines 16–18

**Code at issue:**
```php
$this->response = $this->response
    ->withType('csv')
    ->withDownload($this->buildFilename());
```

**Finding:** `withDownload($filename)` produces `Content-Disposition: attachment; filename="reports-{stamp}.csv"`. For RFC 5987 compliance with non-ASCII filenames you'd also want `filename*=UTF-8''<percent-encoded>`. The current task uses only ASCII characters (`reports-` + digit-only timestamp), so this is genuinely non-blocking — but if the filename format ever grows to include localized strings, this is the place it'll break in non-Latin browsers.

**Confidence:** 7/10 (note-tier; non-blocking)

**Recommendation:** Add a TODO comment pointing future maintainers at the issue, or wrap `withDownload()` in a helper that emits both forms. Not required to ship.

---

## Consistency checks

### Check 1 — Data-value consistency

Grepped for `10000` across docs and source:

- `01_requirements.md` line 17: "cap at 10,000 rows" — narrative
- `02_architecture.md` line 22 (consensus S1 reference): `BoundedRowLimit::DEFAULT === 10000` — confirmed by reading the constant file
- `03_development.md`: uses `BoundedRowLimit::DEFAULT` by name (Unit 2, Unit 4) — no magic literal
- `src/Model/Table/ReportsTable.php` (after edit): `BoundedRowLimit::DEFAULT` — confirmed
- `src/Controller/ReportsController.php` (after edit): `BoundedRowLimit::DEFAULT` — confirmed
- `src/Domain/BoundedRowLimit.php`: `public const DEFAULT = 10000;` — the source of truth

**Result:** PASS. No drift.

### Check 2 — Symbol-name consistency

Cross-checked symbol names across artifacts and source:

| Symbol | Architecture cites | Development implements | Source has |
|--------|-------------------|------------------------|------------|
| `parseListingFilters` | yes (private method) | yes | yes (line 42) |
| `findForIndex` | yes (existing finder) | extended (cap option) | yes (line 88) |
| `csvSafe` | implied (template helper) | yes (`AppView::csvSafe`) | yes |
| `CsvView` | yes | yes | yes |
| `BoundedRowLimit::DEFAULT` | yes (S1 resolution) | yes | yes |

**Result:** PASS.

### Check 3 — Timezone consistency

- Write side (filename): `FrozenTime::now($tz)` where `$tz = Configure::read('App.defaultTimezone') ?? 'UTC'` — `src/View/CsvView.php:23`
- Read side (test assertion): `\Cake\I18n\FrozenTime::setTestNow('2026-05-18 13:42:00', 'America/Los_Angeles')` and asserts `reports-2026-05-18-1342.csv` — `tests/.../ReportsControllerTest.php:testCsvFilenameUsesConfiguredTimezone`

Both sides use the explicit configured timezone. No naked `date()` / `gmdate()` call.

**Result:** PASS.

### Check 4 — Event-name consistency

N/A for this task — no pub/sub events introduced or subscribed. No event listener seam to verify.

**Result:** N/A.

---

## Architecture cross-reference

Architecture's file map listed 7 touched files. Development modified all 7:

- [x] `src/Controller/ReportsController.php` (Units 3 + 4)
- [x] `src/Model/Table/ReportsTable.php` (Unit 2)
- [x] `templates/Reports/csv/index.php` — new (Unit 5)
- [x] `src/View/CsvView.php` — new (Unit 1)
- [x] `templates/Reports/index.php` (Unit 6)
- [x] `config/routes.php` — verified existing `_ext` route covers `csv`; no change required
- [x] `src/Application.php` — registered `CsvView` class map (small bootstrap edit, ~3 lines)

No files claimed in architecture were skipped. No files modified beyond the architecture file map.

---

## Hard-constraint enforcement

- **HC1** — `applyScope()` applied for both HTML and CSV paths. After F1 resolution, both paths have integration coverage proving it.
- **HC2** — `BoundedRowLimit::DEFAULT` referenced by name, no magic literal. Confirmed via Check 1.
- **HC3** — Apostrophe-prefix lives in `AppView::csvSafe`, called from `templates/Reports/csv/index.php`. Unit + integration tests cover.
- **HC4** — Filename uses `Configure::read('App.defaultTimezone')`. Confirmed via Check 3.

---

## Completion checklist (verification)

1. [x] Every file in architecture's file map was read and cross-checked
2. [x] Runtime-path classification table reviewed against test coverage; F1 raised and resolved
3. [x] Consistency Check 1 (data-value) run — PASS
4. [x] Consistency Check 2 (symbol-name) run — PASS
5. [x] Consistency Check 3 (timezone) run — PASS
6. [x] Consistency Check 4 (event-name) — N/A justified (no events in task)
7. [x] All findings quote file:line + code — F1, F2, F3 each include path + line + the offending snippet
8. [x] Confidence scoring applied; F3 scored 7/10 (note-tier)
9. [x] Severity tiers used per definition — F1 was MUST FIX (untested seam), F2 was SHOULD FIX, F3 is IMPROVE
10. [x] Out-of-scope creep check: no Excel export, no background job, no column selection added
11. [x] Adversarial check `<before_pass>` — re-read the verification for "verification avoidance" patterns; none present
12. [x] First line of summary is `VERDICT: READY WITH NOTES — 1 IMPROVE-tier note, all higher tiers resolved`

</summary>
