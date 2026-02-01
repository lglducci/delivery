CREATE OR REPLACE FUNCTION saas_vendas.proc_check_acesso(
  p_empresa_id BIGINT
)
RETURNS TABLE (
  status TEXT,
  bloquear BOOLEAN,
  mensagem TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_hoje DATE := CURRENT_DATE;
  v_usuario RECORD;
  v_ass RECORD;
BEGIN
  ------------------------------------------------------------------
  -- 1️⃣ BUSCA USUÁRIO (TRIAL)
  ------------------------------------------------------------------
  SELECT *
    INTO v_usuario
  FROM saas_vendas.usuarios
  WHERE ativo = true
    AND plano = 'trial'
  ORDER BY criado_em
  LIMIT 1;

  IF FOUND THEN
    IF v_usuario.trial_fim >= now() THEN
      RETURN QUERY
      SELECT
        'TRIAL_ATIVO',
        false,
        'Trial ativo até ' || to_char(v_usuario.trial_fim, 'DD/MM/YYYY');
      RETURN;
    END IF;
  END IF;

  ------------------------------------------------------------------
  -- 2️⃣ BUSCA ASSINATURA ATIVA
  ------------------------------------------------------------------
  SELECT *
    INTO v_ass
  FROM saas_vendas.assinaturas
  WHERE empresa_id = p_empresa_id
    AND status = 'ativa'
    AND data_inicio <= v_hoje
    AND (data_fim IS NULL OR data_fim >= v_hoje)
  ORDER BY data_inicio DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY
    SELECT
      'ASSINATURA_ATIVA',
      false,
      'Assinatura ativa';
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 3️⃣ BLOQUEADO
  ------------------------------------------------------------------
  RETURN QUERY
  SELECT
    'SEM_ACESSO',
    true,
    'Trial expirado e sem assinatura ativa';

END;
$$;
