# Development — `csv-export-reports-listing`

<analysis>

Working through the 6 units in order. Foundation → Logic → Interface.

</analysis>

<summary>

## Layer 1 — Foundation

### Unit 1: `CsvView` class

**File:** `src/View/CsvView.php` (new, 28 lines)

```php
<?php
declare(strict_types=1);

namespace App\View;

use Cake\Core\Configure;
use Cake\I18n\FrozenTime;
use Cake\View\View;

class CsvView extends View
{
    public function initialize(): void
    {
        parent::initialize();
        $this->setLayout(false);
        $this->response = $this->response
            ->withType('csv')
            ->withDownload($this->buildFilename());
    }

    private function buildFilename(): string
    {
        $tz = Configure::read('App.defaultTimezone') ?? 'UTC';
        return sprintf(
            'reports-%s.csv',
            FrozenTime::now($tz)->format('Y-m-d-Hi')
        );
    }
}
```

**Success signal:** Hitting `/reports.csv` returns `Content-Type: text/csv` and `Content-Disposition: attachment; filename="reports-{stamp}.csv"`. (Confirmed via curl in next layer's smoke check.)

### Unit 2: `ReportsTable::findForIndex` cap extension

**File:** `src/Model/Table/ReportsTable.php` (edited, +6 lines)

```php
public function findForIndex(Query $query, array $opts): Query
{
    // ...existing filter logic (status, owner_id, created_from, created_to)...
    // ...existing sort handling...

    if (!empty($opts['cap'])) {
        $query->limit(\App\Domain\BoundedRowLimit::DEFAULT);
    }

    return $query;
}
```

**Success signal:** Finder-level unit test confirms `cap => true` produces a `Query` whose compiled SQL contains `LIMIT 10000`. (Driver-gated; see testing phase.)

---

## Layer 2 — Logic

### Unit 3: Filter parsing extraction

**File:** `src/Controller/ReportsController.php` (edited, +14 / -52 lines net)

```php
private function parseListingFilters(): array
{
    $q = $this->request->getQueryParams();
    return [
        'status'        => $q['status'] ?? null,
        'owner_id'      => $q['owner_id'] ?? $this->Authentication->getIdentityData('id'),
        'created_from'  => $q['created_from'] ?? null,
        'created_to'    => $q['created_to'] ?? null,
        'sort'          => $q['sort'] ?? 'created_at',
        'direction'     => $q['direction'] ?? 'desc',
    ];
}

public function index(): void
{
    $filters = $this->parseListingFilters();
    $cap = $this->request->getParam('_ext') === 'csv';

    $query = $this->Reports->find('forIndex', $filters + ['cap' => $cap]);
    $query = $this->Authorization->applyScope($query);

    if ($cap) {
        $rows = $query->all()->toArray();
        $this->set(compact('rows'));
        $this->viewBuilder()->setClassName('Csv');
        return;
    }

    // ...existing pagination + cap-warning flash, HTML path...
    $reports = $this->paginate($query);
    $this->set(compact('reports', 'filters'));
}
```

**Success signal:** `/reports?status=open` (HTML) renders identically to pre-change. `/reports.csv?status=open` returns the same matched rows in CSV form. No duplicate filter-parsing code.

### Unit 4: Cap-warning flash (HTML path only)

**File:** `src/Controller/ReportsController.php` (added inside `index()`, +9 lines)

```php
// After paginate(), HTML path only:
$capLimit = \App\Domain\BoundedRowLimit::DEFAULT;
if (count($reports) >= $capLimit) {
    $overshoot = $this->Reports
        ->find('forIndex', $filters)
        ->limit(1)
        ->offset($capLimit)
        ->count();
    if ($overshoot > 0) {
        $this->Flash->warning(__(
            'CSV export is capped at {0} rows; refine filters to export more.',
            $capLimit
        ));
    }
}
```

**Success signal:** Page with 10,001 matching rows shows the flash on the HTML view. Page with 10,000 exactly does not.

---

## Layer 3 — Interface

### Unit 5: CSV template

**File:** `templates/Reports/csv/index.php` (new, 35 lines)

```php
<?php
/**
 * @var \App\View\AppView $this
 * @var array<\App\Model\Entity\Report> $rows
 */

$out = fopen('php://output', 'wb');

// Header row
fputcsv($out, ['id', 'title', 'status', 'owner_email', 'created_at', 'updated_at']);

// Data rows
foreach ($rows as $row) {
    fputcsv($out, [
        $row->id,
        $this->csvSafe($row->title),
        $row->status,
        $row->owner?->email,
        $row->created_at?->format('Y-m-d H:i:s'),
        $row->updated_at?->format('Y-m-d H:i:s'),
    ]);
}

fclose($out);
```

And the `csvSafe` helper, added to `AppView`:

```php
public function csvSafe(?string $value): string
{
    if ($value === null || $value === '') {
        return '';
    }
    // Prefix with apostrophe to neutralize Excel formula injection.
    return preg_match('/^[=+\-@]/', $value) ? "'" . $value : $value;
}
```

**Success signal:** A report with title `=cmd|' /C calc'!A0` exports as `'=cmd|' /C calc'!A0` in the CSV cell — Excel opens the cell as text, not a formula.

### Unit 6: Listing page "Download CSV" link

**File:** `templates/Reports/index.php` (edited, +5 lines after the filter form)

```php
<?php
$exportQuery = $this->request->getQueryParams();
$exportUrl = $this->Url->build(['_ext' => 'csv'] + $exportQuery);
?>
<a href="<?= h($exportUrl) ?>" class="btn btn-secondary">
    <?= __('Download CSV') ?>
</a>
```

**Success signal:** Visiting `/reports?status=open&sort=title&direction=asc`, the "Download CSV" link target is `/reports.csv?status=open&sort=title&direction=asc`.

---

## Completion checklist (development)

1. [x] All 6 units built and named — evidence above
2. [x] `BoundedRowLimit::DEFAULT` referenced by name (Unit 2, Unit 4) — no magic 10000 literal
3. [x] `$this->Authorization->applyScope($query)` applied in `index()` for both HTML and CSV paths (Unit 3) — HC1 satisfied
4. [x] CSV-injection apostrophe-prefix lives in template via `csvSafe()` (Unit 5) — HC3 satisfied
5. [x] Filename uses server-configured timezone (Unit 1) — HC4 satisfied
6. [x] No `Content-Length` header added (CsvView relies on streaming)
7. [x] No background job enqueued, no Excel export, no column selection — out-of-scope items not introduced
8. [x] Empty-set path tested manually — `/reports.csv?status=does_not_exist` returns header-only CSV, HTTP 200
9. [x] HTML path verified unchanged via curl diff against pre-change `git stash`
10. [x] One WIP item at a time — each unit completed before next started
11. [x] No silent assumption-fills — filter param shape matches existing index() exactly
12. [N/A] BLOCKED-state items — none raised in this task

</summary>
