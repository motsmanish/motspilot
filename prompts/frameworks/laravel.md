# Laravel 11.x+ Framework Guide

This file is automatically included by the motspilot pipeline when `FRAMEWORK="laravel"` is set in config. It provides framework-specific knowledge for all pipeline phases.

<framework_tool_affinity>
Laravel-specific tool routing:
- Use `php artisan make:model Name -mfcrs` to scaffold Model + Migration + Factory + Controller + Resource + Seeder — never handwrite boilerplate from scratch.
- Use `php artisan make:migration create_things_table` to scaffold migration files — never handwrite the timestamp prefix.
- Use `php artisan route:list` to verify route conflicts before adding new routes.
- Use `php artisan make:request StoreThingRequest` to generate Form Request classes — never validate inside controllers.
- Use `php artisan make:policy ThingPolicy --model=Thing` to scaffold authorization policies.
- Use `php artisan make:test ThingTest` (Feature) or `php artisan make:test ThingTest --unit` (Unit).
- For constant values: grep `app/Models/` and `app/Enums/` for existing constants/enums before defining new ones.
- For queue jobs: `php artisan make:job ProcessThing` — never dispatch closures for non-trivial work.
- For events: `php artisan make:event ThingCreated` + `php artisan make:listener SendThingNotification --event=ThingCreated`.
</framework_tool_affinity>

---

## Version Reference

**This guide is for Laravel 11.x+ (including 12.x). Do NOT use patterns removed in Laravel 11.**

Laravel 11 introduced a streamlined application structure. Laravel 12 is a maintenance release with no breaking changes from 11. Both share the same patterns.

| What | Laravel 11.x+ (correct) | Pre-11 (WRONG for new projects) |
|------|------------------------|-------------------------------|
| Application bootstrap | `bootstrap/app.php` (code-first config) | `app/Http/Kernel.php`, `app/Console/Kernel.php` |
| Middleware registration | `->withMiddleware()` in `bootstrap/app.php` | `$middleware` arrays in `Kernel.php` |
| Exception handling | `->withExceptions()` in `bootstrap/app.php` | `app/Exceptions/Handler.php` |
| Service providers | Single `AppServiceProvider` | 5 default providers |
| Scheduled tasks | `routes/console.php` using `Schedule` facade | `app/Console/Kernel.php` `schedule()` method |
| Default middleware dir | None (define inline or in `bootstrap/app.php`) | `app/Http/Middleware/` |
| Health check route | Built-in `/up` route | Manual |
| Model casts | `protected function casts(): array` method | `protected $casts = []` property |
| Accessor/Mutator syntax | `Illuminate\Database\Eloquent\Casts\Attribute` return type | `getNameAttribute()` / `setNameAttribute()` |
| Password hashing | `Hash::make()` with bcrypt default (Argon2id configurable) | Same |
| Coding standard | PSR-12 | PSR-12 |
| PHP minimum | 8.2 | 8.1 (Laravel 10), 8.0 (Laravel 9) |

---

## Naming Conventions

Laravel uses convention over configuration. Follow these exactly to avoid extra config:

| What | Convention | Example |
|------|-----------|---------|
| Model class | Singular, PascalCase | `PlatformPackage` |
| Table name | Plural, snake_case | `platform_packages` |
| Column name | snake_case | `created_at`, `user_id`, `is_active` |
| Controller class | Singular resource + `Controller` | `PlatformPackageController` |
| Form Request | `Store`/`Update` + Model + `Request` | `StorePlatformPackageRequest` |
| Policy class | Model + `Policy` | `PlatformPackagePolicy` |
| Event class | Past tense, PascalCase | `PlatformPackageCreated` |
| Listener class | Imperative verb, PascalCase | `SendPackageNotification` |
| Job class | Imperative verb, PascalCase | `ProcessPackagePayment` |
| Notification class | Imperative/descriptive, PascalCase | `PackageShipped` |
| Migration file | `create_things_table` / `add_status_to_things_table` | `2026_04_16_120000_create_platform_packages_table` |
| Factory class | Model + `Factory` | `PlatformPackageFactory` |
| Seeder class | Model/Plural + `Seeder` | `PlatformPackageSeeder` |
| Middleware class | PascalCase, descriptive | `EnsureUserIsAdmin` |
| Enum | Singular, PascalCase | `PackageStatus` |
| Blade view | kebab-case or snake_case | `platform-packages/show.blade.php` |
| Route name | Dot-separated, resource-style | `platform-packages.show` |
| Config file | snake_case | `platform_packages.php` |
| Foreign key | Singular model + `_id` | `platform_package_id` |
| Pivot table | Singular models, alphabetical, snake_case | `package_user` |

**Match what the existing project uses.** If it uses `snake_case` view names, do not introduce `kebab-case`.

---

## Files to Explore (Architecture Phase)

When exploring a Laravel codebase, read these files like a detective:

```
bootstrap/app.php              -> Middleware, exception handling, service providers, route files
routes/web.php                 -> Web route patterns, middleware groups, prefix groups
routes/api.php                 -> API routes (if present — optional in Laravel 11+)
app/Models/                    -> ls this directory. Which models exist? Relationships? Scopes?
app/Http/Controllers/          -> Controller patterns. Resource? Invokable? API?
app/Providers/AppServiceProvider.php -> Custom bindings, macros, boot logic
config/                        -> App config, DB config, mail config, queue config
database/migrations/           -> Schema history. What tables exist? What columns?
resources/views/layouts/       -> What layout system? Components? @extends? CSS framework?
composer.json                  -> PHP version, packages, Laravel version, dev dependencies
.env.example                   -> What services are configured? DB driver? Mail driver? Queue driver?
```

**Match what's already there:**
- If the project uses `@extends('layouts.app')`, do not introduce Blade components for layout.
- If the project uses PHPUnit, do not introduce Pest without agreement.
- If the project uses Bootstrap, do not write Tailwind.
- If the project uses the repository pattern, follow it. If it calls Eloquent directly from controllers, do that.
- If the project still has `Kernel.php`, it may be a pre-11 structure running on 11 — match the existing pattern.

---

## PHP File Header

Every PHP file starts with:
```php
<?php

declare(strict_types=1);
```

Laravel does not use `declare(strict_types=1)` by default in its generated files, but it is a best practice. **Match the existing project convention.** If no existing files use strict types, do not introduce it.

---

## Migration Patterns

