 CREATE OR REPLACE VIEW contab.vw_dre_ytd AS
WITH
params AS (
  SELECT
    date_trunc('year',  CURRENT_DATE)::date AS ano_ini,
    date_trunc('month', CURRENT_DATE)::date AS mes_ini
),
limites AS (
  SELECT
    ano_ini,
    mes_ini,
    (mes_ini + INTERVAL '1 month' - INTERVAL '1 day')::date AS mes_fim
  FROM params
),

/* Fonte: razão */
mov AS (
  SELECT
    r.data_mov::date,
    r.conta_codigo,
    COALESCE(r.debito,0)::numeric(18,2)  AS debito,
    COALESCE(r.credito,0)::numeric(18,2) AS credito
  FROM contab.vw_razao r
),

/* Mapeia conta -> grupo da DRE, e aplica sinal (1 = D-C; -1 = C-D) */
valores AS (
  SELECT
    mp.grupo,
    mp.ordem,
    CASE
      WHEN mp.sinal =  1 THEN (m.debito  - m.credito)
      WHEN mp.sinal = -1 THEN (m.credito - m.debito)
      ELSE 0
    END::numeric(18,2) AS valor,
    m.data_mov
  FROM mov m
  JOIN contab.dre_mapeamento mp
    ON m.conta_codigo LIKE mp.conta_prefix || '%'
),

/* Acumula MÊS e YTD por grupo */
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

/* Pivota os grupos para facilitar os cálculos derivados */
p AS (
  SELECT
    /* Receita */
    COALESCE(SUM(CASE WHEN grupo='RECEITA_BRUTA'        THEN valor_mes        END),0)::numeric(18,2) AS rb_mes,
    COALESCE(SUM(CASE WHEN grupo='RECEITA_BRUTA'        THEN valor_acumulado  END),0)::numeric(18,2) AS rb_ytd,
    COALESCE(SUM(CASE WHEN grupo='DEDUCOES'             THEN valor_mes        END),0)::numeric(18,2) AS ded_mes,
    COALESCE(SUM(CASE WHEN grupo='DEDUCOES'             THEN valor_acumulado  END),0)::numeric(18,2) AS ded_ytd,
    /* Custo */
    COALESCE(SUM(CASE WHEN grupo='CMV_CSP'              THEN valor_mes        END),0)::numeric(18,2) AS cmv_mes,
    COALESCE(SUM(CASE WHEN grupo='CMV_CSP'              THEN valor_acumulado  END),0)::numeric(18,2) AS cmv_ytd,
    /* Despesas operacionais */
    COALESCE(SUM(CASE WHEN grupo='DESPESAS_OPERACIONAIS' THEN valor_mes       END),0)::numeric(18,2) AS dop_mes,
    COALESCE(SUM(CASE WHEN grupo='DESPESAS_OPERACIONAIS' THEN valor_acumulado END),0)::numeric(18,2) AS dop_ytd,
    /* Financeiro */
    COALESCE(SUM(CASE WHEN grupo='RECEITAS_FINANCEIRAS' THEN valor_mes        END),0)::numeric(18,2) AS rfin_mes,
    COALESCE(SUM(CASE WHEN grupo='RECEITAS_FINANCEIRAS' THEN valor_acumulado  END),0)::numeric(18,2) AS rfin_ytd,
    COALESCE(SUM(CASE WHEN grupo='DESPESAS_FINANCEIRAS' THEN valor_mes        END),0)::numeric(18,2) AS dfin_mes,
    COALESCE(SUM(CASE WHEN grupo='DESPESAS_FINANCEIRAS' THEN valor_acumulado  END),0)::numeric(18,2) AS dfin_ytd,
    /* IR/CSLL */
    COALESCE(SUM(CASE WHEN grupo='IR_CSLL'              THEN valor_mes        END),0)::numeric(18,2) AS ir_mes,
    COALESCE(SUM(CASE WHEN grupo='IR_CSLL'              THEN valor_acumulado  END),0)::numeric(18,2) AS ir_ytd
  FROM acum
)

/* Saída: linhas básicas + derivadas */
SELECT ordem, grupo AS linha, valor_mes, valor_acumulado
FROM acum

UNION ALL
SELECT 15, 'RECEITA_LIQUIDA',
       (p.rb_mes  - p.ded_mes)::numeric(18,2),
       (p.rb_ytd  - p.ded_ytd)::numeric(18,2)
FROM p

UNION ALL
SELECT 35, 'RESULTADO_BRUTO',
       (p.rb_mes - p.ded_mes - p.cmv_mes)::numeric(18,2),
       (p.rb_ytd - p.ded_ytd - p.cmv_ytd)::numeric(18,2)
FROM p

UNION ALL
SELECT 55, 'RESULTADO_OPERACIONAL',
       ( (p.rb_mes - p.ded_mes - p.cmv_mes) - p.dop_mes )::numeric(18,2),
       ( (p.rb_ytd - p.ded_ytd - p.cmv_ytd) - p.dop_ytd )::numeric(18,2)
FROM p

UNION ALL
SELECT 65, 'RESULTADO_ANTES_IMPOSTOS',
       ( (p.rb_mes - p.ded_mes - p.cmv_mes) - p.dop_mes + p.rfin_mes - p.dfin_mes )::numeric(18,2),
       ( (p.rb_ytd - p.ded_ytd - p.cmv_ytd) - p.dop_ytd + p.rfin_ytd - p.dfin_ytd )::numeric(18,2)
FROM p

UNION ALL
SELECT 80, 'RESULTADO_LIQUIDO',
       ( (p.rb_mes - p.ded_mes - p.cmv_mes) - p.dop_mes + p.rfin_mes - p.dfin_mes - p.ir_mes )::numeric(18,2),
       ( (p.rb_ytd - p.ded_ytd - p.cmv_ytd) - p.dop_ytd + p.rfin_ytd - p.dfin_ytd - p.ir_ytd )::numeric(18,2)
FROM p

ORDER BY 1, 2;
