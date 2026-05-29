CREATE OR REPLACE FUNCTION public.ff_atualizar_regra_classificacao(
  p_id bigint,
  p_empresa_id bigint,
  p_texto_busca text,
  p_tipo_movimento text,
  p_conta_id bigint,
  p_ativo boolean,
  p_prioridade integer,
  p_origem text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_regra public.regras_classificacao_contabil%ROWTYPE;
  v_aplicacao jsonb;
BEGIN
  UPDATE public.regras_classificacao_contabil
  SET
    texto_busca = trim(p_texto_busca),
    tipo_movimento = NULLIF(trim(p_tipo_movimento), ''),
    conta_id = p_conta_id,
    ativo = COALESCE(p_ativo, true),
    prioridade = COALESCE(p_prioridade, 100)
  WHERE id = p_id
    AND empresa_id = p_empresa_id
  RETURNING * INTO v_regra;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Regra não encontrada.'
    );
  END IF;

  IF v_regra.ativo = true
     AND v_regra.conta_id IS NOT NULL
     AND NULLIF(trim(COALESCE(p_origem, '')), '') IS NOT NULL
  THEN
    v_aplicacao := public.ff_aplicar_regra_classificacao_origem(
      p_empresa_id,
      p_id,
      p_origem
    );
  ELSE
    v_aplicacao := jsonb_build_object(
      'ok', true,
      'message', 'Regra atualizada sem aplicação automática.'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'regra_id', v_regra.id,
    'regra', to_jsonb(v_regra),
    'aplicacao', v_aplicacao
  );
END;
$$;