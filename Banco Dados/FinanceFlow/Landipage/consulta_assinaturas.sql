   CREATE OR REPLACE FUNCTION saas_vendas.consulta_assinaturas (
  p_empresa_id BIGINT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_forma TEXT DEFAULT NULL,
  p_data_inicio DATE DEFAULT NULL,
  p_data_fim DATE DEFAULT NULL
)
RETURNS TABLE (
  id BIGINT,
  empresa_id BIGINT,
  plano TEXT,
   valor_mensal  NUMERIC(8,2),
  empresa TEXT,
  status TEXT,
  forma TEXT,
  data_inicio DATE,
  data_fim DATE
)
LANGUAGE sql
AS $$
  SELECT
    a.id,
    a.empresa_id,
    p.nome AS plano,
   p.valor_mensal , 
    e.nome, 
    a.status,
    a.forma_pagamento AS forma,
    a.data_inicio,
    a.data_fim
  FROM saas_vendas.assinaturas a
  JOIN saas_vendas.planos p
    ON p.id = a.plano_id
   JOIN public.empresas as e 
    ON e.id = a.empresa_id
   WHERE
  (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)

AND (
  NULLIF(LOWER(p_status), 'null') IS NULL
  OR a.status = p_status
)

AND (
  NULLIF(LOWER(p_forma), 'null') IS NULL
  OR a.forma_pagamento = p_forma
)

AND (p_data_inicio IS NULL OR a.data_inicio >= p_data_inicio)
AND (p_data_fim    IS NULL OR a.data_inicio <= p_data_fim);

$$;

