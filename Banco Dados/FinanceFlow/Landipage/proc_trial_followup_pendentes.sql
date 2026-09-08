CREATE OR REPLACE FUNCTION saas_vendas.proc_trial_followup_pendentes()
RETURNS TABLE (
  usuario_id             BIGINT,
  nome                   TEXT,
  email                  TEXT,
  telefone               TEXT,
  trial_fim              TIMESTAMP,
  dias_sem_acesso        INTEGER,
  quantidade_mensagens   INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
  SELECT
    u.id AS usuario_id,
    u.nome,
    u.email,
    u.telefone,
    u.trial_fim,

    FLOOR(
      EXTRACT(EPOCH FROM (now() - u.trial_fim))
      / 86400
    )::INTEGER AS dias_sem_acesso,

    COALESCE(u.trial_qtd_mensagens, 0) AS quantidade_mensagens

  FROM saas_vendas.usuarios u

  WHERE UPPER(COALESCE(u.plano, 'TRIAL')) = 'TRIAL'
    AND u.trial_fim IS NOT NULL
    AND u.trial_fim < now()
    AND COALESCE(u.trial_followup_ativo, TRUE) = TRUE

    AND (
      u.trial_proxima_mensagem IS NULL
      OR u.trial_proxima_mensagem <= now()
    )

  ORDER BY
    u.trial_proxima_mensagem NULLS FIRST,
    u.trial_fim;
$$;