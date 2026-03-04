# Contributing to motspilot

The most valuable contribution you can make is a **framework guide** — a document that teaches the AI pipeline how to work with a specific framework.

---

## What Are Framework Guides?

Framework guides live in `prompts/frameworks/<name>.md`. They're included automatically in every pipeline phase when `FRAMEWORK="<name>"` is set in `.motspilot/config`.

Without a guide, the pipeline still works — it discovers framework patterns from your codebase. But a guide makes the AI dramatically more precise by providing:

- **Version-specific API patterns** — so the AI doesn't use CakePHP 5.x syntax in a 4.x project, or React class components in a hooks-based codebase
- **Naming conventions** — so new files follow existing project structure
- **Verification checks** — grep patterns that catch common mistakes for that framework
- **Deployment commands** — exact commands for migrations, cache clearing, rollback

The CakePHP guide (`prompts/frameworks/cakephp.md`) is the reference implementation.

---

## Writing a Framework Guide

### 1. Fork and clone this repo

### 2. Create `prompts/frameworks/<name>.md`

Use lowercase, hyphen-separated names that match what users type in config:
- `laravel.md` (for `FRAMEWORK="laravel"`)
- `nextjs.md` (for `FRAMEWORK="nextjs"`)
- `ruby-on-rails.md` (for `FRAMEWORK="ruby-on-rails"`)

### 3. Include these sections

Every guide should cover:

```markdown
# <Framework> <Version> Framework Guide

This file is automatically included by the motspilot pipeline when
`FRAMEWORK="<name>"` is set in config.

---

## Version Reference

| What | <Version> (correct) | <Other Version> (WRONG) |
|------|---------------------|-------------------------|
| ... | ... | ... |

Document the API differences that trip people up most.
Focus on the version you're targeting.

---

## Naming Conventions

How files, classes, routes, and database objects are named.

---

## Files to Explore (Architecture Phase)

Key landmark files the AI should read to understand a project
using this framework. Example:

  src/Application.php → middleware, plugins, auth wiring
  config/routes.php   → URL patterns and conventions

---

## Migration / Schema Patterns

How to create, run, and rollback schema changes.
Include the exact commands and any idempotency patterns.

---

## Model / Entity Patterns

Access control, validation, relationships, mass assignment protection.

---

## Service / Business Logic Patterns

Where business logic lives. Conventions for service classes.

---

## Controller / Handler Patterns

Request handling conventions. Max action length. Input parsing.

---

## Template / View Patterns

Output escaping, form helpers, CSRF handling, layout structure.

---

## Test Patterns

Test setup, fixtures/factories, security test examples.
Include concrete code examples.

---

## Verification Checks

Grep patterns to catch common mistakes. Example:

  grep -r "BadPattern" src/
  # Should find ZERO results. Explanation of why.

These are run automatically during the verification phase.

---

## Deployment Commands

Exact commands for: migrate, rollback, cache clear, dependency install.
```

### 4. Be version-specific

State the exact framework version in the title and first line. The API differences between major versions are exactly what these guides exist to catch.

Good: `# Laravel 11.x Framework Guide`
Bad: `# Laravel Framework Guide`

### 5. Submit a pull request

- Title: `Add <framework> <version> framework guide`
- Body: briefly describe your experience level with the framework and how you tested the guide

---

## Other Contributions

Bug reports, shell script improvements, and documentation fixes are also welcome. Open an issue first for anything non-trivial so we can discuss the approach.

---

## Public Repository Rules

motspilot is a public repository. All content — examples, docs, framework guides — must be generic:

- **Never use client names, brand names, or product-specific text** in examples or documentation. Use generic placeholders (`APP_NAME`, `Team`, `example.com`).
- **Never include real URLs, email addresses, or API keys** — even in commented-out examples.
- **File references are OK** — referencing a filename like `email_weekly_report.php` is fine; referencing `[ClientName] Weekly Report` as email subject text is not.

If you're porting patterns from a real project into a guide, scrub all identifiers first.

---

## Code Style

- Shell script: follow the existing patterns in `motspilot.sh`
- Markdown: keep it readable, use consistent heading levels
- Framework guides: write like you're explaining to a senior developer who doesn't know this specific framework — not a tutorial, not a reference manual

---

## Response Times

This project is maintained alongside the author's primary work. Please be patient with issue and PR responses — they may take a week or more. If your issue is critical (security, data loss), flag it in the title and it will be prioritized.

The best way to get a fix merged quickly is to submit a well-tested PR with a clear description of the problem and solution.
