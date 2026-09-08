 CREATE OR REPLACE FUNCTION public.ff_titulos_vencidos (
    p_empresa_id BIGINT,
    p_dias_a_vencer INT DEFAULT 0
)
RETURNS TABLE (
    tipo_origem         TEXT,
    origem_id           BIGINT,
    descricao           TEXT,
    parceiro            TEXT,
    valor               NUMERIC(12,2),
    vencimento          DATE,
    dias_atraso         INT,
    status              TEXT,
    evento_codigo       TEXT,
    critico             BOOLEAN,
    critico_msg         TEXT,
    origem_tabela       TEXT
)
LANGUAGE sql
STABLE
AS $$

WITH ultimo AS (
    SELECT MAX(ultimo_dia_processado) AS ultimo_dia_processado
    FROM contab.controle_fechamento
    WHERE empresa_id = p_empresa_id
),

-- =========================
-- CONTAS A PAGAR
-- =========================
pagar AS (
    SELECT
        'PAGAR'::TEXT AS tipo_origem,
        p.id AS origem_id,
        p.descricao,
        pe.nome AS parceiro,
        p.valor::NUMERIC(12,2),

        p.vencimento,
        (CURRENT_DATE - p.vencimento)::INT AS dias_atraso,

        p.status,
        p.evento_codigo,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND p.vencimento < u.ultimo_dia_processado
            THEN TRUE
            ELSE FALSE
        END AS critico,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND p.vencimento < u.ultimo_dia_processado
            THEN '⚠ Vencido antes do último fechamento contábil e não liquidado.'
            ELSE NULL
        END AS critico_msg,

        'contas_a_pagar'::TEXT AS origem_tabela

    FROM contas_a_pagar p
    LEFT JOIN pessoa pe
        ON pe.id = p.fornecedor_id
    CROSS JOIN ultimo u

    WHERE p.empresa_id = p_empresa_id
      AND p.status = 'aberto'
      AND p.vencimento <= CURRENT_DATE + p_dias_a_vencer
),

-- =========================
-- CONTAS A RECEBER
-- =========================
receber AS (
    SELECT
        'RECEBER'::TEXT AS tipo_origem,
        r.id AS origem_id,
        r.descricao,
        pe.nome AS parceiro,
        r.valor::NUMERIC(12,2),

        r.vencimento,
        (CURRENT_DATE - r.vencimento)::INT AS dias_atraso,

        r.status,
        r.evento_codigo,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND r.vencimento < u.ultimo_dia_processado
            THEN TRUE
            ELSE FALSE
        END AS critico,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND r.vencimento < u.ultimo_dia_processado
            THEN '⚠ Vencido antes do último fechamento contábil e não recebido.'
            ELSE NULL
        END AS critico_msg,

        'contas_a_receber'::TEXT AS origem_tabela

    FROM contas_a_receber r
    LEFT JOIN pessoa pe
        ON pe.id = r.fornecedor_id
    CROSS JOIN ultimo u

    WHERE r.empresa_id = p_empresa_id
      AND r.status = 'aberto'
      AND r.vencimento <= CURRENT_DATE + p_dias_a_vencer
),

-- =========================
-- FATURAS DE CARTÃO
-- =========================
faturas AS (
    SELECT
        'FATURA_CARTAO'::TEXT AS tipo_origem,
        f.id AS origem_id,

        'Fatura cartão ' ||
        COALESCE(c.nome, '') ||
        CASE
            WHEN c.numero IS NOT NULL
            THEN ' - ' || c.numero::TEXT
            ELSE ''
        END AS descricao,

        c.nomecartao AS parceiro,
        f.valor_total::NUMERIC(12,2) AS valor,

        f.vencimento,
        (CURRENT_DATE - f.vencimento)::INT AS dias_atraso,

        f.status,
        f.evento_codigo,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND f.vencimento < u.ultimo_dia_processado
            THEN TRUE
            ELSE FALSE
        END AS critico,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND f.vencimento < u.ultimo_dia_processado
            THEN '⚠ Fatura venceu antes do último fechamento contábil e não foi paga.'
            ELSE NULL
        END AS critico_msg,

        'cartoes_faturas'::TEXT AS origem_tabela

    FROM cartoes_faturas f
    JOIN cartoes c
        ON c.id = f.cartao_id
    CROSS JOIN ultimo u

    WHERE f.empresa_id = p_empresa_id
      AND f.status <> 'paga'
      AND f.vencimento <= CURRENT_DATE + p_dias_a_vencer
),

