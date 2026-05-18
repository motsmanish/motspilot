# Consensus synthesis — `csv-export-reports-listing`

**Models fanned out:** Claude Sonnet 4.6, GPT-4o, Gemini 1.5 Pro
**Judge:** Claude Sonnet 4.6 (3-pass: Extract → Reconcile → Synthesize)
**Mode:** `session` — Claude's three consensus roles ran via Task subagents from session quota

---

## Section 1 — Agreed approach

All three models converged on:

- Add a new action `ReportsController::export()` mapped to `GET /reports/export.csv`.
- Reuse the existing filter / sort parsing from `ReportsController::index()` so the export inherits whatever query the user is looking at. Extract that parser into a private method to avoid duplication.
- Stream the CSV (`fputcsv` to `php://output` or equivalent) — don't accumulate in memory.
- Enforce row cap at query level (`LIMIT 10000`), not after fetch, so the DB doesn't materialize 50,000 rows just to throw 40,000 away.
- Filename: `reports-{YYYY-MM-DD-HHMM}.csv` using `FrozenTime::now()->format('Y-m-d-Hi')` in the server's configured timezone.
- Reuse the existing `ReportPolicy::scope()` query modification rather than filtering rows in PHP.

## Section 2 — Agreed risks

Three risks surfaced by ≥2 models:

- **R1. Auth bypass via direct URL.** A user could craft `GET /reports/export.csv?owner_id=999&...` to attempt to dump someone else's reports. Mitigation: the `ReportPolicy::scope()` query modifier must be applied identically to the export query. Test must exercise this through the real auth middleware, not a unit test.
- **R2. Memory blowup if streaming is skipped.** A naive implementation accumulating all 10,000 rows + their CSV-encoded form in memory before sending could OOM under concurrent requests. Mitigation: chunk-stream via `fputcsv` to `php://output` after `Content-Type` headers are sent. Test: confirm peak memory stays bounded.
- **R3. CSV injection (formula injection).** If a report title starts with `=`, `+`, `-`, or `@`, Excel interprets the cell as a formula on open. Mitigation: prefix any such cell value with a `'` (apostrophe) before writing.

## Section 3 — Split decisions (auto-resolved by majority)

**Split S1:** Where to put the row-cap constant.
- Claude: `src/Controller/ReportsController.php` as a class constant.
- GPT-4o: extract to `config/app_local.php` so ops can tune it.
- Gemini: there's already a `BoundedRowLimit::DEFAULT` constant at `src/Domain/BoundedRowLimit.php` used by two other exports — reuse it.

**Resolution (majority — Gemini's option wins, Claude agrees on review):** Reuse `BoundedRowLimit::DEFAULT`. Verification phase should grep to confirm the constant exists at the cited path. If it doesn't, fall back to the GPT-4o option.

## Section 4 — Unique insights

Each model contributed one insight not covered by the others:

- **Claude:** Mention the empty-set requirement explicitly in the architecture phase — the controller must emit `Content-Type: text/csv` and the header row even when the result set is empty, not return 204 or redirect. Architecture should encode this as a separate code path or an explicit "no special case needed if streaming starts with the header" note.
- **GPT-4o:** The `Content-Disposition` filename should be quoted (`filename="reports-2026-05-18-1342.csv"`) to handle filename characters safely across browsers. Use `Content-Disposition: attachment; filename*=UTF-8''...` for full RFC 5987 compliance if internationalized filenames matter (they don't here, but flag).
- **Gemini:** The CSRF middleware in CakePHP's default skeleton only applies to POST/PUT/DELETE — a GET request to `/reports/export.csv` doesn't need CSRF tokens, but flag for verification that no global middleware unexpectedly requires one.

## Section 5 — Open questions for architecture

- Does the listing page currently use `ReportsTable::find('forIndex')` (a custom finder)? If yes, the export should call the same finder. The architecture phase should confirm by reading `src/Model/Table/ReportsTable.php`.
- Where does the flash message live in the layout — top of body, alert region, or floating toast? The development phase should match the existing convention.

## Section 6 — Scope guard

The user explicitly excluded: Excel export, background queueing, custom column selection. Architecture and development must NOT add any of these. If a finding suggests one of them as a "small addition," it's a scope creep — reject.

## Section 7 — Recommended phase model routing

- Architecture: `opus` (default — design trade-offs around controller-action-vs-dedicated-controller, route placement, finder reuse)
- Development: `sonnet`
- Testing: `sonnet`
- Verification: `sonnet` (auth-policy enforcement is a known pattern; no novel reasoning)
- Delivery: `sonnet`

## Section 8 — Synthesis confidence

- High confidence on R1 (auth) and R2 (streaming) — all three models named these as primary risks.
- Medium confidence on R3 (CSV injection) — Claude and GPT-4o flagged it; Gemini did not. Verification should still enforce the apostrophe-prefix rule.
- High confidence on S1 resolution (reuse `BoundedRowLimit::DEFAULT`) — but architecture must verify the constant exists at the cited path.

## Section 9 — Hand-off to architecture

Architecture phase should:

1. Read `src/Controller/ReportsController.php` lines covering `index()` action and its filter parsing.
2. Read `src/Model/Table/ReportsTable.php` to confirm finder name used by the listing.
3. Read `src/Policy/ReportPolicy.php` for the `scope()` method that filters viewable rows.
4. Grep for `BoundedRowLimit` to confirm S1's referenced constant.
5. Decide route: `GET /reports/export.csv` (new) vs `GET /reports.csv` (REST-style via `_ext`). State the trade-off; pick one.
6. Decide where the auth-policy-must-also-apply-to-export check fires (controller `beforeFilter`, action body, or middleware). State the trade-off; pick one.
