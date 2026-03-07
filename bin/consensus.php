#!/usr/bin/env php
<?php
declare(strict_types=1);

/**
 * motspilot Multi-Model Consensus — Standalone CLI
 *
 * Framework-agnostic. Requires only PHP 8.0+ with curl extension.
 *
 * Usage:
 *   php consensus.php --prompt-file=/path/to/prompt.txt --phase=architecture --output-dir=/path/to/consensus/
 *   php consensus.php --prompt="Explain caching strategies" --phase=general --output-dir=./consensus/
 *   echo "Design a login flow" | php consensus.php --phase=development --output-dir=./consensus/
 *
 * Output files (written to --output-dir):
 *   01_claude.md      — Raw Claude response
 *   02_gpt4o.md       — Raw GPT-4o response
 *   03_gemini.md       — Raw Gemini response
 *   04_synthesis.md   — Unified synthesis (judge merges all 3)
 *   05_differences.md — Unique contributions per AI (what each brought that others missed)
 *   consensus.log     — Full execution log
 *
 * Also writes synthesis to stdout for backward compatibility.
 *
 * Exit codes:
 *   0 = success
 *   1 = all APIs failed
 *   2 = bad arguments / missing config
 */

// ─── Configuration ──────────────────────────────────────────────────────────

const TIMEOUT_SECONDS  = 60;
const CONNECT_TIMEOUT  = 15;
const JUDGE_TIMEOUT    = 120;

// ─── Helpers ────────────────────────────────────────────────────────────────

/** Log to stderr and optionally to a log file */
function stderr(string $msg, ?string $logFile = null): void {
    $line = "[consensus] {$msg}";
    fwrite(STDERR, $line . "\n");
    if ($logFile !== null) {
        $ts = date('Y-m-d H:i:s');
        file_put_contents($logFile, "{$ts} {$line}\n", FILE_APPEND);
    }
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
    $opts = [
        'prompt' => '',
        'prompt-file' => '',
        'phase' => 'general',
        'judge-model' => 'claude-sonnet-4-20250514',
        'env-file' => '',
        'output-dir' => '',
    ];
    foreach (array_slice($argv, 1) as $arg) {
        if (preg_match('/^--([a-z-]+)=(.+)$/s', $arg, $m)) {
            $opts[$m[1]] = $m[2];
        }
    }
    return $opts;
}

function save_file(string $path, string $content): void {
    file_put_contents($path, $content);
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
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent',
        [
            'Content-Type: application/json',
            'X-goog-api-key: ' . $apiKey,
        ],
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

function fan_out(string $prompt, array $keys, ?string $logFile = null): array {
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
            stderr("[$name] Skipped - no API key", $logFile);
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
            stderr("[$name] cURL error: {$curlError}", $logFile);
            continue;
        }

        if ($httpCode < 200 || $httpCode >= 300) {
            $snippet = mb_substr((string) $rawBody, 0, 300);
            $failed[$name] = "HTTP {$httpCode}";
            stderr("[$name] HTTP {$httpCode}: {$snippet}", $logFile);
            continue;
        }

        $parser = $providers[$name]['parser'];
        $parsed = $parser((string) $rawBody);

        if ($parsed === null) {
            $failed[$name] = 'Unparseable response';
            stderr("[$name] Unparseable response body", $logFile);
            continue;
        }

        stderr(sprintf('[%s] OK (%d chars)', $name, mb_strlen($parsed)), $logFile);
        $responses[$name] = $parsed;
    }

    curl_multi_close($mh);

    return [$responses, $failed];
}

// ─── Claude judge call (shared helper) ──────────────────────────────────────