-- =========================
-- MESES QUE SERÃO VERIFICADOS
-- =========================
competencias AS (
    SELECT
        gs::DATE AS competencia
    FROM generate_series(
        DATE_TRUNC('month', CURRENT_DATE)::DATE,
        DATE_TRUNC(
            'month',
            CURRENT_DATE + GREATEST(p_dias_a_vencer, 0)
        )::DATE,
        INTERVAL '1 month'
    ) gs
),

-- =========================
-- RECORRENTES AINDA NÃO GERADAS
-- =========================
recorrentes_base AS (
    SELECT
        cr.id,
        cr.empresa_id,
        cr.descricao,
        cr.fornecedor_id,
        cr.valor_padrao,
        cr.tipo_valor,
        cr.dia_vencimento,
        comp.competencia,

        (
            comp.competencia
            +
            (
                LEAST(
                    cr.dia_vencimento,
                    EXTRACT(
                        DAY FROM (
                            comp.competencia
                            + INTERVAL '1 month'
                            - INTERVAL '1 day'
                        )
                    )::INT
                ) - 1
            ) * INTERVAL '1 day'
        )::DATE AS vencimento_calculado

    FROM contas_recorrentes cr
    CROSS JOIN competencias comp

    WHERE cr.empresa_id = p_empresa_id
      AND cr.ativo = TRUE

      AND NOT EXISTS (
          SELECT 1
          FROM contas_recorrentes_geradas cg
          WHERE cg.empresa_id = cr.empresa_id
            AND cg.recorrente_id = cr.id
            AND cg.competencia >= comp.competencia
            AND cg.competencia < comp.competencia + INTERVAL '1 month'
      )
),

recorrentes AS (
    SELECT
        'RECORRENTE'::TEXT AS tipo_origem,
        rb.id AS origem_id,

        rb.descricao ||
        CASE
            WHEN rb.tipo_valor = 'VARIAVEL'
            THEN ' — valor variável'
            ELSE ''
        END AS descricao,

        pe.nome AS parceiro,

        COALESCE(rb.valor_padrao, 0)::NUMERIC(12,2) AS valor,

        rb.vencimento_calculado AS vencimento,

        (
            CURRENT_DATE - rb.vencimento_calculado
        )::INT AS dias_atraso,

        'aberto'::TEXT AS status,

        'RECORRENTE'::TEXT AS evento_codigo,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND rb.vencimento_calculado < u.ultimo_dia_processado
            THEN TRUE
            ELSE FALSE
        END AS critico,

        CASE
            WHEN u.ultimo_dia_processado IS NOT NULL
             AND rb.vencimento_calculado < u.ultimo_dia_processado
            THEN '⚠ Recorrência não foi gerada antes do último fechamento contábil.'
            ELSE NULL
        END AS critico_msg,

        'contas_recorrentes'::TEXT AS origem_tabela

    FROM recorrentes_base rb
    LEFT JOIN pessoa pe
        ON pe.id = rb.fornecedor_id
    CROSS JOIN ultimo u

    WHERE rb.vencimento_calculado
          <= CURRENT_DATE + p_dias_a_vencer
)

-- =========================
-- RESULTADO FINAL
-- =========================
SELECT * FROM pagar

UNION ALL

SELECT * FROM receber

UNION ALL

SELECT * FROM faturas

UNION ALL

SELECT * FROM recorrentes

ORDER BY vencimento, tipo_origem;

$$;