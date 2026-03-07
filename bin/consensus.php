#!/usr/bin/env php
<?php
declare(strict_types=1);

/**
 * motspilot Multi-Model Consensus — Standalone CLI
 *
 * Framework-agnostic. Requires only PHP 8.0+ with curl extension.
 *
 * Usage:
 *   php consensus.php --prompt-file=/path/to/prompt.txt --phase=architecture
 *   php consensus.php --prompt="Explain caching strategies" --phase=general
 *   echo "Design a login flow" | php consensus.php --phase=development
 *
 * Output:
 *   Writes synthesized result to stdout.
 *   Logs progress to stderr so stdout stays clean for piping.
 *
 * Exit codes:
 *   0 = success (synthesis on stdout)
 *   1 = all APIs failed
 *   2 = bad arguments / missing config
 */

// ─── Configuration ──────────────────────────────────────────────────────────

const TIMEOUT_SECONDS  = 60;
const CONNECT_TIMEOUT  = 15;
const JUDGE_TIMEOUT    = 120;

// ─── Helpers ────────────────────────────────────────────────────────────────

function stderr(string $msg): void {
    fwrite(STDERR, "[consensus] {$msg}\n");
}

function load_env(string $path): array {
    if (!is_file($path)) {
        return [];
    }
    $vars = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        if (str_contains($line, '=')) {
            [$key, $value] = explode('=', $line, 2);
            $vars[trim($key)] = trim($value);
        }
    }
    return $vars;
}

function parse_args(array $argv): array {
    $opts = ['prompt' => '', 'prompt-file' => '', 'phase' => 'general', 'judge-model' => 'claude-sonnet-4-20250514', 'env-file' => ''];
    foreach (array_slice($argv, 1) as $arg) {
        if (preg_match('/^--([a-z-]+)=(.+)$/s', $arg, $m)) {
            $opts[$m[1]] = $m[2];
        }
    }
    return $opts;
}

// ─── Provider definitions ───────────────────────────────────────────────────

function build_claude_request(string $prompt, string $apiKey): array {
    return [
        'https://api.anthropic.com/v1/messages',
        [
            'Content-Type: application/json',
            'x-api-key: ' . $apiKey,
            'anthropic-version: 2023-06-01',
        ],
        json_encode([
            'model'      => 'claude-sonnet-4-20250514',
            'max_tokens' => 8192,
            'messages'   => [['role' => 'user', 'content' => $prompt]],
        ], JSON_THROW_ON_ERROR),
    ];
}

function build_gpt4o_request(string $prompt, string $apiKey): array {
    return [
        'https://api.openai.com/v1/chat/completions',
        [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $apiKey,
        ],
        json_encode([
            'model'      => 'gpt-4o',
            'max_tokens' => 8192,
            'messages'   => [['role' => 'user', 'content' => $prompt]],
        ], JSON_THROW_ON_ERROR),
    ];
}

function build_gemini_request(string $prompt, string $apiKey): array {
    return [
        sprintf('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=%s', $apiKey),
        ['Content-Type: application/json'],
        json_encode([
            'contents' => [['parts' => [['text' => $prompt]]]],
            'generationConfig' => ['maxOutputTokens' => 8192],
        ], JSON_THROW_ON_ERROR),
    ];
}

function parse_claude_response(string $raw): ?string {
    $data = json_decode($raw, true);
    return $data['content'][0]['text'] ?? null;
}

function parse_gpt4o_response(string $raw): ?string {
    $data = json_decode($raw, true);
    return $data['choices'][0]['message']['content'] ?? null;
}

function parse_gemini_response(string $raw): ?string {
    $data = json_decode($raw, true);
    return $data['candidates'][0]['content']['parts'][0]['text'] ?? null;
}

// ─── Fan-out ────────────────────────────────────────────────────────────────

