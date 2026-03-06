<?php
declare(strict_types=1);

namespace App\Command;

use Cake\Command\Command;
use Cake\Console\Arguments;
use Cake\Console\ConsoleIo;
use Cake\Console\ConsoleOptionParser;
use Cake\Core\Configure;
use Cake\Log\Log;
use Cake\ORM\Locator\LocatorAwareTrait;
use Motspilot\Service\MultiModelConsensusService;

/**
 * Standalone CLI for testing the Multi-Model Consensus service.
 *
 * Usage:
 *   bin/cake consensus "Explain the CAP theorem"
 *   bin/cake consensus "Design a caching strategy" --phase=architecture
 *   bin/cake consensus "Compare REST vs GraphQL" --judge-model=claude-sonnet-4-20250514
 */
class ConsensusCommand extends Command
{
    use LocatorAwareTrait;

    protected function buildOptionParser(ConsoleOptionParser $parser): ConsoleOptionParser
    {
        $parser
            ->setDescription('Fan out a prompt to 3 LLMs, synthesize consensus via Claude judge.')
            ->addArgument('prompt', [
                'help' => 'The prompt to send to all models.',
                'required' => true,
            ])
            ->addOption('phase', [
                'help' => 'Pipeline phase name for context-aware synthesis.',
                'default' => 'general',
            ])
            ->addOption('judge-model', [
                'help' => 'Claude model to use as the synthesis judge.',
                'default' => 'claude-sonnet-4-20250514',
            ])
            ->addOption('no-save', [
                'help' => 'Skip saving to database.',
                'boolean' => true,
                'default' => false,
            ]);

        return $parser;
    }

    public function execute(Arguments $args, ConsoleIo $io): int
    {
        $prompt = (string)$args->getArgument('prompt');
        $phaseName = (string)$args->getOption('phase');
        $judgeModel = (string)$args->getOption('judge-model');
        $noSave = (bool)$args->getOption('no-save');

        $io->out('Prompt: ' . mb_substr($prompt, 0, 120) . (mb_strlen($prompt) > 120 ? '...' : ''));
        $io->out('Phase: ' . $phaseName);
        $io->hr();

        // Build the service from CakePHP config
        $config = [
            'anthropic_api_key' => Configure::read('ConsensusApi.anthropic_api_key', ''),
            'openai_api_key' => Configure::read('ConsensusApi.openai_api_key', ''),
            'gemini_api_key' => Configure::read('ConsensusApi.gemini_api_key', ''),
        ];

        $logger = function (string $level, string $message) use ($io): void {
            switch ($level) {
                case 'error':
                    $io->error($message);
                    Log::error($message);
                    break;
                case 'warning':
                    $io->warning($message);
                    Log::warning($message);
                    break;
                default:
                    $io->out($message);
                    Log::info($message);
                    break;
            }
        };

        $service = new MultiModelConsensusService($config, $logger);

        // Run consensus
        $io->out('<info>Phase 1:</info> Querying models in parallel...');

        try {
            $result = $service->run($prompt, $phaseName, $judgeModel);
        } catch (\RuntimeException $e) {
            $io->error($e->getMessage());
            return static::CODE_ERROR;
        }

        $io->hr();

        // Persist to DB
        if (!$noSave) {
            $io->out('<info>Saving to database...</info>');
            try {
                $table = $this->fetchTable('ConsensusLogs');
                $entity = $table->newEntity([
                    'phase_name' => $phaseName,
                    'prompt' => $prompt,
                    'response_claude' => $result['responses']['claude'],
                    'response_gpt4o' => $result['responses']['gpt4o'],
                    'response_gemini' => $result['responses']['gemini'],
                    'synthesis' => $result['synthesis'],
                    'apis_failed' => json_encode($result['apis_failed'], JSON_THROW_ON_ERROR),
                ]);
                $table->saveOrFail($entity);
                $io->out(sprintf('<info>Saved</info> to consensus_logs (id=%d).', $entity->id));
            } catch (\Exception $e) {
                $io->warning('DB save failed: ' . $e->getMessage());
                $io->warning('Consensus result is still available below.');
            }
        }

        // Output
        $io->hr();
        $io->out('<info>===== SYNTHESIZED CONSENSUS =====</info>');
        $io->out('');
        $io->out($result['synthesis'] ?? '(synthesis unavailable — see individual responses above)');

        if (!empty($result['apis_failed'])) {
            $io->out('');
            $io->warning('APIs that failed: ' . implode(', ', array_keys($result['apis_failed'])));
        }

        return static::CODE_SUCCESS;
    }
}
