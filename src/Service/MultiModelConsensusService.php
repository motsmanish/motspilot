<?php
declare(strict_types=1);

namespace Motspilot\Service;

use RuntimeException;

/**
 * Multi-Model Consensus Service
 *
 * Fans out a prompt to multiple LLM APIs in parallel (curl_multi),
 * collects responses, then synthesizes a single authoritative output
 * via Claude as the judge.
 *
 * Designed for use inside the motspilot pipeline — any phase can call:
 *   $consensus = new MultiModelConsensusService($config, $logger);
 *   $result = $consensus->run($prompt, $phaseName);
 *
 * Or via CakePHP integration:
 *   $this->consensus->run($prompt, $phaseName);
 */
class MultiModelConsensusService
{
    private const TIMEOUT_SECONDS = 30;
    private const CONNECT_TIMEOUT = 10;
    private const JUDGE_TIMEOUT = 60;

    /**
     * @var array{anthropic_api_key: string, openai_api_key: string, gemini_api_key: string}
     */
    private array $config;

    /**
     * @var callable|null fn(string $level, string $message) — optional logger
     */
    private $logger;

    /**
     * @var array<string, array{url: string, config_key: string, builder: string, parser: string}>
     */
    private array $providers = [
        'claude' => [
            'url' => 'https://api.anthropic.com/v1/messages',
            'config_key' => 'anthropic_api_key',
            'builder' => 'buildClaudeRequest',
            'parser' => 'parseClaudeResponse',
        ],
        'gpt4o' => [
            'url' => 'https://api.openai.com/v1/chat/completions',
            'config_key' => 'openai_api_key',
            'builder' => 'buildGpt4oRequest',
            'parser' => 'parseGpt4oResponse',
        ],
        'gemini' => [
            'url_template' => 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=%s',
            'config_key' => 'gemini_api_key',
            'builder' => 'buildGeminiRequest',
            'parser' => 'parseGeminiResponse',
        ],
    ];

    /**
     * @param array{anthropic_api_key?: string, openai_api_key?: string, gemini_api_key?: string} $config
     * @param callable|null $logger fn(string $level, string $message)
     */
    public function __construct(array $config, ?callable $logger = null)
    {
        $this->config = [
            'anthropic_api_key' => $config['anthropic_api_key'] ?? '',
            'openai_api_key' => $config['openai_api_key'] ?? '',
            'gemini_api_key' => $config['gemini_api_key'] ?? '',
        ];
        $this->logger = $logger;
    }

    /**
     * Run the full consensus pipeline: fan-out → collect → synthesize.
     *
     * @param string $prompt The prompt to send to all models.
     * @param string $phaseName Pipeline phase name (architecture, development, etc.)
     * @param string $judgeModel Claude model for synthesis.
     * @return array{
     *     responses: array<string, string|null>,
     *     synthesis: string|null,
     *     apis_failed: array<string, string>
     * }
     * @throws RuntimeException If all APIs fail (minimum 1 response required).
     */
    public function run(
        string $prompt,
        string $phaseName = 'general',
        string $judgeModel = 'claude-sonnet-4-20250514'
    ): array {
        $this->log('info', "Consensus started for phase: {$phaseName}");

        // Phase 1: Fan out
        [$responses, $apisFailed] = $this->fanOut($prompt);

        $succeeded = array_filter($responses, fn($r) => $r !== null);
        if (count($succeeded) === 0) {
            $failedList = implode(', ', array_keys($apisFailed));
            $this->log('error', "All APIs failed ({$failedList}). Cannot synthesize.");
            throw new RuntimeException(
                "All LLM APIs failed. Cannot synthesize consensus. Failed: {$failedList}"
            );
        }

        $this->log('info', sprintf(
            'Received %d of 3 responses. Failed: %s',
            count($succeeded),
            empty($apisFailed) ? 'none' : implode(', ', array_keys($apisFailed))
        ));

        // Phase 2: Synthesize
        $synthesis = $this->synthesize($responses, $prompt, $phaseName, $judgeModel);

        if ($synthesis === null) {
            $this->log('warning', 'Synthesis judge call failed. Raw responses available.');
        }

        return [
            'responses' => $responses,
            'synthesis' => $synthesis,
            'apis_failed' => $apisFailed,
        ];
    }