Migration files use timestamp naming: `YYYY_MM_DD_HHMMSS_descriptive_name.php`. Use `php artisan make:migration create_orders_table` or `php artisan make:migration add_status_to_orders_table` to generate with correct timestamp.

**One logical action per migration file.** Each migration should do exactly ONE thing:
- Creating a table -> one migration
- Adding columns to an existing table -> one migration
- Seeding/inserting data -> one migration (or use a Seeder)
- Adding an index -> one migration

Never combine multiple unrelated changes in a single migration. Small, focused migrations are easier to debug, rollback, and review.

**Schema builder patterns:**
```php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('status')->default('pending');
            $table->decimal('total', 10, 2);
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('orders');
    }
};
```

**Rules:**
- Always include `down()`. Laravel's `Schema::create` / `Schema::dropIfExists` pair is clean, but `down()` for column additions needs explicit `dropColumn()`.
- Use `->constrained()` for foreign keys — it infers table/column from the column name.
- Use `->cascadeOnDelete()` or `->nullOnDelete()` explicitly. Never leave orphan behavior to chance.
- Guard with `Schema::hasTable()` / `Schema::hasColumn()` checks when adding to existing tables that may have been modified outside migrations.
- Index every column that appears in WHERE, JOIN, or ORDER BY.
- Use anonymous migration classes (Laravel 9+) — `return new class extends Migration`.
- Use `$table->foreignId('thing_id')->constrained()` over manual `$table->unsignedBigInteger()` + `$table->foreign()`.
- For enum-like columns, prefer `$table->string('status')` with PHP enum validation over `$table->enum()` (database-level enums are hard to modify later).

**After creating the migration:**
```bash
php artisan migrate
php artisan migrate:status
```
Verify it ran. Then:
```bash
php artisan migrate:rollback
php artisan migrate:status
```
Verify it rolled back cleanly. Then migrate again.

---

## Model Patterns

Models live in `app/Models/`. Don't write models speculatively — create them as needed.

### Mass Assignment Protection

Use `$fillable` (whitelist) or `$guarded` (blacklist), never both:
```php
class Order extends Model
{
    // Whitelist approach (preferred — explicit about what's allowed)
    protected $fillable = [
        'user_id',
        'status',
        'total',
        'notes',
    ];

    // OR blacklist approach
    // protected $guarded = ['id'];
}
```

**Never `$guarded = []` (empty guard).** Never include `id`, `role`, `is_admin`, `is_verified` in `$fillable`.

### Hidden Attributes

If this model is serialized to JSON (API responses, `toArray()`), what should be invisible?
```php
protected $hidden = [
    'password',
    'remember_token',
    'two_factor_secret',
];
```

### Casts (Laravel 11+ method syntax)

```php
// Laravel 11+: method syntax (preferred)
protected function casts(): array
{
    return [
        'email_verified_at' => 'datetime',
        'password' => 'hashed',
        'total' => 'decimal:2',
        'is_active' => 'boolean',
        'settings' => 'array',
        'status' => PackageStatus::class,  // Enum cast
    ];
}

// Legacy property syntax (still works, use if project already uses it)
// protected $casts = ['email_verified_at' => 'datetime'];
```

### Accessors & Mutators (Laravel 11+ Attribute syntax)

```php
use Illuminate\Database\Eloquent\Casts\Attribute;

// Laravel 11+: Attribute return type (preferred)
protected function fullName(): Attribute
{
    return Attribute::make(
        get: fn () => "{$this->first_name} {$this->last_name}",
    );
}

protected function email(): Attribute
{
    return Attribute::make(
        set: fn (string $value) => strtolower($value),
    );
}
```

### Relationships

```php
// One-to-Many
public function orders(): HasMany
{
    return $this->hasMany(Order::class);
}

// Belongs-To
public function user(): BelongsTo
{
    return $this->belongsTo(User::class);
}

// Many-to-Many
public function roles(): BelongsToMany
{
    return $this->belongsToMany(Role::class)->withTimestamps();
}

// Has-One-Through, Has-Many-Through, Polymorphic — read docs, don't guess.
```

Always type-hint return types on relationships (`HasMany`, `BelongsTo`, etc.). This enables IDE support and static analysis.

### Scopes

```php
// Local scope — called as ->active()
public function scopeActive(Builder $query): Builder
{
    return $query->where('status', 'active');
}

// Local scope with parameter
public function scopeOfStatus(Builder $query, string $status): Builder
{
    return $query->where('status', $status);
}
```

### Eager Loading (Avoid N+1)

```php
// Good: eager load with ->with()
$orders = Order::with(['user', 'items'])->get();

// Bad: N+1 — loads user separately for each order
$orders = Order::all();
foreach ($orders as $order) {
    echo $order->user->name; // extra query per order
}
```

Only load what you need. Use `->with('user:id,name')` to select specific columns. Use `->withCount('items')` for counts without loading the full relation.

### Enums (PHP 8.1+)

```php
// app/Enums/OrderStatus.php
enum OrderStatus: string
{
    case Pending = 'pending';
    case Processing = 'processing';
    case Shipped = 'shipped';
    case Delivered = 'delivered';
    case Cancelled = 'cancelled';
}

// In Model casts
protected function casts(): array
{
    return ['status' => OrderStatus::class];
}

// Usage
$order->status = OrderStatus::Pending;
$order->status->value; // 'pending'
Order::where('status', OrderStatus::Pending)->get();
```

Prefer PHP enums over string constants for statuses, types, and roles. Place enums in `app/Enums/`.

---

## Service / Action Patterns

Put services in `app/Services/` and actions in `app/Actions/`.

**Services** encapsulate reusable business logic used across the application:
```php
// app/Services/OrderService.php
class OrderService
{
    public function __construct(
        private readonly OrderRepository $orders, // or inject Model directly
    ) {}

    public function createOrder(User $user, array $items): Order
    {
        // 1. Validate inventory
        $this->validateInventory($items);

        // 2. Calculate total
        $total = $this->calculateTotal($items);

        // 3. Create order in transaction
        return DB::transaction(function () use ($user, $items, $total) {
            $order = $user->orders()->create([
                'total' => $total,
                'status' => OrderStatus::Pending,
            ]);

            $order->items()->createMany($items);

            event(new OrderCreated($order));

            return $order;
        });
    }
}
```

