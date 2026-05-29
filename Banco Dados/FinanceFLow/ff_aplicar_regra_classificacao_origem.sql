CREATE OR REPLACE FUNCTION public.ff_aplicar_regra_classificacao_origem(
  p_empresa_id bigint,
  p_regra_id bigint,
  p_origem text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_regra record;
  v_qtd int := 0;
BEGIN
  SELECT *
  INTO v_regra
  FROM public.regras_classificacao_contabil
  WHERE id = p_regra_id
    AND empresa_id = p_empresa_id
    AND conta_id IS NOT NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Regra não encontrada ou sem conta.'
    );
  END IF;
 
 IF v_regra.tipo_evento IN ('transacao', 'financeiro') THEN

  UPDATE public.transacoes t
  SET contabil_id = v_regra.conta_id
  WHERE t.empresa_id = p_empresa_id
    AND (v_regra.tipo_evento IS NULL OR t.tipo_evento::text = v_regra.tipo_evento)
    AND (v_regra.classificacao IS NULL OR t.classificacao::text = v_regra.classificacao)
    AND (v_regra.tipo_movimento IS NULL OR t.tipo = v_regra.tipo_movimento)
    AND unaccent(upper(t.descricao)) LIKE '%' || unaccent(upper(v_regra.texto_busca)) || '%';

  GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSIF v_regra.tipo_evento IN ('cartao_compra', 'cartao_compras') THEN

  UPDATE public.cartoes_compras cc
  SET conta_contabil_id = v_regra.conta_id
  WHERE cc.empresa_id = p_empresa_id
    AND cc.tipo_evento::text = COALESCE(v_regra.tipo_evento, cc.tipo_evento::text)
    AND cc.classificacao::text = COALESCE(v_regra.classificacao, cc.classificacao::text)
    AND unaccent(upper(cc.descricao)) = unaccent(upper(v_regra.texto_busca));

  GET DIAGNOSTICS v_qtd = ROW_COUNT;


  ELSIF v_regra.tipo_evento = 'pagar' THEN
    UPDATE public.contas_a_pagar cp
    SET contabil_id = v_regra.conta_id
    WHERE cp.empresa_id = p_empresa_id
      AND unaccent(upper(cp.descricao)) LIKE '%' || unaccent(upper(v_regra.texto_busca)) || '%';

    GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSIF v_regra.tipo_evento = 'receber' THEN
    UPDATE public.contas_a_receber cr
    SET contabil_id = v_regra.conta_id
    WHERE cr.empresa_id = p_empresa_id
      AND unaccent(upper(cr.descricao)) LIKE '%' || unaccent(upper(v_regra.texto_busca)) || '%';

    GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSE
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Origem inválida: ' || p_origem
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'origem', p_origem,
    'regra_id', p_regra_id,
    'conta_id', v_regra.conta_id,
    'linhas_atualizadas', v_qtd
  );
END;
$$;