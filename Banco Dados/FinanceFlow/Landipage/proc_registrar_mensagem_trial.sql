CREATE OR REPLACE FUNCTION saas_vendas.proc_registrar_mensagem_trial(
  p_usuario_id BIGINT,
  p_proximos_dias INTEGER DEFAULT 1
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
BEGIN
  UPDATE saas_vendas.usuarios
     SET trial_qtd_mensagens =
           COALESCE(trial_qtd_mensagens, 0) + 1,

         trial_ultima_mensagem = now(),

         trial_proxima_mensagem =
           now() + make_interval(
             days => GREATEST(COALESCE(p_proximos_dias, 1), 1)
           )

   WHERE id = p_usuario_id
     AND trial_followup_ativo = TRUE;

  RETURN FOUND;
END;
$$;