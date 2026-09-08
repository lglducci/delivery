drop view  vw_despesa_30_dias;

 
 CREATE OR REPLACE VIEW public.vw_despesa_30_dias AS
SELECT
  t.empresa_id,
  COALESCE(SUM(ABS(t.valor)), 0) AS total_despesa
FROM public.transacoes t
WHERE t.tipo = 'saida'
  AND t.data_movimento >= CURRENT_DATE - INTERVAL '30 days'
  AND COALESCE(t.origem, '') NOT IN (
    'transferencia',
    'estorno'
  )
  AND COALESCE(t.classificacao, '') IN (
    'despesa',
    'custo'
  )
GROUP BY t.empresa_id;