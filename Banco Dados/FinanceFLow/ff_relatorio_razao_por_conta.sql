 CREATE OR REPLACE FUNCTION contab.ff_relatorio_razao_por_conta(
  p_empresa_id bigint,
  p_conta_id   bigint,
  p_data_ini   date,
  p_data_fim   date
)
RETURNS TABLE (
  id                  bigint,
  data_mov            date,
  conta_codigo        text,
  conta_nome          text,
  historico           text,
  modelo_codigo       text,
  conta_contrapartida text,
  saldo_inicial       numeric(14,2),
  valor               numeric(14,2),
  saldo_final         numeric(14,2),
  lote_id             bigint
)
LANGUAGE sql
AS $$
WITH conta_base AS (
  SELECT
    c.id,
    c.codigo,
    c.nome,
    c.natureza
  FROM contab.contas c
  WHERE c.id = p_conta_id
),

lancamentos_filtrados AS (
  SELECT
    l.id,
    l.data_mov,
    l.historico,
    l.modelo_id,
    l.lote_id,
    l.conta_id,
    l.debito,
    l.credito,
    c.codigo AS conta_codigo,
    c.nome   AS conta_nome,
    c.natureza,
    CASE
      WHEN c.natureza = 'D' THEN l.debito - l.credito
      ELSE l.credito - l.debito
    END AS valor
  FROM contab.lancamentos l
  JOIN conta_base c ON c.id = l.conta_id
  WHERE l.empresa_id = p_empresa_id
    AND l.conta_id   = p_conta_id
    AND l.data_mov BETWEEN p_data_ini AND p_data_fim
),

 contrapartidas AS (
  SELECT
    x.id_principal,
    string_agg(x.conta_txt, ' | ' ORDER BY x.conta_txt) AS conta_contrapartida
  FROM (
    SELECT DISTINCT
      l1.id AS id_principal,
      c2.codigo || ' - ' || c2.nome AS conta_txt
    FROM contab.lancamentos l1
    JOIN contab.lancamentos l2
      ON l1.lote_id = l2.lote_id
     AND l1.id <> l2.id
     AND l2.conta_id <> l1.conta_id
    JOIN contab.contas c2
      ON c2.id = l2.conta_id
    WHERE l1.empresa_id = p_empresa_id
      AND l1.conta_id   = p_conta_id
      AND l1.data_mov BETWEEN p_data_ini AND p_data_fim
  ) x
  GROUP BY x.id_principal
),

saldo_inicial_cadastrado AS (
  SELECT
    COALESCE(si.saldo, 0)::numeric(14,2) AS saldo
  FROM conta_base c
  LEFT JOIN contab.saldos_iniciais si
    ON si.empresa_id = p_empresa_id
   AND si.conta_id   = c.id
),

movimento_anterior AS (
  SELECT
    COALESCE(SUM(
      CASE
        WHEN c.natureza = 'D' THEN l.debito - l.credito
        ELSE l.credito - l.debito
      END
    ), 0)::numeric(14,2) AS saldo
  FROM conta_base c
  LEFT JOIN contab.lancamentos l
    ON l.empresa_id = p_empresa_id
   AND l.conta_id   = c.id
   AND l.data_mov  < p_data_ini
),

saldo_inicial_base AS (
  SELECT
    (sic.saldo + ma.saldo)::numeric(14,2) AS saldo_inicial
  FROM saldo_inicial_cadastrado sic
  CROSS JOIN movimento_anterior ma
)

SELECT
  l.id,
  l.data_mov,
  l.conta_codigo,
  l.conta_nome,
  l.historico,
  m.codigo AS modelo_codigo,
  cp.conta_contrapartida,
  (
    sib.saldo_inicial
    + COALESCE(
        SUM(l.valor) OVER (
          ORDER BY l.data_mov, l.id
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),
        0
      )
  )::numeric(14,2) AS saldo_inicial,
  l.valor::numeric(14,2),
  (
    sib.saldo_inicial
    + SUM(l.valor) OVER (
        ORDER BY l.data_mov, l.id
      )
  )::numeric(14,2) AS saldo_final,
  l.lote_id
FROM lancamentos_filtrados l
LEFT JOIN contrapartidas cp
  ON cp.id_principal = l.id
LEFT JOIN contab.modelos m
  ON m.id = l.modelo_id
 CROSS JOIN saldo_inicial_base sib

UNION ALL

SELECT
  NULL::bigint AS id,
  p_data_ini AS data_mov,
  c.codigo::text AS conta_codigo,
  c.nome::text AS conta_nome,
  'SALDO INICIAL'::text AS historico,
  NULL::text AS modelo_codigo,
  NULL::text AS conta_contrapartida,
  sib.saldo_inicial::numeric(14,2) AS saldo_inicial,
  0::numeric(14,2) AS valor,
  sib.saldo_inicial::numeric(14,2) AS saldo_final,
  NULL::bigint AS lote_id
FROM conta_base c
CROSS JOIN saldo_inicial_base sib
WHERE NOT EXISTS (
  SELECT 1 FROM lancamentos_filtrados
)

ORDER BY data_mov, id NULLS FIRST;
$$;