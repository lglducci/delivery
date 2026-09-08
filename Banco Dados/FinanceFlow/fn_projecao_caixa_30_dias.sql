CREATE OR REPLACE FUNCTION public.fn_projecao_caixa_30_dias(
  p_empresa_id bigint
)
RETURNS TABLE (
  data_ref date,
  entrada numeric,
  saida numeric,
  saldo_previsto numeric
)
LANGUAGE sql
AS $$
WITH recorrentes_projetadas AS (
  SELECT
    cr.id AS recorrente_id,
    cr.empresa_id,
    cr.descricao,
    make_date(
      EXTRACT(YEAR FROM gs.mes)::int,
      EXTRACT(MONTH FROM gs.mes)::int,
      LEAST(
        cr.dia_vencimento,
        EXTRACT(
          DAY FROM (
            date_trunc('month', gs.mes)
            + interval '1 month - 1 day'
          )
        )::int
      )
    ) AS vencimento,
    COALESCE(cr.valor_padrao, 0)::numeric(14,2) AS valor
  FROM public.contas_recorrentes cr
  CROSS JOIN generate_series(
    date_trunc('month', CURRENT_DATE)::date,
    date_trunc('month', CURRENT_DATE + interval '30 days')::date,
    interval '1 month'
  ) gs(mes)
  WHERE cr.empresa_id = p_empresa_id
    AND cr.ativo = true
    AND COALESCE(cr.valor_padrao, 0) > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.contas_recorrentes_geradas g
      WHERE g.empresa_id = cr.empresa_id
        AND g.recorrente_id = cr.id
        AND date_trunc('month', g.competencia)::date =
            date_trunc('month', gs.mes)::date
    )
),

eventos AS (
  -- contas a receber
  SELECT
    cr.vencimento::date AS data_ref,
    COALESCE(cr.valor, 0)::numeric AS entrada,
    0::numeric AS saida
  FROM public.contas_a_receber cr
  WHERE cr.empresa_id = p_empresa_id
    AND cr.status IN ('aberto', 'aberta')
    AND cr.vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'

  UNION ALL

  -- contas a pagar
  SELECT
    cp.vencimento::date AS data_ref,
    0::numeric AS entrada,
    COALESCE(cp.valor, 0)::numeric AS saida
  FROM public.contas_a_pagar cp
  WHERE cp.empresa_id = p_empresa_id
    AND cp.status IN ('aberto', 'aberta')
    AND cp.vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'

  UNION ALL

  -- faturas de cartão
  SELECT
    cf.vencimento::date AS data_ref,
    0::numeric AS entrada,
    COALESCE(cf.valor_total, 0)::numeric AS saida
  FROM public.cartoes_faturas cf
  WHERE cf.empresa_id = p_empresa_id
    AND cf.status = 'aberta'
    AND cf.vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'

  UNION ALL

  -- recorrentes projetadas
  SELECT
    rp.vencimento::date AS data_ref,
    0::numeric AS entrada,
    rp.valor::numeric AS saida
  FROM recorrentes_projetadas rp
  WHERE rp.vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
),

por_dia AS (
  SELECT
    data_ref,
    SUM(entrada)::numeric(14,2) AS entrada,
    SUM(saida)::numeric(14,2) AS saida
  FROM eventos
  GROUP BY data_ref
),

calculo AS (
  SELECT
    data_ref,
    entrada,
    saida,
    SUM(entrada - saida) OVER (
      ORDER BY data_ref
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS movimento_acumulado
  FROM por_dia
)

SELECT
  data_ref,
  entrada,
  saida,
  (
    public.ff_saldo_atual_empresa(p_empresa_id)
    + movimento_acumulado
  )::numeric(14,2) AS saldo_previsto
FROM calculo
ORDER BY data_ref;
$$;