**Actions** encapsulate a single operation (one class, one `__invoke` or `handle` method):
```php
// app/Actions/CreateOrderAction.php
class CreateOrderAction
{
    public function __construct(
        private readonly CalculateTotalAction $calculateTotal,
    ) {}

    public function __invoke(User $user, array $items): Order
    {
        return DB::transaction(function () use ($user, $items) {
            $order = $user->orders()->create([
                'total' => ($this->calculateTotal)($items),
                'status' => OrderStatus::Pending,
            ]);

            $order->items()->createMany($items);

            return $order;
        });
    }
}
```

**Services and actions must NEVER touch:**
- `request()` or `Request` objects (that is a controller concern)
- `session()` or flash messages (that is a controller concern)
- `redirect()` (that is a controller concern)
- `response()` or `abort()` (that is a controller concern)

Use constructor injection. Throw domain-specific exceptions (not generic `\Exception`).

**Match the existing project pattern.** If it uses services, use services. If it uses actions, use actions. If it puts logic directly in controllers (small app), follow that unless the new feature genuinely needs extraction.

---

## Controller Patterns

A controller action should be boring -- get input, call service/model, respond:

### Resource Controller
```php
class OrderController extends Controller
{
    public function __construct(
        private readonly OrderService $orderService,
    ) {}

    public function index(): View
    {
        $orders = Order::with('user')
            ->latest()
            ->paginate(25);

        return view('orders.index', compact('orders'));
    }

    public function store(StoreOrderRequest $request): RedirectResponse
    {
        try {
            $order = $this->orderService->createOrder(
                $request->user(),
                $request->validated(),
            );

            return redirect()
                ->route('orders.show', $order)
                ->with('success', 'Order created successfully.');
        } catch (InsufficientInventoryException $e) {
            return back()
                ->withInput()
                ->withErrors(['items' => $e->getMessage()]);
        }
    }

    public function show(Order $order): View
    {
        $order->load(['items', 'user']);
        return view('orders.show', compact('order'));
    }
}
```

### Invokable (Single-Action) Controller
```php
class MarkOrderShippedController extends Controller
{
    public function __invoke(Order $order): RedirectResponse
    {
        $this->authorize('update', $order);

        $order->update(['status' => OrderStatus::Shipped]);

        event(new OrderShipped($order));

        return back()->with('success', 'Order marked as shipped.');
    }
}
```

**Controller rules:**
- Actions return typed responses: `View`, `RedirectResponse`, `JsonResponse`, `Response`
- Max 10-15 lines per action
- Use Form Request classes for validation, not inline `$request->validate()`
- Use route model binding (`Order $order` in parameter) instead of manual `Order::findOrFail($id)`
- Use `$this->authorize()` or `Gate::authorize()` for authorization, not inline `if` checks
- **NEVER put business logic in controller private methods.** No `_handleFoo()`, `_processFoo()`. That logic belongs in a Service, Action, or Model method.
- Use `$request->validated()` to get only validated input, never `$request->all()`

### API Controller
```php
class Api\OrderController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $orders = Order::with('user')
            ->latest()
            ->paginate($request->integer('per_page', 25));

        return OrderResource::collection($orders)->response();
    }

    public function store(StoreOrderRequest $request): JsonResponse
    {
        $order = $this->orderService->createOrder(
            $request->user(),
            $request->validated(),
        );

        return (new OrderResource($order))
            ->response()
            ->setStatusCode(201);
    }
}
```

---

## Form Request Patterns

All validation belongs in Form Request classes, never in controllers:

```php
// app/Http/Requests/StoreOrderRequest.php
class StoreOrderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Order::class);
    }

    public function rules(): array
    {
        return [
            'items' => ['required', 'array', 'min:1'],
            'items.*.product_id' => ['required', 'exists:products,id'],
            'items.*.quantity' => ['required', 'integer', 'min:1'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'coupon_code' => ['nullable', 'string', 'exists:coupons,code'],
        ];
    }

    public function messages(): array
    {
        return [
            'items.required' => 'At least one item is required.',
            'items.*.product_id.exists' => 'Product not found.',
        ];
    }
}
```

Use `prepareForValidation()` to normalize input before validation:
```php
protected function prepareForValidation(): void
{
    $this->merge([
        'email' => strtolower($this->email),
        'slug' => Str::slug($this->title),
    ]);
}
```

---

## API Resource Patterns

Transform models to JSON responses with API Resources:

```php
// app/Http/Resources/OrderResource.php
class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status->value,
            'total' => $this->total,
            'notes' => $this->notes,
            'created_at' => $this->created_at->toIso8601String(),
            'user' => new UserResource($this->whenLoaded('user')),
            'items' => OrderItemResource::collection($this->whenLoaded('items')),
            'items_count' => $this->whenCounted('items'),
        ];
    }
}
```

Use `$this->whenLoaded()` to conditionally include relationships only when eager-loaded. Never return raw model data from API endpoints.

---

## Template / View Patterns

### Blade Basics

Assume every variable could contain malicious HTML:
```blade
{{ $user->name }}                   {{-- ALWAYS: auto-escapes with htmlspecialchars --}}
{!! $user->name !!}                 {{-- NEVER: raw, unescaped output --}}
```

Only use `{!! !!}` for trusted HTML you generated (e.g., rendered Markdown from your own system).

### Layout Patterns

**Component-based layout (Laravel 11+ default):**
```blade
{{-- resources/views/components/layouts/app.blade.php --}}
<!DOCTYPE html>
<html>
<head><title>{{ $title ?? 'App' }}</title></head>
<body>
    <nav>...</nav>
    <main>{{ $slot }}</main>
</body>
</html>

{{-- resources/views/orders/index.blade.php --}}
<x-layouts.app title="Orders">
    <h1>Orders</h1>
    ...
</x-layouts.app>
```

**Template inheritance layout (common in existing projects):**
```blade
{{-- resources/views/layouts/app.blade.php --}}
<!DOCTYPE html>
<html>
<head><title>@yield('title', 'App')</title></head>
<body>
    @include('partials.nav')
    <main>@yield('content')</main>
</body>
</html>

{{-- resources/views/orders/index.blade.php --}}
@extends('layouts.app')
@section('title', 'Orders')
@section('content')
    <h1>Orders</h1>
    ...
@endsection
```

**Match the existing project's layout approach.** Do not mix component-based and inheritance-based layouts in the same project.

### Blade Components

```blade
{{-- Anonymous component: resources/views/components/alert.blade.php --}}
@props(['type' => 'info', 'message'])
<div class="alert alert-{{ $type }}">
    {{ $message }}
</div>

{{-- Usage --}}
<x-alert type="success" message="Order created!" />
```

### Forms

