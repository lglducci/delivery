CREATE OR REPLACE FUNCTION saas_vendas.proc_adiar_cobranca (
  p_cobranca_id BIGINT,
  p_dias        INTEGER DEFAULT 7
)
RETURNS TABLE (
  ok              BOOLEAN,
  mensagem        TEXT,
  novo_vencimento DATE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_cobranca saas_vendas.cobrancas%ROWTYPE;
  v_nova_data DATE;
BEGIN
  IF COALESCE(p_dias, 0) <= 0 THEN
    RETURN QUERY
    SELECT FALSE, 'Quantidade de dias inválida', NULL::DATE;
    RETURN;
  END IF;

  SELECT *
    INTO v_cobranca
  FROM saas_vendas.cobrancas
  WHERE id = p_cobranca_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY
    SELECT FALSE, 'Cobrança não encontrada', NULL::DATE;
    RETURN;
  END IF;

  IF v_cobranca.status = 'PAGA' THEN
    RETURN QUERY
    SELECT FALSE, 'Cobrança paga não pode ser adiada', v_cobranca.data_vencimento;
    RETURN;
  END IF;

  IF v_cobranca.status = 'CANCELADA' THEN
    RETURN QUERY
    SELECT FALSE, 'Cobrança cancelada não pode ser adiada', v_cobranca.data_vencimento;
    RETURN;
  END IF;

  v_nova_data := GREATEST(
    v_cobranca.data_vencimento,
    CURRENT_DATE
  ) + p_dias;

  UPDATE saas_vendas.cobrancas
     SET data_vencimento = v_nova_data,
         status = 'PENDENTE',
         atualizado_em = now()
   WHERE id = p_cobranca_id;

  -- Caso tenha sido marcada inadimplente por causa dessa cobrança,
  -- volta para ativa enquanto não houver outra cobrança atrasada.
  UPDATE saas_vendas.assinaturas a
     SET status = 'ATIVA'
   WHERE a.id = v_cobranca.assinatura_id
     AND UPPER(a.status) = 'INADIMPLENTE'
     AND NOT EXISTS (
       SELECT 1
       FROM saas_vendas.cobrancas c
       WHERE c.assinatura_id = a.id
         AND c.id <> p_cobranca_id
         AND c.status = 'ATRASADA'
     );

  -- Reativa usuários da empresa
  UPDATE saas_vendas.usuarios u
     SET ativo = TRUE
   WHERE EXISTS (
     SELECT 1
     FROM saas_vendas.vw_usuario_completo vw
     WHERE vw.saas_usuario_id = u.id
       AND vw.empresa_id = v_cobranca.empresa_id
   );

  RETURN QUERY
  SELECT
    TRUE,
    'Cobrança adiada por ' || p_dias || ' dias',
    v_nova_data;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro ao adiar cobrança: %',
      SQLERRM;
END;
$$;