    // ─── Fan-out: curl_multi ────────────────────────────────────────────────

    /**
     * @return array{0: array<string, string|null>, 1: array<string, string>}
     */
    private function fanOut(string $prompt): array
    {
        $mh = curl_multi_init();
        $handles = [];
        $apisFailed = [];
        $responses = ['claude' => null, 'gpt4o' => null, 'gemini' => null];

        foreach ($this->providers as $name => $provider) {
            $apiKey = $this->config[$provider['config_key']] ?? '';
            if (empty($apiKey)) {
                $reason = "No API key configured ({$provider['config_key']})";
                $apisFailed[$name] = $reason;
                $this->log('warning', "[{$name}] Skipped — {$reason}");
                continue;
            }

            $builderMethod = $provider['builder'];
            [$url, $headers, $body] = $this->{$builderMethod}($prompt, $apiKey, $provider);

            $ch = curl_init();
            curl_setopt_array($ch, [
                CURLOPT_URL => $url,
                CURLOPT_POST => true,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_POSTFIELDS => $body,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => self::TIMEOUT_SECONDS,
                CURLOPT_CONNECTTIMEOUT => self::CONNECT_TIMEOUT,
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
            $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $rawBody = curl_multi_getcontent($ch);
            $curlError = curl_error($ch);

            curl_multi_remove_handle($mh, $ch);
            curl_close($ch);

            if ($curlError !== '') {
                $apisFailed[$name] = "cURL error: {$curlError}";
                $this->log('error', "[{$name}] cURL error: {$curlError}");
                continue;
            }

            if ($httpCode < 200 || $httpCode >= 300) {
                $snippet = mb_substr((string)$rawBody, 0, 300);
                $apisFailed[$name] = "HTTP {$httpCode}: {$snippet}";
                $this->log('error', "[{$name}] HTTP {$httpCode}: {$snippet}");
                continue;
            }

            $parserMethod = $this->providers[$name]['parser'];
            $parsed = $this->{$parserMethod}($rawBody);

            if ($parsed === null) {
                $apisFailed[$name] = 'Unparseable response body';
                $this->log('error', "[{$name}] Unparseable body: " . mb_substr((string)$rawBody, 0, 500));
                continue;
            }

            $this->log('info', sprintf('[%s] OK (%d chars)', $name, mb_strlen($parsed)));
            $responses[$name] = $parsed;
        }

        curl_multi_close($mh);

        return [$responses, $apisFailed];
    }

    // ─── Request builders ───────────────────────────────────────────────────

    private function buildClaudeRequest(string $prompt, string $apiKey, array $provider): array
    {
        return [
            $provider['url'],
            [
                'Content-Type: application/json',
                'x-api-key: ' . $apiKey,
                'anthropic-version: 2023-06-01',
            ],
            json_encode([
                'model' => 'claude-sonnet-4-20250514',
                'max_tokens' => 4096,
                'messages' => [
                    ['role' => 'user', 'content' => $prompt],
                ],
            ], JSON_THROW_ON_ERROR),
        ];
    }

    private function buildGpt4oRequest(string $prompt, string $apiKey, array $provider): array
    {
        return [
            $provider['url'],
            [
                'Content-Type: application/json',
                'Authorization: Bearer ' . $apiKey,
            ],
            json_encode([
                'model' => 'gpt-4o',
                'max_tokens' => 4096,
                'messages' => [
                    ['role' => 'user', 'content' => $prompt],
                ],
            ], JSON_THROW_ON_ERROR),
        ];
    }

    /**
     * SECURITY: Gemini API key is passed as a URL query parameter — this is
     * Google's required auth method for this endpoint. If your reverse proxy
     * (nginx) logs full request URIs, the API key will appear in access logs.
     *
     * Mitigations:
     *   1. Use targeted nginx log exclusion for googleapis.com requests
     *      (see prompts/frameworks/cakephp.md → "Gemini API Key in URL")
     *   2. Long-term: switch to Vertex AI with service account credentials
     *      to eliminate key-in-URL entirely.
     *
     * Do NOT disable all query string logging — that breaks legitimate logging.
     */
    private function buildGeminiRequest(string $prompt, string $apiKey, array $provider): array
    {
        return [
            sprintf($provider['url_template'], $apiKey),
            ['Content-Type: application/json'],
            json_encode([
                'contents' => [
                    ['parts' => [['text' => $prompt]]],
                ],
                'generationConfig' => [
                    'maxOutputTokens' => 4096,
                ],
            ], JSON_THROW_ON_ERROR),
        ];
    }

    // ─── Response parsers ───────────────────────────────────────────────────

    private function parseClaudeResponse(?string $raw): ?string
    {
        if ($raw === null) {
            return null;
        }
        $data = json_decode($raw, true);

        return $data['content'][0]['text'] ?? null;
    }

    private function parseGpt4oResponse(?string $raw): ?string
    {
        if ($raw === null) {
            return null;
        }
        $data = json_decode($raw, true);

        return $data['choices'][0]['message']['content'] ?? null;
    }

    private function parseGeminiResponse(?string $raw): ?string
    {
        if ($raw === null) {
            return null;
        }
        $data = json_decode($raw, true);

        return $data['candidates'][0]['content']['parts'][0]['text'] ?? null;
    }

    // ─── Synthesis ──────────────────────────────────────────────────────────

    private function synthesize(
        array $responses,
        string $originalPrompt,
        string $phaseName,
        string $judgeModel
    ): ?string {
        $apiKey = $this->config['anthropic_api_key'];
        if (empty($apiKey)) {
            $this->log('error', 'Cannot synthesize — anthropic_api_key not configured.');
            return null;
        }

        $labels = [
            'claude' => 'Claude (Anthropic)',
            'gpt4o' => 'GPT-4o (OpenAI)',
            'gemini' => 'Gemini 1.5 Pro (Google)',
        ];

        $sections = '';
        foreach ($responses as $name => $text) {
            $label = $labels[$name] ?? $name;
            if ($text === null) {
                $sections .= "### {$label}\n(no response — API failed)\n\n";
            } else {
                $sections .= "### {$label}\n{$text}\n\n";
            }
        }

        $metaPrompt = <<<PROMPT
You are a senior technical judge in a CakePHP 4 development pipeline.
You are evaluating responses for the **{$phaseName}** phase.

## Context
This is part of an AI-powered feature development pipeline (motspilot).
The project uses PHP 8.x, CakePHP 4, MySQL/MariaDB, and follows
clean architecture with security-first thinking.

## Original prompt
{$originalPrompt}

## Responses from 3 models
{$sections}

## Your task
1. Extract the best ideas, insights, and correct information from each response.
2. Identify and resolve any conflicts or contradictions between responses.
   - When in conflict, favor: security > clean architecture > simplicity > performance.
3. Produce ONE authoritative, well-structured answer that synthesizes the best of all available responses.
4. If a model's response was unavailable, work with what you have.
5. Do NOT mention which model said what — deliver a single unified answer.
6. The output must be directly usable by the next pipeline phase — no meta-commentary.
PROMPT;

        $ch = curl_init('https://api.anthropic.com/v1/messages');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'x-api-key: ' . $apiKey,
                'anthropic-version: 2023-06-01',
            ],
            CURLOPT_POSTFIELDS => json_encode([
                'model' => $judgeModel,
                'max_tokens' => 4096,
                'messages' => [
                    ['role' => 'user', 'content' => $metaPrompt],
                ],
            ], JSON_THROW_ON_ERROR),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => self::JUDGE_TIMEOUT,
            CURLOPT_CONNECTTIMEOUT => self::CONNECT_TIMEOUT,
        ]);

        $raw = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);

        if ($curlError !== '') {
            $this->log('error', "Synthesis cURL error: {$curlError}");
            return null;
        }

        if ($httpCode < 200 || $httpCode >= 300) {
            $snippet = mb_substr((string)$raw, 0, 300);
            $this->log('error', "Synthesis HTTP {$httpCode}: {$snippet}");
            return null;
        }

        return $this->parseClaudeResponse((string)$raw);
    }

    // ─── Logging ────────────────────────────────────────────────────────────

    private function log(string $level, string $message): void
    {
        if ($this->logger !== null) {
            ($this->logger)($level, "[MultiModelConsensus] {$message}");
        }
    }
}