Always use `@csrf` in forms:
```blade
<form method="POST" action="{{ route('orders.store') }}">
    @csrf
    {{-- For PUT/PATCH/DELETE --}}
    @method('PUT')

    <input type="text" name="notes" value="{{ old('notes', $order->notes) }}">
    @error('notes')
        <span class="text-danger">{{ $message }}</span>
    @enderror

    <button type="submit">Save</button>
</form>
```

- Use `{{ old('field', $model->field) }}` to repopulate forms on validation failure.
- Use `@error('field')` directive to show field-specific validation errors.
- Use `route()` helper for URL generation, never hardcode paths.
- Use `$this->Form->create($entity)` only if using a CakePHP-style helper — Laravel uses plain HTML forms with `@csrf`.
- Match the CSS framework and layout patterns already in the project.

---

## Email / Notification Patterns

### Mailable Classes

```php
// app/Mail/OrderShipped.php
class OrderShipped extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly Order $order,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Your Order Has Shipped',
        );
    }

    public function content(): Content
    {
        return new Content(
            markdown: 'emails.orders.shipped',
            with: [
                'orderUrl' => route('orders.show', $this->order),
            ],
        );
    }
}
```

### Notification Classes

```php
// app/Notifications/OrderShippedNotification.php
class OrderShippedNotification extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(
        private readonly Order $order,
    ) {}

    public function via(object $notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Your Order Has Shipped')
            ->greeting("Hello {$notifiable->name},")
            ->line("Your order #{$this->order->id} has been shipped.")
            ->action('View Order', route('orders.show', $this->order))
            ->line('Thank you for your purchase!');
    }

    public function toArray(object $notifiable): array
    {
        return [
            'order_id' => $this->order->id,
            'message' => "Order #{$this->order->id} has been shipped.",
        ];
    }
}
```

**Rules:**
- Use Mailables for transactional emails, Notifications for multi-channel (mail + database + SMS + Slack).
- Always use Blade templates for email content. Never build HTML strings in PHP.
- Use Markdown mail for simple notifications, custom Blade views for branded emails.
- Queue emails and notifications with `implements ShouldQueue` for any feature that sends email.

---

## Event / Listener Patterns

### Event Auto-Discovery (Laravel 11+)

Laravel 11 auto-discovers events and listeners. No manual registration needed.

```php
// app/Events/OrderCreated.php
class OrderCreated
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly Order $order,
    ) {}
}

// app/Listeners/SendOrderConfirmation.php
class SendOrderConfirmation implements ShouldQueue
{
    public function handle(OrderCreated $event): void
    {
        $event->order->user->notify(
            new OrderConfirmationNotification($event->order)
        );
    }
}
```

**Rules:**
- Listeners that do I/O (send email, call API, write to queue) should implement `ShouldQueue`.
- Use `ShouldDispatchAfterCommit` on events that dispatch inside database transactions to avoid dispatching before the commit.
- Name events as past-tense facts (`OrderCreated`, `PaymentFailed`). Name listeners as imperative actions (`SendConfirmation`, `UpdateInventory`).
- Dispatch events via `event(new OrderCreated($order))` or `OrderCreated::dispatch($order)`.

---

## Queue / Job Patterns

```php
// app/Jobs/ProcessPayment.php
class ProcessPayment implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;
    public int $backoff = 60;
    public int $timeout = 120;

    public function __construct(
        private readonly Order $order,
    ) {}

    public function handle(PaymentGateway $gateway): void
    {
        $result = $gateway->charge($this->order->total, $this->order->user);

        if ($result->failed()) {
            $this->order->update(['status' => OrderStatus::PaymentFailed]);
            return;
        }

        $this->order->update(['status' => OrderStatus::Paid]);
        event(new PaymentReceived($this->order));
    }

    public function failed(\Throwable $exception): void
    {
        // Notify admin of payment failure
        Log::error('Payment processing failed', [
            'order_id' => $this->order->id,
            'error' => $exception->getMessage(),
        ]);
    }
}

// Dispatch
ProcessPayment::dispatch($order);
ProcessPayment::dispatch($order)->onQueue('payments');
ProcessPayment::dispatch($order)->delay(now()->addMinutes(5));
```

**Rules:**
- Always set `$tries`, `$backoff`, and `$timeout`.
- Implement `failed()` for error handling and alerting.
- Use `->onQueue('name')` to separate critical from bulk work.
- Jobs must be idempotent — safe to retry after partial failure.
- Use `Bus::chain([...])` for sequential multi-step operations.
- Use `Bus::batch([...])` for parallel processing with completion callbacks.

---

## Middleware Patterns

### Defining Middleware (Laravel 11+)

```php
// app/Http/Middleware/EnsureUserIsAdmin.php
class EnsureUserIsAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->user()?->is_admin) {
            abort(403, 'Unauthorized.');
        }

        return $next($request);
    }
}
```

### Registering Middleware (Laravel 11+)

```php
// bootstrap/app.php
->withMiddleware(function (Middleware $middleware) {
    $middleware->alias([
        'admin' => EnsureUserIsAdmin::class,
    ]);

    $middleware->append(TrackPageViews::class);

    $middleware->web(append: [
        HandleInertiaRequests::class,
    ]);
})
```

### Using Middleware on Routes

```php
Route::middleware('admin')->group(function () {
    Route::get('/admin/dashboard', [AdminController::class, 'dashboard']);
});

// Or on a single route
Route::get('/admin/users', [AdminController::class, 'users'])->middleware('admin');
```

---

## Route Patterns

### Web Routes

```php
// routes/web.php
use App\Http\Controllers\OrderController;

// Resource routes (generates index, create, store, show, edit, update, destroy)
Route::resource('orders', OrderController::class);

// Partial resource
Route::resource('orders', OrderController::class)->only(['index', 'show']);
Route::resource('orders', OrderController::class)->except(['destroy']);

// Nested resource
Route::resource('users.orders', OrderController::class)->scoped();

// Single-action controller
Route::post('/orders/{order}/ship', MarkOrderShippedController::class)
    ->name('orders.ship');

// Grouped routes with middleware
Route::middleware(['auth', 'verified'])->group(function () {
    Route::get('/dashboard', DashboardController::class)->name('dashboard');
    Route::resource('orders', OrderController::class);
});

// Prefix group
Route::prefix('admin')->middleware('admin')->name('admin.')->group(function () {
    Route::resource('users', Admin\UserController::class);
});
```

### API Routes

