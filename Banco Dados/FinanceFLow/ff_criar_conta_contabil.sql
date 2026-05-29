CREATE OR REPLACE FUNCTION public.ff_criar_conta_contabil(
  p_empresa_id bigint,
  p_codigo text,
  p_nome text,
  p_tipo text,
  p_natureza text,
  p_nivel integer,
  p_conta_pai_id bigint DEFAULT NULL,
  p_classificacao_gerencial text DEFAULT NULL,
  p_criar_regra boolean DEFAULT false,
  p_texto_regra text DEFAULT NULL,
  p_tipo_movimento text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_conta_id bigint;
  v_regra_id bigint;
BEGIN
  IF p_empresa_id IS NULL THEN
    RAISE EXCEPTION 'empresa_id obrigatório.';
  END IF;

  IF NULLIF(trim(p_codigo), '') IS NULL THEN
    RAISE EXCEPTION 'Código da conta obrigatório.';
  END IF;

  IF NULLIF(trim(p_nome), '') IS NULL THEN
    RAISE EXCEPTION 'Nome da conta obrigatório.';
  END IF;

  INSERT INTO contab.contas (
    empresa_id,
    codigo,
    nome,
    tipo,
    natureza,
    nivel,
    conta_pai_id,
    analitica,
    sistema,
    classificacao_gerencial
  )
  VALUES (
    p_empresa_id,
    trim(p_codigo),
    trim(p_nome),
    trim(p_tipo),
    trim(p_natureza),
    COALESCE(p_nivel, 1),
    p_conta_pai_id,
    true,
    false,
    p_classificacao_gerencial
  )
  RETURNING id INTO v_conta_id;

  IF p_criar_regra = true THEN
    IF NULLIF(trim(COALESCE(p_texto_regra, '')), '') IS NOT NULL THEN
      INSERT INTO public.regras_classificacao_contabil (
        empresa_id,
        texto_busca,
        tipo_movimento,
        conta_id,
        ativo,
        prioridade
      )
      VALUES (
        p_empresa_id,
        trim(p_texto_regra),
        NULLIF(trim(p_tipo_movimento), ''),
        v_conta_id,
        true,
        100
      )
      RETURNING id INTO v_regra_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_conta_id,
    'codigo', trim(p_codigo),
    'nome', trim(p_nome),
    'tipo', trim(p_tipo),
    'natureza', trim(p_natureza),
    'nivel', COALESCE(p_nivel, 1),
    'conta_pai_id', p_conta_pai_id,
    'regra_criada', v_regra_id IS NOT NULL,
    'regra_id', v_regra_id
  );
END;
$$;