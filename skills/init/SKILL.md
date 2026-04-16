---
name: init
description: Initialize motspilot in the current project. Use when setting up motspilot for the first time in a new project directory.
---

# motspilot Init

Set up motspilot in the current project directory.

## Steps

1. Run the init command:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) init
   ```
   This creates `.motspilot/config` with default values if it doesn't exist.

2. Read the generated `.motspilot/config` file.

3. Auto-detect project settings by scanning the project directory:
   - **Language**: check for `composer.json` (PHP), `package.json` (JS/TS), `requirements.txt`/`pyproject.toml` (Python), `go.mod` (Go), `Gemfile` (Ruby), `pom.xml`/`build.gradle` (Java)
   - **Framework**: check for `config/app.php` + CakePHP in composer.json (CakePHP), `artisan` (Laravel), `manage.py` (Django), `next.config.*` (Next.js), `express` in package.json (Express), etc.
   - **Language version**: read from composer.json require.php, .python-version, .nvmrc, go.mod, etc.
   - **Test command**: check for vendor/bin/phpunit, pytest, npm test, go test, etc.

4. Update `.motspilot/config` with detected values using Edit. Show the user what was detected and let them confirm or adjust.

5. Check consensus dependencies:
   - Run `php --version` — is PHP 8.0+ available?
   - Check if consensus API keys are available via `userConfig` (stored in keychain by Claude Code) or shell environment variables (`$ANTHROPIC_API_KEY`, `$OPENAI_API_KEY`, `$GEMINI_API_KEY`)
   - If PHP or all 3 keys are missing: set CONSENSUS=disabled in config and tell the user consensus is optional, the pipeline works without it
   - If all present: confirm consensus is enabled

6. Show a summary:
   ```
   motspilot initialized for: <project name>
   Language: PHP 8.2
   Framework: CakePHP (guide: prompts/frameworks/cakephp.md)
   Test command: ./vendor/bin/phpunit
   Consensus: enabled / disabled (reason)

   Next: /mots:pilot <describe what to build>
   ```
