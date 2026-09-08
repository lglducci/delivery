CREATE OR REPLACE FUNCTION saas_vendas.controla_trial(
  p_acao       TEXT DEFAULT 'LISTAR',
  p_usuario_id BIGINT DEFAULT NULL,
  p_dias       INTEGER DEFAULT 7
)
RETURNS TABLE (
  id                     BIGINT,
  nome                   TEXT,
  email                  TEXT,
  telefone               TEXT,
  plano                  TEXT,
  status                 TEXT,
  ativo                  BOOLEAN,
  trial_inicio           TIMESTAMP,
  trial_fim              TIMESTAMP,
  dias_concedidos        INTEGER,
  dias_restantes         INTEGER,
  situacao_trial         TEXT,
  precisa_contato        BOOLEAN,
  trial_qtd_mensagens    INTEGER,
  trial_ultima_mensagem  TIMESTAMP,
  trial_proxima_mensagem TIMESTAMP
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = saas_vendas, public
AS $$
DECLARE
  v_acao TEXT := UPPER(COALESCE(NULLIF(TRIM(p_acao), ''), 'LISTAR'));
BEGIN
  ------------------------------------------------------------------
  -- VALIDAR AÇÃO
  ------------------------------------------------------------------
  IF v_acao NOT IN (
    'LISTAR',
    'FECHAR_ACESSO',
    'ADIAR_TRIAL',
    'CONCEDER_LIVRE'
  ) THEN
    RAISE EXCEPTION 'Ação inválida: %', v_acao;
  END IF;

  ------------------------------------------------------------------
  -- AÇÕES EXIGEM USUÁRIO
  ------------------------------------------------------------------
  IF v_acao <> 'LISTAR' AND p_usuario_id IS NULL THEN
    RAISE EXCEPTION 'usuario_id é obrigatório para a ação %', v_acao;
  END IF;

  ------------------------------------------------------------------
  -- FECHAR ACESSO
  --
  -- Bloqueia o sistema, mas mantém o acompanhamento comercial.
  ------------------------------------------------------------------
  IF v_acao = 'FECHAR_ACESSO' THEN
    UPDATE saas_vendas.usuarios u
       SET ativo = FALSE,
           status = 'TRIAL_EXPIRADO',
           trial_followup_ativo = TRUE,
           trial_proxima_mensagem =
             COALESCE(u.trial_proxima_mensagem, now())
     WHERE u.id = p_usuario_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Usuário % não encontrado', p_usuario_id;
    END IF;
  END IF;

  ------------------------------------------------------------------
  -- ADIAR TRIAL
  --
  -- Soma os dias a partir de hoje ou do vencimento atual,
  -- escolhendo a maior data.
  ------------------------------------------------------------------
  IF v_acao = 'ADIAR_TRIAL' THEN
    IF COALESCE(p_dias, 0) <= 0 THEN
      RAISE EXCEPTION 'Quantidade de dias inválida';
    END IF;

    UPDATE saas_vendas.usuarios u
       SET plano = 'TRIAL',
           status = 'TRIAL_ATIVO',
           ativo = TRUE,

           trial_inicio =
             COALESCE(u.trial_inicio, now()),

           trial_fim =
             GREATEST(
               COALESCE(u.trial_fim, now()),
               now()
             ) + make_interval(days => p_dias),

           trial_followup_ativo = TRUE,
           trial_proxima_mensagem = NULL
     WHERE u.id = p_usuario_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Usuário % não encontrado', p_usuario_id;
    END IF;
  END IF;

  ------------------------------------------------------------------
  -- CONCEDER ACESSO LIVRE
  --
  -- FREE com trial_fim nulo não expira e não recebe cobrança
  -- nem mensagens de recuperação do trial.
  ------------------------------------------------------------------
  IF v_acao = 'CONCEDER_LIVRE' THEN
    UPDATE saas_vendas.usuarios u
       SET plano = 'FREE',
           status = 'LIVRE',
           ativo = TRUE,
           trial_fim = NULL,
           trial_followup_ativo = FALSE,
           trial_proxima_mensagem = NULL
     WHERE u.id = p_usuario_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Usuário % não encontrado', p_usuario_id;
    END IF;
  END IF;

  ------------------------------------------------------------------
  -- RETORNO
  ------------------------------------------------------------------
  RETURN QUERY
  SELECT
    u.id,
    u.nome,
    u.email,
    u.telefone,
    COALESCE(u.plano, 'TRIAL') AS plano,
    u.status,
    COALESCE(u.ativo, FALSE) AS ativo,
    u.trial_inicio,
    u.trial_fim,

    CASE
      WHEN u.trial_inicio IS NULL OR u.trial_fim IS NULL THEN NULL
      ELSE GREATEST(
        0,
        CEIL(
          EXTRACT(EPOCH FROM (u.trial_fim - u.trial_inicio))
          / 86400
        )::INTEGER
      )
    END AS dias_concedidos,

    CASE
      WHEN u.trial_fim IS NULL THEN NULL
      ELSE CEIL(
        EXTRACT(EPOCH FROM (u.trial_fim - now()))
        / 86400
      )::INTEGER
    END AS dias_restantes,

    CASE
      WHEN UPPER(COALESCE(u.plano, '')) = 'FREE'
           AND u.trial_fim IS NULL
        THEN 'ACESSO_LIVRE'

      WHEN UPPER(COALESCE(u.plano, 'TRIAL')) = 'TRIAL'
           AND u.trial_fim IS NULL
        THEN 'TRIAL_SEM_VENCIMENTO'

      WHEN UPPER(COALESCE(u.plano, 'TRIAL')) = 'TRIAL'
           AND u.trial_fim >= now()
           AND COALESCE(u.ativo, FALSE) = TRUE
        THEN 'TRIAL_ATIVO'

      WHEN u.trial_fim < now()
           AND COALESCE(u.ativo, FALSE) = TRUE
        THEN 'TRIAL_VENCIDO_COM_ACESSO'

      WHEN u.trial_fim < now()
           AND COALESCE(u.ativo, FALSE) = FALSE
        THEN 'TRIAL_VENCIDO_BLOQUEADO'

      WHEN COALESCE(u.ativo, FALSE) = FALSE
        THEN 'ACESSO_BLOQUEADO'

      ELSE 'INDEFINIDO'
    END AS situacao_trial,

    (
      UPPER(COALESCE(u.plano, 'TRIAL')) = 'TRIAL'
      AND u.trial_fim IS NOT NULL
      AND u.trial_fim < now()
      AND COALESCE(u.trial_followup_ativo, TRUE) = TRUE
    ) AS precisa_contato,

    COALESCE(u.trial_qtd_mensagens, 0),
    u.trial_ultima_mensagem,
    u.trial_proxima_mensagem

  FROM saas_vendas.usuarios u
  WHERE p_usuario_id IS NULL
     OR u.id = p_usuario_id
  ORDER BY
    CASE
      WHEN u.trial_fim < now()
           AND COALESCE(u.ativo, FALSE) = TRUE
        THEN 1

      WHEN u.trial_fim < now()
           AND COALESCE(u.ativo, FALSE) = FALSE
        THEN 2

      WHEN u.trial_fim >= now()
        THEN 3

      WHEN UPPER(COALESCE(u.plano, '')) = 'FREE'
        THEN 4

      ELSE 5
    END,
    u.trial_fim NULLS LAST,
    u.nome;
END;
$$;