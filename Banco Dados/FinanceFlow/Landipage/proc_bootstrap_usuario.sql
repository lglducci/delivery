 CREATE OR REPLACE FUNCTION public.proc_bootstrap_usuario(
  p_auth_user_id UUID,
  p_nome_usuario TEXT,
  p_email TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, contab, saas_vendas
AS $$
DECLARE
  v_usuario_id BIGINT;
  v_empresa_id BIGINT;
  v_perfil_id  BIGINT;
  v_email      TEXT;
BEGIN
  v_email := lower(trim(p_email));

  ------------------------------------------------------------------
  -- 1️⃣ USUÁRIO — NÃO DUPLICA
  ------------------------------------------------------------------
  SELECT id
    INTO v_usuario_id
  FROM public.usuarios
  WHERE auth_user_id = p_auth_user_id
     OR lower(trim(email)) = v_email
  LIMIT 1;

  IF v_usuario_id IS NULL THEN
    INSERT INTO public.usuarios (
      nome,
      email,
      auth_user_id,
      senha_hash
    )
    VALUES (
      p_nome_usuario,
      v_email,
      p_auth_user_id,
      'senha'
    )
    RETURNING id INTO v_usuario_id;
  ELSE
    UPDATE public.usuarios
       SET auth_user_id = COALESCE(auth_user_id, p_auth_user_id),
           nome = COALESCE(NULLIF(p_nome_usuario, ''), nome),
           email = v_email
     WHERE id = v_usuario_id;
  END IF;

  ------------------------------------------------------------------
  -- 2️⃣ SE JÁ TEM EMPRESA ESCOLHIDA, RETORNA E NÃO CRIA NADA
  ------------------------------------------------------------------
  SELECT empresa_id
    INTO v_empresa_id
  FROM public.usuario_empresa
  WHERE usuario_id = v_usuario_id
    AND escolha = true
  LIMIT 1;

  IF v_empresa_id IS NOT NULL THEN
    RETURN v_empresa_id;
  END IF;

  ------------------------------------------------------------------
  -- 3️⃣ SE JÁ TEM ALGUMA EMPRESA, MARCA COMO ESCOLHIDA E RETORNA
  ------------------------------------------------------------------
  SELECT empresa_id
    INTO v_empresa_id
  FROM public.usuario_empresa
  WHERE usuario_id = v_usuario_id
  ORDER BY empresa_id
  LIMIT 1;

  IF v_empresa_id IS NOT NULL THEN
    UPDATE public.usuario_empresa
       SET escolha = false
     WHERE usuario_id = v_usuario_id;

    UPDATE public.usuario_empresa
       SET escolha = true
     WHERE usuario_id = v_usuario_id
       AND empresa_id = v_empresa_id;

    RETURN v_empresa_id;
  END IF;

  ------------------------------------------------------------------
  -- 4️⃣ CRIA EMPRESA PADRÃO
  ------------------------------------------------------------------
  INSERT INTO public.empresas (
    nome,
    tipo,
    documento
  )
  VALUES (
    'Minha Empresa',
    'MEI',
    NULL
  )
  RETURNING id INTO v_empresa_id;

  ------------------------------------------------------------------
  -- 5️⃣ PERFIL CONTÁBIL
  ------------------------------------------------------------------
  SELECT id
    INTO v_perfil_id
  FROM public.perfis
  WHERE codigo = 'TOTAL'
  LIMIT 1;

  IF v_perfil_id IS NULL THEN
    RAISE EXCEPTION 'Perfil TOTAL não encontrado';
  END IF;

  INSERT INTO public.empresa_perfil (
    empresa_id,
    perfil_id,
    ativo,
    criado_em
  )
  VALUES (
    v_empresa_id,
    v_perfil_id,
    true,
    now()
  )
  ON CONFLICT DO NOTHING;

  ------------------------------------------------------------------
  -- 6️⃣ VÍNCULO USUÁRIO x EMPRESA
  ------------------------------------------------------------------
  UPDATE public.usuario_empresa
     SET escolha = false
   WHERE usuario_id = v_usuario_id;

  INSERT INTO public.usuario_empresa (
    usuario_id,
    empresa_id,
    role,
    escolha
  )
  VALUES (
    v_usuario_id,
    v_empresa_id,
    'admin',
    true
  )
  ON CONFLICT DO NOTHING;

  ------------------------------------------------------------------
  -- 7️⃣ CLONA PLANO DE CONTAS
  ------------------------------------------------------------------
  PERFORM contab.ff_clonar_plano_contas_padrao(v_empresa_id);

  ------------------------------------------------------------------
  -- 8️⃣ CATEGORIAS GERENCIAIS
  ------------------------------------------------------------------
  INSERT INTO public.categorias_gerenciais (
    empresa_id,
    nome,
    tipo
  )
  SELECT
    v_empresa_id,
    nome,
    tipo
  FROM saas_vendas.categorias_gerenciais
  ON CONFLICT DO NOTHING;

  ------------------------------------------------------------------
  -- 9️⃣ CONTROLE DE FECHAMENTO
  ------------------------------------------------------------------
  INSERT INTO contab.controle_fechamento (
    empresa_id,
    ultimo_dia_processado
  )
  VALUES (
    v_empresa_id,
    DATE '2026-01-01'
  )
  ON CONFLICT DO NOTHING;

  ------------------------------------------------------------------
  -- 🔟 MODELOS CONTÁBEIS
  ------------------------------------------------------------------
  PERFORM contab.ff_implantar_modelos_sistema(v_empresa_id);

  UPDATE contab.modelos m_filho
     SET modelo_pai_id = m_pai.id
  FROM contab.template_eventos_contabeis t,
       contab.modelos m_pai
  WHERE m_filho.codigo = t.codigo_evento
    AND t.conta_pai IS NOT NULL
    AND m_pai.codigo = t.conta_pai
    AND m_pai.empresa_id = m_filho.empresa_id
    AND m_filho.empresa_id = v_empresa_id;

  

  RETURN v_empresa_id;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION
      'Erro no bootstrap do usuário (%): %',
      p_auth_user_id,
      SQLERRM;
END;
$$;