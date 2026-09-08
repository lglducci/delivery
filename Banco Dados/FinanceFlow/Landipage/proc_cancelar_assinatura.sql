 CREATE OR REPLACE FUNCTION saas_vendas.proc_cancelar_assinatura (
  p_assinatura_id BIGINT
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
  v_empresa_id BIGINT;
  v_status     TEXT;
BEGIN
  ------------------------------------------------------------------
  -- BUSCAR ASSINATURA
  ------------------------------------------------------------------
  SELECT
    a.empresa_id,
    a.status
  INTO
    v_empresa_id,
    v_status
  FROM saas_vendas.assinaturas a
  WHERE a.id = p_assinatura_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY
    SELECT FALSE, 'Assinatura não encontrada';
    RETURN;
  END IF;

  IF UPPER(v_status) = 'CANCELADA' THEN
    RETURN QUERY
    SELECT FALSE, 'Esta assinatura já está cancelada';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- CANCELAR COBRANÇAS AINDA ABERTAS
  ------------------------------------------------------------------
  UPDATE saas_vendas.cobrancas
     SET status = 'CANCELADA',
         atualizado_em = now()
   WHERE assinatura_id = p_assinatura_id
     AND status IN ('PENDENTE', 'ATRASADA');

  ------------------------------------------------------------------
  -- CANCELAR ASSINATURA
  ------------------------------------------------------------------
  UPDATE saas_vendas.assinaturas
     SET status = 'CANCELADA',
         data_fim = CURRENT_DATE
   WHERE id = p_assinatura_id;

  ------------------------------------------------------------------
  -- BLOQUEAR USUÁRIOS DA EMPRESA
  ------------------------------------------------------------------
  UPDATE saas_vendas.usuarios u
     SET ativo = FALSE
   WHERE EXISTS (
     SELECT 1
     FROM saas_vendas.vw_usuario_completo vw
     WHERE vw.saas_usuario_id = u.id
       AND vw.empresa_id = v_empresa_id
   );

  RETURN QUERY
  SELECT TRUE, 'Assinatura cancelada e acesso bloqueado';

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro ao cancelar assinatura: %',
      SQLERRM;
END;
$$;