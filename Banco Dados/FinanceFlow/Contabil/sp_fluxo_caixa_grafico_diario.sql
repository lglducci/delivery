 CREATE OR REPLACE FUNCTION contab.sp_fluxo_caixa_grafico_diario (
    p_empresa_id BIGINT,
    p_data_ini   DATE,
    p_data_fim   DATE
)
RETURNS TABLE (
    data_ref      DATE,
    entrada       NUMERIC(14,2),
    saida         NUMERIC(14,2),
    saldo_inicial NUMERIC(14,2),
    saldo_final   NUMERIC(14,2)
)
LANGUAGE sql
AS $$
WITH contas_caixa AS (
    SELECT c.id
    FROM contab.contas c
    WHERE c.empresa_id = p_empresa_id
      AND c.tipo = 'ATIVO'
      AND c.analitica = TRUE
      AND c.codigo LIKE '1.1.%'
),

saldo_base AS (
    SELECT COALESCE(SUM(si.saldo), 0) AS saldo
    FROM contab.saldos_iniciais si
    WHERE si.empresa_id = p_empresa_id
      AND si.conta_id IN (SELECT id FROM contas_caixa)
),

movimentos AS (
    SELECT
        l.data_mov::date AS data_mov,
        COALESCE(l.debito, 0)  AS entrada,
        COALESCE(l.credito, 0) AS saida,
        COALESCE(l.debito, 0) - COALESCE(l.credito, 0) AS mov_liquido
    FROM contab.lancamentos l
    WHERE l.empresa_id = p_empresa_id
      AND l.conta_id IN (SELECT id FROM contas_caixa)
),

calendario AS (
    SELECT generate_series(p_data_ini, p_data_fim, interval '1 day')::date AS data_ref
),

mov_diario AS (
    SELECT
        c.data_ref,
        COALESCE(SUM(m.entrada), 0) AS entrada,
        COALESCE(SUM(m.saida), 0) AS saida,
        COALESCE(SUM(m.mov_liquido), 0) AS mov_dia
    FROM calendario c
    LEFT JOIN movimentos m ON m.data_mov = c.data_ref
    GROUP BY c.data_ref
),

saldo_anterior AS (
    SELECT
        COALESCE((SELECT saldo FROM saldo_base), 0)
        +
        COALESCE((
            SELECT SUM(m.mov_liquido)
            FROM movimentos m
            WHERE m.data_mov < p_data_ini
        ), 0) AS saldo_ini_periodo
),

serie AS (
    SELECT
        d.data_ref,
        d.entrada,
        d.saida,
        sa.saldo_ini_periodo
        +
        COALESCE(SUM(d.mov_dia) OVER (
            ORDER BY d.data_ref
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0) AS saldo_inicial,
        sa.saldo_ini_periodo
        +
        SUM(d.mov_dia) OVER (
            ORDER BY d.data_ref
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS saldo_final
    FROM mov_diario d
    CROSS JOIN saldo_anterior sa
)

SELECT
    data_ref,
    entrada,
    saida,
    saldo_inicial,
    saldo_final
FROM serie
ORDER BY data_ref;
$$;