 DROP VIEW IF EXISTS public.vw_top_despesas_30_dias;
DROP VIEW IF EXISTS public.vw_bi_gastos_pagos_30_dias;

CREATE OR REPLACE VIEW public.vw_bi_gastos_pagos_30_dias AS

SELECT
  t.empresa_id,
  t.data_movimento::date AS data_movimento,
  t.descricao,
  ABS(t.valor)::numeric(14,2) AS valor,
  cc.id AS conta_id,
  cc.codigo,
  cc.nome AS conta_nome,
  'PAGAR'::text AS origem_bi
FROM public.transacoes t
 JOIN public.contas_a_pagar cp
  ON cp.id = t.pagar_id
 AND cp.empresa_id = t.empresa_id
LEFT JOIN contab.contas cc
  ON cc.id = cp.contabil_id
WHERE t.tipo = 'saida'
  AND t.pagar_id IS NOT NULL
  AND t.data_movimento >= CURRENT_DATE - INTERVAL '30 days'
  AND COALESCE(t.origem, '') = 'Pagamento'
  AND (cc.codigo LIKE '5.%' OR cc.codigo LIKE '6.%')
  AND cc.analitica = true

UNION ALL

SELECT
  t.empresa_id,
  t.data_movimento::date AS data_movimento,
  t.descricao,
  ABS(t.valor)::numeric(14,2) AS valor,
  cc.id AS conta_id,
  cc.codigo,
  cc.nome AS conta_nome,
  'DIRETO'::text AS origem_bi
FROM public.transacoes t

LEFT JOIN contab.contas cc
  ON cc.id = t.contabil_id
WHERE t.tipo = 'saida'
  AND t.pagar_id IS NULL
  AND t.data_movimento >= CURRENT_DATE - INTERVAL '30 days'
  AND COALESCE(t.origem, '') NOT IN ('transferencia', 'estorno')
  AND (cc.codigo LIKE '5.%' OR cc.codigo LIKE '6.%')
  AND cc.analitica = true;



  CREATE OR REPLACE VIEW public.vw_top_despesas_30_dias AS
SELECT
  empresa_id,
  conta_id,
  codigo,
  conta_nome,
  SUM(valor)::numeric(14,2) AS total
FROM public.vw_bi_gastos_pagos_30_dias
GROUP BY
  empresa_id,
  conta_id,
  codigo,
  conta_nome;