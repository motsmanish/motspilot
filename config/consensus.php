<?php
declare(strict_types=1);

/**
 * Multi-Model Consensus API Configuration
 *
 * Load this file in your CakePHP bootstrap (config/bootstrap.php):
 *
 *   Configure::load('consensus');
 *
 * Or in config/app_local.php, merge the ConsensusApi key directly.
 *
 * All keys are read from environment variables — never hardcode secrets.
 */
return [
    'ConsensusApi' => [
        'anthropic_api_key' => env('ANTHROPIC_API_KEY', ''),
        'openai_api_key' => env('OPENAI_API_KEY', ''),
        'gemini_api_key' => env('GEMINI_API_KEY', ''),
    ],
];
