-- ProspectFlow - confirmacao de envio, entrega e leitura
-- Ordem de execucao: tabela -> funcoes de envio -> webhook central.
-- Este script e idempotente e pode ser executado inteiro no SQL Editor.

BEGIN;

ALTER TABLE prospect.interacoes
    ADD COLUMN IF NOT EXISTS evolution_message_id TEXT,
    ADD COLUMN IF NOT EXISTS status_entrega TEXT,
    ADD COLUMN IF NOT EXISTS enviada_em TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS entregue_em TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS lida_em TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS erro_envio TEXT;

CREATE INDEX IF NOT EXISTS idx_interacoes_evolution_message
    ON prospect.interacoes (empresa_id, evolution_message_id)
    WHERE evolution_message_id IS NOT NULL;
 
 