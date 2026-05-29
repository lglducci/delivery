 CREATE OR REPLACE FUNCTION public.ff_aprender_historicos_contabeis(
  p_empresa_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_qtd_transacoes integer := 0;
  v_qtd_cartoes integer := 0;
BEGIN

  INSERT INTO public.regras_classificacao_contabil (
    empresa_id,
    texto_busca,
    tipo_movimento,
    conta_id,
    ativo,
    prioridade,
    tipo_evento,
    classificacao
  )
  SELECT DISTINCT
    t.empresa_id,
    trim(t.descricao) AS texto_busca,
    t.tipo AS tipo_movimento,
    NULL::bigint AS conta_id,
    false AS ativo,
    100 AS prioridade,
    t.tipo_evento,
    t.classificacao
  FROM public.transacoes t
  WHERE t.empresa_id = p_empresa_id
    AND coalesce(trim(t.descricao), '') <> ''
  ON CONFLICT (empresa_id, texto_busca, tipo_movimento) DO NOTHING;

  GET DIAGNOSTICS v_qtd_transacoes = ROW_COUNT;


  INSERT INTO public.regras_classificacao_contabil (
    empresa_id,
    texto_busca,
    tipo_movimento,
    conta_id,
    ativo,
    prioridade,
    tipo_evento,
    classificacao
  )
  SELECT DISTINCT
    c.empresa_id,
    trim(c.estabelecimento) AS texto_busca,
    'entrada' AS tipo_movimento,
    NULL::bigint AS conta_id,
    false AS ativo,
    100 AS prioridade,
    'cartao_compra' AS tipo_evento,
    'despesa' AS classificacao
  FROM public.conciliacao_cartoes c
  WHERE c.empresa_id = p_empresa_id
    AND c.tipo_linha = 'compra'
    AND coalesce(trim(c.estabelecimento), '') <> ''
  ON CONFLICT (empresa_id, texto_busca, tipo_movimento) DO NOTHING;

  GET DIAGNOSTICS v_qtd_cartoes = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'transacoes_inseridas', v_qtd_transacoes,
    'cartoes_inseridos', v_qtd_cartoes,
    'total_inseridos', v_qtd_transacoes + v_qtd_cartoes,
    'message', 'Históricos enviados para aprendizagem contábil.'
  );
END;
$$;