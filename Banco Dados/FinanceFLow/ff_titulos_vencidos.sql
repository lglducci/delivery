  CREATE OR REPLACE FUNCTION public.ff_titulos_vencidos (
    p_empresa_id BIGINT,
    p_dias_a_vencer INT DEFAULT 0   -- 0 = só vencidos | 15 = vencidos + próximos 15 dias
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
    SELECT ultimo_dia_processado
    FROM contab.controle_fechamento
    WHERE empresa_id = p_empresa_id
),

-- =========================
-- CONTAS A PAGAR
-- =========================
pagar AS (
    SELECT
        'PAGAR'                        AS tipo_origem,
        p.id                           AS origem_id,
        p.descricao,
        pe.nome                        AS parceiro,
        p.valor,

        p.vencimento,
        (CURRENT_DATE - p.vencimento)::INT AS dias_atraso,

        p.status,
        p.evento_codigo, 
        CASE
          WHEN u.ultimo_dia_processado IS NOT NULL
           AND p.vencimento < u.ultimo_dia_processado
          THEN true
          ELSE false
        END AS critico,

        CASE
          WHEN u.ultimo_dia_processado IS NOT NULL
           AND p.vencimento < u.ultimo_dia_processado
          THEN
            '⚠ Vencido antes do último fechamento contábil e não liquidado.'
          ELSE NULL
        END AS critico_msg,

        'contas_a_pagar'               AS origem_tabela

    FROM contas_a_pagar p
    LEFT JOIN pessoa pe ON pe.id = p.fornecedor_id
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
        'RECEBER'                      AS tipo_origem,
        r.id                           AS origem_id,
        r.descricao,
        pe.nome                        AS parceiro,
        r.valor,

        r.vencimento,
        (CURRENT_DATE - r.vencimento)::INT AS dias_atraso,

        r.status,
        r.evento_codigo,  
        CASE
          WHEN u.ultimo_dia_processado IS NOT NULL
           AND r.vencimento < u.ultimo_dia_processado
          THEN true
          ELSE false
        END AS critico,

        CASE
          WHEN u.ultimo_dia_processado IS NOT NULL
           AND r.vencimento < u.ultimo_dia_processado
          THEN
            '⚠ Vencido antes do último fechamento contábil e não recebido.'
          ELSE NULL
        END AS critico_msg,

        'contas_a_receber'             AS origem_tabela

    FROM contas_a_receber r
    LEFT JOIN pessoa pe ON pe.id = r.fornecedor_id
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
        'FATURA_CARTAO'                AS tipo_origem,
        f.id                           AS origem_id,
        'Fatura cartão ' || c.nome    AS descricao,
        c.nomecartao                  AS parceiro,
        f.valor_total                 AS valor,

        f.vencimento,
        (CURRENT_DATE - f.vencimento)::INT AS dias_atraso,

        f.status,
        f.evento_codigo, 

        CASE
          WHEN u.ultimo_dia_processado IS NOT NULL
           AND f.vencimento < u.ultimo_dia_processado
          THEN true
          ELSE false
        END AS critico,

        CASE
          WHEN u.ultimo_dia_processado IS NOT NULL
           AND f.vencimento < u.ultimo_dia_processado
          THEN
            '⚠ Fatura venceu antes do último fechamento contábil e não foi paga.'
          ELSE NULL
        END AS critico_msg,

        'cartoes_faturas'              AS origem_tabela

    FROM cartoes_faturas f
    JOIN cartoes c ON c.id = f.cartao_id
    CROSS JOIN ultimo u
    WHERE f.empresa_id = p_empresa_id
      AND f.status <> 'paga'
      AND f.vencimento <= CURRENT_DATE + p_dias_a_vencer
)

-- =========================
-- RESULTADO FINAL
-- =========================
SELECT * FROM pagar
UNION ALL
SELECT * FROM receber
UNION ALL
SELECT * FROM faturas
ORDER BY vencimento, tipo_origem;
$$;