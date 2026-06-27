CREATE OR REPLACE FUNCTION public.fn_reclassificacao_eventos(
  p_empresa_id bigint,
  p_data_ini date,
  p_data_fim date
)
RETURNS TABLE (
  id bigint,
  empresa_id bigint,
  descricao text,
  valor numeric,
  tipo text,
  parcelas int,
  parcela_total int,
  vencimento date,
  data_movimento date,
  evento_codigo text,
  data_criacao timestamp,
  tipo_evento text,
  origem text,
  forma text,
  classificacao text,
  tipo_operacao text,
  conta_id bigint,
  categoria_id bigint,
  fornecedor_id bigint,
  origem_id bigint,
  status text,
  importacao_id bigint,
  contabil_id bigint,
  pode_reclassificar boolean,
  motivo_reclassificacao text
)
LANGUAGE sql
AS $$

-- CONTAS A PAGAR
SELECT
  cp.id,
  cp.empresa_id,
  cp.descricao,
  cp.valor,
  'saida'::text AS tipo,
  cp.parcela_num AS parcelas,
  cp.parcelas AS parcela_total,
  cp.vencimento,
  COALESCE(cp.vencimento, cp.criado_em::date) AS data_movimento,
  cp.evento_codigo,
  cp.criado_em AS data_criacao,
  cp.tipo_evento::text,
  'conta_pagar'::text AS origem,
  cp.forma_pagamento AS forma,
  cp.classificacao,
  'conta_pagar'::text AS tipo_operacao,
  0::bigint AS conta_id,
  cp.categoria_id,
  cp.fornecedor_id,
  0::bigint AS origem_id,
  cp.status,
  0::bigint AS importacao_id,
  cp.contabil_id,
  true AS pode_reclassificar,
  'Conta a pagar aberta e primeira parcela'::text AS motivo_reclassificacao
FROM public.contas_a_pagar cp
WHERE cp.empresa_id = p_empresa_id
  AND COALESCE(cp.vencimento, cp.criado_em::date) BETWEEN p_data_ini AND p_data_fim
  AND COALESCE(cp.parcela_num, 1) = 1
  AND cp.status IN ('aberto', 'aberta')

UNION ALL

-- CONTAS A RECEBER
SELECT
  cr.id,
  cr.empresa_id,
  cr.descricao,
  cr.valor,
  'entrada'::text AS tipo,
  cr.parcela_num AS parcelas,
  cr.parcelas AS parcela_total,
  cr.vencimento,
  COALESCE(cr.vencimento, cr.criado_em::date) AS data_movimento,
  cr.evento_codigo,
  cr.criado_em AS data_criacao,
  cr.tipo_evento::text,
  'conta_receber'::text AS origem,
  cr.forma_recebimento AS forma,
  cr.classificacao,
  'conta_receber'::text AS tipo_operacao,
  0::bigint AS conta_id,
  cr.categoria_id,
  cr.fornecedor_id,
  0::bigint AS origem_id,
  cr.status,
  0::bigint AS importacao_id,
  cr.contabil_id,
  true AS pode_reclassificar,
  'Conta a receber aberta e primeira parcela'::text AS motivo_reclassificacao
FROM public.contas_a_receber cr
WHERE cr.empresa_id = p_empresa_id
  AND COALESCE(cr.vencimento, cr.criado_em::date) BETWEEN p_data_ini AND p_data_fim
  AND COALESCE(cr.parcela_num, 1) = 1
  AND cr.status IN ('aberto', 'aberta')

UNION ALL

-- TRANSAÇÕES DIRETAS
SELECT
  t.id,
  t.empresa_id,
  t.descricao,
  t.valor,
  t.tipo,
  0::int AS parcelas,
  0::int AS parcela_total,
  NULL::date AS vencimento,
  t.data_movimento,
  t.evento_codigo,
  t.criado_em AS data_criacao,
  t.tipo_evento::text,
  'transacao'::text AS origem,
  t.forma_pagamento AS forma,
  t.classificacao,
  'transacao'::text AS tipo_operacao,
  t.conta_id,
  t.categoria_id,
  0::bigint AS fornecedor_id,
  t.origem_id,
  ''::text AS status,
  t.importacao_id,
  t.contabil_id,
  true AS pode_reclassificar,
  'Transação direta sem vínculo com pagar, receber ou fatura'::text AS motivo_reclassificacao
FROM public.transacoes t
WHERE t.empresa_id = p_empresa_id
  AND t.data_movimento BETWEEN p_data_ini AND p_data_fim
  AND t.pagar_id IS NULL
  AND t.receber_id IS NULL
  AND t.fatura_id IS NULL
  AND COALESCE(t.origem, '') NOT IN (
    'pagamento',
    'Pagamento',
    'recebimento',
    'Recebimento',
    'pagamento_fatura',
    'Pagamento Fatura',
    'fatura_cartao',
    'estorno',
    'transferencia'
  )
  UNION ALL

-- COMPRAS NO CARTÃO
SELECT
  cc.id,
  cc.empresa_id,
  cc.descricao,
  cc.valor_total AS valor,
  'saida'::text AS tipo,
  1::int AS parcelas,
  cc.parcelas AS parcela_total,
  NULL::date AS vencimento,
  cc.data_compra AS data_movimento,
  cc.evento_codigo,
  cc.criado_em AS data_criacao,
  cc.tipo_evento::text,
  'cartao_compra'::text AS origem,
  'cartao_credito'::text AS forma,
  cc.classificacao,
  'cartao_compra'::text AS tipo_operacao,
  0::bigint AS conta_id,
  0::bigint AS categoria_id,
  0::bigint AS fornecedor_id,
  cc.id AS origem_id,
  'aberto'::text AS status,
  0::bigint AS importacao_id,
  cc.conta_contabil_id AS contabil_id,
  true AS pode_reclassificar,
  'Compra no cartão ainda não liquidada e primeira parcela'::text AS motivo_reclassificacao
FROM public.cartoes_compras cc
WHERE cc.empresa_id = p_empresa_id
  AND cc.data_compra BETWEEN p_data_ini AND p_data_fim   AND NOT EXISTS (
    SELECT 1
    FROM public.cartoes_transacoes ct
    JOIN public.cartoes_faturas cf
      ON cf.id = ct.fatura_id
     AND cf.empresa_id = ct.empresa_id
    WHERE ct.empresa_id = cc.empresa_id
      AND ct.compra_id = cc.id
      AND cf.status = 'paga'
  ); 

$$;