function fan_out(string $prompt, array $keys): array {
    $providers = [
        'claude' => [
            'key_name' => 'ANTHROPIC_API_KEY',
            'builder'  => 'build_claude_request',
            'parser'   => 'parse_claude_response',
        ],
        'gpt4o' => [
            'key_name' => 'OPENAI_API_KEY',
            'builder'  => 'build_gpt4o_request',
            'parser'   => 'parse_gpt4o_response',
        ],
        'gemini' => [
            'key_name' => 'GEMINI_API_KEY',
            'builder'  => 'build_gemini_request',
            'parser'   => 'parse_gemini_response',
        ],
    ];

    $mh = curl_multi_init();
    $handles = [];
    $failed = [];
    $responses = ['claude' => null, 'gpt4o' => null, 'gemini' => null];

    foreach ($providers as $name => $provider) {
        $apiKey = $keys[$provider['key_name']] ?? '';
        if ($apiKey === '') {
            $failed[$name] = 'No API key configured';
            stderr("[$name] Skipped - no API key");
            continue;
        }

        [$url, $headers, $body] = ($provider['builder'])($prompt, $apiKey);

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_POST           => true,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => TIMEOUT_SECONDS,
            CURLOPT_CONNECTTIMEOUT => CONNECT_TIMEOUT,
        ]);

        curl_multi_add_handle($mh, $ch);
        $handles[$name] = $ch;
    }

    if (!empty($handles)) {
        $running = null;
        do {
            curl_multi_exec($mh, $running);
            curl_multi_select($mh, 0.2);
        } while ($running > 0);
    }

    foreach ($handles as $name => $ch) {
        $httpCode  = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $rawBody   = curl_multi_getcontent($ch);
        $curlError = curl_error($ch);

        curl_multi_remove_handle($mh, $ch);
        curl_close($ch);

        if ($curlError !== '') {
            $failed[$name] = "cURL error: {$curlError}";
            stderr("[$name] cURL error: {$curlError}");
            continue;
        }

        if ($httpCode < 200 || $httpCode >= 300) {
            $snippet = mb_substr((string) $rawBody, 0, 300);
            $failed[$name] = "HTTP {$httpCode}";
            stderr("[$name] HTTP {$httpCode}: {$snippet}");
            continue;
        }

        $parser = $providers[$name]['parser'];
        $parsed = $parser((string) $rawBody);

        if ($parsed === null) {
            $failed[$name] = 'Unparseable response';
            stderr("[$name] Unparseable response body");
            continue;
        }

        stderr(sprintf('[%s] OK (%d chars)', $name, mb_strlen($parsed)));
        $responses[$name] = $parsed;
    }

    curl_multi_close($mh);

    return [$responses, $failed];
}

// ─── Synthesis ──────────────────────────────────────────────────────────────

function synthesize(array $responses, string $originalPrompt, string $phaseName, string $judgeModel, string $anthropicKey): ?string {
    if ($anthropicKey === '') {
        stderr('Cannot synthesize - no ANTHROPIC_API_KEY for judge');
        return null;
    }

    $labels = [
        'claude' => 'Claude (Anthropic)',
        'gpt4o'  => 'GPT-4o (OpenAI)',
        'gemini' => 'Gemini (Google)',
    ];

    $sections = '';
    foreach ($responses as $name => $text) {
        $label = $labels[$name] ?? $name;
        if ($text === null) {
            $sections .= "### {$label}\n(no response - API failed)\n\n";
        } else {
            $sections .= "### {$label}\n{$text}\n\n";
        }
    }

    $metaPrompt = <<<PROMPT
You are a senior technical judge in an AI-powered development pipeline.
You are evaluating responses for the **{$phaseName}** phase.

## Original prompt
{$originalPrompt}

## Responses from 3 models
{$sections}

## Your task
1. Extract the best ideas, insights, and correct information from each response.
2. Identify and resolve any conflicts or contradictions between responses.
   - When in conflict, favor: correctness > completeness > clarity > simplicity.
3. Produce ONE authoritative, well-structured answer that synthesizes the best of all available responses.
4. If a model's response was unavailable, work with what you have.
5. Do NOT mention which model said what - deliver a single unified answer.
6. The output must be directly usable by the next pipeline phase - no meta-commentary.
7. Be comprehensive. Include all relevant details, code, examples, and structure from the best parts of each response.
PROMPT;

    stderr('Synthesizing via Claude judge...');

    $ch = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'x-api-key: ' . $anthropicKey,
            'anthropic-version: 2023-06-01',
        ],
        CURLOPT_POSTFIELDS     => json_encode([
            'model'      => $judgeModel,
            'max_tokens' => 16384,
            'messages'   => [['role' => 'user', 'content' => $metaPrompt]],
        ], JSON_THROW_ON_ERROR),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => JUDGE_TIMEOUT,
        CURLOPT_CONNECTTIMEOUT => CONNECT_TIMEOUT,
    ]);

    $raw       = curl_exec($ch);
    $httpCode  = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if ($curlError !== '') {
        stderr("Synthesis cURL error: {$curlError}");
        return null;
    }

    if ($httpCode < 200 || $httpCode >= 300) {
        $snippet = mb_substr((string) $raw, 0, 300);
        stderr("Synthesis HTTP {$httpCode}: {$snippet}");
        return null;
    }

    $result = parse_claude_response((string) $raw);
    if ($result !== null) {
        stderr(sprintf('Synthesis complete (%d chars)', mb_strlen($result)));
    }

    return $result;
}