```php
// routes/api.php
Route::middleware('auth:sanctum')->group(function () {
    Route::apiResource('orders', Api\OrderController::class);
    Route::post('/orders/{order}/ship', Api\MarkOrderShippedController::class);
});
```

**Route rules:**
- Use `Route::resource()` / `Route::apiResource()` for CRUD routes.
- Use route model binding: `Route::get('/orders/{order}', ...)` auto-resolves to `Order` model.
- Use `->name('orders.ship')` on custom routes so views can use `route('orders.ship', $order)`.
- Read existing routes file. Understand the patterns. Add yours at the end of the appropriate group.
- Ask: "Could my route pattern accidentally match a URL that something else is supposed to handle?"
- Use `php artisan route:list` to verify no conflicts.

---

## Artisan Command Patterns

```php
// app/Console/Commands/SendWeeklyReport.php
class SendWeeklyReport extends Command
{
    protected $signature = 'reports:weekly
                            {--dry-run : Preview without sending}
                            {--user= : Send only for a specific user}';

    protected $description = 'Send weekly report emails to all active users';

    public function handle(ReportService $reportService): int
    {
        $isDryRun = $this->option('dry-run');

        $users = $this->option('user')
            ? User::where('id', $this->option('user'))->get()
            : User::active()->get();

        $bar = $this->output->createProgressBar($users->count());

        foreach ($users as $user) {
            if ($isDryRun) {
                $this->info("Would send report to {$user->email}");
            } else {
                $reportService->sendWeeklyReport($user);
            }
            $bar->advance();
        }

        $bar->finish();
        $this->newLine();
        $this->info('Done.');

        return Command::SUCCESS;
    }
}
```

- Return `Command::SUCCESS` (0) or `Command::FAILURE` (1) -- never `exit()`.
- Use dependency injection in `handle()` for services.
- Use `ConsoleOutput` methods (`info`, `error`, `table`, `progressBar`) for output, not `echo`.
- Register scheduled tasks in `routes/console.php` (Laravel 11+):

```php
// routes/console.php
use Illuminate\Support\Facades\Schedule;

Schedule::command('reports:weekly')->weeklyOn(1, '8:00');
Schedule::command('queue:prune-batches --hours=48')->daily();
```

---

## Date/Time Handling

Laravel uses Carbon (immutable by default in models since Laravel 8+):
```php
use Illuminate\Support\Carbon;

$now = Carbon::now();
$yesterday = Carbon::yesterday();
$formatted = now()->format('Y-m-d H:i:s');
$iso = now()->toIso8601String();

// Relative
$threeDaysAgo = now()->subDays(3);
$nextWeek = now()->addWeek();

// Comparison
$order->created_at->isToday();
$order->created_at->diffForHumans(); // "2 hours ago"
```

Database datetime columns are automatically cast to Carbon instances on models. Use `->format()` in templates, not PHP's `date()`. Use `now()` helper instead of `Carbon::now()` in most cases.

---

## Security Patterns

### Authentication

Laravel provides Breeze (simple), Jetstream (advanced), or Fortify (headless) for authentication scaffolding. **Check which the project uses and match it.**

For API authentication, use Laravel Sanctum (token-based) or Passport (full OAuth2).

### Authorization (Policies and Gates)

```php
// app/Policies/OrderPolicy.php
class OrderPolicy
{
    public function view(User $user, Order $order): bool
    {
        return $user->id === $order->user_id || $user->is_admin;
    }

    public function update(User $user, Order $order): bool
    {
        return $user->id === $order->user_id
            && $order->status === OrderStatus::Pending;
    }

    public function delete(User $user, Order $order): bool
    {
        return $user->is_admin;
    }
}
```

Policies are auto-discovered when they follow naming conventions (`OrderPolicy` for `Order` model in `app/Policies/`).

Usage in controllers:
```php
$this->authorize('update', $order);             // In controller method
Gate::authorize('update', $order);              // Via Gate facade
$request->user()->can('update', $order);        // Inline check
```

Usage in Blade:
```blade
@can('update', $order)
    <a href="{{ route('orders.edit', $order) }}">Edit</a>
@endcan
```

### Gates (for non-model actions)

```php
// app/Providers/AppServiceProvider.php boot()
Gate::define('access-admin', function (User $user) {
    return $user->is_admin;
});
```

### CSRF Protection

Laravel automatically protects against CSRF. All POST/PUT/PATCH/DELETE forms must include `@csrf`:
```blade
<form method="POST" action="/orders">
    @csrf
    ...
</form>
```

For AJAX requests, include the token in headers:
```javascript
axios.defaults.headers.common['X-CSRF-TOKEN'] = document
    .querySelector('meta[name="csrf-token"]')
    .getAttribute('content');
```

### Input Validation

Always validate input. Never trust `$request->all()`:
```php
// In Form Request (preferred)
public function rules(): array
{
    return [
        'email' => ['required', 'email', 'unique:users,email'],
        'password' => ['required', 'min:8', 'confirmed'],
        'role' => ['prohibited'],  // Block mass-assignment of role
    ];
}

// Inline (only for simple one-off cases)
$validated = $request->validate([
    'name' => 'required|string|max:255',
]);
```

### Rate Limiting

```php
// bootstrap/app.php or AppServiceProvider
RateLimiter::for('login', function (Request $request) {
    return Limit::perMinute(5)->by($request->ip());
});

// In routes
Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:login');
```

### SQL Injection Prevention

Eloquent and Query Builder use prepared statements by default. **Never use raw queries with string interpolation:**
```php
// GOOD: parameterized
User::where('email', $email)->first();
DB::select('SELECT * FROM users WHERE email = ?', [$email]);

// BAD: SQL injection
DB::select("SELECT * FROM users WHERE email = '$email'");
```

### XSS Prevention

Blade `{{ }}` auto-escapes output. Never use `{!! !!}` with user input. For JSON in `<script>` tags:
```blade
<script>
    const data = @json($data);  {{-- Safe: uses JSON_HEX_TAG etc. --}}
</script>
```

---

## Test Patterns

### Test Infrastructure

```bash
ls tests/Feature/                    # What feature test patterns exist?
ls tests/Unit/                       # What unit test patterns exist?
php artisan test                     # Run all tests
php artisan test --filter=OrderTest  # Run specific test
php artisan test --parallel          # Parallel execution (with ParaTest)
```

### Feature Tests (PHPUnit)

