 CREATE OR REPLACE FUNCTION public.ff_consultar_saldo_periodo(
  p_empresa_id BIGINT,
  p_data_ini   DATE,
  p_data_fim   DATE,
  p_conta_id   BIGINT
)
RETURNS TABLE (
  conta_id BIGINT,
  conta_nome TEXT,
  nro_banco TEXT,
  banco_nome TEXT,
  icone_url TEXT,
  cor_hex TEXT,
  agencia TEXT,
  conta TEXT,
  conjunta BOOLEAN,
  juridica BOOLEAN,
  saldo_inicial NUMERIC,
  entradas_periodo NUMERIC,
  saídas_periodo NUMERIC,
  saldo_final NUMERIC
)
LANGUAGE sql
AS $$

WITH contas AS (
  SELECT
    cf.id,
    cf.nome,
    cf.nro_banco,
    b.nome AS banco_nome,
    b.icone_url,
    b.cor_hex,
    cf.agencia,
    cf.conta,
    cf.conjunta,
    cf.juridica,
    cf.saldo_inicial
  FROM public.contas_financeiras cf
  LEFT JOIN public.bancos b
    ON b.codigo = cf.nro_banco
  WHERE cf.empresa_id = p_empresa_id
    AND (p_conta_id IS NULL OR p_conta_id = 0 OR cf.id = p_conta_id)
),

mov_antes AS (
  SELECT
    t.conta_id,
    SUM(CASE WHEN t.tipo = 'entrada' THEN t.valor ELSE 0 END) AS entradas_antes,
    SUM(CASE WHEN t.tipo = 'saida' THEN t.valor ELSE 0 END) AS saídas_antes
  FROM public.transacoes t
  WHERE t.empresa_id = p_empresa_id
    AND t.data_movimento < p_data_ini
    AND (p_conta_id IS NULL OR p_conta_id = 0 OR t.conta_id = p_conta_id)
  GROUP BY t.conta_id
),

mov_periodo AS (
  SELECT
    t.conta_id,
    SUM(CASE WHEN t.tipo = 'entrada' THEN t.valor ELSE 0 END) AS entradas,
    SUM(CASE WHEN t.tipo = 'saida' THEN t.valor ELSE 0 END) AS saídas
  FROM public.transacoes t
  WHERE t.empresa_id = p_empresa_id
    AND t.data_movimento BETWEEN p_data_ini AND p_data_fim
    AND (p_conta_id IS NULL OR p_conta_id = 0 OR t.conta_id = p_conta_id)
  GROUP BY t.conta_id
)

SELECT
  c.id AS conta_id,
  c.nome AS conta_nome,
  c.nro_banco,
  c.banco_nome,
  c.icone_url,
  c.cor_hex,
  c.agencia,
  c.conta,
  c.conjunta,
  c.juridica,

  (
    c.saldo_inicial
    + COALESCE(ma.entradas_antes, 0)
    - COALESCE(ma.saídas_antes, 0)
  ) AS saldo_inicial,

  COALESCE(mp.entradas, 0) AS entradas_periodo,
  COALESCE(mp.saídas, 0) AS saídas_periodo,

  (
    c.saldo_inicial
    + COALESCE(ma.entradas_antes, 0)
    - COALESCE(ma.saídas_antes, 0)
    + COALESCE(mp.entradas, 0)
    - COALESCE(mp.saídas, 0)
  ) AS saldo_final

FROM contas c
LEFT JOIN mov_antes ma ON ma.conta_id = c.id
LEFT JOIN mov_periodo mp ON mp.conta_id = c.id
ORDER BY c.nome;

$$;