// ─── Main ───────────────────────────────────────────────────────────────────

function main(array $argv): int {
    $opts = parse_args($argv);

    // Resolve .env file path
    $envFile = $opts['env-file'];
    if ($envFile === '') {
        // Default: look for .env in the motspilot directory (parent of bin/)
        $envFile = dirname(__DIR__) . '/.env';
    }

    $keys = load_env($envFile);
    if (empty($keys)) {
        stderr("No API keys found. Checked: {$envFile}");
        stderr('Create motspilot/.env with ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY');
        return 2;
    }

    // Resolve prompt: --prompt-file > --prompt > stdin
    $prompt = '';
    if ($opts['prompt-file'] !== '') {
        if (!is_file($opts['prompt-file'])) {
            stderr("Prompt file not found: {$opts['prompt-file']}");
            return 2;
        }
        $prompt = file_get_contents($opts['prompt-file']);
    } elseif ($opts['prompt'] !== '') {
        $prompt = $opts['prompt'];
    } else {
        // Try stdin (non-blocking check)
        if (!posix_isatty(STDIN)) {
            $prompt = stream_get_contents(STDIN);
        }
    }

    $prompt = trim((string) $prompt);
    if ($prompt === '') {
        stderr('No prompt provided. Use --prompt="...", --prompt-file=/path, or pipe via stdin.');
        return 2;
    }

    $phase      = $opts['phase'];
    $judgeModel = $opts['judge-model'];

    stderr("Phase: {$phase}");
    stderr(sprintf('Prompt: %s%s', mb_substr($prompt, 0, 120), mb_strlen($prompt) > 120 ? '...' : ''));
    stderr('Querying 3 models in parallel...');

    // Phase 1: Fan out
    [$responses, $failed] = fan_out($prompt, $keys);

    $succeeded = array_filter($responses, fn($r) => $r !== null);
    if (count($succeeded) === 0) {
        stderr('ALL APIs failed. Cannot synthesize.');
        foreach ($failed as $name => $reason) {
            stderr("  {$name}: {$reason}");
        }
        return 1;
    }

    stderr(sprintf('%d of 3 models responded.', count($succeeded)));

    // Phase 2: Synthesize
    $synthesis = synthesize(
        $responses,
        $prompt,
        $phase,
        $judgeModel,
        $keys['ANTHROPIC_API_KEY'] ?? ''
    );

    if ($synthesis === null) {
        // Fallback: output the best available raw response
        stderr('Synthesis failed. Outputting best raw response as fallback.');
        // Prefer Claude > GPT-4o > Gemini
        $fallback = $responses['claude'] ?? $responses['gpt4o'] ?? $responses['gemini'] ?? '';
        fwrite(STDOUT, $fallback);
        return 0;
    }

    fwrite(STDOUT, $synthesis);
    return 0;
}

exit(main($argv));
