<?php
declare(strict_types=1);

use Migrations\AbstractMigration;

class CreateConsensusLogs extends AbstractMigration
{
    public function change(): void
    {
        if ($this->hasTable('consensus_logs')) {
            return;
        }

        $this->table('consensus_logs')
            ->addColumn('phase_name', 'string', [
                'limit' => 50,
                'null' => false,
                'comment' => 'Pipeline phase: architecture, development, testing, verification, delivery, general',
            ])
            ->addColumn('prompt', 'text', [
                'null' => false,
            ])
            ->addColumn('response_claude', 'text', [
                'default' => null,
                'null' => true,
            ])
            ->addColumn('response_gpt4o', 'text', [
                'default' => null,
                'null' => true,
            ])
            ->addColumn('response_gemini', 'text', [
                'default' => null,
                'null' => true,
            ])
            ->addColumn('synthesis', 'text', [
                'default' => null,
                'null' => true,
            ])
            ->addColumn('apis_failed', 'text', [
                'default' => null,
                'null' => true,
                'comment' => 'JSON object: {"provider": "reason"}',
            ])
            ->addColumn('created', 'datetime', [
                'null' => false,
            ])
            ->addIndex(['phase_name'], ['name' => 'idx_consensus_logs_phase'])
            ->addIndex(['created'], ['name' => 'idx_consensus_logs_created'])
            ->create();
    }
}