```php
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OrderControllerTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_view_own_orders(): void
    {
        $user = User::factory()->create();
        $order = Order::factory()->for($user)->create();

        $this->actingAs($user)
            ->get(route('orders.show', $order))
            ->assertOk()
            ->assertViewHas('order', $order);
    }

    public function test_user_cannot_view_others_orders(): void
    {
        $user = User::factory()->create();
        $otherUser = User::factory()->create();
        $order = Order::factory()->for($otherUser)->create();

        $this->actingAs($user)
            ->get(route('orders.show', $order))
            ->assertForbidden();
    }

    public function test_order_creation_stores_record_and_dispatches_event(): void
    {
        Event::fake([OrderCreated::class]);

        $user = User::factory()->create();
        $product = Product::factory()->create(['price' => 29.99]);

        $this->actingAs($user)
            ->post(route('orders.store'), [
                'items' => [
                    ['product_id' => $product->id, 'quantity' => 2],
                ],
            ])
            ->assertRedirect()
            ->assertSessionHas('success');

        // Side-effect: DB record exists
        $this->assertDatabaseHas('orders', [
            'user_id' => $user->id,
            'status' => 'pending',
        ]);

        // Side-effect: Event dispatched through real framework plumbing
        Event::assertDispatched(OrderCreated::class, function ($event) use ($user) {
            return $event->order->user_id === $user->id;
        });
    }
}
```

### Feature Tests (Pest)

```php
use App\Models\User;
use App\Models\Order;

uses(Tests\TestCase::class, Illuminate\Foundation\Testing\RefreshDatabase::class);

it('allows user to view own orders', function () {
    $user = User::factory()->create();
    $order = Order::factory()->for($user)->create();

    $this->actingAs($user)
        ->get(route('orders.show', $order))
        ->assertOk()
        ->assertViewHas('order', $order);
});

it('prevents user from viewing other users orders', function () {
    $user = User::factory()->create();
    $order = Order::factory()->for(User::factory())->create();

    $this->actingAs($user)
        ->get(route('orders.show', $order))
        ->assertForbidden();
});

it('validates required fields on order creation', function () {
    $this->actingAs(User::factory()->create())
        ->post(route('orders.store'), [])
        ->assertSessionHasErrors(['items']);
});
```

### Security Test Examples

```php
// Auth bypass
public function test_protected_route_redirects_without_login(): void
{
    $this->get(route('orders.index'))
        ->assertRedirect(route('login'));
}

// CSRF bypass
public function test_form_submit_without_csrf_fails(): void
{
    $user = User::factory()->create();

    $this->actingAs($user)
        ->withoutMiddleware(\Illuminate\Foundation\Http\Middleware\VerifyCsrfToken::class)
        // Actually test WITH middleware by not calling withoutMiddleware:
        ->post(route('orders.store'), ['items' => []])
        ->assertStatus(419); // CSRF token mismatch
}

// IDOR
public function test_user_cannot_update_others_order(): void
{
    $user = User::factory()->create();
    $otherOrder = Order::factory()->for(User::factory())->create();

    $this->actingAs($user)
        ->put(route('orders.update', $otherOrder), ['notes' => 'hacked'])
        ->assertForbidden();
}

// Mass assignment
public function test_cannot_set_admin_role_via_mass_assignment(): void
{
    $this->post(route('register'), [
        'name' => 'Hacker',
        'email' => 'hacker@example.com',
        'password' => 'Test1234!',
        'password_confirmation' => 'Test1234!',
        'is_admin' => true,
    ]);

    $user = User::where('email', 'hacker@example.com')->first();
    if ($user) {
        $this->assertFalse($user->is_admin);
    }
}
```

### Factory Patterns

```php
// database/factories/OrderFactory.php
class OrderFactory extends Factory
{
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'status' => OrderStatus::Pending,
            'total' => $this->faker->randomFloat(2, 10, 500),
            'notes' => $this->faker->optional()->sentence(),
            'created_at' => now(),
        ];
    }

    // Named states for test scenarios
    public function shipped(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => OrderStatus::Shipped,
            'shipped_at' => now(),
        ]);
    }

    public function cancelled(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => OrderStatus::Cancelled,
        ]);
    }
}

// Usage in tests
Order::factory()->count(5)->shipped()->for($user)->create();
```

### Database Assertions

```php
$this->assertDatabaseHas('orders', ['user_id' => $user->id, 'status' => 'pending']);
$this->assertDatabaseMissing('orders', ['status' => 'cancelled']);
$this->assertDatabaseCount('orders', 3);
$this->assertSoftDeleted('orders', ['id' => $order->id]);
$this->assertModelExists($order);
$this->assertModelMissing($deletedOrder);
```

### Testing Framework Plumbing (motspilot integration test requirement)

For any runtime path that runs inside framework plumbing (events, middleware, observers, lifecycle hooks, schedulers, queues), at least one test must exercise the real dispatch mechanism:

```php
// GOOD: Tests real event dispatch through framework plumbing
public function test_order_creation_fires_event_through_dispatcher(): void
{
    Event::fake([OrderCreated::class]);

    // This goes through the full HTTP stack -> controller -> service -> event()
    $this->actingAs($user)
        ->post(route('orders.store'), $validData)
        ->assertRedirect();

    Event::assertDispatched(OrderCreated::class);
}

// BAD: Reflection-based — directly calling listener handle() method
// This does NOT prove the listener is wired to the event
public function test_listener_handles_event(): void
{
    $listener = new SendOrderConfirmation();
    $listener->handle(new OrderCreated($order));
    // This only tests the listener logic, not the wiring
}
```

```php
// GOOD: Tests real middleware through HTTP stack
public function test_admin_middleware_blocks_non_admin(): void
{
    $user = User::factory()->create(['is_admin' => false]);

    $this->actingAs($user)
        ->get('/admin/dashboard')
        ->assertForbidden();
}

// GOOD: Tests real queue dispatch
public function test_payment_job_is_dispatched_to_queue(): void
{
    Queue::fake();

    $this->actingAs($user)
        ->post(route('orders.pay', $order))
        ->assertRedirect();

    Queue::assertPushed(ProcessPayment::class, function ($job) use ($order) {
        return $job->order->id === $order->id;
    });
}
```

### Runtime Path Classification

The testing summary must include a runtime-path classification table:

| Path | Type | Test Strategy |
|------|------|--------------|
| OrderService::calculateTotal() | (a) pure logic | Unit test |
| OrderCreated event -> SendConfirmation listener | (b) plumbing-dependent | Feature test with Event::fake() |
| ProcessPayment job -> PaymentGateway API | (c) external I/O | Feature test with Queue::fake() + unit test with mocked gateway |

