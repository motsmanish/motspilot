# Architecture — `csv-export-reports-listing`

<analysis>

## Files read during investigation

| File | Lines read | What was learned |
|------|-----------|------------------|
| `src/Controller/ReportsController.php` | 1–180 | `index()` action parses `status`, `owner_id`, `created_from`, `created_to`, `sort`, `direction` from query. Filter parser is inlined (lines 42–98). Calls `Reports::find('forIndex', $filters)`. |
| `src/Model/Table/ReportsTable.php` | 1–240 | Custom finder `findForIndex(Query $q, array $opts)` applies the filter array. Returns `Query`, not executed. |
| `src/Policy/ReportPolicy.php` | 1–60 | `scope(IdentityInterface $user, Query $query): Query` returns the query narrowed to rows the user can see. Already called from `ReportsController::index()` via `$this->Authorization->applyScope($query)`. |
| `src/Domain/BoundedRowLimit.php` | 1–35 | Class exists. `BoundedRowLimit::DEFAULT === 10000`. Used by `OrdersExporter` and `InvoicesExporter`. Reuse is correct per consensus S1. |
| `config/routes.php` | 1–140 | Routes scoped under `/` use `DashedRoute` class. `_ext` extension routing is enabled for `['csv', 'json']` on the resources scope. |
| `templates/Reports/index.php` | 1–95 | Flash messages render at top of `<div class="content">`, via `<?= $this->Flash->render() ?>`. Filters submit as `GET` to current path. |

## Trade-offs considered

**Route placement: `GET /reports/export.csv` vs `GET /reports.csv` (via `_ext`)**
- The `_ext` form is more idiomatic for CakePHP and works with the existing extension routing.
- The named-action form is more discoverable in route listings and decouples the export from any future REST-style JSON listing.
- **Picked:** `_ext` form — `GET /reports.csv` routed to `ReportsController::index()` with `$this->RequestHandler` switching the render. Reuses the `index()` action body for filter parsing; renders the CSV view instead of the HTML template. **Reasoning:** the consensus risk R1 (auth bypass via direct URL) is harder to introduce when both formats go through the same action and the same `applyScope()` call. A separate `export()` action means two places to maintain the auth posture.

**Where the row cap is enforced**
- Application of `LIMIT 10000` happens inside the `findForIndex` finder when `$opts['cap'] === true` is passed, not in the controller. Keeps the SQL boundary in one place.
- The flash-message "cap was applied" warning fires from the controller when it observes `count($rows) === 10000` AND a second query returns at least one more matching row. (Two queries — cheap, the second is just `LIMIT 1`.)

**Empty-set handling**
- No special branch. The CSV view template renders the header row unconditionally, then iterates `$rows`. Empty `$rows` → just the header. HTTP 200, `Content-Type: text/csv`, `Content-Disposition: attachment`.

</analysis>

<summary>

## Architecture summary

### File map

| Action | Path | Notes |
|--------|------|-------|
| EDIT | `src/Controller/ReportsController.php` | Extract filter parsing from `index()` into private `parseListingFilters(): array`. Pass `cap` flag to finder when serving CSV. Add cap-warning flash logic. |
| EDIT | `src/Model/Table/ReportsTable.php` | Extend `findForIndex(Query $q, array $opts)` to honor `$opts['cap']` by appending `->limit(BoundedRowLimit::DEFAULT)`. |
| NEW | `templates/Reports/csv/index.php` | CakePHP view template invoked when `_ext=csv`. Streams CSV via `$this->set('rows', $rows)` + `fputcsv`-loop. |
| NEW | `src/View/CsvView.php` | Lightweight `View` subclass setting `Content-Type: text/csv`. Templates live under `templates/Reports/csv/`. |
| EDIT | `templates/Reports/index.php` | Add "Download CSV" link with `?_ext=csv` query-string-preserved. |
| EDIT | `config/routes.php` | Confirm `_ext` route includes `csv` for the `/reports` scope. (Already does — verify only.) |
| EDIT | `src/Application.php` | Register `CsvView` with `ViewBuilder` for `csv` ext via the `addClassMap` hook in `bootstrap()`. |

