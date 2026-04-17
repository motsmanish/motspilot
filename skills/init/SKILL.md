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

5. **Set up consensus (interactive — must block and wait):**

   Check if consensus can run:
   - Run `php --version` — is PHP 8.0+ available?
   - Check process env for `$ANTHROPIC_API_KEY`, `$OPENAI_API_KEY`, `$GEMINI_API_KEY`.
   - If any key is missing from process env, also check whether it's defined in `~/.bashrc` / `~/.zshrc` / `~/.profile` (using `grep -lE 'export (ANTHROPIC|OPENAI|GEMINI)_API_KEY' ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null`). This distinguishes "user never set it" from "Claude Code stripped it."
   - Also check for a project-local file: `.motspilot/.env` in the current working directory.

   **Case A — PHP missing:** Tell the user "Consensus requires PHP 8.0+ (not installed). Skipping — the pipeline works without it." Set `CONSENSUS=disabled` and move on.

   **Case B — all 3 keys resolvable (from env OR from `.motspilot/.env`):** Tell the user "Consensus is ready (keys detected from [source])." Set `CONSENSUS=enabled` and move on.

   **Case C — Claude Code stripping detected** (`ANTHROPIC_API_KEY` is in `~/.bashrc` etc. but not in process env, while OpenAI/Gemini are present):

   This is expected behavior — Claude Code strips `ANTHROPIC_API_KEY` from the session env when the user declines "use this key for your Claude Code session" at startup. The project-local `.env` is the fix.

   Use `AskUserQuestion` to ask: "Your Anthropic key is in ~/.bashrc but Claude Code strips it from this session (by design, so it doesn't bill your API key for Claude Code itself). The standard fix is a project-local `.motspilot/.env` that consensus reads directly. Create one now?"
   Options:
   - `Yes, I'll paste the keys into .motspilot/.env` — print the instructions block below
   - `Skip — keep consensus disabled`

   If Yes, print this block verbatim:

   ```
   In your TERMINAL (not this chat — keys shouldn't touch the transcript), run:

     mkdir -p .motspilot
     cat > .motspilot/.env <<'EOF'
     ANTHROPIC_API_KEY=sk-ant-...
     OPENAI_API_KEY=sk-...
     GEMINI_API_KEY=...
     EOF
     chmod 600 .motspilot/.env

   Replace the three placeholder values with your real keys. Then:
     grep -qxF '.motspilot/.env' .gitignore 2>/dev/null || echo '.motspilot/.env' >> .gitignore

   Re-run /mots:init — consensus will read from the file and flip CONSENSUS=enabled.
   ```

   Set `CONSENSUS=disabled` in config for now.

   **Case D — keys simply absent** (not in env, not in any rc file, no `.motspilot/.env`):

   Use `AskUserQuestion` with options `Yes, show me how to set the env vars` / `Skip for now`.

   If Yes, print verbatim:

   ```
   Two options — pick one:

   Option 1 (recommended) — per-project file, gitignored:
     mkdir -p .motspilot
     cat > .motspilot/.env <<'EOF'
     ANTHROPIC_API_KEY=sk-ant-...
     OPENAI_API_KEY=sk-...
     GEMINI_API_KEY=...
     EOF
     chmod 600 .motspilot/.env
     grep -qxF '.motspilot/.env' .gitignore 2>/dev/null || echo '.motspilot/.env' >> .gitignore

   Option 2 — shell-wide env vars in ~/.bashrc:
     export ANTHROPIC_API_KEY="sk-ant-..."
     export OPENAI_API_KEY="sk-..."
     export GEMINI_API_KEY="..."
   (Note: Claude Code will strip ANTHROPIC_API_KEY from its own session unless
    you accept the startup "use this key" prompt. Option 1 avoids that.)

   Get keys:
     Anthropic: https://console.anthropic.com/settings/keys
     OpenAI:    https://platform.openai.com/api-keys
     Gemini:    https://aistudio.google.com/apikey

   Re-run /mots:init once the file or exports are in place.
   ```

   Set `CONSENSUS=disabled` in config for now.

6. Show a summary:
   ```
   motspilot initialized for: <project name>
   Language: PHP 8.2
   Framework: Laravel (guide: prompts/frameworks/laravel.md)
   Test command: ./vendor/bin/phpunit
   Consensus: enabled / disabled (reason)

   Next: /mots:pilot <describe what to build>
   ```