---

## Verification Checks

Run these searches to catch common mistakes. **Note for subagents:** Use the Grep tool (not shell `grep`) for these checks -- it handles permissions correctly and integrates with the tool output.

```bash
# Mass assignment vulnerability — empty guarded:
grep -rn "guarded = \[\]" app/Models/
# Review each result. Empty guard allows ALL fields.

# Mass assignment — wildcard fillable:
grep -rn "fillable.*\*" app/Models/
# Should find ZERO results.

# Raw unescaped output:
grep -rn "{!!" resources/views/
# Every result is potential XSS. Verify each is trusted HTML.

# Raw SQL with string interpolation:
grep -rn "DB::raw\|DB::select.*\\\$\|DB::statement.*\\\$" app/
# Each result needs manual review for SQL injection.

# Direct superglobals:
grep -rn "\$_POST\|\$_GET\|\$_REQUEST\|\$_SERVER" app/
# Should find ZERO results in app/. Use Request object.

# env() called outside config files:
grep -rn "env(" app/ routes/
# Should find ZERO results. env() returns null when config is cached.
# All env() calls must be in config/*.php files only.

# Sensitive fields in $fillable:
grep -rn "fillable" app/Models/ | grep -i "role\|admin\|password\|is_admin\|is_verified"
# Each result needs review for privilege escalation.

# Missing auth middleware on routes:
grep -rn "Route::" routes/web.php | grep -v "middleware\|login\|register\|password\|verification\|__invoke"
# Unprotected routes need review.

# N+1 queries — lazy loading in loops:
grep -rn "->each\|->map\|foreach" app/ | grep -v "with\|load"
# Review for potential N+1 patterns.

# Deprecated accessor/mutator syntax used in new code:
grep -rn "get.*Attribute\|set.*Attribute" app/Models/
# In Laravel 11+ projects, new code should use Attribute::make().
# Existing code using old syntax is fine — don't refactor unless asked.

# Missing return types on relationships:
grep -rn "function.*():.*{" app/Models/ | grep -v "HasMany\|BelongsTo\|HasOne\|BelongsToMany\|MorphTo\|MorphMany\|MorphOne\|Attribute\|array\|string\|bool\|int\|void\|static\|self"
# Relationship methods should have typed return types.
```

---

## Deployment Commands

### Deploy

```bash
# Install dependencies (production)
composer install --no-dev --optimize-autoloader

# Run migrations
php artisan migrate --force

# Cache everything for performance
php artisan optimize

# This is equivalent to running all of:
# php artisan config:cache
# php artisan route:cache
# php artisan view:cache
# php artisan event:cache

# If using queue workers, restart them to pick up new code
php artisan queue:restart
```

### Rollback

```bash
# Code-level rollback
git checkout PREVIOUS_COMMIT
composer install --no-dev --optimize-autoloader
php artisan migrate:rollback
php artisan optimize

# Nuclear rollback (if database is in bad state)
mysql -u USER -p DATABASE < backup_YYYYMMDD_HHMMSS.sql
git checkout PREVIOUS_COMMIT
composer install --no-dev --optimize-autoloader
php artisan optimize
```

### Clear Caches (Development)

```bash
# Clear all caches at once
php artisan optimize:clear

# Individual cache clearing
php artisan cache:clear          # Application cache
php artisan config:clear         # Config cache
php artisan route:clear          # Route cache
php artisan view:clear           # Compiled Blade views
php artisan event:clear          # Event/listener cache
```

### Smoke Tests

Every smoke test must assert **both** that the route is reachable **and** that the route's expected side effect actually happened. Status-code-only tests cannot distinguish "works" from "silently broken" -- a 200 with an empty insert is still a bug.

Generic template:

```bash
# Entry-point check -- proves the route is reachable
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' https://APP_URL/new-route)
test "$HTTP_CODE" = "200" || { echo "FAIL: route unreachable ($HTTP_CODE)"; exit 1; }

# Side-effect check -- proves the route did the expected work.
# Example: if the route writes to a DB table, assert the row landed
# Example: if the route sends an email, assert the mail catcher received it
# Example: if the route updates cache, assert the cache key changed
# Adapt this pattern to the framework's preferred DB/email/cache tooling.
```

**Laravel-specific shape (adapt, do not copy):** the cleanest way to query a side effect from a shell script is to use `php artisan tinker --execute`. If the project has a smoke command, use that. Otherwise fall back to the `mysql` CLI or `php artisan tinker`.

```bash
# DB side-effect via artisan tinker
ROW_COUNT=$(php artisan tinker --execute="echo App\Models\Order::where('created_at', '>=', now()->subMinute())->count();")
test "$ROW_COUNT" -gt 0 || { echo "FAIL: expected row in orders"; exit 1; }
```

Or, direct DB query when tinker is overkill:

```bash
ROW_COUNT=$(mysql -N -B -e "SELECT COUNT(*) FROM orders WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 MINUTE)" mydb)
test "$ROW_COUNT" -gt 0 || { echo "FAIL: expected row in orders"; exit 1; }
```

For email side effects, use whichever mail catcher the project runs (Mailpit, MailHog, smtp4dev). Mailpit and MailHog expose a compatible HTTP API on port 8025 by default: `curl -s http://localhost:8025/api/v2/messages | jq '.total'` and assert the count increased.

For queue side effects, check that the job was dispatched and processed:
```bash
# Check failed jobs table is empty (no failures)
FAILED=$(php artisan tinker --execute="echo DB::table('failed_jobs')->where('failed_at', '>=', now()->subMinutes(5))->count();")
test "$FAILED" -eq 0 || { echo "FAIL: found $FAILED failed jobs"; exit 1; }
```

For cache side effects:
```bash
# Redis cache check
CACHE_VALUE=$(redis-cli GET "laravel_cache:my_key")
test -n "$CACHE_VALUE" || { echo "FAIL: expected cache key"; exit 1; }
```

> The delivery phase gates on smoke test execution -- see `prompts/delivery.md` section 3.2. Smoke tests without side-effect checks are treated as zero tests and fail the phase.

Check logs after deploy:
```bash
tail -f storage/logs/laravel.log
```

---

## Claude Code Skills Reference

Use these Claude Code capabilities at the right time to save effort and catch mistakes early:

