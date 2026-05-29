CREATE OR REPLACE FUNCTION public.ff_criar_regra_classificacao(
  p_empresa_id bigint,
  p_texto_busca text,
  p_tipo_movimento text,
  p_conta_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_regra_id bigint;
BEGIN
  IF p_empresa_id IS NULL THEN
    RAISE EXCEPTION 'empresa_id obrigatório.';
  END IF;

  IF NULLIF(trim(p_texto_busca), '') IS NULL THEN
    RAISE EXCEPTION 'Texto da regra obrigatório.';
  END IF;

  IF p_conta_id IS NULL THEN
    RAISE EXCEPTION 'Conta obrigatória.';
  END IF;

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
    trim(p_texto_busca),
    NULLIF(trim(p_tipo_movimento), ''),
    p_conta_id,
    true,
    100
  )
  RETURNING id INTO v_regra_id;

  RETURN jsonb_build_object(
    'ok', true,
    'regra_id', v_regra_id,
    'empresa_id', p_empresa_id,
    'texto_busca', trim(p_texto_busca),
    'tipo_movimento', NULLIF(trim(p_tipo_movimento), ''),
    'conta_id', p_conta_id
  );
END;
$$;