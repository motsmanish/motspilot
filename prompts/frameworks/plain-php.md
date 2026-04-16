# Plain PHP Framework Guide

This file is automatically included by the motspilot pipeline when `FRAMEWORK="plain-php"` is set in config. It provides conventions for PHP projects **without a full-stack framework** — no Laravel, Symfony, CakePHP, CodeIgniter. Expect hand-rolled PDO, procedural or lightly-OO code, Composer-optional, PSR-4 autoloading if lucky.

<framework_tool_affinity>
Plain-PHP-specific tool routing:
- Use `php -l <file>` to syntax-check every modified file — no framework CLI to fall back on.
- Use `composer dump-autoload` after adding new classes if PSR-4 autoloading is present.
- For constant values: grep the project root for existing `define()` or `const` declarations before defining new ones.
- For database: prefer prepared statements via PDO. Never interpolate user input into SQL strings.
</framework_tool_affinity>

---

## Version Reference

**Target: PHP 8.1+ (8.2–8.5 are the actively supported branches as of 2026).** Do not use PHP 7.x-only patterns. Pick a minimum that matches hosting and test the minimum in CI.

| What | PHP 8.x (preferred) | PHP 7.x (avoid) |
|------|-------------------|------------------------------|
| Null safe chaining | `$user?->email` | `isset($user) ? $user->email : null` |
| Named args | `htmlspecialchars(string: $x, flags: ENT_QUOTES)` | Positional only |
| First-class callable | `htmlspecialchars(...)` | `'htmlspecialchars'` string |
| Constructor promotion | `public function __construct(public string $name)` | Manual assignment in body |
| Readonly properties | `public readonly int $id` | Private + getter |
| Match expression | `match($type) { 'a' => 1, 'b' => 2 }` | Switch + break |
| Enums | `enum Status: string { case Active = 'active'; }` | Class constants |
| Strict types | `declare(strict_types=1);` at top of every file | Optional |

**Every PHP file starts with:**
```php
<?php
declare(strict_types=1);
```

Tooling version caveats to check before adopting:
- **PHPUnit 12** requires PHP 8.3+. Use an earlier major if supporting 8.2.
- **Pest** requires PHP 8.3+.
- **Psalm (latest)** requires PHP 8.2+.
- **PSR-12** replaces PSR-2. PSR-0 autoloading is deprecated; use PSR-4.

---

## Project Shape Detection

Plain PHP projects split into two common shapes. Detect which one you're in before planning work. Shape determines which subsections of this guide apply — security, DB, testing, and static-analysis content applies to both shapes unchanged, but routing, page structure, and webserver isolation differ.

### Detecting your shape

Use this heuristic at the start of the Architecture phase:

- If `public/index.php` exists AND it routes through a dispatcher / front controller / middleware stack → **Shape B**.
- If page files sit at the document root (or individually under `public/`) and each file is its own URL → **Shape A**.
- If both patterns are present, the project is a hybrid — treat new work as whichever style the nearest existing page uses.

Subsections in this guide tagged `**Shape A only**` or `**Shape B only**` apply only to that shape. Unlabelled content applies to both.

### Shape A: Page-file project (no routing)
```
config/app.php         # Bootstrap: sessions, constants, includes
config/database.php    # .env parsing, PDO singleton
includes/auth.php      # Session auth, CSRF, throttle
includes/functions.php # Helpers: db, escape, audit, formatting
includes/layout.php    # pageHeader() / pageFooter()
public/                # Web root — every page is its own .php file
```
No routing framework. No ORM. No DI. Every page `require_once`s the bootstrap and runs its own flow.

