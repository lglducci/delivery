-- ProspectFlow: amplia tarefas para também registrar reuniões.
-- Não cria uma tabela separada. Os novos campos permanecem nulos
-- para tarefas comuns, como ligar ou cobrar resposta.

ALTER TABLE prospect.tarefas
    ADD COLUMN IF NOT EXISTS titulo TEXT,
    ADD COLUMN IF NOT EXISTS participante_email TEXT,
    ADD COLUMN IF NOT EXISTS duracao_minutos INTEGER,
    ADD COLUMN IF NOT EXISTS plataforma TEXT,
    ADD COLUMN IF NOT EXISTS link_reuniao TEXT,
    ADD COLUMN IF NOT EXISTS resultado_reuniao TEXT,
    ADD COLUMN IF NOT EXISTS decisoes TEXT,
    ADD COLUMN IF NOT EXISTS proxima_acao TEXT,
    ADD COLUMN IF NOT EXISTS resultado_registrado_em TIMESTAMPTZ;

ALTER TABLE prospect.tarefas
    DROP CONSTRAINT IF EXISTS tarefas_tipo_check;

ALTER TABLE prospect.tarefas
    ADD CONSTRAINT tarefas_tipo_check
    CHECK (
        tipo = ANY (
            ARRAY[
                'LIGAR'::TEXT,
                'ENVIAR_MENSAGEM'::TEXT,
                'ENVIAR_PROPOSTA'::TEXT,
                'COBRAR_RESPOSTA'::TEXT,
                'VISITAR'::TEXT,
                'REUNIAO'::TEXT,
                'OUTRO'::TEXT
            ]
        )
    );

ALTER TABLE prospect.tarefas
    DROP CONSTRAINT IF EXISTS tarefas_duracao_minutos_check;

ALTER TABLE prospect.tarefas
    ADD CONSTRAINT tarefas_duracao_minutos_check
    CHECK (
        duracao_minutos IS NULL
        OR duracao_minutos BETWEEN 5 AND 1440
    );

ALTER TABLE prospect.tarefas
    DROP CONSTRAINT IF EXISTS tarefas_plataforma_check;

ALTER TABLE prospect.tarefas
    ADD CONSTRAINT tarefas_plataforma_check
    CHECK (
        plataforma IS NULL
        OR plataforma = ANY (
            ARRAY[
                'GOOGLE_MEET'::TEXT,
                'MICROSOFT_TEAMS'::TEXT,
                'PRESENCIAL'::TEXT,
                'OUTRO'::TEXT
            ]
        )
    );
