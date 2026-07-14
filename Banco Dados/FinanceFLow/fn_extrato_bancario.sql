CREATE OR REPLACE FUNCTION public.fn_extrato_bancario(
  p_empresa_id bigint,
  p_conta_id bigint,
  p_data_ini date,
  p_data_fim date
)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH mov AS (
  SELECT
    t.id,
    t.data_movimento,
    t.descricao,
    t.conta_id,
    c.nome AS conta_nome,
    t.tipo,
    t.origem,
    t.classificacao,
    t.forma_pagamento,
     
    t.valor
  FROM public.transacoes t
  LEFT JOIN public.contas_financeiras c ON c.id = t.conta_id
  WHERE t.empresa_id = p_empresa_id
    AND t.conta_id = p_conta_id
    AND t.data_movimento BETWEEN p_data_ini AND p_data_fim
),
saldo_anterior AS (
  SELECT COALESCE(SUM(
    CASE 
      WHEN t.tipo = 'entrada' THEN t.valor
      ELSE -t.valor
    END
  ),0) AS saldo
  FROM public.transacoes t
  WHERE t.empresa_id = p_empresa_id
    AND t.conta_id = p_conta_id
    AND t.data_movimento < p_data_ini
),
totais AS (
  SELECT
    COUNT(*) AS qtd_registros,
    COALESCE(SUM(CASE WHEN tipo = 'entrada' THEN valor ELSE 0 END),0) AS entradas,
    COALESCE(SUM(CASE WHEN tipo = 'saida' THEN valor ELSE 0 END),0) AS saidas
  FROM mov
)
SELECT jsonb_build_object(
  'saldo_inicial', s.saldo,
  'qtd_registros', t.qtd_registros,
  'entradas', t.entradas,
  'saidas', t.saidas,
  'saldo_final', s.saldo + t.entradas - t.saidas,
  'linhas', COALESCE((
    SELECT jsonb_agg(to_jsonb(m) ORDER BY m.data_movimento, m.id)
    FROM mov m
  ), '[]'::jsonb)
)
FROM saldo_anterior s
CROSS JOIN totais t;
$$;