### Shape B: PDS-skeleton project (composer + front controller)
```
bin/                # CLI entry points (optional)
config/             # Config definitions, no secrets committed
public/index.php    # Front controller — routes all requests
resources/          # Templates, migrations, fixtures
src/                # Application source (PSR-4 autoloaded)
tests/              # Tests (autoload-dev)
var/                # Runtime cache/logs (gitignored)
composer.json
composer.lock
phpunit.xml.dist
README.md  LICENSE  CHANGELOG.md
```
This follows the [PDS skeleton](https://github.com/php-pds/skeleton) naming standard. `public/` is the only web-exposed directory; a front controller (`public/index.php`) routes through a lightweight router or middleware stack.

Projects may also be hybrids (Composer + page files). Match what's there.

---

## Files to Explore (Architecture Phase)

Read these like a detective before touching anything:

```
composer.json        → PHP version constraint? Autoload map? What libraries?
composer.lock        → Confirms exact versions CI/prod uses
public/index.php     → Front controller (Shape B) or simplest page (Shape A)
config/app.php       → Session config, autoloads, globals
config/database.php  → PDO DSN, charset, error mode. Singleton vs global?
includes/auth.php    → Auth entry points, CSRF, throttle, 2FA presence
includes/functions.php → Every helper. Read entirely before writing new ones.
includes/layout.php  → How pages are wrapped, what pageHeader() includes
src/                 → PSR-4 source (Shape B only)
database/schema.sql  → Tables, columns, indexes, FKs, views
database/seed.sql    → Initial data (roles, categories)
nginx/site.conf      → CSP headers, PHP-FPM socket, fastcgi_params
.env.example         → Config values expected; never has real secrets
```

**Match what's already there:**
- If pages call `requireAuth()` at the top, don't invent your own auth check.
- If `db()` returns the PDO singleton, don't create a new PDO instance inline.
- If templates escape with `e($value)`, don't use `htmlspecialchars()` directly.
- If there's no router and pages are self-contained, don't introduce a routing library.
- If there's a front controller with a router, don't bypass it.

---

## Naming Conventions

Plain PHP has no framework-imposed naming. Match what already exists. Common defaults:

- **Helper functions** — camelCase: `getUserSetting()`, `buildPlaceholders()`, `formatMoney()`
- **Constants** — SCREAMING_SNAKE: `MAX_UPLOAD_BYTES`, `DEFAULT_LOCALE`
- **Database tables** — snake_case: `bank_accounts`, `user_settings`, `v_transactions`
- **SQL columns** — snake_case: `user_id`, `status`, `created_at`

> **Shape A only:** Page files use lowercase dashes or underscores: `audit-log.php`, `transactions.php`. Keep the convention consistent — mixing `audit-log.php` and `audit_log.php` in the same project is a smell.

> **Shape B only:** Classes use StudlyCaps, one class per file, file path mirrors namespace: `src/Auth/LoginService.php` → `App\Auth\LoginService`.

---

## Autoloading

Composer-based projects should use PSR-4 exclusively for new code:

```json
{
  "autoload": {
    "psr-4": { "App\\": "src/" }
  },
  "autoload-dev": {
    "psr-4": { "App\\Tests\\": "tests/" }
  }
}
```

- Entry points (`public/index.php`, `bin/*`) `require vendor/autoload.php` — never `require_once` scattered business code.
- Production builds: `composer install --no-dev --optimize-autoloader` (or `--classmap-authoritative` for max-performance read-only deploys).
- Commit `composer.lock`. CI uses `composer install` (not `update`) for reproducibility.

If no Composer, the project uses `require_once` chains. Read the bootstrap file to find them; don't introduce Composer unless asked.

---

## Page File Structure

> **Shape A only.** Shape B routes through a front controller — skip to the next section.

Every page file follows the same shape:

```php
<?php
declare(strict_types=1);

require_once __DIR__ . '/../config/app.php';
requireAuth();                // or requireAdmin() for admin pages

// ─── AJAX endpoints go at the top, before any HTML output ───
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'save_thing') {
    verifyCsrf();
    header('Content-Type: application/json');
    // ... handle the action
    echo json_encode(['success' => true]);
    exit;
}

// ─── GET handlers (downloads, exports) ───
if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['export'])) {
    // ... stream file
    exit;
}

// ─── Page render ───
pageHeader('Page Title', 'menu-key');
?>

<h4>Content here</h4>
<!-- HTML and PHP echo expressions, all escaped via e() -->

<?php pageFooter(); ?>
```

**Rules:**
- AJAX handlers **at the top**, before any output. Always `exit;` after responding.
- **One page file = one logical screen.** Don't dispatch multiple unrelated features from one file.
- `requireAuth()` / `requireAdmin()` called **before any output** — it may redirect.
- Page title and active nav key passed to `pageHeader()` — match existing calls.

---

## Front Controller + Router

> **Shape B only.** Shape A has no front controller — each page file is its own entry point.

If the project has a router, `public/index.php` typically looks like:

```php
<?php
declare(strict_types=1);

require __DIR__ . '/../vendor/autoload.php';

use App\Http\Kernel;

(new Kernel())->handle($_SERVER['REQUEST_METHOD'], $_SERVER['REQUEST_URI']);
```

- All non-asset requests rewrite to `/index.php` (nginx `try_files $uri /index.php?$query_string`).
- New routes go wherever existing routes are registered — match the file.
- If using PSR-7/15 middleware (Slim, Nyholm, Laminas), add new middleware at the **end** of the stack unless the order matters.

---

## Database Patterns

### PDO singleton
All queries go through a single PDO instance. Never instantiate `new PDO(...)` in a page file.

```php
$stmt = db()->prepare('SELECT id, name FROM users WHERE email = ?');
$stmt->execute([$email]);
$user = $stmt->fetch();
```

PDO should be configured at bootstrap with:
```php
new PDO($dsn, $user, $pass, [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
    PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci",
]);
```

### Always prepared statements
```php
// CORRECT
$stmt = db()->prepare('SELECT * FROM transactions WHERE person_id = ? AND date >= ?');
$stmt->execute([$personId, $fromDate]);

// WRONG — SQL injection
db()->query("SELECT * FROM transactions WHERE person_id = $personId");
```

**Dynamic `ORDER BY` / column lists are a validation problem, not an escaping problem.** Whitelist allowed columns:
```php
$allowed = ['date', 'amount', 'category'];
$sort = in_array($_GET['sort'] ?? '', $allowed, true) ? $_GET['sort'] : 'date';
$sql = "SELECT ... ORDER BY $sort";  // Safe because $sort is whitelisted
```

### IN clauses
```php
$ids = [1, 2, 3, 5, 8];
$ph = buildPlaceholders($ids);                    // "?,?,?,?,?"
$stmt = db()->prepare("SELECT * FROM items WHERE id IN ($ph)");
$stmt->execute($ids);
```

### Transactions
```php
db()->beginTransaction();
try {
    $stmt = db()->prepare('INSERT INTO orders (...) VALUES (...)');
    $stmt->execute([...]);
    $orderId = (int)db()->lastInsertId();

    $stmt = db()->prepare('INSERT INTO order_items (order_id, ...) VALUES (?, ...)');
    foreach ($items as $item) {
        $stmt->execute([$orderId, ...]);
    }
    db()->commit();
} catch (\Throwable $e) {
    db()->rollBack();
    throw $e;
}
```

### Schema changes
Plain PHP projects rarely have a migration framework. Schema changes go into `database/schema.sql` **plus** a dated diff file (`database/schema_diff_YYYYMMDD.sql`) the operator runs manually. Every diff includes a rollback statement as a comment at the top.

---

## Security Patterns

### Authentication
`includes/auth.php` (or `src/Auth/`) typically exposes:
- `requireAuth()` — redirects to login if no session user; called at the top of every protected page
- `requireAdmin()` — stricter variant; 403s non-admins
- `currentUser()` / `currentUserId()` — session user record/id
- `login($email, $password)` / `logout()` — handles session rotation
- Brute-force throttle (N attempts / M minutes / IP) on login

**Always call `requireAuth()` before any output.** Never assume the session is set.

### Password hashing
```php
// Storing — prefer Argon2id when available, otherwise bcrypt
$hash = password_hash($plaintext, PASSWORD_ARGON2ID);   // or PASSWORD_BCRYPT

// Verifying
if (!password_verify($plaintext, $user['password_hash'])) {
    // fail
}

// Rehash on login if algorithm has upgraded
if (password_needs_rehash($user['password_hash'], PASSWORD_ARGON2ID)) {
    // update stored hash
}
```
**Never use `md5`, `sha1`, or custom hashing for passwords.**

### CSRF tokens
Every state-changing request (POST/PUT/PATCH/DELETE) must verify a CSRF token. GET must never change state.

```php
// In forms
<form method="post">
    <input type="hidden" name="csrf_token" value="<?= e(csrfToken()) ?>">
</form>

// In AJAX
fetch('/page.php', {
    method: 'POST',
    headers: { 'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').content },
    body: formData
});

// In handler
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    verifyCsrf();   // throws/403s if invalid
}
```

`verifyCsrf()` must accept tokens from either `$_POST['csrf_token']` OR `X-CSRF-TOKEN` header. Pair with `SameSite=Strict` cookies for defense-in-depth.

### Session hardening
`config/app.php` sets these **before** `session_start()`:

```php
ini_set('session.cookie_httponly', '1');
ini_set('session.cookie_samesite', 'Strict');
ini_set('session.cookie_secure', '1');      // on HTTPS
ini_set('session.use_strict_mode', '1');
session_start();

// Idle + absolute timeouts
if (isset($_SESSION['last_activity']) && time() - $_SESSION['last_activity'] > 7200) {
    session_destroy();
    header('Location: /login.php');
    exit;
}
$_SESSION['last_activity'] = time();
```

On successful login: `session_regenerate_id(true);` (prevents session fixation).

### TOTP 2FA
If present, uses RFC 6238 TOTP (30-second window, SHA1, 6 digits). Recovery codes stored hashed (bcrypt) and consumed on use. QR codes generated server-side via a vendored library — no external CDN.

### Output escaping
**Every variable echoed into HTML must be escaped by context.** Use the project's `e()` helper (wraps `htmlspecialchars($x, ENT_QUOTES, 'UTF-8')`):

```php
<h4><?= e($user['name']) ?></h4>                                    <!-- ALWAYS -->
<h4><?= $user['name'] ?></h4>                                        <!-- NEVER -->

<!-- URLs and attributes -->
<a href="?id=<?= (int)$id ?>">Edit</a>
<input value="<?= e($row['email']) ?>">

<!-- JSON inside <script> -->
<script>var data = <?= json_encode($data, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;</script>
```

Numeric IDs get `(int)` / `(float)`, dates format via `DateTime->format()`, everything else `e()`.

### File uploads
- Validate MIME with `finfo_file()`, not the client-provided type.
- Validate extension against an allowlist.
- `is_uploaded_file()` before moving. Never trust `$_FILES`.
- Store outside the web root **or** with a random filename in a non-executable directory.
- Never echo the uploaded filename without sanitizing.
- Enforce size via nginx `client_max_body_size` + PHP `upload_max_filesize`.
- Reject `.php`, `.phtml`, `.phar`, `.htaccess`.

### Webserver isolation rules

Only `public/` is reachable over HTTP. Everything else (`config/`, `includes/`, `src/`, `lib/`, `tests/`, `vendor/`, `.env`, `.git/`, and all dotfiles) must be physically **above** the document root OR explicitly denied at the webserver layer. Historically, most PHP app compromises start with a reachable `.env`, `.git/config`, `composer.json`, or `phpinfo.php` — not with code bugs. Treat the webserver config as part of the application's security perimeter.

**Nginx drop-in** (include inside the `server { }` block, after `root` and `index`):

```nginx
# Block all dotfiles (.env, .git, .htaccess, .DS_Store, editor swap dirs)
location ~ /\. {
    deny all;
    return 404;
}

# Belt-and-suspenders: explicit .env
location ~ /\.env {
    deny all;
    return 404;
}

# Git metadata
location ~ /\.git {
    deny all;
    return 404;
}

# Non-public code directories
location ~* /(config|includes|src|lib|tests|vendor)/ {
    deny all;
    return 404;
}

# Sensitive file extensions (dumps, backups, swap files, configs, logs)
location ~* \.(sql|bak|swp|log|ini|yml|yaml|toml|lock)$ {
    deny all;
    return 404;
}

# Package manifests at the root
location = /composer.json      { deny all; return 404; }
location = /composer.lock      { deny all; return 404; }
location = /package.json       { deny all; return 404; }
location = /package-lock.json  { deny all; return 404; }
```

Each block returns `404` rather than `403` — a 403 confirms the path exists. A 404 tells the scanner nothing.

**Apache `.htaccess` equivalent** for shared-hosting deployments where the main server config isn't editable. Drop into the document root:

```apache
# Dotfiles (.env, .git, .htaccess, .DS_Store)
<FilesMatch "^\.">
    Require all denied
</FilesMatch>
<Files ".env">
    Require all denied
</Files>

# Non-public code directories
<DirectoryMatch "^.*/(config|includes|src|lib|tests|vendor)/">
    Require all denied
</DirectoryMatch>

# Sensitive extensions and package manifests
<FilesMatch "\.(sql|bak|swp|log|ini|yml|yaml|toml|lock)$">
    Require all denied
</FilesMatch>
<FilesMatch "^(composer\.json|composer\.lock|package\.json|package-lock\.json)$">
    Require all denied
</FilesMatch>

# Make denials indistinguishable from missing files
ErrorDocument 403 /404.html
```

`mod_authz_core` must be enabled. On Apache 2.2 and earlier, `Require all denied` is replaced by `Order deny,allow` / `Deny from all`.

> **Shape A only — MANDATORY.** If the project has no `public/` subdirectory (a flat-layout Shape A project where `index.php` and sibling page files live at the document root), the isolation rules above are **mandatory** because `config/`, `includes/`, `lib/`, etc. sit in the document root alongside servable pages. Either restructure to add a `public/` subdirectory and move page files under it, OR deny every non-page path at the webserver. There is no third option — a flat Shape A layout with no webserver denies is a public `.env` waiting to be scraped.

**Quick self-test** after deploying — run from any machine that can reach the site:

```bash
curl -I https://APP_URL/.env
curl -I https://APP_URL/.git/config
curl -I https://APP_URL/composer.json
curl -I https://APP_URL/config/database.php
```

Every response must be `HTTP/1.1 404 Not Found`. A `200` means the file is being served. A `403` means the path is denied but its existence is being leaked — fix the config to return 404 instead. There is no acceptable response other than 404.

### Nginx CSP
`nginx/site.conf` should set a strict CSP. Check before adding any external resource:

```
Content-Security-Policy: default-src 'self';
  script-src 'self' 'unsafe-inline';
  style-src 'self' 'unsafe-inline';
  font-src 'self';
  img-src 'self' data: blob:;
  connect-src 'self';
  object-src 'self' blob:;
  frame-src 'self' blob:;
```

- **Never add CDN links.** JS, CSS, fonts, icons are vendored in `public/assets/`.
- `blob:` must be allowed in `img-src`, `object-src`, `frame-src` if the app generates downloadable PDFs/Excel via `fetch → blob → window.open`.
- Any new CSP directive needs a reason and an audit comment.

### Audit logging
Every mutating action is logged via `audit()`:

```php
audit('create', 'order', $orderId, 'total=5000, status=pending');
audit('update', 'user', $userId, 'role changed: user->admin');
audit('login', 'user', $userId);
audit('download', 'document', $docId, "file=$filename");
```

Signature: `audit(string $action, string $entity, ?int $id, ?string $details)`. Inserts into `audit_log` with `user_id`, IP, user agent.

**Log all:** login/logout, failed login, CRUD on sensitive tables, config changes, exports/downloads of sensitive data, 2FA enable/disable, password changes. Never log raw `$_POST` / `$_GET` — may contain passwords/tokens.

---

## Helper Functions (`includes/functions.php`)

Common helpers to read before writing new ones. **Don't write new helpers speculatively** — add them when a concrete page needs one, keep them in `includes/functions.php`.

### Escaping
- `e($value)` — `htmlspecialchars($value, ENT_QUOTES, 'UTF-8')`

### Money formatting
- `money($n)` — two decimals, thousands separator (`1,234.56`)
- `moneyInt($n)` — no decimals, symbol prefix

### Dates
- Use `DateTimeImmutable` over `DateTime` (mutation-free).
- Store all timestamps in UTC at the DB layer; convert to local on output only.
- If the project has a locale/reporting-period concept (fiscal year, billing cycle, academic term), centralize the boundaries in one helper file — never scatter date arithmetic across pages.

### Settings
- `getUserSetting($key)` / `setUserSetting($key, $value)` — per-user key-value store (`user_settings` table)

### Data
- `buildPlaceholders(array $ids): string` — `?,?,?` for IN clauses
- `flash($message, $type = 'success')` — one-time session message

### Layout
- `pageHeader($title, $navKey)` — emits `<html>…<body>` + nav
- `pageFooter()` — closing tags + footer scripts

### Audit
- `audit($action, $entity, $id, $details)`

---

## Configuration & Environment

- Config that varies by deploy (DB credentials, API keys, feature flags) lives in environment variables.
- `.env` allowed for local development only; loaded early via `vlucas/phpdotenv` or hand-rolled parser.
- `.env` must be **gitignored**; commit `.env.example` with placeholder values.
- CI / production secrets come from the platform secret store — never committed.
- Access via `getenv()` / `$_ENV`, ideally wrapped in a config service for testability.
- `date_default_timezone_set('UTC')` (or project TZ) at bootstrap; store timestamps in UTC.

---

## Error Handling & Logging

Separate developer-facing from user-facing:
- **Local/dev:** verbose errors, stack traces visible.
- **Production:** safe messages, stack traces never leaked to the browser, correlation/request IDs in logs.

```php
// Bootstrap
set_error_handler(function ($severity, $message, $file, $line) {
    throw new \ErrorException($message, 0, $severity, $file, $line);
});

set_exception_handler(function (\Throwable $e) {
    error_log(sprintf("[%s] %s in %s:%d\n%s",
        date('c'), $e->getMessage(), $e->getFile(), $e->getLine(), $e->getTraceAsString()
    ));
    if (!headers_sent()) {
        http_response_code(500);
    }
    echo "An error occurred. Please try again."; // no trace in prod
});
```

For structured logging prefer **Monolog** (PSR-3 `LoggerInterface` implementation). For lowest-dependency projects, PHP's built-in `error_log()` writing to a file is acceptable.

---

## Excel & PDF I/O Patterns

Spreadsheet and PDF handling are the two most common "heavy" I/O features
in plain-PHP projects. Standardize them once and reuse everywhere.

### Excel reading (import pipelines)

Library: `phpoffice/phpspreadsheet` (Composer). Typical pipeline:

1. **`getColumnMap($formatType)`** — dict mapping internal field names to
   source column names per format. One entry per supported format.
2. **`getHeaderKeywords($formatType)`** — keywords used to auto-detect the
   header row when the source file has metadata rows above it.
3. **`parseSpreadsheet($path, $formatType)`** — reads the file, locates
   the header row, yields rows keyed by internal field names.
4. **Deduplication** — MD5 hash of a stable tuple of the row's natural-key
   columns, stored in a `hash` column with a UNIQUE index. Duplicate
   imports silently skipped.
5. **Audit log** — record filename, format, row count, inserted/skipped
   counts.

Every new format is added to both `getColumnMap` and `getHeaderKeywords`.
Test fixtures live in `tests/fixtures/import/` with one tiny `.xlsx` per
format.

**Memory:** large files go through `Xlsx`'s read filter to load only the
columns you need. Never `toArray()` a multi-megabyte sheet.

### Excel writing (exports, reports)

Same library. Typical pattern:

```php
$ss = new PhpOffice\PhpSpreadsheet\Spreadsheet();
$sheet = $ss->getActiveSheet();
$sheet->fromArray($rows, null, 'A1');   // bulk write — fast
$sheet->getStyle('A1:Z1')->getFont()->setBold(true);

header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
header('Content-Disposition: attachment; filename="export.xlsx"');
(new PhpOffice\PhpSpreadsheet\Writer\Xlsx($ss))->save('php://output');
exit;
```

Rules:
- Use `fromArray()` for bulk writes, not per-cell `setCellValue()` in a loop.
- Destroy the spreadsheet (`$ss->disconnectWorksheets(); unset($ss);`) after
  writing — phpspreadsheet leaks memory otherwise.
- Stream large exports directly to `php://output`, don't buffer in memory.

### PDF reading (extracting text from uploads)

Library: `smalot/pdfparser` (Composer) for text extraction. Pattern:

```php
$parser = new \Smalot\PdfParser\Parser();
$pdf    = $parser->parseFile($path);
$text   = $pdf->getText();
```

Rules:
- `pdfparser` handles text-based PDFs only. Scanned images need OCR
  (Tesseract via `thiagoalessio/tesseract_ocr`) — flag this as a
  separate pipeline, not a fallback.
- Validate MIME type (`finfo_file()`) before parsing — never trust the
  uploaded filename extension.
- Extract into a normalized structure, then apply the same dedup/audit
  pattern as Excel imports.

### PDF writing (generated documents)

See the "PDF Generation Pattern (TCPDF)" section below. TCPDF is the
go-to for templated PDF output. Dompdf is a lighter alternative for
HTML-to-PDF with minimal styling.

---

## PDF Generation Pattern (TCPDF)

If the project generates PDFs, TCPDF may be vendored at `lib/tcpdf/` rather than installed via Composer:

```bash
git -c core.fileMode=false clone --depth 1 \
    https://github.com/tecnickcom/TCPDF.git /tmp/tcpdf-src
cp -r /tmp/tcpdf-src lib/tcpdf
```

### Template pattern
Put the HTML template in `includes/*_template.php` as a function `renderXyzHtml($data): string`. Keep **all constants** (vendor info, colors, paths) at the top of the file.

### TCPDF `writeHTML()` quirks — AVOID
- **`<img src="/absolute/path.png"/>` is silently dropped.** Use data URIs:
  ```php
  function imageDataUri(string $path): string {
      return 'data:image/png;base64,' . base64_encode(file_get_contents($path));
  }
  ```
- **Mixed font sizes inline with `<br/>` cause baseline drift** — each line lands at a different x-offset. Put each line in its own `<tr>`. Single font-size per `<td>`.
- **`valign="middle"` on `<td>` is unreliable.** Use explicit `padding-top` / `padding-bottom`.
- **Column widths must be set on every row**, not just `<thead>`. Propagation from thead to tbody is broken. Use flat `<tr>` siblings with `width="X%"` on each `<td>`.
- **Don't use `<h1>`-`<h6>`** for styled text — they have hard-coded spacing. Use `<span style="font-size:Xpt;">`.

### Output: `inline` not `attachment`
Chrome flags `Content-Disposition: attachment` PDF downloads from HTTP origins as "insecure download". Use `inline`:

```php
header('Content-Type: application/pdf');
header('Content-Disposition: inline; filename="' . $filename . '.pdf"');
header('Content-Length: ' . strlen($pdfData));
header('X-Content-Type-Options: nosniff');
echo $pdfData;
```

Client-side, use **`fetch → blob → window.open`** — the browser's built-in viewer has its own Download button:

```js
fetch(url, { credentials: 'same-origin' })
    .then(r => r.blob())
    .then(blob => {
        const objUrl = URL.createObjectURL(blob);
        window.open(objUrl, '_blank');
        setTimeout(() => URL.revokeObjectURL(objUrl), 60000);
    });
```

Requires `blob:` in the nginx CSP.

---

## Test Patterns

### Layout
```
tests/
  bootstrap.php          # Sets up test DB, loads config
  fixtures/              # Sample .xlsx / .sql fixtures
  unit/
    FunctionsTest.php    # Pure functions: formatMoney(), buildPlaceholders(), slugify()
  integration/
    AuthTest.php         # Login / logout / session
    CsrfTest.php         # POST without token → 403
    AuditTest.php        # audit() writes correct row
  security/
    XssTest.php
    IdorTest.php
```

### Test database
Never run against production. Use a separate `_test` database:

```php
// tests/bootstrap.php
putenv('DB_NAME=myapp_test');
require_once __DIR__ . '/../config/app.php';

// Wipe and re-seed before each test
db()->exec('SET FOREIGN_KEY_CHECKS=0');
foreach (['audit_log', 'transactions', 'users'] as $t) {
    db()->exec("TRUNCATE TABLE $t");
}
db()->exec('SET FOREIGN_KEY_CHECKS=1');
```

### Security tests (non-negotiable)
- **Auth bypass** — every protected route 403/redirects without session
- **CSRF bypass** — every POST without a token returns 403
- **IDOR** — user 1 cannot `GET /transactions.php?id=2` where txn 2 belongs to user 2
- **XSS** — `<script>alert(1)</script>` in every text field renders escaped
- **SQL injection** — `'; DROP TABLE users;--` handled by prepared statements
- **File upload** — uploading `.php`, `.phtml`, `.phar` is rejected
- **Brute force** — Nth login attempt in M minutes from same IP is throttled
- **2FA** — login without 2FA code rejected for 2FA-enabled users

### Minimum test policy for new code
- **Unit tests required** for new business logic
- **Integration tests required** for DB queries and HTTP endpoints
- Minimum: 1 happy-path + 1 failure-path per endpoint/service

### Running
```bash
./vendor/bin/phpunit --testdox
./vendor/bin/phpunit --filter=AuthTest
```
Match `TEST_CMD` in `.motspilot/config`.

---

## Static Analysis, Style, Linting

Plain PHP projects rely heavily on static analysis because there's no framework to provide guardrails.

| Tool | Purpose | CI gate |
|------|---------|---------|
| **PHPStan** | Pragmatic type analysis; level-based strictness (0–9) | Required for PRs |
| **Psalm** | Strong type system, refactoring aids (alternative to PHPStan) | Required for PRs |
| **PHP_CodeSniffer (phpcs)** | PSR-12 style enforcement | Required for PRs |
| **PHP-CS-Fixer** | Auto-fix style; run in check mode in CI | Optional gate / pre-commit |
| **`php -l`** | Syntax lint (`--syntax-check`) | Required |

**Policy:** new code must not increase the PHPStan/Psalm baseline. Prefer tightening rules over time.

### Composer scripts (stable CI interface)
```json
{
  "scripts": {
    "ci:lint":    "php -l public/index.php",
    "ci:cs":      "phpcs --standard=PSR12 src tests",
    "ci:analyze": "phpstan analyse src tests",
    "ci:test":    "phpunit -c phpunit.xml.dist",
    "ci:audit":   "composer audit"
  }
}
```

CI calls `composer run ci:*` rather than tool binaries directly, so tool changes don't break pipelines.

---

## CI Pipeline Steps (Required Order)

1. `composer validate`
2. `composer install --no-interaction --prefer-dist` (locked — never `update` in CI)
3. **Syntax lint** — `php -l` across `public/`, `src/`
4. **Code style** — PSR-12 via phpcs
5. **Static analysis** — PHPStan or Psalm
6. **Tests** — PHPUnit (unit + integration)
7. **Dependency audit** — `composer audit` (non-zero exit = vulnerability)
8. **Build artifact** — `composer install --no-dev --optimize-autoloader` + `tar -czf app.tar.gz public src config resources vendor composer.json composer.lock`
9. **Deploy** — environment-gated (staging on main, production on tags)
10. **Post-deploy** — smoke tests, health checks, rollback plan

PHP version matrix: test minimum supported + latest supported (e.g., 8.2 and 8.5).

---

## Verification Checks

Run these searches to catch common vulnerabilities. **Use the Grep tool** (not shell `grep`) for clean output. Language-level findings (XSS, SQL injection, weak hashing, hardcoded secrets, dangerous functions) apply to both shapes; only the search paths differ.

> **Shape A note:** if page files sit at the document root rather than under `public/`, substitute `./` or the project root for any `public/` path below, and add `*.php` at the top level to the glob. Shape B checks assume the `public/` convention holds.

```bash
# Unescaped output (XSS)
grep -rn "<?= \$" public/ | grep -v "e("
# Every result is a potential XSS hole. Exceptions: (int), (float) casts.
# Shape A: also grep the project root, since page files may live there.

# Direct superglobals bypassing helpers
grep -rn "\$_POST\|\$_GET\|\$_REQUEST" public/
# Acceptable ONLY at the top of page files. Flag anything in includes/, src/, lib/.
# Shape A: grep the project root too.

# Raw PDO instantiation bypassing db()
grep -rn "new PDO(" .
# Should have ZERO matches outside config/database.php. Both shapes.

# String interpolation in SQL
grep -rnE "query\(.*\\\$|exec\(.*\\\$|prepare\(.*\\\$.*\\\$" .
# Every result is potential SQL injection. Both shapes.

# Missing CSRF on POST handlers
grep -rn "REQUEST_METHOD.*POST" public/
# Cross-reference each file to verify verifyCsrf() is called.
# Shape A: grep the project root; POST handlers may sit in top-level .php files.
# Shape B: also grep src/ for controller classes handling POST.

# Missing auth check at top of page
# Shape A (page files at doc root or in public/):
for f in public/*.php ./*.php; do
    [ -f "$f" ] || continue
    head -5 "$f" | grep -qE "requireAuth|requireAdmin|install|login" || echo "UNPROTECTED: $f"
done
# Shape B: auth is middleware-based — grep src/ for route definitions and verify
# each non-public route is inside an auth-guarded group. There's no per-file head check.

# Weak password hashing
grep -rn "md5\|sha1\b" includes/ public/ src/
# Should have ZERO matches on password handling. md5/sha1 OK only for dedup keys. Both shapes.

# Session started without hardening
grep -rn "session_start" config/ includes/ src/
# Must be preceded by cookie_httponly, cookie_samesite, cookie_secure. Both shapes.

# External CDN (violates CSP)
grep -rn "https://cdn\|https://fonts\|unpkg\|jsdelivr" public/
# Should have ZERO matches. All assets vendored.
# Shape A: extend to the project root and any templates/ directory.

# Hardcoded secrets
grep -rnE "password\s*=\s*['\"][^'\"]{8,}|api[_-]?key\s*=\s*['\"]" --include="*.php" .
# Every match is suspect. Secrets go in .env. Both shapes.

# Dangerous functions
grep -rnE "\beval\(|\bsystem\(|\bexec\(|\bshell_exec\(|\bpassthru\(" .
# Every match is severe risk. Should be ZERO. Both shapes.

# GET state mutation
grep -rn "REQUEST_METHOD.*GET" public/ src/ | xargs -I{} grep -l "INSERT\|UPDATE\|DELETE" {}
# Any match violates CSRF policy. State changes must require POST.
# Shape A: include the project root in the first grep.

# Webserver isolation (post-deploy — see "Webserver isolation rules")
curl -sI https://APP_URL/.env         | head -1   # expect HTTP/1.1 404
curl -sI https://APP_URL/.git/config  | head -1   # expect HTTP/1.1 404
curl -sI https://APP_URL/composer.json| head -1   # expect HTTP/1.1 404
# Any 200 is a critical finding. Any 403 leaks existence — fix to 404.
```

---

## Deployment Commands

### Deploy
```bash
git pull origin main
composer install --no-dev --optimize-autoloader

# Apply schema changes (manual — no migration framework)
mysql -u dev -p myapp < database/schema_diff_YYYYMMDD.sql

# Reload nginx if site.conf changed
sudo nginx -t && sudo nginx -s reload

# Reload PHP-FPM to clear opcache
sudo systemctl reload php8.2-fpm
```

For zero-downtime, use release directories + atomic symlink switch (e.g., Deployer).

### Rollback
```bash
# Code-level
git checkout PREVIOUS_COMMIT
composer install --no-dev --optimize-autoloader
sudo systemctl reload php8.2-fpm

# Nuclear (database in bad state)
mysql -u dev -p myapp < backup_YYYYMMDD_HHMMSS.sql
git checkout PREVIOUS_COMMIT
composer install --no-dev --optimize-autoloader
sudo systemctl reload php8.2-fpm
```

### Smoke tests

Every smoke test must assert **both** that the route is reachable **and** that the route's expected side effect actually happened. Status-code-only tests can't distinguish "works" from "silently broken" — a 200 with an empty insert is still a bug.

Generic template:

```bash
# Entry-point check — proves the route is reachable
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' https://APP_URL/new-route)
test "$HTTP_CODE" = "200" || { echo "FAIL: route unreachable ($HTTP_CODE)"; exit 1; }

# Side-effect check — proves the route did the expected work.
# Example: if the route writes to a DB table, assert the row landed
# Example: if the route sends an email, assert the mail catcher received it
# Example: if the route updates cache, assert the cache key changed
# Adapt this pattern to the framework's preferred DB/email/cache tooling.
```

**Plain-PHP-specific shape (adapt, don't copy):** since there's no ORM or console runner, use `php -r` to bootstrap the project's DB helper and run a targeted query. Point it at whatever table/column the route was supposed to touch:

```bash
ROW_COUNT=$(php -r "
require 'config/database.php';
\$r = db()->query(\"SELECT COUNT(*) FROM widgets WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 MINUTE)\")->fetchColumn();
echo (int)\$r;
")
test "$ROW_COUNT" -gt 0 || { echo "FAIL: expected row in widgets"; exit 1; }
```

For email side effects, use whichever mail catcher the project runs (Mailpit, MailHog, smtp4dev). Mailpit and MailHog expose a compatible HTTP API on port 8025 by default: `curl -s http://localhost:8025/api/v2/messages | jq '.total'` and assert the count increased. For cache, `redis-cli GET mykey` or `memcached-tool ... stats` against the expected key.

> The delivery phase gates on smoke test execution — see `prompts/delivery.md` section 3.2. Smoke tests without side-effect checks are treated as zero tests and fail the phase.

Check logs after deploy:
```bash
tail -f storage/app.log
tail -f /var/log/nginx/error.log
```

---

## Claude Code Skills Reference

| Skill / Pattern | When to Use | Why |
|---|---|---|
| **Explore agent** | Before writing anything new | Finds existing patterns in `includes/functions.php` and pages — prevents reinventing helpers |
| **Plan agent** | Before multi-file features | Plans file touch list + DB schema changes before coding |
| **Grep tool** | Verification checks, vulnerability scans | Precise searches across `includes/`, `public/`, `src/`, `lib/` |
| **Read tool** | Reading existing pages as templates for new ones | Preserve style exactly |
| **Background tasks** | Long SQL imports, full grep sweeps | Avoid timeouts |
| **Parallel tool calls** | Reading `schema.sql` + `functions.php` + `app.php` together | Don't serialize independent reads |

---

## Common Pitfalls

- **Don't build HTML by string concatenation inside functions.** Use `ob_start()` / template partials so escaping stays clean.
- **Don't `echo` before `session_start()`** or before `header()`. Triggers headers-sent errors.
- **Don't use `date()` with timezone-naive columns** — set `date_default_timezone_set()` at bootstrap and store UTC.
- **Don't trust `$_SERVER['HTTP_X_FORWARDED_FOR']`** for rate limiting unless `set_real_ip_from` is configured in nginx.
- **Don't assume `$_FILES` is populated** — check `is_uploaded_file()` before moving.
- **Don't leave `install.php` in production.** Delete after initial setup.
- **Don't `require_once` inside a function** unless the file only defines functions.
- **Don't use `include` instead of `include_once`** for helpers — redeclared-function errors.
- **Don't put real secrets in `.env.example`** — only placeholders.
- **Don't log full `$_POST` / `$_GET`** — may contain passwords/tokens. Filter first.
- **Don't introduce a framework / router / ORM** unless explicitly asked. If the project is plain PHP, it's plain PHP on purpose.

---

## Self-Doubt Checklist

After completing work, run through these. **If any answer is "I'm not sure", verify.**

**Database:**
- [ ] Every query uses `db()->prepare()` with `?` placeholders? (No string concat into SQL)
- [ ] IN clauses use `buildPlaceholders()`?
- [ ] Multi-statement writes wrapped in `beginTransaction() / commit() / rollBack()`?
- [ ] Dynamic ORDER BY / column lists validated against a whitelist?
- [ ] Schema changes documented in `database/schema.sql` with rollback statement?

**Auth / Session:**
- [ ] Every protected page calls `requireAuth()` or `requireAdmin()` before any output?
- [ ] Login regenerates session id via `session_regenerate_id(true)`?
- [ ] Passwords hashed via `password_hash(PASSWORD_ARGON2ID)` or `PASSWORD_BCRYPT`?
- [ ] `password_needs_rehash()` checked on login?
- [ ] Session cookies: `httponly`, `samesite=Strict`, `secure` on HTTPS?
- [ ] Session idle + absolute timeouts implemented?

**CSRF:**
- [ ] Every POST handler calls `verifyCsrf()`?
- [ ] Every form includes `<input type="hidden" name="csrf_token">`?
- [ ] AJAX requests send `X-CSRF-TOKEN`?
- [ ] No state changes via GET?

**Output:**
- [ ] Every `<?= $var ?>` wrapped in `e()` or numeric cast?
- [ ] JSON in `<script>` encoded with `JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT`?
- [ ] No raw HTML built via string concatenation in business logic?

**Files / Uploads:**
- [ ] MIME validated by `finfo_file()`, not client type?
- [ ] Extension allowlist enforced?
- [ ] Filenames sanitized / randomized before storage?
- [ ] Uploads outside web root or in a non-executable directory?

**Audit:**
- [ ] Every mutating action calls `audit()` with meaningful details?
- [ ] Login success/failure/logout logged?
- [ ] Sensitive exports (CSV, PDF, Excel) logged?

**Nginx / CSP:**
- [ ] Any new resources are local (no CDN)?
- [ ] CSP allows `blob:` for `img-src` / `object-src` / `frame-src` if PDF blob-viewer is used?
- [ ] CSP changes documented and reviewed?

**PHP gotchas:**
- [ ] `declare(strict_types=1);` at the top of new files?
- [ ] `exit;` after every AJAX handler?
- [ ] `require_once` not `require`?
- [ ] No output before `header()` / `session_start()`?

**Standards / CI:**
- [ ] PSR-12 style, no new phpcs violations?
- [ ] New code passes PHPStan/Psalm at the project's baseline level?
- [ ] Tests added for happy + failure paths?
- [ ] `composer audit` clean?
- [ ] `composer.lock` updated only intentionally?

**Tests:**
- [ ] New auth/CSRF/security tests cover the new feature?
- [ ] IDOR test: can user 1 access user 2's new records?
- [ ] XSS test: `<script>alert(1)</script>` in every new input rendered escaped?
- [ ] Tests run against `_test` database, not production?
