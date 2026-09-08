CREATE OR REPLACE VIEW public.vw_variacao_despesas_30_dias AS
WITH atual AS (

  SELECT
    empresa_id,
    conta_id,
    codigo,
    conta_nome,
    SUM(valor) AS valor_atual
  FROM public.vw_bi_gastos_pagos_base
  WHERE data_movimento >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY
    empresa_id,
    conta_id,
    codigo,
    conta_nome

),

anterior AS (

  SELECT
    empresa_id,
    conta_id,
    codigo,
    conta_nome,
    SUM(valor) AS valor_anterior
  FROM public.vw_bi_gastos_pagos_base
  WHERE data_movimento >= CURRENT_DATE - INTERVAL '60 days'
    AND data_movimento < CURRENT_DATE - INTERVAL '30 days'
  GROUP BY
    empresa_id,
    conta_id,
    codigo,
    conta_nome

)

SELECT
  COALESCE(a.empresa_id, b.empresa_id) AS empresa_id,
  COALESCE(a.conta_id, b.conta_id) AS conta_id,
  COALESCE(a.codigo, b.codigo) AS codigo,
  COALESCE(a.conta_nome, b.conta_nome) AS conta_nome,

  COALESCE(a.valor_atual, 0) AS valor_atual,
  COALESCE(b.valor_anterior, 0) AS valor_anterior,

  COALESCE(a.valor_atual, 0)
    - COALESCE(b.valor_anterior, 0)
    AS variacao_valor,

  CASE
    WHEN COALESCE(b.valor_anterior, 0) = 0
         AND COALESCE(a.valor_atual, 0) > 0
    THEN 999

    WHEN COALESCE(b.valor_anterior, 0) = 0
    THEN 0

    ELSE ROUND(
      (
        (
          COALESCE(a.valor_atual, 0)
          - COALESCE(b.valor_anterior, 0)
        )
        /
        b.valor_anterior
      ) * 100,
      2
    )
  END AS variacao_percentual

FROM atual a
FULL OUTER JOIN anterior b
  ON a.empresa_id = b.empresa_id
 AND a.conta_id = b.conta_id;