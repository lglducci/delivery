-- ============================================================================
-- ProspectFlow - Controle simples de ligacoes
-- Script Prospect2.sql
--
-- Este script:
--   1. cria a tabela prospect.ligacoes;
--   2. lista os leads de telefone ainda sem ligacao;
--   3. cria a fila diaria com ate 12 empresas e tres tentativas;
--   4. registra o resultado de cada tentativa.
--
-- A public.prospectflow_api nao e alterada neste script.
-- ============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS prospect;

-- ----------------------------------------------------------------------------
-- TABELA
-- Cada registro representa uma tentativa de ligacao.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS prospect.ligacoes (
    id              BIGSERIAL PRIMARY KEY,
    empresa_id      BIGINT NOT NULL,
    lead_id         BIGINT NOT NULL
                    REFERENCES prospect.leads(id) ON DELETE CASCADE,
    agendada_para   TIMESTAMPTZ NOT NULL,
    tentativa       SMALLINT NOT NULL
                    CHECK (tentativa BETWEEN 1 AND 3),
    resultado       TEXT NOT NULL DEFAULT 'PENDENTE'
                    CHECK (
                        resultado IN (
                            'PENDENTE',
                            'ATENDEU',
                            'SEM_SUCESSO',
                            'RETORNAR',
                            'CANCELADA'
                        )
                    ),
    observacao      TEXT,
    realizada_em    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_ligacoes_empresa_lead_tentativa
        UNIQUE (empresa_id, lead_id, tentativa)
);

CREATE INDEX IF NOT EXISTS idx_ligacoes_empresa_agendada
    ON prospect.ligacoes (empresa_id, agendada_para);

CREATE INDEX IF NOT EXISTS idx_ligacoes_empresa_resultado
    ON prospect.ligacoes (empresa_id, resultado, agendada_para);

CREATE INDEX IF NOT EXISTS idx_ligacoes_lead
    ON prospect.ligacoes (empresa_id, lead_id);

