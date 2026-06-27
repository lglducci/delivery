  CREATE OR REPLACE FUNCTION public.ff_relatorio_pagar_fornecedor_agregado(
  p_empresa_id bigint
)
RETURNS TABLE (
  fornecedor_id bigint,
  fornecedor_nome text,
  vencido numeric,
  vence_7_dias numeric,
  vence_15_dias numeric,
  vence_30_dias numeric,
  vence_60_dias numeric,
  acima_60_dias numeric,
  total_aberto numeric,
  qtd_titulos bigint
)
LANGUAGE sql
AS $$
  SELECT
    cp.fornecedor_id,
    COALESCE(f.nome, 'Sem fornecedor') AS fornecedor_nome,

    SUM(CASE WHEN cp.vencimento < CURRENT_DATE THEN cp.valor ELSE 0 END) AS vencido,

    SUM(CASE WHEN cp.vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + 7 THEN cp.valor ELSE 0 END) AS vence_7_dias,

    SUM(CASE WHEN cp.vencimento BETWEEN CURRENT_DATE + 8 AND CURRENT_DATE + 15 THEN cp.valor ELSE 0 END) AS vence_15_dias,

    SUM(CASE WHEN cp.vencimento BETWEEN CURRENT_DATE + 16 AND CURRENT_DATE + 30 THEN cp.valor ELSE 0 END) AS vence_30_dias,

    SUM(CASE WHEN cp.vencimento BETWEEN CURRENT_DATE + 31 AND CURRENT_DATE + 60 THEN cp.valor ELSE 0 END) AS vence_60_dias,

    SUM(CASE WHEN cp.vencimento > CURRENT_DATE + 60 THEN cp.valor ELSE 0 END) AS acima_60_dias,

    SUM(cp.valor) AS total_aberto,

    COUNT(*) AS qtd_titulos

  FROM public.contas_a_pagar cp
  LEFT JOIN public.pessoa f
    ON f.id = cp.fornecedor_id

  WHERE cp.empresa_id = p_empresa_id
    AND COALESCE(cp.status, 'aberto') IN ('aberto', 'aberta')

  GROUP BY
    cp.fornecedor_id,
    COALESCE(f.nome, 'Sem fornecedor')

  ORDER BY
    SUM(cp.valor) DESC;
$$;