| Skill / Pattern | When to Use | Why |
|---|---|---|
| **Explore agent** | Before writing anything new | Finds existing patterns to match -- prevents reinventing what is already in the codebase |
| **Plan agent** | Before multi-file features | Architects the approach first so you do not code yourself into a corner |
| **`/simplify`** | After finishing code | Catches duplication, missed reuse opportunities, over-engineering |
| **Background tasks** (`run_in_background`) | DB imports, long migrations, full test suites | Avoids timeout on commands that take > 2 minutes |
| **Parallel tool calls** | Independent file reads, searches, glob+grep combos | Do not read 5 files sequentially when you can read them all at once |
| **Mail catcher API check** (`curl localhost:8025/api/v2/messages` -- Mailpit/MailHog) | After any feature that sends email | Visually verify the email rendered correctly |

### When to Use Which Agent

- **Quick search** (specific file/class/function) -> Use Glob or Grep directly
- **Broad exploration** (understanding a module, finding patterns across codebase) -> Explore agent
- **Multi-step implementation planning** -> Plan agent
- **Running a phase of work autonomously** -> General-purpose agent

### Common Time-Wasters to Avoid

- Do not build HTML inline in services/jobs/listeners -- always create Blade templates or Mailable classes
- Do not guess at styling -- find an existing view and match it exactly
- Do not run long DB scripts with default timeout -- use `run_in_background` or extended timeout
- Do not call `env()` outside of `config/` files -- it returns null when config is cached
- Do not skip Form Requests for "simple" validation -- consistency matters more than brevity
- Do not add routes outside the existing route group structure -- read the file first

---

## Common Pitfalls

- **`env()` outside config files.** After `php artisan config:cache`, `env()` returns null everywhere except in `config/*.php` files. Always use `config('app.key')` instead.
- **Missing `--force` on production migrations.** `php artisan migrate` prompts for confirmation in production. Use `--force` in deploy scripts.
- **N+1 queries.** Use `->with()` for eager loading. Enable `Model::preventLazyLoading()` in `AppServiceProvider::boot()` during development.
- **Mass assignment on sensitive fields.** Never put `is_admin`, `role`, `email_verified_at` in `$fillable`. Use `$guarded` or explicit assignment.
- **Forgetting `@csrf` in forms.** Results in 419 status code. Every POST/PUT/PATCH/DELETE form needs it.
- **Testing with `$request->all()` instead of `$request->validated()`.** The former includes unvalidated fields -- potential mass assignment vector.
- **String-based scheduling in wrong file.** Laravel 11+ uses `routes/console.php`, not `Kernel.php`.
- **Forgetting to restart queue workers after deploy.** Workers load code into memory at boot. Use `php artisan queue:restart`.
- **Caching config in development.** Run `php artisan config:clear` after `.env` changes, or just do not cache in dev.
- **Not using transactions for multi-model writes.** If one save fails, the others are orphaned. Wrap in `DB::transaction()`.
- **Putting business logic in Eloquent observers.** Observers make control flow invisible. Prefer explicit event dispatch or service methods.
- **Using `Schema::hasColumn()` inside models.** This runs a DB query every request. Use it only in migrations.

---

## Self-Doubt Checklist

After completing work, run through these. **If any answer is "I'm not sure", verify.**

**Models:**
- [ ] Did I put sensitive fields (`is_admin`, `role`, `password`) in `$fillable`? -> Remove them.
- [ ] Did I use `$guarded = []` (empty guard)? -> Add specific guarded fields or use `$fillable`.
- [ ] Did I use old-style `getNameAttribute()` accessors in a Laravel 11+ project? -> Use `Attribute::make()`.
- [ ] Did I use `protected $casts = []` property instead of `casts()` method in Laravel 11+? -> Match project convention.
- [ ] Did I forget return types on relationship methods? -> Add `HasMany`, `BelongsTo`, etc.
- [ ] Did I lazy-load relationships in a loop instead of using `->with()`?
- [ ] Did I forget `$hidden` on models with passwords/tokens that get serialized?

**Controllers:**
- [ ] Did I put validation logic directly in a controller? -> Move to Form Request class.
- [ ] Did I use `$request->all()` instead of `$request->validated()`?
- [ ] Did I put business logic in controller private methods? -> Move to Service/Action/Model.
- [ ] Did I manually find a model instead of using route model binding?
- [ ] Did I forget authorization checks (`$this->authorize()`, Policy, Gate)?

**Views:**
- [ ] Did I use `{!! $var !!}` with user-supplied data? -> Use `{{ $var }}`.
- [ ] Did I forget `@csrf` in any form?
- [ ] Did I forget `@method('PUT')` / `@method('DELETE')` for non-POST forms?
- [ ] Did I hardcode URLs instead of using `route()` helper?
- [ ] Did I forget `old('field')` for form repopulation on validation failure?

**Routes:**
- [ ] Did I add routes outside the appropriate middleware group?
- [ ] Did I forget `->name()` on custom routes?
- [ ] Did I run `php artisan route:list` to check for conflicts?

**Config & Environment:**
- [ ] Did I call `env()` anywhere outside of `config/*.php` files?
- [ ] Did I add new config values without updating `.env.example`?

**Database:**
- [ ] Did I include `down()` in every migration?
- [ ] Did I use foreign key constraints with explicit cascade behavior?
- [ ] Did I index columns used in WHERE/JOIN/ORDER BY?
- [ ] Did I wrap multi-model writes in `DB::transaction()`?

**Security:**
- [ ] Is there any place a user could access another user's data by guessing an ID? -> Add policy check.
- [ ] Did I use raw DB queries with string interpolation? -> Use parameterized queries.
- [ ] Did I expose internal IDs or database structure in API responses? -> Use API Resources.
- [ ] Did I rate-limit sensitive endpoints (login, register, password reset)?

**Events & Queues:**
- [ ] Did I dispatch events inside a transaction without `ShouldDispatchAfterCommit`?
- [ ] Did I forget to implement `ShouldQueue` on listeners that do I/O?
- [ ] Did I forget `$tries`, `$backoff`, `$timeout` on queue jobs?
- [ ] Did I forget the `failed()` method on queue jobs?

**Tests:**
- [ ] Did I test framework plumbing paths (events, middleware, queues) through the HTTP stack, not just unit tests?
- [ ] Did I use `RefreshDatabase` trait in feature tests?
- [ ] Did I test both the happy path and error/edge cases?
- [ ] Did I test authorization (can't access other user's resources)?
- [ ] Did I test validation (missing fields, invalid data)?