function call_claude_judge(string $prompt, string $apiKey, string $model, ?string $logFile = null): ?string {
    if ($apiKey === '') {
        stderr('Cannot call judge - no ANTHROPIC_API_KEY', $logFile);
        return null;
    }

    $ch = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'x-api-key: ' . $apiKey,
            'anthropic-version: 2023-06-01',
        ],
        CURLOPT_POSTFIELDS     => json_encode([
            'model'      => $model,
            'max_tokens' => 16384,
            'messages'   => [['role' => 'user', 'content' => $prompt]],
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
        stderr("Judge cURL error: {$curlError}", $logFile);
        return null;
    }

    if ($httpCode < 200 || $httpCode >= 300) {
        $snippet = mb_substr((string) $raw, 0, 300);
        stderr("Judge HTTP {$httpCode}: {$snippet}", $logFile);
        return null;
    }

    return parse_claude_response((string) $raw);
}

// ─── Synthesis ──────────────────────────────────────────────────────────────

function synthesize(array $responses, string $originalPrompt, string $phaseName, string $judgeModel, string $anthropicKey, ?string $logFile = null): ?string {
    $sections = build_response_sections($responses);

    $metaPrompt = <<<PROMPT
You are a senior technical judge in an AI-powered development pipeline.
You are evaluating responses for the **{$phaseName}** phase.

## Original prompt
{$originalPrompt}

## Responses from 3 models
{$sections}

## Your task

### Pass 1 — Extract
For each response, list every distinct idea, recommendation, technical detail, and code example. Do not skip anything — even minor details matter. If a model's response was unavailable, note it and continue.

### Pass 2 — Reconcile
Compare the extracted points across models:
- Identify agreements (shared by 2+ models) — these form your high-confidence core.
- Identify conflicts — resolve each one explicitly. Favor: correctness > completeness > clarity > simplicity. State which position you chose and why in a brief internal note (do not include this in the final output).
- Identify unique points (only one model mentioned) — include them if they are correct and relevant.

### Pass 3 — Synthesize
Produce ONE authoritative, well-structured answer that merges all surviving points into a coherent whole.

### Completeness contract
Every unique technical insight, recommendation, code example, and architectural decision from any response MUST appear in your synthesis. After writing your synthesis, mentally verify: for each model that responded, can every key point from that model be found somewhere in your output? If not, add what's missing.

### Output rules
- Do NOT mention which model said what — deliver a single unified answer.
- Do NOT include meta-commentary, preamble, or explanation of your process.
- The output must be directly usable by the next pipeline phase.
- Only include information that can be traced back to one or more of the responses — do not invent new recommendations.
PROMPT;

    stderr('Synthesizing via Claude judge...', $logFile);
    $result = call_claude_judge($metaPrompt, $anthropicKey, $judgeModel, $logFile);

    if ($result !== null) {
        stderr(sprintf('Synthesis complete (%d chars)', mb_strlen($result)), $logFile);
    }

    return $result;
}

// ─── Differences analysis ───────────────────────────────────────────────────

function analyze_differences(array $responses, string $originalPrompt, string $judgeModel, string $anthropicKey, ?string $logFile = null): ?string {
    $succeeded = array_filter($responses, fn($r) => $r !== null);
    if (count($succeeded) < 2) {
        stderr('Need at least 2 responses to analyze differences.', $logFile);
        return null;
    }

    $sections = build_response_sections($responses);

    $diffPrompt = <<<PROMPT
You are an analytical judge comparing outputs from multiple AI models.

## Original prompt they were given
{$originalPrompt}

## Responses
{$sections}

## Your task — Unique Contributions Analysis

Work in two passes:

### Pass 1 — Catalog every point
For each model, create a complete list of every distinct idea, recommendation, technical detail, code snippet, and design decision. Be thorough — even small details count.

### Pass 2 — Cross-reference and filter
For each point in each model's list, check whether ANY other model covered the same idea (even if worded differently). Remove shared points. What remains are the unique contributions.

### Output format (follow exactly)

---

# Unique Contributions by Each AI

## Claude — Unique Points
- **[Short label]**: [Specific description of the unique point — quote or paraphrase the actual content so the reader understands the value without reading the full response]
(If Claude had no response, say "No response received." If no unique points, say "No unique contributions.")

## GPT-4o — Unique Points
- **[Short label]**: [Specific description]
(Same rules as above.)

## Gemini — Unique Points
- **[Short label]**: [Specific description]
(Same rules as above.)

## Notable Conflicts
(For each conflict: state what each model said, which position is more likely correct, and why. If no conflicts, say "No notable conflicts.")

---

### Quality rules
- Be specific — vague summaries like "provided more detail" are not acceptable. State WHAT detail.
- Every bullet must contain enough context that the reader understands the unique value without reading the original response.
- If a model provided a unique code example, technique, or specific parameter value, include it.
- Do not pad sections. If a model truly had no unique contributions, say so.
PROMPT;

    stderr('Analyzing unique contributions per AI...', $logFile);
    $result = call_claude_judge($diffPrompt, $anthropicKey, $judgeModel, $logFile);

    if ($result !== null) {
        stderr(sprintf('Differences analysis complete (%d chars)', mb_strlen($result)), $logFile);
    }

    return $result;
}

