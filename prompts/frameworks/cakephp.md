# CakePHP 4.x Framework Guide

This file is automatically included by the motspilot pipeline when `FRAMEWORK="cakephp"` is set in config. It provides framework-specific knowledge for all pipeline phases.

---

## Version Reference

**This guide is for CakePHP 4.x. Do NOT use CakePHP 5.x APIs.**

| What | CakePHP 4.x (correct) | CakePHP 5.x (WRONG — don't use) |
|------|----------------------|---------------------|
| Custom finder params | `(Query $query, array $options)` | `(SelectQuery $query)` |
| Query class | `Cake\ORM\Query` | `Cake\ORM\Query\SelectQuery` |
| Query ORDER BY | `->order(['col' => 'ASC'])` | `->orderBy()`, `->orderByAsc()`, `->orderByDesc()` |
| Query GROUP BY | `->group(['col'])` | `->groupBy()` (on Query — fine on Collection) |
| Query select extra | N/A | `->selectAlso()` |
| Table loading (controllers) | `$this->fetchTable('Name')` (4.3+) or `$this->getTableLocator()->get('Name')` | Only `$this->fetchTable()` |
| Auth | AuthComponent or Authentication plugin (check which the project uses) | Authentication plugin only |
| CSRF | `CsrfProtectionMiddleware` (cookie-based) | Also `SessionCsrfProtectionMiddleware` |
| Coding standard | PSR-2 | PSR-12 |
| Migrations | `Migrations\AbstractMigration` with `change()` (auto-reversible) | Same |

---

## Naming Conventions

- **Plural**: table names (`platform_packages`), controller classes (`PlatformPackagesController`), table classes (`PlatformPackagesTable`)
- **Singular**: entity classes (`PlatformPackage`)

---

## Files to Explore (Architecture Phase)

When exploring a CakePHP codebase, read these files like a detective:

```
src/Application.php          → What middleware? What plugins? How is auth wired?
config/routes.php             → What patterns? Prefix routing? RESTful? Slug-based?
src/Model/Table/              → ls this directory. Which tables exist? How are they named?
templates/layout/default.php  → What CSS framework? What's the navigation structure?
composer.json                 → PHP version? What packages? Any CakePHP plugins?
```

**Match what's already there:**
- If the project uses `$this->loadModel('Users')` everywhere, don't use `$this->fetchTable()`.
- If the project uses AuthComponent, don't introduce the Authentication plugin.
- If the project uses Bootstrap 4, don't write Tailwind.

---

## PHP File Header

Every PHP file starts with:
```php
<?php
declare(strict_types=1);
```

---

## Migration Patterns

Migration files use timestamp naming: `YYYYMMDDHHMMSS_DescriptiveName.php` (e.g., `20260327120000_AddStatusToOrders.php`). Use `bin/cake bake migration AddStatusToOrders` to generate with correct timestamp, or name manually if baking isn't available.

**One logical action per migration file.** Each migration should do exactly ONE thing:
- Creating a table → one migration
- Adding columns to an existing table → one migration
- Seeding/inserting data → one migration
- Adding an index → one migration

Never combine multiple unrelated changes (e.g., creating two different tables, or creating a table + seeding data) in a single migration. Small, focused migrations are easier to debug, rollback, and review.

**Other rules:**
- Use `change()` so CakePHP can auto-rollback. Only use `up()`/`down()` if you need custom rollback logic, and ALWAYS include the `down()`.
- New table: `$this->table('name')->addColumn(...)->create()`
- Add column to existing: `$this->table('name')->addColumn(...)->update()`
- Guard with `hasColumn()` / `hasTable()` checks before adding/removing — migrations should be idempotent.
- Index every column that appears in WHERE, JOIN, or ORDER BY.
- Foreign keys: verify the referenced table actually exists.

**After creating the migration:**
```bash
bin/cake migrations migrate
bin/cake migrations status
```
Verify it ran. Then:
```bash
bin/cake migrations rollback
bin/cake migrations status
```
Verify it rolled back cleanly. Then migrate again.

---

## Entity Patterns

### `$_accessible` — Mass assignment protection
Think through every field:
- `id` → false (auto-increment, never user-set)
- `role`, `is_admin`, `is_verified` → false (privilege escalation)
- `email`, `name`, `password` → true (user-editable fields)
- `created`, `modified` → omit (handled by Timestamp behavior)

**Never `'*' => true`. Never include `id`, `role`, `is_admin`.**

### `$_hidden` — Serialization protection
If this entity is serialized to JSON or displayed in debug, what should be invisible?
- Passwords, tokens, secrets → always hidden

### Virtual fields
Use `_getFieldName()` accessor methods.

---

## Table Class Patterns

Don't write custom finders speculatively. Write them as you need them in the service layer.

CakePHP 4.x finder signature (NOT 5.x):
```php
public function findActive(Query $query, array $options): Query
{
    return $query->where(['status' => 'active']);
}
```
Use `Cake\ORM\Query`, NOT `Cake\ORM\Query\SelectQuery`.

### Validation vs Rules

CakePHP separates these — don't confuse them:
- **`validationDefault()`** — Format and presence checks (required, maxLength, email format). Runs before save, operates on raw input. Put field-level validation here.
- **`buildRules()`** — Application/database rules (uniqueness, foreign key existence, custom business rules). Runs during save, has access to the entity. Put `isUnique`, `existsIn` here.

```php
// In Table class
public function validationDefault(Validator $validator): Validator
{
    $validator->requirePresence('email', 'create')
        ->notEmptyString('email')
        ->email('email');
    return $validator;
}

public function buildRules(RulesChecker $rules): RulesChecker
{
    $rules->add($rules->isUnique(['email']), ['errorField' => 'email', 'message' => 'Email already exists']);
    return $rules;
}
```

### Associations

When adding associations (`hasMany`, `belongsTo`, `hasOne`, `belongsToMany`):
- Match the existing association style in the Table class (inline in `initialize()` or separate methods)
- Set `'dependent' => true` on `hasMany`/`hasOne` if child records should be deleted when the parent is deleted
- Set `'cascadeCallbacks' => true` if the child entity has callbacks/behaviors that must fire on delete (slower — only when needed)
- Always verify the foreign key column exists before adding the association

### Query Containment

Use `->contain()` to eager-load associations and avoid N+1 queries:
```php
// Good: one query for orders + one for items
$orders = $this->Orders->find()->contain(['Items'])->all();

// Bad: N+1 — loads items separately for each order
$orders = $this->Orders->find()->all();
foreach ($orders as $order) {
    $items = $order->items; // lazy load = extra query per order
}
```

Only contain what you need. Deep containment (`contain(['Users.Roles.Permissions'])`) can generate expensive JOINs.

### Pagination

Controllers use `$this->paginate()` with settings defined as a property:
```php
// In controller
public $paginate = [
    'limit' => 25,
    'order' => ['created' => 'desc'],
    'contain' => ['Users'],
];

// In action
$results = $this->paginate($this->MyTable->find('active'));
$this->set(compact('results'));
```

Match the existing pagination style and limits in the project. Templates use `$this->Paginator->` helpers for links.

Validate in Table classes, not Controllers.

---

## Service Patterns

Put services in `src/Service/`.

A service method should read like a story of what happens:
```php
public function registerUser(array $data): User
{
    // 1. Does this email already exist?
    $existing = $this->usersTable->findByEmail($data['email'])->first();
    if ($existing) {
        throw new UserAlreadyExistsException($data['email']);
    }

    // 2. Create the user
    $user = $this->usersTable->newEntity($data);
    $savedUser = $this->usersTable->saveOrFail($user);

    // 3. Generate verification token
    $this->createVerificationToken($savedUser);

    return $savedUser;
}
```

**Services must NEVER touch:**
- `$this->request` (that's a controller concern)
- `$this->Flash` (that's a controller concern)
- `$this->redirect()` (that's a controller concern)

Use `LocatorAwareTrait` to access tables. Constructor loads table references. Methods throw domain-specific exceptions (not `\Exception`).

### Exception Handling

CakePHP exceptions auto-map to HTTP status codes — use them instead of manual error handling:
```php
use Cake\Http\Exception\NotFoundException;
use Cake\Http\Exception\ForbiddenException;
use Cake\Http\Exception\BadRequestException;

// In controller — these render the appropriate error page automatically
$order = $this->Orders->get($id); // Throws NotFoundException if not found
if ($order->user_id !== $userId) {
    throw new ForbiddenException('You do not have access to this resource.');
}
```

For service-layer errors, create domain-specific exceptions in `src/Exception/` and catch them in the controller to set flash messages + redirect.

---

## Controller Patterns

A controller action should be boring — get input, call service, respond:
```php
public function register(): ?\Cake\Http\Response
{
    $user = $this->Users->newEmptyEntity();

    if ($this->request->is('post')) {
        try {
            $user = $this->registrationService->register(
                $this->request->getData()
            );
            $this->Flash->success(__('Registration successful. Check your email.'));
            return $this->redirect(['action' => 'login']);
        } catch (UserAlreadyExistsException $e) {
            $this->Flash->error(__('That email is already registered.'));
        }
    }

    $this->set(compact('user'));
    return null;
}
```

- Actions return `?\Cake\Http\Response`
- Max 10-15 lines per action
- Use `$this->request->getData()`, never `$_POST`
- Use `$this->request->getQuery()`, never `$_GET`
- **NEVER put business logic in controller private methods.** No `_handleFoo()`, `_processFoo()`, or similar private methods that contain DB queries, entity saves, or status changes. That logic belongs in a Table class or Service class. Controllers should ONLY parse input, call Table/Service methods, and handle the response (flash, redirect, set view vars). If a POST handler needs complex logic, create a method on the relevant Table class (e.g., `$this->Orders->createCampaign($id, $data)`) and call it from the controller.

---

## Template Patterns

Assume every variable contains malicious HTML:
```php
<?= h($user->name) ?>              <!-- ALWAYS -->
<?= $user->name ?>                  <!-- NEVER -->
```

- Use `$this->Form->create($entity)` for ALL forms — handles CSRF automatically.
- Use `$this->Html->link()` for links.
- Use existing elements (`$this->element('sidebar')`) when they exist.
- Match the CSS framework and layout patterns already in the project.

---

## Email Template Patterns

**Always use a dedicated email template** — never hardcode HTML in Shell, Table, Entity, or Service files.

### Rules
- Create email templates in `templates/email/html/` (e.g., `email_hnc_budget_threshold.php`)
- Pass only the variables the template needs via the `vars` array — no pre-built HTML
- Use the same inline styling conventions as existing templates (explicit `color:#333333`, `font-size:13px`, `font-family:Montserrat,...`, `border-bottom:1px solid #dddddd`, etc.)
- Match the look and feel of existing email templates (e.g., `email_hnc_weekly_profitability.php`)

### Example — Correct (template approach)
```php
// In Shell/Service — send data, not HTML
sendEmail([
    'to' => readAppEmail('TEAM_EMAIL'),
    'subject' => __('Weekly Report - {0} items', $count),
    'template' => 'email_my_report',
    'vars' => [
        'hello' => 'Team',
        'rows' => $rows,
        'totalCount' => $count,
        'monthDisplay' => date('F Y'),
    ],
]);
```

```php
// In templates/email/html/email_my_report.php — all HTML lives here
<?php
$thStyle = 'padding:8px 10px;text-align:left;border-bottom:2px solid #333333;font-size:13px;color:#333333;white-space:nowrap;';
$tdStyle = 'padding:6px 10px;border-bottom:1px solid #dddddd;font-size:13px;color:#333333;white-space:nowrap;';
?>
<p style="color:#333333;margin:0 0 16px 0;">Report for <strong><?= h($monthDisplay) ?></strong></p>
<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;font-family:Montserrat,Helvetica,Arial,sans-serif;">
    <thead>
        <tr style="background-color:#f8f8f8;">
            <th style="<?= $thStyle ?>">Column</th>
        </tr>
    </thead>
    <tbody>
        <?php foreach ($rows as $i => $row): ?>
        <tr style="background-color:<?= ($i % 2 === 0) ? '#ffffff' : '#f9f9f9' ?>;">
            <td style="<?= $tdStyle ?>"><?= h($row['value']) ?></td>
        </tr>
        <?php endforeach; ?>
    </tbody>
</table>
```

### Example — Wrong (inline HTML in Shell)
```php
// DON'T do this — HTML does not belong in Shell/Table/Entity files
$body = '<table border="1"><tr><th>Order</th></tr>';
foreach ($rows as $row) {
    $body .= '<tr><td>' . $row['id'] . '</td></tr>';
}
$body .= '</table>';
sendEmail(['template' => 'dump', 'vars' => ['body' => $body]]);
```

### Reference templates
- `templates/email/html/email_hnc_weekly_profitability.php` — table report with totals row
- `templates/email/html/email_hnc_budget_threshold.php` — summary + data table
- `templates/layout/email/html/default_email_layout.php` — shared layout (header, footer, hello block)

---

## Console Command Patterns

CakePHP 4.x uses Console Commands (not the older Shell system, though legacy projects may still have Shells).

```php
// src/Command/SendReportCommand.php
<?php
declare(strict_types=1);

namespace App\Command;

use Cake\Command\Command;
use Cake\Console\Arguments;
use Cake\Console\ConsoleIo;
use Cake\Console\ConsoleOptionParser;

class SendReportCommand extends Command
{
    public function buildOptionParser(ConsoleOptionParser $parser): ConsoleOptionParser
    {
        $parser->addArgument('type', ['help' => 'Report type', 'required' => true]);
        $parser->addOption('dry-run', ['help' => 'Preview without sending', 'boolean' => true]);
        return $parser;
    }

    public function execute(Arguments $args, ConsoleIo $io): int
    {
        // Use services for business logic, not inline here
        $io->out('Report sent.');
        return static::CODE_SUCCESS;
    }
}
```

- Check whether the project uses Commands or legacy Shells — match the existing pattern
- Run with `bin/cake send_report weekly`
- Return `CODE_SUCCESS` (0) or `CODE_ERROR` (1) — never `exit()`
- Use `ConsoleIo` for output, not `echo`

---

## Date/Time Handling

CakePHP 4.x uses `Cake\I18n\FrozenTime` (immutable) — do NOT use PHP's native `DateTime`:
```php
use Cake\I18n\FrozenTime;

$now = FrozenTime::now();
$yesterday = FrozenTime::now()->subDays(1);
$formatted = $now->format('Y-m-d H:i:s');
$iso = $now->toIso8601String();
```

Database datetime columns are automatically hydrated as `FrozenTime` objects on entities. Use `->format()` in templates, not PHP's `date()`.

---

## Route Patterns

Read the existing routes file. Understand the patterns. Add yours at the end of the appropriate scope. Ask: "Could my route pattern accidentally match a URL that something else is supposed to handle?"

CakePHP uses DashedRoute by convention (kebab-case URLs).

---

## Test Patterns

### Test infrastructure
```bash
ls tests/Fixture/                    # What fixtures exist?
ls tests/TestCase/Controller/        # What test patterns?
```

### Integration tests
```php
use Cake\TestSuite\IntegrationTestTrait;
use Cake\TestSuite\TestCase;

class FeatureControllerTest extends TestCase
{
    use IntegrationTestTrait;

    protected $fixtures = [
        'app.Users',              // Existing — reuse
        'app.NewThings',          // New — you create this
    ];

    // Copy whatever auth setup pattern the project's existing tests use.
    private function loginAs(int $userId): void
    {
        $this->session(['Auth' => [
            'id' => $userId,
            // ... match existing session structure
        ]]);
    }

    public function testSomething(): void
    {
        $this->enableCsrfToken();
        $this->enableSecurityToken();
        // ...
    }
}
```

### Security test examples
```php
// Auth bypass
public function testProtectedRouteRedirectsWithoutLogin(): void
{
    $this->get('/protected-route');
    $this->assertRedirectContains('/login');
}

// CSRF bypass
public function testFormSubmitWithoutCsrfFails(): void
{
    $this->post('/register', ['email' => 'test@test.com']);
    $this->assertResponseCode(403);
}

// IDOR
public function testUserCannotViewOtherUsersProfile(): void
{
    $this->loginAs(1);
    $this->get('/users/view/2');
    // Should either 403 or redirect — NOT show user 2's data
}

// Mass assignment
public function testCannotSetRoleViaMassAssignment(): void
{
    $this->enableCsrfToken();
    $this->enableSecurityToken();
    $this->post('/register', [
        'email' => 'hacker@example.com',
        'password' => 'Test1234!',
        'role' => 'admin',
    ]);
    $user = $this->getTableLocator()->get('Users')
        ->find()->where(['email' => 'hacker@example.com'])->first();
    if ($user) {
        $this->assertNotEquals('admin', $user->role);
    }
}
```

### Fixture patterns
```php
<?php
declare(strict_types=1);

namespace App\Test\Fixture;

use Cake\TestSuite\Fixture\TestFixture;

class VerificationTokensFixture extends TestFixture
{
    public function init(): void
    {
        $this->records = [
            // Valid, happy path
            ['id' => 1, 'token' => 'valid-abc123', 'expires_at' => date('Y-m-d H:i:s', strtotime('+24 hours')), 'consumed_at' => null],
            // Expired
            ['id' => 2, 'token' => 'expired-xyz789', 'expires_at' => date('Y-m-d H:i:s', strtotime('-1 hour')), 'consumed_at' => null],
            // Already consumed
            ['id' => 3, 'token' => 'consumed-def456', 'expires_at' => date('Y-m-d H:i:s', strtotime('+24 hours')), 'consumed_at' => '2024-01-15 10:30:00'],
        ];
        parent::init();
    }
}
```

**If a fixture already exists:** add records with IDs starting at 100+ to avoid conflicts. Match the existing column structure exactly.

---

## Verification Checks

Run these searches to catch common mistakes. **Note for subagents:** Use the Grep tool (not shell `grep`) for these checks — it handles permissions correctly and integrates with the tool output.

```bash
# 5.x API used instead of 4.x:
grep -r "SelectQuery" src/
# Should find ZERO results. Must use Query.

grep -r "use Cake\\ORM\\Query\\SelectQuery" src/
# Should find ZERO results.

# 5.x Query methods used instead of 4.x equivalents:
grep -rn "->orderBy(" src/
# Should find ZERO results. Use ->order() in 4.x.

grep -rn "->orderByAsc(\|->orderByDesc(" src/
# Should find ZERO results. Use ->order(['col' => 'ASC']) in 4.x.

grep -rn "->groupBy(" src/
# Should find ZERO results on Query chains. Use ->group() in 4.x.
# NOTE: ->groupBy() on Collection/ResultSet (after ->all()) is fine.

grep -rn "->selectAlso(" src/
# Should find ZERO results. 5.x only.

# Raw HTML forms instead of FormHelper:
grep -rn "<form" templates/
# Should only find results inside $this->Form->create() or existing code.

# Unescaped output:
grep -rn "<?= \$" templates/ | grep -v "h(" | grep -v "Form->" | grep -v "Html->" | grep -v "Flash->" | grep -v "element(" | grep -v "Paginator->"
# Every result here is a potential XSS vulnerability.

# Mass assignment vulnerability:
grep -rn "'\\*' => true" src/Model/Entity/
# Should find ZERO results in new entities. May exist in old ones (note as concern).

# Direct superglobals:
grep -rn "\$_POST\|\$_GET\|\$_REQUEST" src/
# Should find ZERO results.
```

---

## Deployment Commands

### Deploy
```bash
# Run migrations
bin/cake migrations migrate

# Clear caches
bin/cake cache clear_all
bin/cake schema_cache clear  # if using schema cache
```

### Rollback
```bash
# Code-level rollback
git checkout PREVIOUS_COMMIT
composer install --no-dev --optimize-autoloader
bin/cake migrations rollback
bin/cake cache clear_all

# Nuclear rollback (if database is in bad state)
mysql -u USER -p DATABASE < backup_YYYYMMDD_HHMMSS.sql
git checkout PREVIOUS_COMMIT
composer install --no-dev --optimize-autoloader
bin/cake cache clear_all
```

### Smoke test
```bash
curl -s -o /dev/null -w "%{http_code}" https://APP_URL/          # Homepage → 200
curl -s -o /dev/null -w "%{http_code}" https://APP_URL/login      # Login → 200
curl -s -o /dev/null -w "%{http_code}" https://APP_URL/new-route  # New route → 200
```

---

## Claude Code Skills Reference

Use these Claude Code capabilities at the right time to save effort and catch mistakes early:

| Skill / Pattern | When to Use | Why |
|---|---|---|
| **Explore agent** | Before writing anything new | Finds existing patterns to match — prevents reinventing what's already in the codebase |
| **Plan agent** | Before multi-file features | Architects the approach first so you don't code yourself into a corner |
| **`/simplify`** | After finishing code | Catches inline HTML in business logic, duplication, missed reuse opportunities |
| **Background tasks** (`run_in_background`) | DB imports, long migrations, full test suites | Avoids timeout on commands that take > 2 minutes |
| **Parallel tool calls** | Independent file reads, searches, glob+grep combos | Don't read 5 files sequentially when you can read them all at once |
| **MailHog API check** (`curl localhost:8025/api/v2/messages`) | After any feature that sends email | Visually verify the email rendered correctly — fonts, colors, no white-on-white |

### When to use which agent

- **Quick search** (specific file/class/function) → Use Glob or Grep directly
- **Broad exploration** (understanding a module, finding patterns across codebase) → Explore agent
- **Multi-step implementation planning** → Plan agent
- **Running a phase of work autonomously** → General-purpose agent

### Common time-wasters to avoid

- Don't build HTML inline in Shell/Table/Entity files — always create a template (see Email Template Patterns above)
- Don't guess at styling — find an existing email/report and match it exactly
- Don't run long DB scripts with default timeout — use `run_in_background` or extended timeout

---

## Mobile-First UI/UX Design Guidelines (Project-Specific)

> **Note:** The guidelines below are specific to THIS project's conventions (Bootstrap 5, Bootstrap Icons, inline CSS for emails). Other CakePHP projects may use different UI frameworks. When in doubt, check the project's existing templates.

> These guidelines are for building CakePHP template UIs used by **non-technical users on mobile phones with slow mobile networks**.

### Navigation

1. **Icon-only arrow buttons for prev/next** — Never use text like "Previous" or "Next". Use `<i class="bi bi-chevron-left"></i>` and `<i class="bi bi-chevron-right"></i>` inside `btn btn-sm btn-outline-secondary`. Saves horizontal space on mobile.

2. **Week navigation pattern:**
   ```php
   <div class="d-flex justify-content-between align-items-center">
       <a href="?week=<?= $prevWeek ?>" class="btn btn-sm btn-outline-secondary"><i class="bi bi-chevron-left"></i></a>
       <strong style="font-size:0.9rem;"><?= $weekStart->format('d M') ?> — <?= $weekEnd->format('d M Y') ?></strong>
       <a href="?week=<?= $nextWeek ?>" class="btn btn-sm btn-outline-secondary"><i class="bi bi-chevron-right"></i></a>
   </div>
   ```

3. **Month navigation pattern:**
   ```php
   <a href="?month=<?= $prevMonth ?>"><i class="bi bi-chevron-left"></i> <?= $prevMonthName ?></a>
   <strong><?= $monthStart->format('F Y') ?></strong>
   <a href="?month=<?= $nextMonth ?>"><?= $nextMonthName ?> <i class="bi bi-chevron-right"></i></a>
   ```
   Month nav can include short month name next to the arrow (e.g., "Feb >") since there's more space than week labels.

4. **"This Week" / "Current Month" button** — Only show when user has navigated away from current period. Hide when already on current period.

5. **Preserve filters when navigating** — Carry forward active filters (e.g., category, user_id) via query parameters in prev/next links.

### Tables & Data Display

6. **No horizontal scrolling on mobile** — Show only essential columns (Name, ID, Total) in the main table. Put detailed/day-by-day data in a **modal popup** triggered by clicking the summary value.

7. **Clickable totals for detail drilldown** — Summary numbers (e.g., totals, counts) should be clickable links that open a modal. Style: `text-primary font-weight-bold` with underline.

8. **Modal for detail views** — Use `modal-dialog-centered modal-dialog-scrollable`. Layout:
   - **Info card** — Name, ID
   - **Summary card** — Key metrics in horizontal row (`d-flex justify-content-around text-center`)
   - **Detail table** — Full breakdown (date, category, status)
   - **Link to full page** — "View Full Report" button to the dedicated detail page

9. **Skip modal tables for auto-download** — When auto-detecting tables for Excel export, use `table:not(.modal table)` selector so hidden modal tables don't get download buttons.

10. **Fractional totals** — When items have partial values (e.g., Full = 1, Half = 0.5), display as integer when whole (e.g., "3"), decimal when not (e.g., "2.5").

### Mobile-First Patterns

11. **Card-based layouts over table rows** — For primary interaction screens (e.g., status marking, data entry), use cards with large touch targets. Colored left border indicates status (`border-left: 4px solid #28a745`).

12. **Sticky filters on mobile** — Filter bars should be `position: sticky; top: 70px; z-index: 100; background: white;` so they stay visible while scrolling.

13. **Fixed bottom action buttons on mobile:**
    ```css
    @media (max-width: 576px) {
        .save-container {
            position: fixed; bottom: 0; left: 0; right: 0;
            padding: 10px 15px; background: white;
            box-shadow: 0 -2px 10px rgba(0,0,0,0.1); z-index: 100;
        }
    }
    ```

14. **Large touch targets** — Action buttons: `padding: 10px 4px` minimum on mobile. Use `flex: 1` so buttons fill width equally.

15. **Stat cards in 2-column grid** — Use `col-6 col-md-3` for 2x2 on mobile, 4-column on desktop. Large number + small label.

### Interaction & Feedback

16. **Double-tap prevention** — Disable submit buttons after first tap, show spinner:
    ```javascript
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Saving...';
    ```

17. **Loading overlay** — Full-screen semi-transparent overlay with centered spinner during form submissions.

18. **Toast notifications for AJAX** — Temporary `alert` banners (`position-fixed; top:15px; right:15px; z-index:9999;`) that auto-dismiss after 4 seconds.

19. **Consistent color coding:**
    - Green (`text-success`, `badge-success`, `btn-success`) = Positive / Complete / Active
    - Yellow/Orange (`text-warning`, `badge-warning`, `btn-warning`) = Partial / Pending
    - Red (`text-danger`, `badge-danger`, `btn-danger`) = Negative / Missing / Inactive
    - Blue (`text-primary`) = Totals / Neutral highlights

20. **Confirmation for destructive actions** — `confirm()` before remove/delete. Show spinner on the button during AJAX call.

### Component Patterns

21. **AJAX search with dropdown** — Text input + `position-absolute` `list-group` dropdown. Debounce 300ms. "No results" message. Close on outside click.

22. **Bulk action buttons** — Row of action buttons above a list for quick bulk operations. Use `flex-fill` so they share width equally.

23. **Date input constraints** — When date picker operates within a specific range (e.g., a week), set `min` and `max` attributes to constrain selection.

24. **Page heading element** — Use `ele_page_heading` element. Pass `downloadTableButton => true` for auto Excel download buttons.

---

## Self-Doubt Checklist

After completing work, run through these:

- Did I use `SelectQuery` anywhere? → Must be `Query` for 4.x
- Did I use `->orderBy()` anywhere? → Must be `->order()` for 4.x
- Did I use `->groupBy()` on a Query? → Must be `->group()` for 4.x (fine on Collection/ResultSet)
- Did I use `->orderByAsc()` / `->orderByDesc()` / `->selectAlso()`? → 5.x only, not available in 4.x
- Did I use `$this->fetchTable()` in a pre-4.3 project? → Use `$this->getTableLocator()->get()` instead
- Did I create any `<form>` tags instead of `$this->Form->create()`?
- Grep templates for `<?= $` without `h(` — any XSS holes?
- Check every entity `$_accessible` — any dangerous fields set to true?
- Is there any place a user could access another user's data by guessing an ID?
- Raw `$_POST` or `$_GET` anywhere? Must use `$this->request->getData()` / `getQuery()`
- Did I use PHP's native `DateTime` instead of `Cake\I18n\FrozenTime`?
- Did I put uniqueness/existence checks in `validationDefault()` instead of `buildRules()`?
- Did I lazy-load associations in a loop instead of using `->contain()`?
- Did I put business logic in a Console Command instead of a service?
- Did I add an association without checking if the foreign key column exists?