-- ----------------------------------------------------------------------------
-- LEADS ELEGIVEIS
-- Retorna os telefones mais antigos que ainda nao possuem nenhuma ligacao.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prospect.fn_ligacoes_leads_elegiveis(
    p_empresa_id BIGINT,
    p_limite     INTEGER DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_limite INTEGER := LEAST(GREATEST(COALESCE(p_limite, 12), 1), 100);
    v_dados  JSONB;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    SELECT COALESCE(
        JSONB_AGG(TO_JSONB(q) ORDER BY q.updated_at, q.id),
        '[]'::JSONB
    )
    INTO v_dados
    FROM (
        SELECT
            l.id,
            l.empresa_id,
            l.nome,
            l.empresa_nome,
            l.telefone,
            l.cidade,
            l.segmento,
            l.canal_preferido,
            l.updated_at
        FROM prospect.leads AS l
        WHERE l.empresa_id = p_empresa_id
          AND l.canal_preferido = 'TELEFONE'
          AND NULLIF(BTRIM(l.telefone), '') IS NOT NULL
          AND COALESCE(l.nao_contatar, FALSE) = FALSE
          AND l.status NOT IN ('CONVERTIDO', 'ENCERRADO', 'BLOQUEADO')
          AND NOT EXISTS (
              SELECT 1
              FROM prospect.ligacoes AS lg
              WHERE lg.empresa_id = l.empresa_id
                AND lg.lead_id = l.id
          )
        ORDER BY l.updated_at ASC, l.id ASC
        LIMIT v_limite
    ) AS q;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'total', JSONB_ARRAY_LENGTH(v_dados),
        'dados', v_dados
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- CRIAR FILA DO DIA
-- Seleciona ate 12 leads elegiveis e cria as tentativas das 09:00, 15:00 e
-- 17:00 no fuso horario de Sao Paulo.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prospect.fn_ligacoes_criar_fila(
    p_empresa_id BIGINT,
    p_data       DATE DEFAULT CURRENT_DATE,
    p_limite     INTEGER DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_limite          INTEGER := LEAST(GREATEST(COALESCE(p_limite, 12), 1), 100);
    v_total_leads     INTEGER := 0;
    v_total_ligacoes  INTEGER := 0;
    v_dados           JSONB;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    IF p_data IS NULL THEN
        RAISE EXCEPTION 'data da fila e obrigatoria';
    END IF;

    WITH elegiveis AS (
        SELECT l.id AS lead_id
        FROM prospect.leads AS l
        WHERE l.empresa_id = p_empresa_id
          AND l.canal_preferido = 'TELEFONE'
          AND NULLIF(BTRIM(l.telefone), '') IS NOT NULL
          AND COALESCE(l.nao_contatar, FALSE) = FALSE
          AND l.status NOT IN ('CONVERTIDO', 'ENCERRADO', 'BLOQUEADO')
          AND NOT EXISTS (
              SELECT 1
              FROM prospect.ligacoes AS lg
              WHERE lg.empresa_id = l.empresa_id
                AND lg.lead_id = l.id
          )
        ORDER BY l.updated_at ASC, l.id ASC
        LIMIT v_limite
        FOR UPDATE OF l SKIP LOCKED
    ),
    tentativas AS (
        SELECT
            e.lead_id,
            h.tentativa,
            (p_data + h.horario) AT TIME ZONE 'America/Sao_Paulo'
                AS agendada_para
        FROM elegiveis AS e
        CROSS JOIN (
            VALUES
                (1::SMALLINT, TIME '09:00'),
                (2::SMALLINT, TIME '15:00'),
                (3::SMALLINT, TIME '17:00')
        ) AS h(tentativa, horario)
    ),
    inseridas AS (
        INSERT INTO prospect.ligacoes (
            empresa_id,
            lead_id,
            agendada_para,
            tentativa,
            resultado
        )
        SELECT
            p_empresa_id,
            t.lead_id,
            t.agendada_para,
            t.tentativa,
            'PENDENTE'
        FROM tentativas AS t
        ON CONFLICT (empresa_id, lead_id, tentativa) DO NOTHING
        RETURNING *
    )
    SELECT
        COUNT(DISTINCT i.lead_id),
        COUNT(*)
    INTO
        v_total_leads,
        v_total_ligacoes
    FROM inseridas AS i;

    SELECT COALESCE(
        JSONB_AGG(TO_JSONB(q) ORDER BY q.nome, q.tentativa),
        '[]'::JSONB
    )
    INTO v_dados
    FROM (
        SELECT
            lg.id,
            lg.lead_id,
            COALESCE(NULLIF(l.empresa_nome, ''), l.nome) AS nome,
            l.telefone,
            lg.tentativa,
            lg.agendada_para,
            lg.resultado,
            lg.observacao,
            lg.realizada_em
        FROM prospect.ligacoes AS lg
        INNER JOIN prospect.leads AS l
            ON l.id = lg.lead_id
           AND l.empresa_id = lg.empresa_id
        WHERE lg.empresa_id = p_empresa_id
          AND (lg.agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE = p_data
        ORDER BY nome, lg.tentativa
    ) AS q;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'data', p_data,
        'leads_adicionados', v_total_leads,
        'ligacoes_criadas', v_total_ligacoes,
        'dados', v_dados
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- ATUALIZAR LIGACAO
--
-- ATENDEU:
--   conclui a tentativa e cancela as proximas tentativas pendentes.
--
-- SEM_SUCESSO:
--   conclui a tentativa e mantem a proxima tentativa programada.
--   Quando a observacao nao for informada, grava "Nao atendeu".
--
-- RETORNAR:
--   conclui a tentativa atual e muda o horario da proxima tentativa pendente.
--   O parametro p_retornar_em torna-se obrigatorio.
--
-- CANCELADA:
--   cancela apenas a tentativa informada.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prospect.fn_ligacoes_atualizar(
    p_empresa_id   BIGINT,
    p_ligacao_id   BIGINT,
    p_resultado    TEXT,
    p_observacao   TEXT DEFAULT NULL,
    p_retornar_em  TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_resultado         TEXT := UPPER(BTRIM(COALESCE(p_resultado, '')));
    v_ligacao           prospect.ligacoes%ROWTYPE;
    v_proxima_id        BIGINT;
    v_canceladas        INTEGER := 0;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    IF p_ligacao_id IS NULL THEN
        RAISE EXCEPTION 'ligacao_id e obrigatorio';
    END IF;

    IF v_resultado NOT IN (
        'ATENDEU',
        'SEM_SUCESSO',
        'RETORNAR',
        'CANCELADA'
    ) THEN
        RAISE EXCEPTION 'resultado de ligacao invalido: %', p_resultado;
    END IF;

    IF v_resultado = 'RETORNAR' AND p_retornar_em IS NULL THEN
        RAISE EXCEPTION 'informe a data e o horario do retorno';
    END IF;

    SELECT lg.*
    INTO v_ligacao
    FROM prospect.ligacoes AS lg
    WHERE lg.id = p_ligacao_id
      AND lg.empresa_id = p_empresa_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ligacao nao encontrada para esta empresa';
    END IF;

    IF v_ligacao.resultado <> 'PENDENTE' THEN
        RAISE EXCEPTION 'esta ligacao ja possui o resultado %', v_ligacao.resultado;
    END IF;

    UPDATE prospect.ligacoes AS lg
       SET resultado = v_resultado,
           observacao = COALESCE(
               NULLIF(BTRIM(p_observacao), ''),
               CASE
                   WHEN v_resultado = 'SEM_SUCESSO' THEN 'Nao atendeu'
                   ELSE lg.observacao
               END
           ),
           realizada_em = CASE
               WHEN v_resultado = 'CANCELADA' THEN NULL
               ELSE NOW()
           END
     WHERE lg.id = v_ligacao.id
       AND lg.empresa_id = p_empresa_id
    RETURNING lg.* INTO v_ligacao;

    IF v_resultado = 'ATENDEU' THEN
        UPDATE prospect.ligacoes AS futuras
           SET resultado = 'CANCELADA',
               observacao = COALESCE(
                   futuras.observacao,
                   'Cancelada porque uma tentativa anterior foi atendida'
               )
         WHERE futuras.empresa_id = p_empresa_id
           AND futuras.lead_id = v_ligacao.lead_id
           AND futuras.tentativa > v_ligacao.tentativa
           AND futuras.resultado = 'PENDENTE';

        GET DIAGNOSTICS v_canceladas = ROW_COUNT;
    END IF;

    IF v_resultado = 'RETORNAR' THEN
        SELECT futuras.id
        INTO v_proxima_id
        FROM prospect.ligacoes AS futuras
        WHERE futuras.empresa_id = p_empresa_id
          AND futuras.lead_id = v_ligacao.lead_id
          AND futuras.tentativa > v_ligacao.tentativa
          AND futuras.resultado = 'PENDENTE'
        ORDER BY futuras.tentativa
        LIMIT 1
        FOR UPDATE;

        IF v_proxima_id IS NULL THEN
            RAISE EXCEPTION 'nao existe proxima tentativa disponivel para este lead';
        END IF;

        UPDATE prospect.ligacoes AS proxima
           SET agendada_para = p_retornar_em,
               observacao = COALESCE(
                   proxima.observacao,
                   'Retorno solicitado em ligacao anterior'
               )
         WHERE proxima.id = v_proxima_id
           AND proxima.empresa_id = p_empresa_id;
    END IF;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'ligacao', TO_JSONB(v_ligacao),
        'proxima_ligacao_id', v_proxima_id,
        'tentativas_canceladas', v_canceladas
    );
END;
$$;

COMMIT;

-- Exemplos para teste manual:
--
-- SELECT prospect.fn_ligacoes_leads_elegiveis(1, 12);
--
-- SELECT prospect.fn_ligacoes_criar_fila(1, CURRENT_DATE, 12);
--
-- SELECT prospect.fn_ligacoes_atualizar(
--     1,
--     10,
--     'SEM_SUCESSO',
--     'Telefone chamou, mas ninguem atendeu.',
--     NULL
-- );
--
-- SELECT prospect.fn_ligacoes_atualizar(
--     1,
--     11,
--     'RETORNAR',
--     'Responsavel chega depois das 16 horas.',
--     (CURRENT_DATE + TIME '16:30') AT TIME ZONE 'America/Sao_Paulo'
-- );
