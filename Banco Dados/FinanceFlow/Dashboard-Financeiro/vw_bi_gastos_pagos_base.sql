DROP VIEW IF EXISTS public.vw_bi_gastos_pagos_base;

CREATE OR REPLACE VIEW public.vw_bi_gastos_pagos_base AS

-- 1) Pagamentos de contas a pagar
SELECT
  t.empresa_id,
  t.data_movimento::date AS data_movimento,
  t.descricao,
  ABS(t.valor)::numeric(14,2) AS valor,
  cc.id AS conta_id,
  cc.codigo,
  cc.nome AS conta_nome,
  'CONTA_PAGAR'::text AS origem_bi
FROM public.transacoes t
JOIN public.contas_a_pagar cp
  ON cp.id = t.pagar_id
 AND cp.empresa_id = t.empresa_id
JOIN contab.contas cc
  ON cc.id = cp.contabil_id
WHERE t.tipo = 'saida'
  AND t.pagar_id IS NOT NULL
  AND COALESCE(t.origem, '') NOT IN ('transferencia', 'estorno')
  AND (
    cc.codigo LIKE '5.%'
    OR cc.codigo LIKE '6.%'
  )
  AND cc.analitica = true

UNION ALL

-- 2) Saídas diretas
SELECT
  t.empresa_id,
  t.data_movimento::date AS data_movimento,
  t.descricao,
  ABS(t.valor)::numeric(14,2) AS valor,
  cc.id AS conta_id,
  cc.codigo,
  cc.nome AS conta_nome,
  'SAIDA_DIRETA'::text AS origem_bi
FROM public.transacoes t
JOIN contab.contas cc
  ON cc.id = t.contabil_id
WHERE t.tipo = 'saida'
  AND t.pagar_id IS NULL
  AND t.receber_id IS NULL
  AND t.fatura_id IS NULL
  AND COALESCE(t.origem, '') NOT IN (
    'transferencia',
    'estorno',
    'pagamento',
    'recebimento',
    'pagamento_fatura',
    'fatura_cartao'
  )
  AND (
    cc.codigo LIKE '5.%'
    OR cc.codigo LIKE '6.%'
  )
  AND cc.analitica = true;