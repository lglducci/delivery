CREATE OR REPLACE FUNCTION public.ff_classificar_conciliacao_financeira(
  p_empresa_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_qtd integer := 0;
BEGIN
  UPDATE public.conciliacao_financeira cf
  SET conta_id = r.conta_id
  FROM public.regras_classificacao_contabil r
  WHERE cf.empresa_id = p_empresa_id
    AND r.empresa_id = p_empresa_id
    AND r.ativo = true
    AND cf.conta_id IS NULL
    AND (r.tipo_movimento IS NULL OR r.tipo_movimento = cf.tipo)
    AND upper(cf.historico) LIKE '%' || upper(r.texto_busca) || '%';

  GET DIAGNOSTICS v_qtd = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'classificadas', v_qtd
  );
END;
$$;