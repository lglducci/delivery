  CREATE OR REPLACE FUNCTION contab.sp_fluxo_caixa_projetado_agrupado (
    p_empresa_id BIGINT,
    p_data_ini   DATE,
    p_data_fim   DATE,
    p_tipo       TEXT
)
RETURNS TABLE (
    periodo_ini   DATE,
    periodo_fim   DATE,
    legenda       TEXT,
    saldo_inicial NUMERIC(14,2),
    entrada       NUMERIC(14,2),
    saida         NUMERIC(14,2),
    saldo_final   NUMERIC(14,2)
)
LANGUAGE sql
AS $$
WITH base AS (
    SELECT *
    FROM contab.sp_fluxo_caixa_projetado_diario(
        p_empresa_id,
        p_data_ini,
        p_data_fim
    )
),

marcacao AS (
    SELECT
        b.*,
        CASE
            WHEN UPPER(p_tipo) = 'MENSAL' THEN date_trunc('month', b.data_ref)::date
            WHEN UPPER(p_tipo) = '7D' THEN (p_data_ini + (((b.data_ref - p_data_ini) / 7) * 7))::date
            WHEN UPPER(p_tipo) = '15D' THEN (p_data_ini + (((b.data_ref - p_data_ini) / 15) * 15))::date
            ELSE b.data_ref
        END AS grupo_ini
    FROM base b
),

agrupado AS (
    SELECT
        grupo_ini AS periodo_ini,
        MAX(data_ref) AS periodo_fim,
        MIN(saldo_inicial) AS saldo_inicial,
        SUM(entrada)::numeric(14,2) AS entrada,
        SUM(saida)::numeric(14,2) AS saida,
        MAX(saldo_final) AS saldo_final
    FROM marcacao
    GROUP BY grupo_ini
)

SELECT
    a.periodo_ini,
    a.periodo_fim,
    CASE
        WHEN UPPER(p_tipo) = 'MENSAL'
            THEN to_char(a.periodo_ini, 'MM/YYYY')
        ELSE to_char(a.periodo_ini, 'DD/MM/YYYY') || ' a ' || to_char(a.periodo_fim, 'DD/MM/YYYY')
    END AS legenda,
    a.saldo_inicial::numeric(14,2),
    a.entrada::numeric(14,2),
    a.saida::numeric(14,2),
    a.saldo_final::numeric(14,2)
FROM agrupado a
ORDER BY a.periodo_ini;
$$;