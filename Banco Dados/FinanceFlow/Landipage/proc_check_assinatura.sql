 CREATE OR REPLACE FUNCTION saas_vendas.proc_check_assinatura (
  p_empresa_id BIGINT
)
RETURNS TABLE (
  status TEXT,
  bloquear BOOLEAN,
  mensagem TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_hoje       DATE := CURRENT_DATE;
  v_assinatura RECORD;
  v_usuario    RECORD;
BEGIN
  ------------------------------------------------------------------
  -- 1. PRIMEIRO: VERIFICAR ASSINATURA VÁLIDA
  ------------------------------------------------------------------
  SELECT
    a.id,
    UPPER(COALESCE(a.status, '')) AS status,
    a.data_inicio,
    a.data_fim
  INTO v_assinatura
  FROM saas_vendas.assinaturas a
  WHERE a.empresa_id = p_empresa_id
    AND UPPER(COALESCE(a.status, '')) = 'ATIVA'
    AND a.data_inicio <= v_hoje
    AND (
      a.data_fim IS NULL
      OR a.data_fim >= v_hoje
    )
  ORDER BY a.data_inicio DESC, a.id DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY
    SELECT
      'OK'::TEXT,
      FALSE,
      'Assinatura ativa'::TEXT;
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 2. SEM ASSINATURA VÁLIDA: BUSCAR USUÁRIO/TRIAL DA EMPRESA
  ------------------------------------------------------------------
  SELECT
    svu.id,
    COALESCE(svu.ativo, FALSE) AS ativo,
    UPPER(COALESCE(svu.plano, 'TRIAL')) AS plano,
    svu.trial_inicio,
    svu.trial_fim
  INTO v_usuario
  FROM public.usuario_empresa ue
  JOIN public.usuarios pu
    ON pu.id = ue.usuario_id
  JOIN saas_vendas.usuarios svu
    ON svu.auth_user_id = pu.auth_user_id
  WHERE ue.empresa_id = p_empresa_id
  ORDER BY svu.id
  LIMIT 1;

  ------------------------------------------------------------------
  -- 3. SEM USUÁRIO SAAS
  ------------------------------------------------------------------
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT
      'SEM_ACESSO'::TEXT,
      TRUE,
      'Empresa sem assinatura e sem trial válido'::TEXT;
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 4. ACESSO LIVRE
  ------------------------------------------------------------------
  IF v_usuario.plano = 'FREE'
     AND v_usuario.ativo = TRUE
     AND v_usuario.trial_fim IS NULL THEN

    RETURN QUERY
    SELECT
      'FREE'::TEXT,
      FALSE,
      'Acesso livre'::TEXT;
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 5. TRIAL VÁLIDO
  ------------------------------------------------------------------
  IF v_usuario.plano = 'TRIAL'
     AND v_usuario.ativo = TRUE
     AND v_usuario.trial_inicio IS NOT NULL
     AND v_usuario.trial_inicio::DATE <= v_hoje
     AND v_usuario.trial_fim IS NOT NULL
     AND v_usuario.trial_fim::DATE >= v_hoje THEN

    RETURN QUERY
    SELECT
      'TRIAL'::TEXT,
      FALSE,
      (
        'Trial ativo até '
        || TO_CHAR(v_usuario.trial_fim, 'DD/MM/YYYY')
      )::TEXT;
    RETURN;
  END IF;

  ------------------------------------------------------------------
  -- 6. SEM ASSINATURA E SEM TRIAL LIBERADO
  ------------------------------------------------------------------
  RETURN QUERY
  SELECT
    'BLOQUEADO'::TEXT,
    TRUE,
    'Sem assinatura ativa e sem trial válido'::TEXT;
END;
$$;