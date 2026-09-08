 CREATE OR REPLACE FUNCTION saas_vendas.proc_fechar_assinatura (
  p_empresa_id      BIGINT,
  p_plano_id        BIGINT,
  p_forma_pagamento TEXT DEFAULT 'PIX'
)
RETURNS TABLE (
  status   TEXT,
  mensagem TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_plano_nome       TEXT;
  v_valor             NUMERIC(12,2);
  v_data_fim          DATE;
  v_tem_ativa         BOOLEAN;
  v_tem_pend          BOOLEAN;
  v_assinatura_id     BIGINT;
  v_cobranca_id       BIGINT;
  v_competencia       DATE;
BEGIN
  ------------------------------------------------------------------
  -- 1. BUSCAR E VALIDAR O PLANO
  ------------------------------------------------------------------
  SELECT
    LOWER(p.nome),
    p.valor_mensal
  INTO
    v_plano_nome,
    v_valor
  FROM saas_vendas.planos p
  WHERE p.id = p_plano_id
    AND p.ativo = TRUE;

  IF NOT FOUND THEN
    RETURN QUERY
    SELECT
      'ERRO',
      'Plano não encontrado ou inativo';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 2. VALIDAR VALOR
  ------------------------------------------------------------------
  IF COALESCE(v_valor, 0) <= 0 THEN
    RETURN QUERY
    SELECT
      'ERRO',
      'O plano não possui um valor válido para cobrança';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 3. CALCULAR DATA FINAL
  ------------------------------------------------------------------
  IF v_plano_nome LIKE '%mensal%' THEN
    v_data_fim :=
      (CURRENT_DATE + INTERVAL '1 month' - INTERVAL '1 day')::date;

  ELSIF v_plano_nome LIKE '%semestral%' THEN
    v_data_fim :=
      (CURRENT_DATE + INTERVAL '6 months' - INTERVAL '1 day')::date;

  ELSIF v_plano_nome LIKE '%anual%' THEN
    v_data_fim :=
      (CURRENT_DATE + INTERVAL '1 year' - INTERVAL '1 day')::date;

  ELSE
    RETURN QUERY
    SELECT
      'ERRO',
      'Não foi possível identificar a periodicidade do plano';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 4. VERIFICAR ASSINATURA ATIVA
  ------------------------------------------------------------------
  SELECT EXISTS (
    SELECT 1
    FROM saas_vendas.assinaturas a
    WHERE a.empresa_id = p_empresa_id
      AND UPPER(a.status) = 'ATIVA'
      AND a.data_inicio <= CURRENT_DATE
      AND (
        a.data_fim IS NULL
        OR a.data_fim >= CURRENT_DATE
      )
  )
  INTO v_tem_ativa;

  IF v_tem_ativa THEN
    RETURN QUERY
    SELECT
      'TEM_ATIVA',
      'Empresa já possui assinatura ativa';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 5. VERIFICAR ASSINATURA PENDENTE
  ------------------------------------------------------------------
  SELECT EXISTS (
    SELECT 1
    FROM saas_vendas.assinaturas a
    WHERE a.empresa_id = p_empresa_id
      AND UPPER(a.status) = 'PENDENTE_PAGAMENTO'
  )
  INTO v_tem_pend;

  IF v_tem_pend THEN
    RETURN QUERY
    SELECT
      'PENDENTE',
      'Já existe uma assinatura aguardando pagamento para esta empresa';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 6. CRIAR ASSINATURA PENDENTE
  ------------------------------------------------------------------
  INSERT INTO saas_vendas.assinaturas (
    empresa_id,
    plano_id,
    data_inicio,
    data_fim,
    status,
    forma_pagamento
  )
  VALUES (
    p_empresa_id,
    p_plano_id,
    CURRENT_DATE,
    v_data_fim,
    'PENDENTE_PAGAMENTO',
    UPPER(COALESCE(p_forma_pagamento, 'PIX'))
  )
  RETURNING id
  INTO v_assinatura_id;

  ------------------------------------------------------------------
  -- 7. CRIAR PRIMEIRA COBRANÇA
  ------------------------------------------------------------------
  v_competencia :=
    date_trunc('month', CURRENT_DATE)::date;

  INSERT INTO saas_vendas.cobrancas (
    assinatura_id,
    empresa_id,
    competencia,
    valor,
    data_vencimento,
    status
  )
  VALUES (
    v_assinatura_id,
    p_empresa_id,
    v_competencia,
    v_valor,
    CURRENT_DATE,
    'PENDENTE'
  )
  RETURNING id
  INTO v_cobranca_id;

  ------------------------------------------------------------------
  -- 8. RETORNO
  ------------------------------------------------------------------
  RETURN QUERY
  SELECT
    'OK',
    'Assinatura e cobrança criadas. Cobrança ID: '
      || v_cobranca_id::text;

EXCEPTION
  WHEN unique_violation THEN
    RETURN QUERY
    SELECT
      'ERRO',
      'Já existe cobrança para esta assinatura e competência';

  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro ao fechar assinatura: %',
      SQLERRM;
END;
$$;