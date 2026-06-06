CREATE OR REPLACE FUNCTION public.ff_dashboard_contas_recorrentes(
  p_empresa_id bigint,
  p_data_ini date,
  p_data_fim date
)
RETURNS TABLE (
  competencia date,
  qtd integer,
  total_previsto numeric,
  total_fixo numeric,
  total_variavel numeric
)
LANGUAGE sql
AS $$
WITH meses AS (
  SELECT generate_series(
    date_trunc('month', p_data_ini)::date,
    date_trunc('month', p_data_fim)::date,
    interval '1 month'
  )::date AS competencia
),
base AS (
  SELECT
    m.competencia,
    cr.id,
    cr.tipo_valor,
    COALESCE(cr.valor_padrao, 0) AS valor_padrao
  FROM meses m
  JOIN public.contas_recorrentes cr
    ON cr.empresa_id = p_empresa_id
   AND cr.ativo = true
)
SELECT
  competencia,
  COUNT(*)::integer AS qtd,
  SUM(valor_padrao)::numeric(14,2) AS total_previsto,
  SUM(CASE WHEN tipo_valor = 'FIXO' THEN valor_padrao ELSE 0 END)::numeric(14,2) AS total_fixo,
  SUM(CASE WHEN tipo_valor = 'VARIAVEL' THEN valor_padrao ELSE 0 END)::numeric(14,2) AS total_variavel
FROM base
GROUP BY competencia
ORDER BY competencia;
$$;