CREATE OR REPLACE FUNCTION public.ff_classificar_historicos_lote(
  p_empresa_id bigint,
  p_linhas jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_item jsonb;
  v_resultado jsonb := '[]'::jsonb;
  v_linha_id text;
  v_historico text;
  v_tipo text;
  v_regra record;
BEGIN
  FOR v_item IN
    SELECT * FROM jsonb_array_elements(p_linhas)
  LOOP
    v_linha_id := v_item->>'_id';
    v_historico := v_item->>'historico';
    v_tipo := v_item->>'tipo';

    SELECT
      r.id AS regra_id,
      r.texto_busca,
      r.conta_id,
      c.codigo,
      c.nome
    INTO v_regra
    FROM public.regras_classificacao_contabil r
    JOIN contab.contas c ON c.id = r.conta_id
    WHERE r.empresa_id = p_empresa_id
      AND r.ativo = true
      AND (r.tipo_movimento IS NULL OR r.tipo_movimento = v_tipo)
      AND upper(v_historico) LIKE '%' || upper(r.texto_busca) || '%'
    ORDER BY
      r.prioridade ASC,
      length(r.texto_busca) DESC,
      r.id DESC
    LIMIT 1;

    IF v_regra.conta_id IS NOT NULL THEN
      v_resultado := v_resultado || jsonb_build_array(
        jsonb_build_object(
          '_id', v_linha_id,
          'historico', v_historico,
          'tipo', v_tipo,
          'encontrado', true,
          'regra_id', v_regra.regra_id,
          'texto_busca', v_regra.texto_busca,
          'conta_id', v_regra.conta_id,
          'conta_codigo', v_regra.codigo,
          'conta_nome', v_regra.nome
        )
      );
    ELSE
      v_resultado := v_resultado || jsonb_build_array(
        jsonb_build_object(
          '_id', v_linha_id,
          'historico', v_historico,
          'tipo', v_tipo,
          'encontrado', false
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'linhas', v_resultado
  );
END;
$$;