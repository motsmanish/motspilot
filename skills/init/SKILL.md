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

5. **Set up consensus (interactive — ask, don't defer):**

   Check if consensus can run:
   - Run `php --version` — is PHP 8.0+ available?
   - Check for API keys in shell environment: `$ANTHROPIC_API_KEY`, `$OPENAI_API_KEY`, `$GEMINI_API_KEY`

   Then ask the user ONE question:

   **If PHP is available but keys are missing:**
   > Consensus requires 3 API keys (Anthropic, OpenAI, Google Gemini) to fan out requirements to multiple AI models before the pipeline runs. It's optional — the pipeline works fine without it.
   >
   > Would you like to set up consensus now?
   > 1. **Yes** — I'll tell you which environment variables to add
   > 2. **Skip** — disable consensus, I can enable it later by re-running /mots:init

   If they choose **Yes**, tell them:
   > Add these to your `~/.bashrc` (or `~/.zshrc`), then restart Claude Code:
   > ```
   > export ANTHROPIC_API_KEY="your-key-here"
   > export OPENAI_API_KEY="your-key-here"
   > export GEMINI_API_KEY="your-key-here"
   > ```
   > After restarting, run `/mots:init` again and I'll detect them automatically.

   Set `CONSENSUS=disabled` in config for now (it will be enabled on next init when keys are detected).

   **If PHP is missing:**
   > Consensus requires PHP 8.0+ (not installed). Skipping — the pipeline works without it.

   Set `CONSENSUS=disabled` in config.

   **If PHP and all 3 keys are present:**
   > Consensus is ready (PHP + all 3 API keys detected).

   Set `CONSENSUS=enabled` in config.

6. Show a summary:
   ```
   motspilot initialized for: <project name>
   Language: PHP 8.2
   Framework: Laravel (guide: prompts/frameworks/laravel.md)
   Test command: ./vendor/bin/phpunit
   Consensus: enabled / disabled (reason)

   Next: /mots:pilot <describe what to build>
   ```
