 CREATE OR REPLACE FUNCTION saas_vendas.proc_verificar_inadimplencia()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_hoje DATE := CURRENT_DATE;
  v_qtd  INTEGER := 0;
BEGIN
  ------------------------------------------------------------------
  -- 1️⃣ MARCAR COBRANÇAS VENCIDAS
  ------------------------------------------------------------------
  UPDATE saas_vendas.cobrancas
     SET status = 'ATRASADA',
         atualizado_em = now()
   WHERE status = 'PENDENTE'
     AND data_vencimento < v_hoje;

  ------------------------------------------------------------------
  -- 2️⃣ MARCAR ASSINATURAS COMO INADIMPLENTES (POR EMPRESA)
  ------------------------------------------------------------------
  UPDATE saas_vendas.assinaturas a
     SET status = 'INADIMPLENTE'
   WHERE a.status = 'ATIVA'
     AND EXISTS (
       SELECT 1
       FROM saas_vendas.cobrancas c
       WHERE c.assinatura_id = a.id
         AND c.status = 'ATRASADA'
     );

  ------------------------------------------------------------------
  -- 3️⃣ BLOQUEAR USUÁRIOS SAAS DA EMPRESA
  ------------------------------------------------------------------
  UPDATE saas_vendas.usuarios u
     SET ativo = false
   WHERE u.ativo = true
     AND EXISTS (
       SELECT 1
       FROM saas_vendas.vw_usuario_completo vw
       JOIN saas_vendas.assinaturas a
         ON a.empresa_id = vw.empresa_id
       WHERE vw.saas_usuario_id = u.id
         AND a.status = 'INADIMPLENTE'
     );

  GET DIAGNOSTICS v_qtd = ROW_COUNT;
  RETURN v_qtd;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro CRON 2 – verificação de inadimplência: %',
      SQLERRM;
END;
$$;


 