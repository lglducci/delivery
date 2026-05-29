CREATE OR REPLACE FUNCTION public.ff_buscar_regra_classificacao_parecida(
  p_empresa_id bigint,
  p_texto text,
  p_tipo_movimento text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'ok', true,
    'regra_id', r.id,
    'texto_busca', r.texto_busca,
    'tipo_movimento', r.tipo_movimento,
    'conta_id', c.id,
    'conta_codigo', c.codigo,
    'conta_nome', c.nome
  )
  INTO v_result
  FROM public.regras_classificacao_contabil r
  JOIN contab.contas c ON c.id = r.conta_id
  WHERE r.empresa_id = p_empresa_id
    AND r.ativo = true
    AND (r.tipo_movimento IS NULL OR r.tipo_movimento = p_tipo_movimento)
    AND (
      upper(p_texto) LIKE '%' || upper(r.texto_busca) || '%'
      OR upper(r.texto_busca) LIKE '%' || upper(p_texto) || '%'
      OR split_part(upper(p_texto), ' ', 1) = split_part(upper(r.texto_busca), ' ', 1)
    )
  ORDER BY length(r.texto_busca) DESC, r.prioridade ASC, r.id DESC
  LIMIT 1;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Nenhuma regra parecida encontrada.');
  END IF;

  RETURN v_result;
END;
$$;