// ─── Shared helper ──────────────────────────────────────────────────────────

function build_response_sections(array $responses): string {
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

    return $sections;
}

// ─── Main ───────────────────────────────────────────────────────────────────

function main(array $argv): int {
    $opts = parse_args($argv);

    // Resolve .env file path
    $envFile = $opts['env-file'];
    if ($envFile === '') {
        $envFile = dirname(__DIR__) . '/.env';
    }

    $keys = load_env($envFile);
    if (empty($keys)) {
        stderr("No API keys found. Checked: {$envFile}");
        stderr('Create motspilot/.env with ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY');
        return 2;
    }

    // Resolve output directory
    $outputDir = $opts['output-dir'];
    $logFile = null;
    if ($outputDir !== '') {
        if (!is_dir($outputDir)) {
            mkdir($outputDir, 0755, true);
        }
        $logFile = rtrim($outputDir, '/') . '/consensus.log';
        // Clear previous log
        file_put_contents($logFile, '');
    }

    // Resolve prompt: --prompt-file > --prompt > stdin
    $prompt = '';
    if ($opts['prompt-file'] !== '') {
        if (!is_file($opts['prompt-file'])) {
            stderr("Prompt file not found: {$opts['prompt-file']}", $logFile);
            return 2;
        }
        $prompt = file_get_contents($opts['prompt-file']);
    } elseif ($opts['prompt'] !== '') {
        $prompt = $opts['prompt'];
    } else {
        if (!posix_isatty(STDIN)) {
            $prompt = stream_get_contents(STDIN);
        }
    }

    $prompt = trim((string) $prompt);
    if ($prompt === '') {
        stderr('No prompt provided. Use --prompt="...", --prompt-file=/path, or pipe via stdin.', $logFile);
        return 2;
    }

    $phase      = $opts['phase'];
    $judgeModel = $opts['judge-model'];

    stderr("Phase: {$phase}", $logFile);
    stderr(sprintf('Prompt: %s%s', mb_substr($prompt, 0, 120), mb_strlen($prompt) > 120 ? '...' : ''), $logFile);
    stderr('Querying 3 models in parallel...', $logFile);

    // ── Phase 1: Fan out to all 3 AIs ──────────────────────────────────────

    [$responses, $failed] = fan_out($prompt, $keys, $logFile);

    $succeeded = array_filter($responses, fn($r) => $r !== null);
    if (count($succeeded) === 0) {
        stderr('ALL APIs failed. Cannot synthesize.', $logFile);
        foreach ($failed as $name => $reason) {
            stderr("  {$name}: {$reason}", $logFile);
        }
        return 1;
    }

    stderr(sprintf('%d of 3 models responded.', count($succeeded)), $logFile);

    // ── Save individual AI responses ───────────────────────────────────────

    $fileMap = ['claude' => '01_claude.md', 'gpt4o' => '02_gpt4o.md', 'gemini' => '03_gemini.md'];
    $labels  = ['claude' => 'Claude (Anthropic)', 'gpt4o' => 'GPT-4o (OpenAI)', 'gemini' => 'Gemini (Google)'];

    if ($outputDir !== '') {
        foreach ($responses as $name => $text) {
            $filePath = rtrim($outputDir, '/') . '/' . $fileMap[$name];
            if ($text !== null) {
                $header = "# {$labels[$name]} — Response\n\n";
                $header .= "> Phase: {$phase}\n";
                $header .= "> Generated: " . date('Y-m-d H:i:s') . "\n\n---\n\n";
                save_file($filePath, $header . $text . "\n");
                stderr("Saved: {$fileMap[$name]}", $logFile);
            } else {
                $reason = $failed[$name] ?? 'Unknown error';
                save_file($filePath, "# {$labels[$name]} — Response\n\n**API FAILED:** {$reason}\n");
                stderr("Saved (failed): {$fileMap[$name]}", $logFile);
            }
        }
    }

    // ── Phase 2: Synthesize all responses ──────────────────────────────────

    $synthesis = synthesize(
        $responses,
        $prompt,
        $phase,
        $judgeModel,
        $keys['ANTHROPIC_API_KEY'] ?? '',
        $logFile
    );

    if ($outputDir !== '' && $synthesis !== null) {
        $header = "# Multi-Model Consensus — Synthesis\n\n";
        $header .= "> Phase: {$phase}\n";
        $header .= "> Models: " . implode(', ', array_keys($succeeded)) . "\n";
        $header .= "> Judge: {$judgeModel}\n";
        $header .= "> Generated: " . date('Y-m-d H:i:s') . "\n\n---\n\n";
        save_file(rtrim($outputDir, '/') . '/04_synthesis.md', $header . $synthesis . "\n");
        stderr('Saved: 04_synthesis.md', $logFile);
    }

    // ── Phase 3: Analyze unique contributions / differences ────────────────

    $differences = analyze_differences(
        $responses,
        $prompt,
        $judgeModel,
        $keys['ANTHROPIC_API_KEY'] ?? '',
        $logFile
    );

    if ($outputDir !== '' && $differences !== null) {
        $header = "# Multi-Model Differences — Unique Contributions\n\n";
        $header .= "> Phase: {$phase}\n";
        $header .= "> Models compared: " . implode(', ', array_keys($succeeded)) . "\n";
        $header .= "> Generated: " . date('Y-m-d H:i:s') . "\n\n---\n\n";
        save_file(rtrim($outputDir, '/') . '/05_differences.md', $header . $differences . "\n");
        stderr('Saved: 05_differences.md', $logFile);
    }

    // ── Summary ────────────────────────────────────────────────────────────

    if ($outputDir !== '') {
        $summary  = sprintf("%d of 3 models responded", count($succeeded));
        $summary .= empty($failed) ? '' : sprintf(' (failed: %s)', implode(', ', array_keys($failed)));
        stderr('', $logFile);
        stderr('=== CONSENSUS COMPLETE ===', $logFile);
        stderr($summary, $logFile);
        stderr("Files written to: {$outputDir}", $logFile);
        stderr('  01_claude.md      — Claude raw response', $logFile);
        stderr('  02_gpt4o.md       — GPT-4o raw response', $logFile);
        stderr('  03_gemini.md      — Gemini raw response', $logFile);
        stderr('  04_synthesis.md   — Unified synthesis', $logFile);
        stderr('  05_differences.md — Unique contributions per AI', $logFile);
        stderr('  consensus.log     — Execution log', $logFile);
    }

    // Write synthesis to stdout for backward compatibility / piping
    if ($synthesis !== null) {
        fwrite(STDOUT, $synthesis);
    } elseif ($synthesis === null) {
        stderr('Synthesis failed. Outputting best raw response as fallback.', $logFile);
        $fallback = $responses['claude'] ?? $responses['gpt4o'] ?? $responses['gemini'] ?? '';
        fwrite(STDOUT, (string) $fallback);
    }

    return 0;
}

exit(main($argv));