### 6-unit decomposition

1. **Foundation — `CsvView` class** (`src/View/CsvView.php`). Sets `Content-Type` and `Content-Disposition` headers. No data logic.
2. **Foundation — `findForIndex` extension** (`src/Model/Table/ReportsTable.php`). Honor `$opts['cap']`. Verify with a finder-level unit test.
3. **Logic — controller filter extraction** (`src/Controller/ReportsController.php`). Extract `parseListingFilters()`; both HTML and CSV paths call it. No behavior change for HTML.
4. **Logic — controller cap-warning flash** (`src/Controller/ReportsController.php`). Only fires on the HTML path. Skipped for CSV since flash messages aren't visible in a downloaded file.
5. **Interface — CSV template** (`templates/Reports/csv/index.php`). Header row + `foreach` with `fputcsv` and the CSV-injection apostrophe-prefix on any cell starting with `=`, `+`, `-`, `@`.
6. **Interface — listing page "Download CSV" link** (`templates/Reports/index.php`). Builds `$this->Url->build(['_ext' => 'csv'] + $this->request->getQueryParams())`.

### Blast radius

- **`ReportsController::index()` body changes:** filter-parsing extraction has zero behavior change for HTML clients; cap-flag is only set on CSV path. HTML response is byte-identical.
- **`ReportsTable::findForIndex` changes:** the `cap` option is additive; existing callers (none in HTML path, since cap is only set from CSV) are unaffected.
- **Auth posture:** unchanged. `$this->Authorization->applyScope($query)` is already called inside `index()`. Since both HTML and CSV reuse the same action body, the auth scope applies identically. This is the main reason the architecture chose `_ext` over a separate action — fewer places for the policy to drift.
- **Flash messages:** HTML-path-only. CSV-path doesn't render layout, so flashes are unread (would be displayed on the next HTML page load). Cap warning is HTML-only.
- **Routes:** zero new entries. The `_ext` extension routing for `csv` already covers `/reports` scope.

### Hard constraints carried into development

- **HC1.** The CSV path MUST call `$this->Authorization->applyScope($query)` before fetching. If a refactor breaks this, verification will catch it via Check 4 (event-name consistency analogue: policy-applied check).
- **HC2.** `BoundedRowLimit::DEFAULT` MUST be referenced by name, not duplicated as a magic 10000 literal. Verification will grep.
- **HC3.** The CSV-injection apostrophe-prefix MUST be applied in the template, not the model. (Models stay format-agnostic; the injection threat is CSV/Excel-specific.)
- **HC4.** Filename timestamp MUST use the server-configured timezone (`Configure::read('App.defaultTimezone')`), not `gmdate()` or `date()` with implicit timezone.

### What development must NOT do

- Do NOT add `Content-Length` (streaming, length unknown until rows are fetched).
- Do NOT enqueue a background job. The cap of 10,000 keeps this synchronous on purpose.
- Do NOT add column-selection logic. Out of scope.
- Do NOT add Excel/.xlsx fallback. Out of scope.
- Do NOT skip the apostrophe-prefix because "Excel isn't our target audience" — CSVs end up in Excel for most users regardless.

### Completion checklist (architecture)

1. [x] Filter-parsing extraction location decided — `parseListingFilters()` private method
2. [x] Route mechanism decided — `_ext=csv` reusing `index()` action
3. [x] Row cap location decided — finder-level via `$opts['cap']`
4. [x] Empty-set handling decided — no special branch, header-row always written
5. [x] Auth posture verified — `applyScope()` already in `index()`; reuse path means single enforcement point
6. [x] CSV-injection mitigation decided — apostrophe-prefix in template
7. [x] Filename format decided — `reports-{Y-m-d-Hi}.csv` server timezone
8. [x] File map enumerated — 5 edits + 2 new files
9. [x] 6-unit decomposition produced
10. [x] Blast radius traced for each touched file
11. [x] Hard constraints (HC1–HC4) stated for development
12. [x] Out-of-scope items reasserted from consensus Section 6

</summary>
