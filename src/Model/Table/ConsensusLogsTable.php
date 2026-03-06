<?php
declare(strict_types=1);

namespace App\Model\Table;

use Cake\ORM\Table;
use Cake\Validation\Validator;

/**
 * ConsensusLogs Model
 *
 * Stores all multi-model consensus requests: the prompt sent, each model's
 * raw response, the synthesized output, and which APIs failed.
 */
class ConsensusLogsTable extends Table
{
    public function initialize(array $config): void
    {
        parent::initialize($config);

        $this->setTable('consensus_logs');
        $this->setDisplayField('id');
        $this->setPrimaryKey('id');

        $this->addBehavior('Timestamp', [
            'events' => [
                'Model.beforeSave' => [
                    'created' => 'new',
                ],
            ],
        ]);
    }

    public function validationDefault(Validator $validator): Validator
    {
        $validator
            ->notEmptyString('prompt', 'A prompt is required.')
            ->notEmptyString('phase_name', 'A phase name is required.');

        return $validator;
    }
}
