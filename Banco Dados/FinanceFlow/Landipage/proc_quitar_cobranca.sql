CREATE OR REPLACE FUNCTION saas_vendas.proc_quitar_cobranca (
  p_cobranca_id    BIGINT,
  p_gateway        TEXT DEFAULT 'MANUAL',
  p_payment_id     TEXT DEFAULT NULL,
  p_meio_pagamento TEXT DEFAULT 'OUTRO'
)
RETURNS TABLE (
  ok       BOOLEAN,
  mensagem TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_cobranca saas_vendas.cobrancas%ROWTYPE;
  v_payment_id TEXT;
BEGIN
  ------------------------------------------------------------------
  -- BUSCAR COBRANÇA
  ------------------------------------------------------------------
  SELECT *
    INTO v_cobranca
  FROM saas_vendas.cobrancas
  WHERE id = p_cobranca_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY
    SELECT FALSE, 'Cobrança não encontrada';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- VALIDAR SITUAÇÃO
  ------------------------------------------------------------------
  IF v_cobranca.status = 'PAGA' THEN
    RETURN QUERY
    SELECT FALSE, 'Esta cobrança já está paga';
    RETURN;
  END IF;

  IF v_cobranca.status = 'CANCELADA' THEN
    RETURN QUERY
    SELECT FALSE, 'Cobrança cancelada não pode ser quitada';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- GERAR IDENTIFICADOR PARA PAGAMENTO MANUAL
  ------------------------------------------------------------------
  v_payment_id := COALESCE(
    NULLIF(TRIM(p_payment_id), ''),
    'MANUAL-' || p_cobranca_id::TEXT || '-' ||
    to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS')
  );

  ------------------------------------------------------------------
  -- REGISTRAR PAGAMENTO
  ------------------------------------------------------------------
  INSERT INTO saas_vendas.pagamentos (
    cobranca_id,
    empresa_id,
    gateway,
    payment_id,
    meio_pagamento,
    valor_pago,
    status_gateway,
    data_pagamento
  )
  VALUES (
    v_cobranca.id,
    v_cobranca.empresa_id,
    UPPER(COALESCE(p_gateway, 'MANUAL')),
    v_payment_id,
    UPPER(COALESCE(p_meio_pagamento, 'OUTRO')),
    v_cobranca.valor,
    'approved',
    now()
  );

  ------------------------------------------------------------------
  -- QUITAR COBRANÇA
  ------------------------------------------------------------------
  UPDATE saas_vendas.cobrancas
     SET status = 'PAGA',
         atualizado_em = now()
   WHERE id = v_cobranca.id;

  ------------------------------------------------------------------
  -- ATIVAR ASSINATURA
  ------------------------------------------------------------------
  UPDATE saas_vendas.assinaturas
     SET status = 'ATIVA'
   WHERE id = v_cobranca.assinatura_id;

  ------------------------------------------------------------------
  -- REATIVAR USUÁRIOS DA EMPRESA
  ------------------------------------------------------------------
  UPDATE saas_vendas.usuarios u
     SET ativo = TRUE
   WHERE EXISTS (
     SELECT 1
     FROM saas_vendas.vw_usuario_completo vw
     WHERE vw.saas_usuario_id = u.id
       AND vw.empresa_id = v_cobranca.empresa_id
   );

  RETURN QUERY
  SELECT TRUE, 'Cobrança quitada e assinatura ativada';

EXCEPTION
  WHEN unique_violation THEN
    RETURN QUERY
    SELECT FALSE, 'Este pagamento já foi registrado';

  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro ao quitar cobrança: %',
      SQLERRM;
END;
$$;