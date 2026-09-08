 CREATE OR REPLACE FUNCTION saas_vendas.proc_gerar_cobrancas_mensais()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_competencia DATE := date_trunc('month', CURRENT_DATE)::date;
  v_qtd         INTEGER := 0;
BEGIN
  /*
    Gera cobranças mensais recorrentes:

    - somente assinaturas ATIVAS;
    - uma cobrança por assinatura e competência;
    - vencimento no dia 10 do mês;
    - não gera novamente se a cobrança já existir.

    Esta função não cria a primeira cobrança da contratação.
    A primeira cobrança deve ser criada ao fechar a assinatura.
  */

  INSERT INTO saas_vendas.cobrancas (
    assinatura_id,
    empresa_id,
    competencia,
    valor,
    data_vencimento,
    status
  )
  SELECT
    a.id                                            AS assinatura_id,
    a.empresa_id                                    AS empresa_id,
    v_competencia                                   AS competencia,
    p.valor_mensal                                  AS valor,
    (v_competencia + INTERVAL '9 days')::date       AS data_vencimento,
    'PENDENTE'                                      AS status
  FROM saas_vendas.assinaturas a

  JOIN saas_vendas.planos p
    ON p.id = a.plano_id
   AND p.ativo = TRUE

  WHERE UPPER(a.status) = 'ATIVA'

    AND a.data_inicio <= CURRENT_DATE

    AND (
      a.data_fim IS NULL
      OR a.data_fim >= CURRENT_DATE
    )

    -- Empresa com usuário SaaS ativo
    AND EXISTS (
      SELECT 1
      FROM saas_vendas.vw_usuario_completo vw
      WHERE vw.empresa_id = a.empresa_id
        AND vw.saas_ativo = TRUE
    )

    -- Evita cobrança duplicada
    AND NOT EXISTS (
      SELECT 1
      FROM saas_vendas.cobrancas c
      WHERE c.assinatura_id = a.id
        AND c.competencia = v_competencia
    );

  GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ------------------------------------------------------------------
  -- ATUALIZAR ÚLTIMA COBRANÇA DAS ASSINATURAS PROCESSADAS
  ------------------------------------------------------------------
  IF v_qtd > 0 THEN

    UPDATE saas_vendas.assinaturas a
       SET ultima_cobranca = v_competencia
     WHERE UPPER(a.status) = 'ATIVA'

       AND EXISTS (
         SELECT 1
         FROM saas_vendas.cobrancas c
         WHERE c.assinatura_id = a.id
           AND c.competencia = v_competencia
       );

  END IF;

  RETURN v_qtd;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro ao gerar cobranças mensais: %',
      SQLERRM;
END;
$$;