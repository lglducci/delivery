  CREATE OR REPLACE FUNCTION public.ff_relatorio_receber_pessoa_agregado(
  p_empresa_id bigint
)
RETURNS TABLE (
  pessoa_id bigint,
  pessoa_nome text,
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
  cr.fornecedor_id,
    COALESCE(p.nome, 'Sem pessoa') AS pessoa_nome,

    SUM(
      CASE
        WHEN cr.vencimento < CURRENT_DATE
        THEN cr.valor
        ELSE 0
      END
    ) AS vencido,

    SUM(
      CASE
        WHEN cr.vencimento BETWEEN CURRENT_DATE
        AND CURRENT_DATE + 7
        THEN cr.valor
        ELSE 0
      END
    ) AS vence_7_dias,

    SUM(
      CASE
        WHEN cr.vencimento BETWEEN CURRENT_DATE + 8
        AND CURRENT_DATE + 15
        THEN cr.valor
        ELSE 0
      END
    ) AS vence_15_dias,

    SUM(
      CASE
        WHEN cr.vencimento BETWEEN CURRENT_DATE + 16
        AND CURRENT_DATE + 30
        THEN cr.valor
        ELSE 0
      END
    ) AS vence_30_dias,

    SUM(
      CASE
        WHEN cr.vencimento BETWEEN CURRENT_DATE + 31
        AND CURRENT_DATE + 60
        THEN cr.valor
        ELSE 0
      END
    ) AS vence_60_dias,

    SUM(
      CASE
        WHEN cr.vencimento > CURRENT_DATE + 60
        THEN cr.valor
        ELSE 0
      END
    ) AS acima_60_dias,

    SUM(cr.valor) AS total_aberto,

    COUNT(*) AS qtd_titulos

  FROM public.contas_a_receber cr

  LEFT JOIN public.pessoa p
    ON p.id = cr.fornecedor_id

  WHERE cr.empresa_id = p_empresa_id
    AND COALESCE(cr.status, 'aberto') IN ('aberto', 'aberta')

  GROUP BY
   cr.fornecedor_id,
    COALESCE(p.nome, 'Sem pessoa')

  ORDER BY
    SUM(cr.valor) DESC;
$$;