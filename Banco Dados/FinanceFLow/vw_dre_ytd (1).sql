-- View de Demonstração do Resultado do Exercício (Mês x Acumulado no Ano)
DROP VIEW IF EXISTS contab.vw_dre_ytd CASCADE;

CREATE OR REPLACE VIEW contab.vw_dre_ytd AS
WITH
params AS (
  SELECT
    date_trunc('year', CURRENT_DATE)::date  AS ano_ini,
    date_trunc('month', CURRENT_DATE)::date AS mes_ini
),
limites AS (
  SELECT
    ano_ini,
    mes_ini,
    (mes_ini + INTERVAL '1 month' - INTERVAL '1 day')::date AS mes_fim
  FROM params
),

-- movimentos da razão
mov AS (
  SELECT
    r.data_mov::date,
    r.conta_codigo,
    COALESCE(r.debito,0)::numeric(18,2)  AS debito,
    COALESCE(r.credito,0)::numeric(18,2) AS credito
  FROM contab.vw_razao r
),

-- mapeamento DRE (prefixos -> grupo, ordem, sinal)
-- Crie esta tabela se ainda não existir:
-- CREATE TABLE contab.dre_mapeamento (
--   conta_prefix text,
--   grupo text,
--   ordem int,
--   sinal int  -- 1 = D-C, -1 = C-D
-- );
mov_map AS (
  SELECT
    m.*,
    mp.grupo,
    mp.ordem,
    mp.sinal
  FROM mov m
  JOIN contab.dre_mapeamento mp
    ON m.conta_codigo LIKE mp.conta_prefix || '%'
),

-- aplica sinal
valores AS (
  SELECT
    mm.grupo,
    mm.ordem,
    CASE WHEN mm.sinal =  1 THEN (mm.debito - mm.credito)
         WHEN mm.sinal = -1 THEN (mm.credito - mm.debito)
         ELSE 0 END AS valor,
    mm.data_mov
  FROM mov_map mm
),

-- acumula mês e YTD por grupo
acum AS (
  SELECT
    v.grupo,
    MIN(v.ordem) AS ordem,
    SUM(CASE WHEN v.data_mov BETWEEN l.mes_ini AND l.mes_fim THEN v.valor ELSE 0 END)::numeric(18,2) AS valor_mes,
    SUM(CASE WHEN v.data_mov BETWEEN l.ano_ini AND l.mes_fim THEN v.valor ELSE 0 END)::numeric(18,2) AS valor_acumulado
  FROM valores v
  CROSS JOIN limites l
  GROUP BY v.grupo
),

-- pivot (facilita cálculos derivados)
p AS (
  SELECT
    COALESCE(MAX(CASE WHEN grupo='RECEITA_BRUTA'        THEN valor_mes END),0) AS rb_mes,
    COALESCE(MAX(CASE WHEN grupo='RECEITA_BRUTA'        THEN valor_acumulado END),0) AS rb_ytd,
    COALESCE(MAX(CASE WHEN grupo='DEDUCOES'             THEN valor_mes END),0) AS ded_mes,
    COALESCE(MAX(CASE WHEN grupo='DEDUCOES'             THEN valor_acumulado END),0) AS ded_ytd,
    COALESCE(MAX(CASE WHEN grupo='CMV_CSP'              THEN valor_mes END),0) AS cmv_mes,
    COALESCE(MAX(CASE WHEN grupo='CMV_CSP'              THEN valor_acumulado END),0) AS cmv_ytd,
    COALESCE(MAX(CASE WHEN grupo='DESPESAS_OPERACIONAIS' THEN valor_mes END),0) AS dop_mes,
    COALESCE(MAX(CASE WHEN grupo='DESPESAS_OPERACIONAIS' THEN valor_acumulado END),0) AS dop_ytd,
    COALESCE(MAX(CASE WHEN grupo='RECEITAS_FINANCEIRAS' THEN valor_mes END),0) AS rfin_mes,
    COALESCE(MAX(CASE WHEN grupo='RECEITAS_FINANCEIRAS' THEN valor_acumulado END),0) AS rfin_ytd,
    COALESCE(MAX(CASE WHEN grupo='DESPESAS_FINANCEIRAS' THEN valor_mes END),0) AS dfin_mes,
    COALESCE(MAX(CASE WHEN grupo='DESPESAS_FINANCEIRAS' THEN valor_acumulado END),0) AS dfin_ytd,
    COALESCE(MAX(CASE WHEN grupo='IR_CSLL'              THEN valor_mes END),0) AS ir_mes,
    COALESCE(MAX(CASE WHEN grupo='IR_CSLL'              THEN valor_acumulado END),0) AS ir_ytd
  FROM acum
)

-- saída final
SELECT ordem, grupo, valor_mes, valor_acumulado
FROM acum

UNION ALL
SELECT 15,'RECEITA_LIQUIDA',
       (p.rb_mes - p.ded_mes),
       (p.rb_ytd - p.ded_ytd)
FROM p

UNION ALL
SELECT 35,'RESULTADO_BRUTO',
       (p.rb_mes - p.ded_mes - p.cmv_mes),
       (p.rb_ytd - p.ded_ytd - p.cmv_ytd)
FROM p

UNION ALL
SELECT 55,'RESULTADO_OPERACIONAL',
       ((p.rb_mes - p.ded_mes - p.cmv_mes) - p.dop_mes),
       ((p.rb_ytd - p.ded_ytd - p.cmv_ytd) - p.dop_ytd)
FROM p

UNION ALL
SELECT 65,'RESULTADO_ANTES_IMPOSTOS',
       ((p.rb_mes - p.ded_mes - p.cmv_mes) - p.dop_mes + p.rfin_mes - p.dfin_mes),
       ((p.rb_ytd - p.ded_ytd - p.cmv_ytd) - p.dop_ytd + p.rfin_ytd - p.dfin_ytd)
FROM p

UNION ALL
SELECT 80,'RESULTADO_LIQUIDO',
       ((p.rb_mes - p.ded_mes - p.cmv_mes) - p.dop_mes + p.rfin_mes - p.dfin_mes - p.ir_mes),
       ((p.rb_ytd - p.ded_ytd - p.cmv_ytd) - p.dop_ytd + p.rfin_ytd - p.dfin_ytd - p.ir_ytd)
FROM p

ORDER BY 1,2;
