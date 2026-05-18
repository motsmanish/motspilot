# Requirements — `csv-export-reports-listing`

**Task:** `csv-export-reports-listing`
**Created:** 2026-05-18
**Status:** completed (synthetic example)

---

## User-supplied description

> Add a "Download CSV" button to the reports listing page. The export should respect whatever filters and sort order the user has applied, only include reports the user is authorized to see, cap at 10,000 rows, and include a timestamp in the filename.

## Clarifications captured during /mots:init confirmation

- **Framework:** CakePHP 4.5
- **Reports listing route:** `GET /reports` (existing — handled by `ReportsController::index()`)
- **Existing filters on the page:** status (open/closed/archived), owner_id (defaults to current user, admin can override), created_at date range
- **Existing sort options:** title asc/desc, created_at asc/desc, status
- **Auth:** CakePHP `Authentication` plugin (session-based)
- **Authorization:** `cakephp/authorization` plugin, policy at `src/Policy/ReportPolicy.php`
- **Filename format desired:** `reports-{YYYY-MM-DD-HHMM}.csv` (server timezone)
- **Edge case from user:** "if there are zero matching rows, still download a CSV with just the header row — don't 404 or redirect"

## Out of scope (asked-and-rejected)

- Excel (.xlsx) export — user wants CSV only for now; Excel is a separate task.
- Background export for >10,000 rows with email-on-complete — defer; the 10k cap is intentional.
- Custom column selection — every row exports all visible columns.

## Acceptance criteria

1. A "Download CSV" button visible on `/reports` for any authenticated user who can see the listing.
2. Clicking it triggers a CSV download with `Content-Disposition: attachment; filename="reports-2026-05-18-1342.csv"` (filename timestamp matches server clock).
3. The CSV contains a header row matching the visible columns: `id, title, status, owner_email, created_at, updated_at`.
4. Rows respect the active filter state and sort order from the listing.
5. Rows respect the existing authorization policy — a user must not see rows in the CSV they wouldn't see in the table.
6. If the matched set exceeds 10,000 rows, the CSV contains the first 10,000 (per the active sort), and a flash message warns the user a cap was applied.
7. Empty matched set → CSV with just the header row, HTTP 200.
8. Existing `/reports` listing page behavior is unchanged when the button is not clicked.
